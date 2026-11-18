;==============================================================================
; autotest.s - scripted keys for the headless screenshot build (AUTOTEST)
;
; VICE's headless mode cannot press keys in a program that scans the
; keyboard itself, so `make c64-smoke` builds with -D AUTOTEST: the raster
; IRQ calls AutoTestTick each frame, which follows Script: put a key into
; ROM_KEY (the menus), or hold control keys for a few frames (play).
; Nothing here is in the normal build.
;==============================================================================

        .include "c64.inc"

        .export AutoTestTick, testKeys

ROMKEY  = 0                             ; value = ASCII
HOLD    = 1                             ; value = key_state bits, held 4 frames

.macro STEP frame, kind, value
        .word   frame
        .byte   kind, value
.endmacro

        .segment "CODE"

AutoTestTick:
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
@r:     rts

        .segment "RODATA"

UP      = $04                           ; key_bits, as KeysToDir reads them
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
        STEP   2500, ROMKEY, KEY_F1     ; home screen: Enhanced -> Classic
.endif
        STEP   2600, ROMKEY, '1'        ; hi-score screen: new game
        STEP   3030, HOLD, UP           ; hop onto the road...
        STEP   3070, HOLD, UP
        STEP   3110, HOLD, LEFT
        STEP   3150, HOLD, UP
        STEP   3190, HOLD, UP
        STEP   3230, HOLD, UP
        STEP   3270, HOLD, UP
        STEP   3310, HOLD, UP
        STEP   3350, HOLD, UP
        .word   $FFFF

        .segment "BSS"
testFrame:      .res 2
testPos:        .res 1
testHold:       .res 1
testKeys:       .res 1
