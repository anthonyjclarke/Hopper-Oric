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
        STEP    200, ROMKEY, '2'        ; controls: redefine keys
        STEP    215, ROMKEY, 'N'        ; left
        STEP    230, ROMKEY, 'M'        ; right
        STEP    245, ROMKEY, 'P'        ; up: refused (pause)
        STEP    260, ROMKEY, 'Q'        ; up
        STEP    275, ROMKEY, 'N'        ; down: refused (already left)
        STEP    290, ROMKEY, 'A'        ; down -> credits
        STEP   2325, ROMKEY, '1'        ; hi-score screen: new game
        STEP   2755, HOLD, UP           ; hop onto the road...
        STEP   2795, HOLD, UP
        STEP   2835, HOLD, LEFT
        STEP   2875, HOLD, UP
        STEP   2915, HOLD, UP
        STEP   2955, HOLD, UP
        STEP   2995, HOLD, UP
        STEP   3035, HOLD, UP
        STEP   3075, HOLD, UP
        .word   $FFFF

        .segment "BSS"
testFrame:      .res 2
testPos:        .res 1
testHold:       .res 1
testKeys:       .res 1
