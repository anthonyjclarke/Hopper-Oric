;==============================================================================
; input.s - keyboard and joystick
;
; Oric: ReadKeys selects a matrix row through VIA port B and a column through
; AY port A for each of five keys. C64: CIA1 port A selects a column, port B
; reads the rows. The game's own tables (key_rows, key_cols, key_bits) hold
; the C64 column select and row mask, so ControlsMenu still swaps the key
; sets by copying them. Joystick port 2 adds to the keys.
;
; The Oric ROM's interrupt filled ROM_KEY ($02DF) with the ASCII code of a
; new key, bit 7 set; the menus and the name entry read it. ScanRomKey does
; the same from the raster IRQ while the Oric code has that interrupt on.
;==============================================================================

        .include "c64.inc"

        .import key_rows, key_cols, key_bits, keys_set2, ControlsWaitKey
        .import key_name_left, key_name_right, key_name_up, key_name_down
        .import DelayXC64, IdleParse
        .export InitInput, ReadKeysC64, ScanRomKey, RedefineKeys
        .import QuitGameC64
.ifdef AUTOTEST
        .import testKeys
.endif

        .segment "CODE"

InitInput:
        lda     #$FF
        sta     CIA1_DDRA               ; port A out: column select
        sta     CIA1_PRA
        lda     #$00
        sta     CIA1_DDRB               ; port B in: rows
        sta     zLastKey
        rts

;------------------------------------------------------------------------------
; ReadKeysC64 - replaces ReadKeys: key_state = one bit per control key held
; (key_bits), plus joystick 2. Returns X = $FF as ReadKeys did.
;------------------------------------------------------------------------------
ReadKeysC64:
        lda     zRomIrq                 ; in a game (ROM IRQ off): RUN/STOP
        bne     :+                      ; quits to the hi-score table (Remix)
        lda     #$7F                    ; column 7, row 7
        sta     CIA1_PRA
        lda     CIA1_PRB
        bmi     :+
        jmp     QuitGameC64
:       lda     #$FF
        sta     CIA1_PRA
        lda     CIA1_PRB                ; rows held by joystick 1, not keys
        sta     zJoyIdle
        lda     #0
        sta     key_state
        ldx     #4
@key:   lda     key_rows,x              ; C64: column select
        sta     CIA1_PRA
        lda     CIA1_PRB
        eor     #$FF
        and     zJoyIdle
        and     key_cols,x              ; C64: row mask
        beq     @next
        lda     key_bits,x
        ora     key_state
        sta     key_state
@next:  dex
        bpl     @key
        lda     #$FF
        sta     CIA1_PRA
        lda     CIA1_PRA                ; joystick 2 (active low)
        eor     #$FF
        and     #$0F
        tax
        lda     JoyToKeys,x
        ora     key_state
.ifdef AUTOTEST
        ora     testKeys
.endif
        sta     key_state
        ldx     #$FF
        rts

;------------------------------------------------------------------------------
; RedefineKeys - ControlsMenu choice 2 (C64 only). Called in place of
; "cmp #'2' / bne": any other key goes back to the menu's key wait. Asks for
; LEFT, RIGHT, UP and DOWN under the menu, puts each key's column select and
; row mask in keys_set2 and its name in the four lda #imm that ControlsMenu
; then writes into the credits text, and returns to ControlsMenu, which
; copies keys_set2 to key_rows as it always did. P stays pause. The Oric's
; set 2 orders its keys up, down, left, right, with key_bits to match, so
; the bits are rewritten here in set 1's order, the order the prompts use.
; Refused: keys with no character, P, SPACE, RETURN, DEL, the frog's
; characters (: ; =) and a key already chosen.
;------------------------------------------------------------------------------
REDEF_ROW       = SCREEN + 24*40 + 7        ; ink attribute, then the prompts

RedefineKeys:
        cmp     #'2'
        beq     @go
        pla                             ; not 2: back to the menu's key wait
        pla
        jmp     ControlsWaitKey
