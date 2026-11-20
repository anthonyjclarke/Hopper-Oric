;==============================================================================
; autotest.s - scripted keys for the headless screenshot build (AUTOTEST)
;
; VICE's headless mode cannot press keys in a program that scans the
; keyboard itself, so `make c64-smoke` builds with -D AUTOTEST: the raster
; IRQ calls AutoTestTick each frame, which follows Script: put a key into
; ROM_KEY (the menus), or hold control keys for a few frames (play).
; Nothing here is in the normal build.
;
; The Enhanced test build (AUTOTEST_ENHANCED) drives the frog itself in
; play instead (Drive): each frame it looks where an UP hop would land and
; hops only when that is safe, so the frog crosses the road and rides the
; river for the enh-* captures and make c64-flicker, without key timings
; that a few extra cycles would break. Deterministic, like the script.
;
; The sound build (AUTOTEST_SOUND, make c64-sound) records the docs' audio:
; it patches PickTune to play the four in-game tunes in order (0, 1, 2, 3,
; 0, ...) instead of at random, hops once up and back, then lets the frog
; sit on the verge until its time runs out (tools/c64_sound.py).
;==============================================================================

        .include "c64.inc"

        .export AutoTestTick, testKeys
.ifdef AUTOTEST_SOUND
        .export soundLog
.endif
.ifdef AUTOTEST_ENHANCED
        .import row_steps_up
.endif
.ifdef AUTOTEST_SOUND
        .import PickTune
.endif

ROMKEY  = 0                             ; value = ASCII
HOLD    = 1                             ; value = key_state bits, held 4 frames

.macro STEP frame, kind, value
        .word   frame
        .byte   kind, value
.endmacro

        .segment "HIDATA"               ; test builds only: out of main memory

AutoTestTick:
.ifdef AUTOTEST_SOUND
        lda     #$20                    ; PickTune's lda rand_seed+1 / and #3
        sta     PickTune+3              ; (4 bytes) -> jsr SoundTune / nop
        lda     #<SoundTune
        sta     PickTune+4
        lda     #>SoundTune
        sta     PickTune+5
        lda     #$EA
        sta     PickTune+6
.endif
        lda     testHold
        beq     :+
        dec     testHold
        bne     :+
        lda     #0
        sta     testKeys
:       inc     testFrame
        bne     :+
        inc     testFrame+1
:       ldx     testPos
        lda     Script+1,x
        cmp     #$FF
        beq     @r
        lda     testFrame
        cmp     Script,x
        bne     @r
        lda     testFrame+1
        cmp     Script+1,x
        bne     @r
        lda     Script+2,x
        bne     @hold
        lda     Script+3,x
        ora     #$80
        sta     ROM_KEY
        jmp     @next
@hold:  lda     Script+3,x
        sta     testKeys
        lda     #4
        sta     testHold
@next:  inx
        inx
        inx
        inx
        stx     testPos
@r:
.ifdef AUTOTEST_ENHANCED
        jmp     Drive
.else
        rts
.endif

