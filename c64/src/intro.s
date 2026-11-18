;==============================================================================
; intro.s - the start-up picture (not in the Oric game)
;
; A multicolour bitmap made from the original PSS cassette inlay by
; tools/make_intro.py and stored run-length packed in intro.rle: bitmap,
; then screen colours, then colour RAM, each ending with $FE $00.
;
; UnpackPicture puts it in VIC bank 3, which nothing else uses: bitmap at
; $E000 (RAM under the KERNAL, banked out), screen colours at $C000, and a
; copy of the colour RAM at $C400. It stays there, so ShowPicture can show
; it again in the attract loop (after the hi-score table) by copying the
; colour RAM back and switching banks; the game's own bank 2 (character
; sets, hi-scores, Oric screen) is never touched.
;
; ShowPicture masks interrupts while it is up and times itself on the
; raster: the raster IRQ would set each text row's paper and character set.
;==============================================================================

        .include "c64.inc"

        .export UnpackPicture, ShowPicture

PIC_BITMAP      = $E000                 ; bank 3 + $2000
PIC_COLOURS     = $C000                 ; bank 3 + $0000
PIC_COLRAM      = $C400                 ; colour RAM copy
PIC_BANK_BITS   = %00                   ; $DD00 bits 0-1 for bank 3
PIC_D018        = ((PIC_COLOURS - $C000) / $400) << 4 | ((PIC_BITMAP - $C000) / $2000) << 3
PIC_FRAMES      = 8 * 50                ; about 8 s (PAL), or a key or fire

        .segment "CODE"

;------------------------------------------------------------------------------
; UnpackPicture - unpack intro.rle into bank 3. Once, from Start.
;------------------------------------------------------------------------------
UnpackPicture:
        lda     #<IntroData
        sta     zSrc
        lda     #>IntroData
        sta     zSrc+1
        lda     #<PIC_BITMAP
        ldx     #>PIC_BITMAP
        jsr     Unpack
        lda     #<PIC_COLOURS
        ldx     #>PIC_COLOURS
        jsr     Unpack
        lda     #<PIC_COLRAM
        ldx     #>PIC_COLRAM
        jmp     Unpack

;------------------------------------------------------------------------------
; ShowPicture - show the picture until a key, fire, or 8 seconds, then put
; the VIC back in text mode on bank 2 with a blank screen (the caller's next
; SetRowMap makes Present redraw every row and its colours). Returns A = 1
; if it ended on 1 or fire (start a game), else A = 0. Leaves interrupts
; masked: the caller does cli.
;------------------------------------------------------------------------------
ShowPicture:
        sei
        lda     #$0B                    ; blank while setting up
        sta     VIC_CTRL1
        ldx     #0                      ; colour RAM from the copy
@col:   lda     PIC_COLRAM,x
        sta     COLOUR_RAM,x
        lda     PIC_COLRAM+$100,x
        sta     COLOUR_RAM+$100,x
        lda     PIC_COLRAM+$200,x
        sta     COLOUR_RAM+$200,x
        lda     PIC_COLRAM+$2E8,x
        sta     COLOUR_RAM+$2E8,x
        inx
        bne     @col
        lda     CIA2_DDRA
        ora     #%00000011
        sta     CIA2_DDRA
        lda     CIA2_PRA
        and     #%11111100
        ora     #PIC_BANK_BITS
        sta     CIA2_PRA
        lda     #COL_BLACK
        sta     VIC_BORDER
        sta     VIC_BG0                 ; the picture's shared background
        sta     VIC_SPR_ENA
        lda     #PIC_D018
        sta     VIC_MEMSETUP
        lda     #$D8                    ; multicolour, 40 columns
        sta     VIC_CTRL2
        jsr     NextFrame
        lda     #$3B                    ; bitmap, screen on
        sta     VIC_CTRL1

        lda     #<PIC_FRAMES
        sta     zTmp0
        lda     #>PIC_FRAMES
        sta     zTmp1
@held:  jsr     Pressed                 ; a key may still be down
        beq     @wait
        jsr     NextFrame
        jmp     @held
@wait:  jsr     NextFrame
        jsr     Pressed
        bne     @key
        lda     zTmp0
        bne     :+
        dec     zTmp1
:       dec     zTmp0
        lda     zTmp0
        ora     zTmp1
        bne     @wait
        lda     #0                      ; timed out
        beq     @end
@key:   jsr     StartPressed
        sta     zTmp2
@up:    jsr     NextFrame               ; let go before the game reads keys
        jsr     Pressed
        bne     @up
        lda     zTmp2
@end:   pha
        lda     #$0B                    ; blank, back to text on bank 2
        sta     VIC_CTRL1
        ldx     #0
        lda     #$20
@clr:   sta     VIC_SCREEN,x
        sta     VIC_SCREEN+$100,x
        sta     VIC_SCREEN+$200,x
        sta     VIC_SCREEN+$2E8,x
        inx
        bne     @clr
        lda     CIA2_PRA
        and     #%11111100
        ora     #VIC_BANK_BITS
        sta     CIA2_PRA
        lda     #$08                    ; 40 columns, hires
        sta     VIC_CTRL2
        lda     #D018_NORMAL
        sta     VIC_MEMSETUP
        jsr     NextFrame
        lda     #$1B                    ; text, screen on
        sta     VIC_CTRL1
        pla
        rts

; Wait for the next frame (raster line 251 from above).
NextFrame:
:       lda     VIC_RASTER
        cmp     #251
        beq     :-
:       lda     VIC_RASTER
        cmp     #251
        bne     :-
        rts

; Z clear if any key or either fire button is down.
Pressed:
        lda     #$00                    ; every keyboard column
        sta     CIA1_PRA
        lda     CIA1_PRB                ; keys, and joystick 1
        ldx     #$FF
        stx     CIA1_PRA
        cmp     #$FF
        bne     @yes
        lda     CIA1_PRA                ; joystick 2 fire
        and     #$10
        eor     #$10
        rts
@yes:   lda     #1
        rts

; A = 1 if 1 or joystick 2 fire is down, else 0.
StartPressed:
        lda     #$7F                    ; column 7: 1 is row 0
        sta     CIA1_PRA
        lda     CIA1_PRB
        ldx     #$FF
        stx     CIA1_PRA
        and     #$01
        beq     @yes
        lda     CIA1_PRA
        and     #$10
        beq     @yes
        lda     #0
        rts
@yes:   lda     #1
        rts

; Unpack from zSrc (left after the end marker) to A/X: $FE n v writes n
; copies of v, $FE $00 ends, any other byte is copied.
Unpack:
        sta     zDst
        stx     zDst+1
        ldy     #0
@next:  jsr     GetByte
        cmp     #$FE
        beq     @run
        sta     (zDst),y
        jsr     NextDest
        jmp     @next
@run:   jsr     GetByte
        beq     @end
        tax
        jsr     GetByte
@copy:  sta     (zDst),y
        jsr     NextDest
        dex
        bne     @copy
        jmp     @next
@end:   rts

; Next packed byte in A (flags from it); keeps X, Y = 0.
GetByte:
        lda     (zSrc),y
        inc     zSrc
        bne     :+
        inc     zSrc+1
:       cmp     #0
        rts

NextDest:
        inc     zDst
        bne     :+
        inc     zDst+1
:       rts

        .segment "RODATA"

IntroData:
        .incbin "intro.rle"