@go:    ldx     #4                      ; keys_set2's bits in set 1's order (the Oric's
@bits:  lda     RedefBits,x             ; set 2 lists up, down, left, right)
        sta     keys_set2+10,x
        dex
        bpl     @bits
        lda     #0
        sta     redefIdx
@prompt:
        ldx     redefIdx
        lda     PromptRowLo,x
        sta     zPtr
        lda     PromptRowHi,x
        sta     zPtr+1
        lda     #$06                    ; Oric ink cyan
        ldy     #0
        sta     (zPtr),y
        lda     PromptText,x            ; offset of the direction's name
        tax
@text:  lda     PromptWords,x
        beq     @release
        iny
        sta     (zPtr),y
        inx
        bne     @text
@release:
        jsr     WaitNoKeys              ; the key that chose 2, or the last one, let go
@key:   jsr     IdleParse               ; draw the screen while waiting
        lda     ROM_KEY
        beq     @key
        ldx     #0
        stx     ROM_KEY
        and     #$7F
        ldx     #RefusedEnd-Refused-1
@ref:   cmp     Refused,x
        beq     @key
        dex
        bpl     @ref
        ldx     redefIdx                ; not one already chosen
        beq     @find
@dup:   dex
        cmp     redefName,x
        beq     @key
        cpx     #0
        bne     @dup
@find:  ldx     #63                     ; its place in the matrix
@look:  cmp     KeyAscii,x
        beq     @found
        dex
        bpl     @look
        bmi     @key
@found: ldy     redefIdx
        sta     redefName,y
        pha
        lda     PromptRowLo,y           ; (the drawing may have used zPtr)
        sta     zPtr
        lda     PromptRowHi,y
        sta     zPtr+1
        pla
        ldy     #PROMPT_KEYCOL          ; show it after the prompt
        sta     (zPtr),y
        txa
        and     #7
        tay
        lda     RowBit,y
        pha
        txa
        lsr     a
        lsr     a
        lsr     a
        tay
        lda     ColumnSelect,y
        ldx     redefIdx
        ldy     PromptSlot,x            ; left, right, down, up, as key_rows
        sta     keys_set2,y
        pla
        sta     keys_set2+5,y
        lda     NameLo,x
        sta     zPtr
        lda     NameHi,x
        sta     zPtr+1
        lda     redefName,x
        ldy     #0
        sta     (zPtr),y
        inc     redefIdx
        lda     redefIdx
        cmp     #4
        beq     :+
        jmp     @prompt
:       ldx     #0                      ; a moment to see the last one
        jsr     DelayXC64
        ldx     #0
        jmp     DelayXC64

;------------------------------------------------------------------------------
; WaitNoKeys - for RedefineKeys: wait until no key has been down for
; RELEASE_FRAMES frames in a row, then forget any key ScanRomKey reported
; meanwhile, so a held or bouncing key is not taken for the next prompt.
;------------------------------------------------------------------------------
RELEASE_FRAMES  = 5

WaitNoKeys:
        lda     #RELEASE_FRAMES
        sta     redefQuiet
        lda     zTick
        sta     redefTick
@loop:  jsr     IdleParse
        lda     #$00                    ; every column
        sta     CIA1_PRA
        lda     CIA1_PRB
        ldx     #$FF
        stx     CIA1_PRA
        cmp     #$FF
        bne     WaitNoKeys              ; a key is down: start counting again
        lda     zTick
        cmp     redefTick
        beq     @loop
        sta     redefTick
        dec     redefQuiet
        bne     @loop
        lda     #0
        sta     ROM_KEY
        sta     zLastKey                ; the next press is new
        rts

;------------------------------------------------------------------------------
; ScanRomKey - from the raster IRQ: a newly pressed key goes to ROM_KEY as
; ASCII + $80. Scans the whole matrix; SHIFT, CTRL and C= are ignored.
;------------------------------------------------------------------------------
ScanRomKey:
        lda     #$FF
        sta     CIA1_PRA
        lda     CIA1_PRB
        sta     scanIdle
        lda     #0
        sta     scanKey
        ldx     #7                      ; column
