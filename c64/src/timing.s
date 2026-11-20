;==============================================================================
; timing.s - clock, the Oric's busy-wait delays, VIA timer 2, raster IRQ
;
; The Oric paced HOPPER with busy loops (FrameDelay, DelayX) and polled VIA
; timer 2 for the TIME count. The C64 keeps those timings, measured with a
; free-running CIA2 clock, and spends the waiting time drawing the Oric
; screen onto the C64's (Present, video.s). A wait that overruns because of
; the drawing carries the overrun into the next wait (zDebt), so a run of
; short delays (a jingle) keeps its total length.
;
; The raster IRQ does what the Oric's ULA did per text row: one paper colour
; and one character set (normal or double height) per C64 row, set at the
; end of the row above from rowPaper / rowCset as they are at that moment,
; so a row that Present recolours mid-frame is right in the same frame. At the bottom of the screen it counts frames, flips
; the blink phase and, while the Oric code has its ROM interrupt on
; (zRomIrq), scans the keyboard into ROM_KEY and blinks the ROM cursor.
;==============================================================================

        .include "c64.inc"

        .import Present, ParseNextRow, ScanRomKey, ServiceTimer, CheckMenuKeys
        .import rowPaper, rowCset, rowMc1, rowMc2, rowCtl2, rowIrqBg, SprTick, attractOn
        .export catchUp, MarkRow
        .export InitTiming, ReadClock, WaitCycles, DelayXC64, FrameDelayC64, T2Check, Idle, IdleParse
        .export AttractWait
.ifdef AUTOTEST
        .import AutoTestTick
.endif
        .export IrqHandler, IrqDefault, NmiEntry

        .segment "CODE"

;------------------------------------------------------------------------------
; InitTiming - PAL/NTSC, CIA2 clock, vectors, raster IRQ. IRQs masked.
;------------------------------------------------------------------------------
InitTiming:
        ; Highest raster line, low byte: PAL $37 (311), NTSC $06 or $05.
@w0:    lda     VIC_RASTER
@w1:    cmp     VIC_RASTER
        beq     @w1
        bmi     @w0
        ldx     #0
        cmp     #$20
        bcc     :+
        inx
:       stx     zIsPAL

        ; CIA2: timer A counts cycles, timer B counts A's underflows; both
        ; free-running from $FFFF. ReadClock reads 24 bits of the pair.
        lda     #$FF
        sta     CIA2_TALO
        sta     CIA2_TAHI
        sta     CIA2_TBLO
        sta     CIA2_TBHI
        lda     #%00010001              ; start, continuous, load
        sta     CIA2_CRA
        lda     #%01010001              ; start, continuous, load, count A underflows
        sta     CIA2_CRB

        lda     #<IrqHandler
        sta     VEC_IRQ
        lda     #>IrqHandler
        sta     VEC_IRQ+1
        lda     #<NmiEntry
        sta     VEC_NMI
        lda     #>NmiEntry
        sta     VEC_NMI+1

        lda     #0
        sta     zTick
        sta     evIdx
        sta     zDebt
        sta     zDebt+1
        sta     zWaitHook
        sta     zT2Dl
        sta     zT2Dl+1
        sta     zT2Dl+2
        lda     #16
        sta     blinkCount
        lda     #FRAME_IRQ_LINE
        sta     VIC_RASTER
        lda     VIC_CTRL1
        and     #$7F
        sta     VIC_CTRL1
        lda     #$01
        sta     VIC_IRQ_MASK
        sta     VIC_IRQ_FLAG
        rts

;------------------------------------------------------------------------------
; ReadClock - zNow = cycles since start (24 bits, wraps every 17 s).
; Clobbers A.
;------------------------------------------------------------------------------
ReadClock:
@again: lda     CIA2_TBLO
        sta     zNow+2
        lda     CIA2_TAHI
        sta     zNow+1
        lda     CIA2_TALO
        sta     zNow
        lda     CIA2_TBLO
        cmp     zNow+2
        bne     @again
        lda     zNow                    ; the timers count down
        eor     #$FF
        sta     zNow
        lda     zNow+1
        eor     #$FF
        sta     zNow+1
        lda     zNow+2
        eor     #$FF
        sta     zNow+2
        rts