.ifdef AUTOTEST_SOUND
; SoundTune - A = the next tune, 0-3 in turn (for PickTune's sta tmp0).
; Logs the frame of each call in soundLog for tools/c64_sound.py.
SoundTune:
        lda     soundTune
        asl     a
        tax
        lda     testFrame
        sta     soundLog,x
        lda     testFrame+1
        sta     soundLog+1,x
        lda     soundTune
        pha
        clc
        adc     #1
        and     #63                     ; (the log: 64 calls)
        sta     soundTune
        pla
        and     #3
        rts
soundLog:       .res 128                ; testFrame at each call (out of main memory)
.endif

.ifdef AUTOTEST_ENHANCED
;------------------------------------------------------------------------------
; Drive - from DRIVE_FROM, hop UP whenever the landing place is safe: on the
; road, the frog's two columns clear in both rows of the lane, DRIVE_WIDE
; columns on the side the traffic comes from and 2 on the other; on the river, a log or turtle under the frog's columns and one
; either side. The median is always safe. It stops on the top river lane
; (frog_row 8) and rides it; a death puts the frog back on the verge and it
; starts again.
;------------------------------------------------------------------------------
DRIVE_FROM      = 3030
DRIVE_GAP       = 12                    ; frames between hops
DRIVE_WIDE      = 8                     ; road: clear this far towards the traffic

Drive:
        lda     testFrame+1
        cmp     #>DRIVE_FROM
        bcc     @r
        bne     :+
        lda     testFrame
        cmp     #<DRIVE_FROM
        bcc     @r
:       lda     testHold                ; a hop still held
        bne     @r
        lda     driveWait
        beq     :+
        dec     driveWait
@r:     rts
:       ldx     frog_row
        cpx     #8
        bcs     @r
        sec                             ; landing = frog_pos - row_steps_up
        lda     frog_pos
        sbc     row_steps_up,x
        sta     driveAt
        lda     frog_pos+1
        sbc     #0
        sta     driveAt+1
        inx                             ; the row it lands in
        cpx     #4
        beq     @hop                    ; the median
        bcs     @river
        jsr     DriveDanger             ; traffic close where it stands: any
        bcc     @gap                    ; landing with its own two columns
        lda     #0                      ; clear will do
        jsr     DriveBase
        ldy     #1
        bne     @cells
@gap:   lda     DriveLeft-1,x           ; road: a gap, wide on the side the
        jsr     DriveBase               ; traffic comes from, both rows
        ldy     #DRIVE_WIDE+3
@cells:
:       jsr     DriveRead
        cmp     #$20
        bne     @r
        tya
        clc
        adc     #COLS
        tay
        jsr     DriveRead
        cmp     #$20
        bne     @r
        tya
        sec
        sbc     #COLS
        tay
        dey
        bpl     :-
        bmi     @hop
@river: lda     #1                      ; river: columns -1..+2, top row
        jsr     DriveBase
        ldy     #3
:       jsr     DriveRead
        cmp     #$20
        beq     @r
        dey
        bpl     :-
@hop:   lda     #UP
        sta     testKeys
        lda     #4
        sta     testHold
        lda     #DRIVE_GAP
        sta     driveWait
        rts

; DriveDanger - X = the row it would land in (2-4): C = 1 when the frog
; stands in a road lane (frog_row 1-3) with traffic within 4 columns on the
; side it comes from. Preserves X.
DriveDanger:
        lda     frog_row
        beq     @no                     ; the verge
        cmp     #4
        bcs     @no
        tay                             ; 1, 3: traffic from the right (+2..+5)
        lda     frog_pos                ; 2: from the left (-4..-1)
        sta     driveAt2
        lda     frog_pos+1
        sta     driveAt2+1
        lda     DangerFrom-1,y
        clc
        adc     driveAt2
        sta     @rd+1
        lda     DangerFromHi-1,y
        adc     driveAt2+1
        sta     @rd+2
        ldy     #3
@rd:    lda     $FFFF,y
        cmp     #$20
        bne     @yes
        dey
        bpl     @rd
@no:    clc
        rts
@yes:   sec
        rts
DangerFrom:     .byte   <2, <-4, <2
DangerFromHi:   .byte   >2, >-4, >2

; DriveBase - point DriveRead at driveAt - A.
DriveBase:
        sta     driveTmp
        sec
        lda     driveAt
        sbc     driveTmp
        sta     DriveRead+1
        lda     driveAt+1
        sbc     #0
        sta     DriveRead+2
        rts
DriveRead:
        lda     $FFFF,y                 ; (patched by DriveBase)
        rts
; The columns left of the frog to check, by the road lane landed in (frog_row
; 1-3): the lanes on rows 23 and 17 move left, row 20's right.
DriveLeft:      .byte   2, DRIVE_WIDE, 2
.endif

        .segment "HIDATA"

UP      = $04                           ; key_bits, as KeysToDir reads them
DOWN    = $08
LEFT    = $20
RIGHT   = $10

; Frames since start-up (PAL, 50 per second). tools/c64_screens.py takes its
; screenshots at fixed points of this script.
Script:
        STEP    150, ROMKEY, '3'        ; sound menu: loud
        STEP    230, ROMKEY, '2'        ; controls: redefine keys
        STEP    255, ROMKEY, 'N'        ; left (25 frames apart: each prompt
        STEP    280, ROMKEY, 'M'        ; right  first waits for 5 quiet frames)
        STEP    305, ROMKEY, 'P'        ; up: refused (pause)
        STEP    330, ROMKEY, 'Q'        ; up
        STEP    355, ROMKEY, 'N'        ; down: refused (already left)
        STEP    380, ROMKEY, 'A'        ; down -> credits
.ifndef AUTOTEST_ENHANCED                ; (the Enhanced build stays in Enhanced)
        STEP    520, ROMKEY, KEY_F1     ; Enhanced instructions page -> Classic
.endif
.ifdef AUTOTEST_ENHANCED                 ; (Enhanced's page comes at once: its
        STEP   2480, ROMKEY, '1'        ; attract loop runs ahead) hi-scores: new game
.else
        STEP   2600, ROMKEY, '1'        ; hi-score screen: new game
.endif
.ifdef AUTOTEST_SOUND
        STEP   3030, HOLD, UP           ; one hop up and back, then sit
        STEP   3060, HOLD, DOWN
.elseif .not .defined(AUTOTEST_ENHANCED) ; (Enhanced: Drive steers from 3030)
        STEP   3030, HOLD, UP           ; hop onto the road...
        STEP   3070, HOLD, UP
        STEP   3110, HOLD, LEFT
        STEP   3150, HOLD, UP
        STEP   3190, HOLD, UP
        STEP   3230, HOLD, UP
        STEP   3270, HOLD, UP
        STEP   3310, HOLD, UP
        STEP   3350, HOLD, UP
.endif
        .word   $FFFF

        .segment "BSS"
testFrame:      .res 2
testPos:        .res 1
testHold:       .res 1
testKeys:       .res 1
.ifdef AUTOTEST_SOUND
soundTune:      .res 1          ; calls so far, mod 64 (the tune is the low 2 bits)
.endif
.ifdef AUTOTEST_ENHANCED
driveWait:      .res 1
driveAt:        .res 2
driveTmp:       .res 1
driveAt2:       .res 2
.endif