@col:   lda     ColumnSelect,x
        sta     CIA1_PRA
        lda     CIA1_PRB
        eor     #$FF
        and     scanIdle
        beq     @nextCol
        ldy     #7                      ; row
@row:   asl     a
        bcc     @nextRow
        pha
        stx     scanCol
        txa
        asl     a
        asl     a
        asl     a
        sty     scanRow
        ora     scanRow                 ; index = column * 8 + row
        tay
        lda     KeyAscii,y
        beq     :+
        sta     scanKey
:       ldy     scanRow
        ldx     scanCol
        pla
@nextRow:
        dey
        bpl     @row
@nextCol:
        dex
        bpl     @col
        lda     #$FF
        sta     CIA1_PRA
        lda     scanKey
        cmp     zLastKey
        beq     @r
        sta     zLastKey
        beq     @r                      ; released
        ora     #$80
        sta     ROM_KEY
@r:     rts

        .segment "RODATA"

ColumnSelect:
        .byte   $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

; Joystick bits (up 1, down 2, left 4, right 8, after inversion) to key_bits
; (KeysToDir: $04 up, $08 down, $20 left, $10 right).
JoyToKeys:
        .repeat 16, j
        .byte   ((j & 1) * $04) | (((j >> 1) & 1) * $08) | (((j >> 2) & 1) * $20) | (((j >> 3) & 1) * $10)
        .endrepeat

; Matrix index (column * 8 + row) -> ASCII as the Oric ROM gave it. 0 = none.
KeyAscii:
        .byte   $7F, $0D, 0, 0, KEY_F1, 0, 0, 0            ; DEL RETURN CRSR F7 F1 F3 F5 CRSR
        .byte   "3", "W", "A", "4", "Z", "S", "E", 0       ; (L-SHIFT)
        .byte   "5", "R", "D", "6", "C", "F", "T", "X"
        .byte   "7", "Y", "G", "8", "B", "H", "U", "V"
        .byte   "9", "I", "J", "0", "M", "K", "O", "N"
        .byte   "+", "P", "L", "-", ".", ":", "@", ","
        .byte   $5C, "*", ";", 0, 0, "=", "^", "/"         ; \ on the pound key (HOME R-SHIFT)
        .byte   "1", "_", 0, "2", " ", 0, "Q", 0           ; (CTRL C= STOP)

; RedefineKeys: one prompt row each for LEFT, RIGHT, UP, DOWN
PROMPT_KEYCOL   = 17                    ; column of the key, from REDEF_ROW
PromptRowLo:    .lobytes REDEF_ROW, REDEF_ROW+40, REDEF_ROW+80, REDEF_ROW+120
PromptRowHi:    .hibytes REDEF_ROW, REDEF_ROW+40, REDEF_ROW+80, REDEF_ROW+120
PromptSlot:     .byte   0, 1, 3, 2      ; key_rows order: left, right, down, up
RedefBits:      .byte   $20, $10, $08, $04, $80 ; left, right, down, up, pause (P stays in slot 4)
NameLo:         .lobytes key_name_left, key_name_right, key_name_up, key_name_down
NameHi:         .hibytes key_name_left, key_name_right, key_name_up, key_name_down
PromptText:     .byte   PwLeft-PromptWords, PwRight-PromptWords, PwUp-PromptWords, PwDown-PromptWords
PromptWords:
PwLeft:  .byte   "Key for LEFT  :  ", 0
PwRight: .byte   "Key for RIGHT :  ", 0
PwUp:    .byte   "Key for UP    :  ", 0
PwDown:  .byte   "Key for DOWN  :  ", 0
Refused:        .byte   "P", " ", $0D, $7F, ":", ";", "=", KEY_F1
RefusedEnd:
RowBit:         .byte   $01, $02, $04, $08, $10, $20, $40, $80

        .segment "BSS"
redefIdx:       .res 1
redefQuiet:     .res 1
redefTick:      .res 1
redefName:      .res 4
scanIdle:       .res 1
scanKey:        .res 1
scanCol:        .res 1
scanRow:        .res 1