;------------------------------------------------------------------------------
; T2Check - replaces `bit VIA_IFR` in ServiceTimer: Z = 0 if timer 2 has run
; out. The game reloads the VIA timer next; here the period restarts at
; once. Preserves X, Y.
;------------------------------------------------------------------------------
T2Check:
        jsr     ReadClock
        sec
        lda     zNow
        sbc     zT2Dl
        lda     zNow+1
        sbc     zT2Dl+1
        lda     zNow+2
        sbc     zT2Dl+2
        bmi     @running
        clc
        lda     zNow
        adc     #<T2_PERIOD
        sta     zT2Dl
        lda     zNow+1
        adc     #>T2_PERIOD
        sta     zT2Dl+1
        lda     zNow+2
        adc     #0
        sta     zT2Dl+2
        lda     #$20                    ; Z = 0
        rts
@running:
        lda     #0                      ; Z = 1
        rts

;------------------------------------------------------------------------------
; DelayXC64 - the Oric's DelayX: X x 1286 cycles (X = 0: 256). Returns
; X = Y = 0 as DelayX did; preserves A.
;------------------------------------------------------------------------------
DelayXC64:
        pha
        lda     #1                      ; DelayX keeps the Oric's pace: debt
        sta     catchUp                 ; carried, Presents thinned if need be
        lda     #HOOK_NONE
        sta     zWaitHook
        lda     #<DELAYX_UNIT
        ldy     #>DELAYX_UNIT
        jsr     MulUnit
        jsr     WaitCycles
        pla
        ldx     #0
        ldy     #0
        rts

;------------------------------------------------------------------------------
; FrameDelayC64 - the Oric's FrameDelay: game_delay x 1823 cycles, calling
; ServiceTimer meanwhile, as FrameDelay did once per count.
;------------------------------------------------------------------------------
FrameDelayC64:
        lda     #0                      ; play: a Present every frame, at the
        sta     catchUp                 ; cost of some of the Oric's pace
        ldx     game_delay
        lda     #<FRAMEDELAY_UNIT
        ldy     #>FRAMEDELAY_UNIT
        jsr     MulUnit
        lda     #HOOK_SERVICE
        sta     zWaitHook
        jsr     WaitCycles
        lda     #HOOK_NONE
        sta     zWaitHook
        ldx     #0
        ldy     #0
        rts

;------------------------------------------------------------------------------
; AttractWait - replaces AttractMode's counting loop (inc tmp0 / CheckMenuKeys
; over 8 x 65536 passes, 34 cycles each on the Oric, ~17.8 s): the same time
; by the clock, calling CheckMenuKeys meanwhile. Leaves the counters as the
; loop did.
;------------------------------------------------------------------------------
ATTRACT_PART    = 65536*34 + 256*8      ; one pass of the outer counter (tmp2)

AttractWait:
        lda     #8
        sta     attractCount
@part:  lda     #<ATTRACT_PART
        sta     zWait
        lda     #>ATTRACT_PART
        sta     zWait+1
        lda     #^ATTRACT_PART
        sta     zWait+2
        lda     #HOOK_MENUKEYS
        sta     zWaitHook
        jsr     WaitCycles
        lda     #HOOK_NONE
        sta     zWaitHook
        dec     attractCount
        bne     @part
        lda     #0
        sta     tmp0
        sta     key_state
        lda     #8
        sta     tmp2
        rts

; zWait = X (0 = 256) x unit (A low, Y high). Clobbers A, X, Y.
MulUnit:
        sta     zTmp0
        sty     zTmp1
        lda     #0
        sta     zWait
        sta     zWait+1
        sta     zWait+2
        txa
        bne     @mul
        lda     zTmp0                   ; X = 0: 256 x unit
        sta     zWait+1
        lda     zTmp1
        sta     zWait+2
        rts
@mul:   sta     zTmp2
        ldy     #8
@bit:   asl     zWait
        rol     zWait+1
        rol     zWait+2
        asl     zTmp2
        bcc     @next
        clc
        lda     zWait
        adc     zTmp0
        sta     zWait
        lda     zWait+1
        adc     zTmp1
        sta     zWait+1
        bcc     @next
        inc     zWait+2
@next:  dey
        bne     @bit
        rts

;------------------------------------------------------------------------------
; WaitCycles - wait zWait cycles (less any carried overrun), drawing the
; screen meanwhile. With zWaitHook set, calls the game's ServiceTimer in the
; loop (FrameDelay); ServiceTimer can itself call DelayX, so the deadline is
; kept on the stack around it.
;------------------------------------------------------------------------------
WaitCycles:
        jsr     ReadClock
        lda     #0
        sta     presented
        ; zWait -= zDebt; if that goes negative, the wait is used up by debt
        sec
        lda     zWait
        sbc     zDebt
        sta     zWait
        lda     zWait+1
        sbc     zDebt+1
        sta     zWait+1
        lda     zWait+2
        sbc     #0
        sta     zWait+2
        bcs     @nodebtleft
        lda     zWait                   ; debt left = -zWait
        eor     #$FF
        clc
        adc     #1
        sta     zDebt
        lda     zWait+1
        eor     #$FF
        adc     #0
        sta     zDebt+1
        lda     #0
        sta     zWait
        sta     zWait+1
        sta     zWait+2
        beq     @setdl
@nodebtleft:
        lda     #0
        sta     zDebt
        sta     zDebt+1
@setdl: clc
        lda     zNow
        adc     zWait
        sta     zDeadline
        lda     zNow+1
        adc     zWait+1
        sta     zDeadline+1
        lda     zNow+2
        adc     zWait+2
        sta     zDeadline+2

@loop:  jsr     ReadClock
        sec                             ; zTmp = now - deadline
        lda     zNow
        sbc     zDeadline
        sta     zTmp0
        lda     zNow+1
        sbc     zDeadline+1
        sta     zTmp1
        lda     zNow+2
        sbc     zDeadline+2
        sta     zTmp2
        bmi     :+
        jmp     @done
:       ; time left: draw if a frame has passed, else parse a row if there is room
        sec
        lda     zNow
        sbc     zLastPresent
        tax
        lda     zNow+1
        sbc     zLastPresent+1
        tay
        lda     zNow+2
        sbc     zLastPresent+2
        bne     @present                ; >= 65536 cycles
        lda     lagging                 ; DelayX: Presents overrunning its waits (the
        beq     :+                      ; death flash: DelayX 6, 7.7k cycles,
        cpy     #>PRESENT_GAP_BEHIND    ; against a Present's ~18k): every other
        bcc     @noPresent              ; frame, so the game keeps the Oric's pace
        bne     @present
        cpx     #<PRESENT_GAP_BEHIND
        bcc     @noPresent
        bcs     @present
:       cpy     #>PRESENT_GAP
        bcc     @noPresent
        bne     @present
        cpx     #<PRESENT_GAP
        bcc     @noPresent
@present:
        lda     #1
        sta     presented
        lda     zNow
        sta     zLastPresent
        lda     zNow+1
        sta     zLastPresent+1
        lda     zNow+2
        sta     zLastPresent+2
        jsr     Present
        jmp     @service
@noPresent:
        ; room for a row parse: (now - deadline) + PARSE_COST still negative?
        clc
        lda     zTmp0
        adc     #<PARSE_COST
        lda     zTmp1
        adc     #>PARSE_COST
        lda     zTmp2
        adc     #0
        bpl     @service                ; less than PARSE_COST left
        jsr     ParseNextRow
@service:
        lda     zWaitHook
        beq     @loop
        pha
        lda     zDeadline
        pha
        lda     zDeadline+1
        pha
        lda     zDeadline+2
        pha
        tsx
        lda     #HOOK_NONE
        sta     zWaitHook
        lda     $0104,x                 ; the hook
        cmp     #HOOK_SERVICE
        bne     :+
        jsr     ServiceTimer
        jmp     @back
:       jsr     CheckMenuKeys           ; may jump away to a new game or the credits
@back:  pla
        sta     zDeadline+2
        pla
        sta     zDeadline+1
        pla
        sta     zDeadline
        pla
        sta     zWaitHook
        jmp     @loop

@done:  ; overrun = now - deadline (zTmp0-2) -> debt, capped. In DelayX
        ; (catchUp) it is added to any debt this wait could not pay (zDebt),
        ; and a Present that overran makes the next ones every third frame
        lda     catchUp
        bne     :+
        sta     lagging
        sta     zDebt
        sta     zDebt+1
        beq     @add
:       lda     presented               ; a Present in this wait: lagging if
        beq     :+                      ; it overran by LAG_OVERRUN or more
        sec
        lda     zTmp2
        bne     @lag
        lda     zTmp1
        cmp     #>LAG_OVERRUN
@lag:   lda     #0
        rol     a                       ; C = the overrun was big
        sta     lagging
:
@add:   clc
        lda     zTmp0
        adc     zDebt
        sta     zTmp0
        lda     zTmp1
        adc     zDebt+1
        sta     zTmp1
        lda     zTmp2
        adc     #0
        bne     @cap
        lda     zTmp1
        cmp     #>MAX_DEBT
        bcc     @keep
        bne     @cap
        lda     zTmp0
        cmp     #<MAX_DEBT
        bcc     @keep
@cap:   lda     #<MAX_DEBT
        sta     zDebt
        lda     #>MAX_DEBT
        sta     zDebt+1
        rts
@keep:  lda     zTmp0
        sta     zDebt
        lda     zTmp1
        sta     zDebt+1
        rts

;------------------------------------------------------------------------------
; Idle - called from the game's key-wait loops: draw every IDLE_TICKS frames.
; Clobbers A, X, Y.
;------------------------------------------------------------------------------
Idle:
        lda     zTick
        sec
        sbc     zIdleTick
        cmp     #IDLE_TICKS
        bcc     @r
        lda     zTick
        sta     zIdleTick
        jmp     Present
@r:     rts

;------------------------------------------------------------------------------
; IdleParse - Idle, and a row parse when not drawing, so text drawn with
; attributes mid-row (the controls menu) gets its colours. Only for waits
; that are not counted: CheckMenuKeys runs in timed loops and keeps Idle.
;------------------------------------------------------------------------------
IdleParse:
        lda     zTick
        sec
        sbc     zIdleTick
        cmp     #IDLE_TICKS
        bcc     @parse
        lda     zTick
        sta     zIdleTick
        jmp     Present
@parse: jmp     ParseNextRow

;------------------------------------------------------------------------------
; IrqHandler - raster IRQ. At the last line of each text row it sets the
; paper and character set of the row below (rows 1-24), read live from
; rowPaper / rowCset; the bottom-border IRQ sets row 0 and does the
; per-frame jobs.
;------------------------------------------------------------------------------

; IRQ_PAD: nops before the row IRQ's three VIC stores, for experiments; 0.
; Each one moves the stores 2 cycles later, which the late end can't spare.
.ifndef IRQ_PAD
IRQ_PAD = 0
.endif

; The next row's three VIC values into registers, so the stores come back to
; back, 4 cycles apart, in the border between the row above's last line and
; this row's first (a badline, which stalls the CPU from its start): Y =
; $D018, A = $D021, X = $D016. X = the row on entry.
;
; Timing, measured in VICE (PAL, the monitor's line/cycle at each store):
; without sprites the first store starts at cycle 49-55 of the line (the
; IRQ's jitter) and the third by cycle 0 of the next. One cycle earlier and
; the first store lands before the row above's last line ends (a changed
; paper shows in its last pixels). A store must start by cycle 8 of the
; next line, or the badline holds it to that line's end and the row's first
; line keeps the row above's value. The frog's sprite DMA stops the CPU at
; about cycles 56-62; when it catches the first store, all three come after
; it and the third starts at cycle 4-7. Two things keep that in time: the
; registers are saved in zero page, not pushed (3 cycles; it was cycle 9,
; now and then), and in Enhanced play the third store is a register that
; doesn't change at that boundary, picked per row (IrqArmPlay): IrqHandler
; stores $D016 last (menus, Classic, and rows where the other two change),
; IrqBgLast the paper (river), IrqCsLast the character set (road).
.macro ROW_LOADS
        ldy     rowCset,x
        lda     D018Table,y
        tay
        lda     rowCtl2,x
        sta     zIrqCtl
        lda     rowIrqBg,x
        ldx     zIrqCtl
        .repeat IRQ_PAD
        nop
        .endrepeat
.endmacro

IrqToFrame:
        jmp     IrqFrame                ; (out of a branch's reach)
IrqHandler:
        sta     zIrqA                   ; 3 cycles fewer than pushing them
        stx     zIrqX                   ; (a: keeps 1: 4 fewer puts the first
        sty     a:zIrqY                 ; store a cycle early, see ROW_LOADS)
        ldx     evIdx                   ; 0: bottom border, else the row
        beq     IrqToFrame
        ROW_LOADS
        sty     VIC_MEMSETUP            ; the character set first: a late one
        sta     VIC_BG0                 ; draws a whole line of the wrong glyphs
        stx     VIC_CTRL2
IrqMark:
IrqLine = * + 1
        ldx     #0                      ; V6: a road marking (FineRow) makes
        beq     IrqPlain                ; the row's first line grey; its paper
IrqPaper = * + 1
        ldy     #0                      ; goes back as the second line starts.
:       cpx     VIC_RASTER              ; The loop is running before the
        bcs     :-                      ; badline stall, so after it (and the
        sty     VIC_BG0                 ; frog's sprite DMA) it leaves on the
                                        ; line change, not on code timing.
                                        ; Both immediates are set by IrqArm.
IrqPlain:
        ldx     evIdx
        lda     zMcPlay                 ; Enhanced play
        beq     @next
@mc:    lda     rowMc1,x                ; multicolour shade and highlight
        sta     VIC_BG1                 ; (only multicolour cells use them).
        lda     rowMc2,x                ; These land after the badline stall,
        sta     VIC_BG2                 ; too late for the row's first line,
        lda     rowCset,x               ; so a row without multicolour cells
        cmp     #CS_MC                  ; (the water between river lanes, the
        beq     @next                   ; verges) loads the next row's now
        lda     rowMc1+1,x
        sta     VIC_BG1
        lda     rowMc2+1,x
        sta     VIC_BG2
@next:  inx
        cpx     #C64_ROWS
        bcc     :+
        ldx     #0
:       stx     evIdx
IrqArm: ldy     #0                      ; Enhanced play: the next row's
        bit     zMcPlay                 ; marking and store order
        bpl     :+
        jsr     IrqArmPlay
:       sty     IrqLine
        lda     RowLine,x
        sta     VIC_RASTER
        lda     #$01
        sta     VIC_IRQ_FLAG
        lda     zIrqA
        ldx     zIrqX
        ldy     zIrqY
        rti

IrqFrame: ; --- bottom border: row 0's settings, frame jobs, then row 1's IRQ
        lda     rowPaper
        sta     VIC_BG0
        ldy     rowCset
        lda     D018Table,y
        sta     VIC_MEMSETUP
        lda     rowMc1
        sta     VIC_BG1
        lda     rowMc2
        sta     VIC_BG2
        lda     rowCtl2                 ; Enhanced play: multicolour text mode
        sta     VIC_CTRL2               ; (cells with colour RAM below 8 stay hires)
        lda     zMcPlay                 ; and the sprites (V2, V3; F1's frog)
        ora     attractOn
        beq     :+
        jsr     SprTick
:
        inc     zTick
        dec     blinkCount
        bne     :+
        lda     #16
        sta     blinkCount
        lda     zBlink
        eor     #1
        sta     zBlink
        jsr     CursorBlink
:       lda     zRomIrq
        beq     :+
        jsr     ScanRomKey
:
.ifdef AUTOTEST
        jsr     AutoTestTick
.endif
        ldx     #1
        stx     evIdx
        bne     IrqArm                  ; always

; The ROM cursor: while the ROM interrupt is on and ROM_CURPTR points into
; the screen, invert the character there on each blink phase.
CursorBlink:
        lda     zRomIrq
        beq     @r
        lda     ROM_CURPTR+1
        cmp     #>SCREEN
        bcc     @r
        bne     :+
        lda     ROM_CURPTR
        cmp     #<SCREEN
        bcc     @r
:       lda     ROM_CURPTR+1
        cmp     #>(SCREEN + ORIC_ROWS*COLS)
        bcc     :+
        bne     @r
        lda     ROM_CURPTR
        cmp     #<(SCREEN + ORIC_ROWS*COLS)
        bcs     @r
:       ldy     #0
        lda     (ROM_CURPTR),y
        eor     #$80
        sta     (ROM_CURPTR),y
@r:     rts

;------------------------------------------------------------------------------
; NmiEntry - RESTORE: the Oric's RESET button, which jumps through $022B
; (ColdStart puts JMP NmiHandler there).
;------------------------------------------------------------------------------
NmiEntry:
        jmp     NMI_VECTOR

        .segment "RODATA"
D018Table:
        .byte   D018_NORMAL, D018_DHTOP, D018_DHBOT, D018_MC

; Enhanced play (V6): the C64 rows that start with a road marking, where the
; port hides Oric rows 19 and 22 (MapGame): above Oric rows 20 and 23.
MarkRow:
        .repeat C64_ROWS, r
        .byte   (r = 18) .or (r = 20)
        .endrepeat

; Raster line of each row's IRQ: the last line of the row above (row 0's is
; the bottom-border frame IRQ).
RowLine:
        .byte   FRAME_IRQ_LINE
        .repeat C64_ROWS-1, r
        .byte   FIRST_TEXT_LINE + (r+1)*8 - 1
        .endrepeat

        .segment "HIDATA"

; IrqDefault - from SetRowMap, after it sets zMcPlay: the IRQ vector back to
; IrqHandler, whose stores suit every screen (out of play nothing else sets
; it). IrqBgLast and IrqCsLast do any row and the frame IRQ meanwhile.
IrqDefault:
        php
        sei
        lda     #<IrqHandler
        sta     VEC_IRQ
        lda     #>IrqHandler
        sta     VEC_IRQ+1
        plp
        rts

; IrqArmPlay - IrqArm in Enhanced play, X = the next row (0: the frame IRQ).
; Returns Y = the raster line whose start ends a road marking (the row's
; badline + 1) and sets IrqPaper, or Y = 0 for no marking. Points the IRQ
; vector at the store order for that row (see ROW_LOADS). Preserves X.
IrqArmPlay:
        lda     rowIrqBg,x              ; V6: a row that starts grey
        cmp     #MARK_COLOUR
        bne     :+
        lda     rowPaper,x
        sta     IrqPaper
        sta     IrqPaperC
        ldy     RowLine,x
        iny
:       sty     IrqLineC
        lda     rowCset,x               ; the store that may come late is one
        cmp     rowCset-1,x             ; whose register keeps its value
        beq     @csLast                 ; (row 0, the frame: any order works)
        lda     rowIrqBg,x
        cmp     rowPaper-1,x            ; (the paper after a marking's line)
        beq     @bgLast
        lda     #<IrqHandler
        sta     VEC_IRQ
        lda     #>IrqHandler
        sta     VEC_IRQ+1
        rts
@csLast:
        lda     #<IrqCsLast
        sta     VEC_IRQ
        lda     #>IrqCsLast
        sta     VEC_IRQ+1
        rts
@bgLast:
        lda     #<IrqBgLast
        sta     VEC_IRQ
        lda     #>IrqBgLast
        sta     VEC_IRQ+1
        rts

; The row IRQ with the paper last (the water between river lanes: the
; character set and the fine scroll change, the paper doesn't)
IrqBgLast:
        sta     zIrqA                   ; 3 cycles fewer than pushing them
        stx     zIrqX                   ; (a: keeps 1: 4 fewer puts the first
        sty     a:zIrqY                 ; store a cycle early, see ROW_LOADS)
        ldx     evIdx
        bne     :+
        jmp     IrqFrame
:       ROW_LOADS
        sty     VIC_MEMSETUP
        stx     VIC_CTRL2
        sta     VIC_BG0
        jmp     IrqMark

; The row IRQ with the character set last (the road: the paper of a marking
; and the fine scroll change, the character set doesn't). $D016 goes first:
; early, it moves only the blank right margin of the line above. Its own copy
; of the marking loop: a jmp to IrqMark first would let the badline catch it
; before the loop is running, and the paper would go back late.
IrqCsLast:
        sta     zIrqA                   ; 3 cycles fewer than pushing them
        stx     zIrqX                   ; (a: keeps 1: 4 fewer puts the first
        sty     a:zIrqY                 ; store a cycle early, see ROW_LOADS)
        ldx     evIdx
        bne     :+
        jmp     IrqFrame
:       ROW_LOADS
        stx     VIC_CTRL2
        sta     VIC_BG0
        sty     VIC_MEMSETUP
IrqLineC = * + 1
        ldx     #0
        beq     IrqPlainC
IrqPaperC = * + 1
        ldy     #0
:       cpx     VIC_RASTER
        bcs     :-
        sty     VIC_BG0
IrqPlainC:
        jmp     IrqPlain

        .segment "BSS"
evIdx:         .res 1
blinkCount:    .res 1
presented:     .res 1          ; WaitCycles has called Present
lagging:       .res 1          ; a Present overran its DelayX wait: every third frame
catchUp:       .res 1          ; the wait is DelayX's (1), not FrameDelay's (0)
attractCount:   .res 1
