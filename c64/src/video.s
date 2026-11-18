;==============================================================================
; video.s - showing the Oric's TEXT screen on the C64
;
; The game draws on its 40x28 Oric screen at SCREEN ($BB80), attribute bytes
; and all, exactly as on the Oric. Present copies 25 of those rows to the
; VIC screen and turns the Oric's serial attributes into C64 colours:
;
;   Oric                                C64
;   28 rows                             25: a row map per screen hides 3 rows
;   attribute bytes $00-$1F             blank cells (glyphs 0-31 are blank)
;   ink per cell (serial)               colour RAM per cell
;   paper per cell (serial)             one $D021 per row, set by the raster
;                                       IRQ; other papers drawn as inverse
;                                       cells in the paper colour
;   double height ($0A, $0E)            per row: a top- or bottom-half set
;   blink ($0C-$0F)                     cells blanked on alternate phases
;   inverse (bit 7)                     glyphs 128-255 are the inverse set
;
; Rows whose only attributes are in columns 0-1 (the playfield) are copied
; by unrolled code and get one ink for the whole row; rows with attributes
; further in (the status line, signs, menus) are parsed cell by cell every
; time. A changed column 0 or 1 is seen at once; attributes appearing later
; in a row are found by ParseNextRow, which the waits run in spare time.
;
; Columns 0-1 are drawn only by FastRow and ParseRow, never by the copy, so
; both show them as the Oric does (column 0 black, column 1 the row's
; paper) and a parse cannot leave a cell there that the next copy undoes.
;==============================================================================

        .include "c64.inc"

        .export InitVideo, SetRowMap, Present, ParseNextRow, RefreshCharsets
        .export rowPaper, rowCset

        .segment "CODE"

;------------------------------------------------------------------------------
; InitVideo - VIC bank 2, text mode, the ASCII font at CHARSET, blank screen.
; IRQs masked (the character ROM is switched in to copy the font).
;------------------------------------------------------------------------------
InitVideo:
        lda     CIA2_DDRA
        ora     #%00000011
        sta     CIA2_DDRA
        lda     CIA2_PRA
        and     #%11111100
        ora     #VIC_BANK_BITS
        sta     CIA2_PRA
        lda     #$1B                    ; text, 25 rows, screen on, YSCROLL 3
        sta     VIC_CTRL1
        lda     #$08                    ; 40 columns, hires
        sta     VIC_CTRL2
        lda     #D018_NORMAL
        sta     VIC_MEMSETUP
        lda     #0
        sta     VIC_SPR_ENA
        sta     VIC_BORDER
        sta     VIC_BG0

        ldx     #0                      ; VIC screen blank, colour RAM white
@clr:   lda     #$20
        sta     VIC_SCREEN,x
        sta     VIC_SCREEN+$100,x
        sta     VIC_SCREEN+$200,x
        sta     VIC_SCREEN+$2E8,x
        lda     #COL_WHITE
        sta     COLOUR_RAM,x
        sta     COLOUR_RAM+$100,x
        sta     COLOUR_RAM+$200,x
        sta     COLOUR_RAM+$2E8,x
        inx
        bne     @clr

        jsr     BuildFont
        ldx     #C64_ROWS-1
        lda     #COL_BLACK
@rows:  sta     rowPaper,x
        dex
        bpl     @rows
        lda     #MAP_MENU
        jmp     SetRowMap

;------------------------------------------------------------------------------
; BuildFont - CHARSET codes $20-$7F: ASCII from the C64's lower/upper case
; font, plus the few Oric characters the C64 lacks. Codes $00-$1F (attribute
; cells) are blank in all three sets, $80-$9F solid. The Oric ROM put its font
; here; ColdStart saves it to $3100 as on the Oric.
;------------------------------------------------------------------------------
BuildFont:
        ldx     #0                      ; codes 0-31 blank, 128-159 solid
@att:   lda     #0
        sta     CHARSET,x
        sta     CHARSET_DHTOP,x
        sta     CHARSET_DHBOT,x
        lda     #$FF
        sta     CHARSET+$400,x
        sta     CHARSET_DHTOP+$400,x
        sta     CHARSET_DHBOT+$400,x
        inx
        bne     @att

        lda     #MEM_CHARROM
        sta     CPU_PORT
        lda     #<(CHARSET+$20*8)
        sta     zDst
        lda     #>(CHARSET+$20*8)
        sta     zDst+1
        ldx     #0                      ; ASCII - $20
@ch:    lda     AsciiToScreen,x
        bmi     @custom
        ; source = $D800 + code*8 (lower/upper case set)
        sta     zSrc
        lda     #0
        asl     zSrc
        rol     a
        asl     zSrc
        rol     a
        asl     zSrc
        rol     a
        adc     #$D8
        sta     zSrc+1
        jmp     @copy
@custom:
        and     #$7F                    ; index into CustomGlyphs
        asl     a
        asl     a
        asl     a
        clc
        adc     #<CustomGlyphs
        sta     zSrc
        lda     #>CustomGlyphs
        adc     #0
        sta     zSrc+1
@copy:  ldy     #7
@row:   lda     (zSrc),y
        sta     (zDst),y
        dey
        bpl     @row
        clc
        lda     zDst
        adc     #8
        sta     zDst
        bcc     :+
        inc     zDst+1
:       inx
        cpx     #$60
        bne     @ch
        lda     #MEM_IO_ONLY
        sta     CPU_PORT
        rts

;------------------------------------------------------------------------------
; RefreshCharsets - from the live CHARSET codes $20-$7F, rebuild their
; inverse (codes $A0-$FF) and both double-height sets. Run when the row map
; changes and when a row turns double height; about 50,000 cycles.
;------------------------------------------------------------------------------
RefreshCharsets:
        lda     #0
        sta     zNeedRefresh
        lda     #<(CHARSET+$20*8)
        sta     zSrc
        lda     #>(CHARSET+$20*8)
        sta     zSrc+1
        lda     #<($20*8)
        sta     zDst                    ; offset within a set, same for all
        lda     #>($20*8)
        sta     zDst+1
        ldx     #$60
@ch:    ; normal inverse: CHARSET + $400 + offset
        clc
        lda     zDst
        sta     zCol
        lda     zDst+1
        adc     #>(CHARSET+$400)
        sta     zCol+1
        ldy     #7
@inv:   lda     (zSrc),y
        eor     #$FF
        sta     (zCol),y
        dey
        bpl     @inv
        ; top halves: rows 0-3 doubled; normal at +0, inverse at +$400
        lda     zDst+1
        adc     #>CHARSET_DHTOP
        sta     zCol+1
        ldy     #3
        jsr     Doubled
        ; bottom halves: rows 4-7 doubled
        lda     zDst+1
        clc
        adc     #>CHARSET_DHBOT
        sta     zCol+1
        ldy     #7
        jsr     Doubled
        clc
        lda     zSrc
        adc     #8
        sta     zSrc
        bcc     :+
        inc     zSrc+1
:       clc
        lda     zDst
        adc     #8
        sta     zDst
        bcc     :+
        inc     zDst+1
:       dex
        bne     @ch
        rts

; Write a doubled half glyph at (zCol) and its inverse at (zCol)+$400. Y =
; last source row of the half (3 or 7). Preserves X.
Doubled:
        stx     zTmp2
        lda     #7
        sta     zTmp0                   ; destination row
@r:     lda     (zSrc),y
        sta     zTmp1
        sty     zRow                    ; zRow is free here (not parsing)
        ldy     zTmp0
        sta     (zCol),y
        dey
        sta     (zCol),y
        sty     zTmp0
        lda     zCol+1
        clc
        adc     #4                      ; +$400: inverse half
        sta     zCol+1
        lda     zTmp1
        eor     #$FF
        sta     (zCol),y
        iny
        sta     (zCol),y
        lda     zCol+1
        sec
        sbc     #4
        sta     zCol+1
        ldy     zRow
        dey
        dec     zTmp0
        bpl     @r
        ldx     zTmp2
        rts

;------------------------------------------------------------------------------
; SetRowMap - A = MAP_*: which 25 of the 28 Oric rows to show. Patches the
; copy code (columns 2-39), forces every row to be parsed again and rebuilds the derived
; character sets. About 70,000 cycles.
;------------------------------------------------------------------------------
SetRowMap:
        tax
        lda     MapLo,x
        sta     zPtr
        lda     MapHi,x
        sta     zPtr+1
        ldy     #C64_ROWS-1
@map:   lda     (zPtr),y
        sta     rowMap,y
        tax                             ; Oric row -> source address
        lda     OricRowLo,x
        sta     rowSrcLo,y
        lda     OricRowHi,x
        sta     rowSrcHi,y
        lda     #1
        sta     rowComplex,y            ; parse on the next Present
        lda     #0
        sta     rowDH,y
        dey
        bpl     @map

        ; patch the lda operands of CopyRows: 40 per row, 6 bytes apart
        ldx     #0
@row:   lda     CopyLo,x
        clc
        adc     #1
        sta     zPtr
        lda     CopyHi,x
        adc     #0
        sta     zPtr+1
        lda     rowSrcLo,x              ; copy starts at column 2
        clc
        adc     #2
        sta     zSrc
        lda     rowSrcHi,x
        adc     #0
        sta     zSrc+1
        lda     #COPY_COLS
        sta     zTmp0
@op:    ldy     #0
        lda     zSrc
        sta     (zPtr),y
        iny
        lda     zSrc+1
        sta     (zPtr),y
        inc     zSrc
        bne     :+
        inc     zSrc+1
:       clc
        lda     zPtr
        adc     #6
        sta     zPtr
        bcc     :+
        inc     zPtr+1
:       dec     zTmp0
        bne     @op
        inx
        cpx     #C64_ROWS
        bne     @row
        lda     #0
        sta     zRR
        jmp     RefreshCharsets

;------------------------------------------------------------------------------
; Present - show the Oric screen. Clobbers A, X, Y and the zp temporaries.
;------------------------------------------------------------------------------
Present:
        ldx     #0
@row:   stx     zRow
        lda     rowComplex,x
        bne     @parse
        lda     CopyLo,x
        sta     @call+1
        lda     CopyHi,x
        sta     @call+2
@call:  jsr     $FFFF                   ; CopyRow n (patched above)
        ldx     zRow
        lda     rowSrcLo,x
        sta     zSrc
        lda     rowSrcHi,x
        sta     zSrc+1
        ldy     #0
        lda     (zSrc),y
        cmp     rowSave0,x
        bne     @fast
        iny
        lda     (zSrc),y
        cmp     rowSave1,x
        bne     @fast
        lda     rowSave0,x              ; column 0 a character: a text row,
        and     #$60                    ; where text with its own colours
        beq     @next                   ; may just have been printed
        jsr     ScanRow
        bcc     @next
        ldx     zRow
        jsr     ParseRow
        jmp     @next
@fast:  jsr     FastRow
        jmp     @next
@parse: jsr     ParseRow
@next:  ldx     zRow
        inx
        cpx     #C64_ROWS
        bne     @row
        lda     zNeedRefresh
        beq     :+
        jsr     RefreshCharsets
:       rts

;------------------------------------------------------------------------------
; ScanRow - C = 1 if the Oric row at zSrc has an attribute (codes $00-$1F,
; $80-$9F) in columns 2-39. Present runs it on simple rows that start with
; a character (a cleared screen, where the game prints signs and menus), so
; text printed there gets its colours and height in the same frame instead
; of waiting for ParseNextRow. Playfield rows start with an attribute and
; are not scanned. Clobbers A, Y, zPtr.
;------------------------------------------------------------------------------
ScanRow:
        clc
        lda     zSrc
        adc     #2
        sta     zPtr
        lda     zSrc+1
        adc     #0
        sta     zPtr+1
        ldy     #COLS-3
@s:     lda     (zPtr),y
        and     #$60
        beq     @hit
        dey
        bpl     @s
        clc
        rts
@hit:   sec
        rts

;------------------------------------------------------------------------------
; ParseNextRow - parse one row, round robin: finds attributes written into
; the middle of a row that was simple.
;------------------------------------------------------------------------------
ParseNextRow:
        ldx     zRR
        inx
        cpx     #C64_ROWS
        bcc     :+
        ldx     #0
:       stx     zRR
        stx     zRow
        jsr     ParseRow
        lda     zNeedRefresh
        beq     :+
        jsr     RefreshCharsets
:       rts

;------------------------------------------------------------------------------
; FastRow - row zRow (X) is simple and column 0 or 1 changed: recolour the
; whole row from its two attribute cells and draw those two cells as
; ParseRow would. Anything unusual there (a mode attribute, a character)
; goes to the full parse.
;------------------------------------------------------------------------------
FastRow:
        lda     #7
        sta     zInk
        lda     #0
        sta     zPaper
        ldy     #0
@cell:  lda     (zSrc),y
        and     #$7F
        cmp     #$20
        bcs     @full
        cmp     #$08
        bcc     @ink
        cmp     #$10
        bcc     @full                   ; mode attribute
        cmp     #$18
        bcs     @nx                     ; video mode attribute: ignored
        and     #7
        sta     zPaper
        bpl     @nx
@ink:   sta     zInk
@nx:    lda     (zSrc),y                ; the paper this cell shows
        asl     a                       ; C = inverse
        lda     zPaper
        bcc     :+
        eor     #7
:       sta     zFg,y                   ; zFg, zBg: cells 0 and 1
        iny
        cpy     #2
        bne     @cell
        ldx     zRow
        ldy     #0
        lda     (zSrc),y
        sta     rowSave0,x
        iny
        lda     (zSrc),y
        sta     rowSave1,x
        ldy     zPaper
        lda     C64Colour,y
        sta     rowPaper,x
        lda     #CS_NORMAL
        sta     rowCset,x
        sta     rowDH,x
        lda     rowColLo,x
        sta     zCol
        lda     rowColHi,x
        sta     zCol+1
        ldy     zInk
        lda     C64Colour,y
        ldy     #COLS-1
@fill:  sta     (zCol),y
        dey
        bpl     @fill
        lda     rowDstLo,x
        sta     zDst
        lda     rowDstHi,x
        sta     zDst+1
        ldy     #1
@att:   lda     zFg,y                   ; the row's paper: blank; else a block
        cmp     zPaper
        beq     @blank
        tax
        lda     C64Colour,x
        sta     (zCol),y
        lda     #$A0
        bne     @put
@blank: lda     #$20
@put:   sta     (zDst),y
        dey
        bpl     @att
        rts
@full:  ldx     zRow
        jmp     ParseRow

;------------------------------------------------------------------------------
; ParseRow - row zRow (also in X), cell by cell, as the Oric's ULA reads it.
;------------------------------------------------------------------------------
ParseRow:
        lda     rowSrcLo,x
        sta     zSrc
        lda     rowSrcHi,x
        sta     zSrc+1
        lda     rowDstLo,x
        sta     zDst
        lda     rowDstHi,x
        sta     zDst+1
        lda     rowColLo,x
        sta     zCol
        lda     rowColHi,x
        sta     zCol+1

        ; The row's C64 background: the paper in force at the first character.
        lda     #0
        sta     zPaper
        ldy     #0
@pre:   lda     (zSrc),y
        and     #$7F
        cmp     #$20
        bcs     @preDone
        cmp     #$10
        bcc     @preNext
        cmp     #$18
        bcs     @preNext
        and     #7
        sta     zPaper
@preNext:
        iny
        cpy     #COLS
        bne     @pre
@preDone:
        lda     zPaper
        sta     zRowBg

        lda     #7
        sta     zInk
        lda     #0
        sta     zPaper
        sta     zMode
        sta     zComplex
        sta     zRowDH
        ldy     #0
@cell:  lda     (zSrc),y
        tax
        and     #$7F
        cmp     #$20
        bcs     @char

        ; --- attribute cell: takes effect at once, shows as paper
        cpy     #2
        bcc     :+
        inc     zComplex                ; attributes past column 1
:       cmp     #$08
        bcs     :+
        sta     zInk
        bcc     @attrShow
:       cmp     #$10
        bcs     :+
        and     #%00000110              ; bit 1 double height, bit 2 blink
        sta     zMode
        bcc     @attrShow
:       cmp     #$18
        bcs     @attrShow               ; video mode attribute: ignored
        and     #7
        sta     zPaper
@attrShow:
        lda     zPaper
        cpx     #$80
        bcc     :+
        eor     #7                      ; inverse attribute cell
:       cmp     zRowBg
        beq     @blank
        tax
        lda     #$A0                    ; inverse space: a block of paper
        sta     (zDst),y
        lda     C64Colour,x
        sta     (zCol),y
        jmp     @next
@blank: lda     #$20
        sta     (zDst),y
        ldx     zInk
        lda     C64Colour,x
        sta     (zCol),y
        jmp     @next

        ; --- character cell
@char:  sta     zGlyph
        lda     zMode
        beq     @plain
        and     #%00000010
        beq     :+
        sta     zRowDH
:       inc     zComplex
@plain: lda     zInk
        sta     zFg
        lda     zPaper
        sta     zBg
        cpx     #$80
        bcc     :+
        eor     #7                      ; inverse: both colours complemented
        sta     zBg
        lda     zFg
        eor     #7
        sta     zFg
:       lda     zMode
        and     #%00000100
        beq     :+
        lda     zBlink
        beq     :+
        lda     zBg                     ; blink, hidden phase
        sta     zFg
:       lda     zBg
        cmp     zRowBg
        bne     @swap
        lda     zGlyph
        sta     (zDst),y
        ldx     zFg
        lda     C64Colour,x
        sta     (zCol),y
        jmp     @next
@swap:  lda     zGlyph                  ; another paper: inverse glyph in it
        ora     #$80
        sta     (zDst),y
        ldx     zBg
        lda     C64Colour,x
        sta     (zCol),y
@next:  iny
        cpy     #COLS
        beq     @done
        jmp     @cell

@done:  ldx     zRow
        ldy     zRowBg
        lda     C64Colour,y
        sta     rowPaper,x
        lda     zRowDH
        beq     @normal
        lda     rowDH,x
        bne     :+
        inc     zNeedRefresh            ; newly double height: rebuild the sets
:       lda     #1
        sta     rowDH,x
        lda     rowMap,x                ; even Oric row: top halves
        and     #1
        clc
        adc     #CS_DHTOP
        sta     rowCset,x
        inc     zComplex
        bne     @cs
@normal:
        sta     rowDH,x                 ; A = 0 = CS_NORMAL
        sta     rowCset,x
@cs:    lda     zComplex
        sta     rowComplex,x
        ldy     #0
        lda     (zSrc),y
        sta     rowSave0,x
        iny
        lda     (zSrc),y
        sta     rowSave1,x
        rts

;------------------------------------------------------------------------------
; CopyRows - per C64 row, 38 x (lda Oric cell / sta VIC cell) for columns
; 2-39, and rts. Columns 0-1 are FastRow's and ParseRow's. The lda operands
; are set by SetRowMap.
;------------------------------------------------------------------------------
COPY_COLS       = COLS - 2
COPYROW_SIZE    = COPY_COLS*6 + 1

.macro COPYROW r
        .repeat COPY_COLS, i
        lda     a:SCREEN+2+i
        sta     a:VIC_SCREEN + (r)*COLS + 2 + i
        .endrepeat
        rts
.endmacro

CopyRows:
        .repeat C64_ROWS, r
        COPYROW r
        .endrepeat

        .segment "RODATA"

CopyLo:
        .repeat C64_ROWS, r
        .byte   <(CopyRows + r*COPYROW_SIZE)
        .endrepeat
CopyHi:
        .repeat C64_ROWS, r
        .byte   >(CopyRows + r*COPYROW_SIZE)
        .endrepeat
OricRowLo:
        .repeat ORIC_ROWS, r
        .byte   <(SCREEN + r*COLS)
        .endrepeat
OricRowHi:
        .repeat ORIC_ROWS, r
        .byte   >(SCREEN + r*COLS)
        .endrepeat
rowDstLo:
        .repeat C64_ROWS, r
        .byte   <(VIC_SCREEN + r*COLS)
        .endrepeat
rowDstHi:
        .repeat C64_ROWS, r
        .byte   >(VIC_SCREEN + r*COLS)
        .endrepeat
rowColLo:
        .repeat C64_ROWS, r
        .byte   <(COLOUR_RAM + r*COLS)
        .endrepeat
rowColHi:
        .repeat C64_ROWS, r
        .byte   >(COLOUR_RAM + r*COLS)
        .endrepeat

; Oric colour (0 black, 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan,
; 7 white) -> C64 colour
C64Colour:
        .byte   COL_BLACK, COL_RED, COL_GREEN, COL_YELLOW
        .byte   COL_BLUE, COL_PURPLE, COL_CYAN, COL_WHITE

; Row maps: the Oric row shown on each C64 row. Three rows are hidden on each
; screen, chosen from the rows that screen leaves blank (tools/oric_screens.py
; prints them); in play, the strip of river under the homes (3) and the two
; road markings (19, 22).
.macro ROWMAP h1, h2, h3
        .repeat ORIC_ROWS, r
        .if r <> h1 .and r <> h2 .and r <> h3
        .byte   r
        .endif
        .endrepeat
.endmacro
MapMenu:        ROWMAP 9, 10, 11
MapCredits:     ROWMAP 4, 8, 9
MapHiscore:     ROWMAP 3, 20, 21
MapGame:        ROWMAP 3, 19, 22
MapLo:  .byte   <MapMenu, <MapCredits, <MapHiscore, <MapGame
MapHi:  .byte   >MapMenu, >MapCredits, >MapHiscore, >MapGame

; ASCII $20-$7F -> C64 screen code in the lower/upper case set, or $80+n for
; CustomGlyphs n.
AsciiToScreen:
        .repeat 32, i                   ; $20-$3F: same codes
        .byte   $20 + i
        .endrepeat
        .byte   $00                     ; @
        .repeat 26, i                   ; A-Z
        .byte   $41 + i
        .endrepeat
        .byte   $1B, $80, $1D, $1E, $81 ; [ \ ] ^(up arrow) _
        .byte   $82                     ; `
        .repeat 26, i                   ; a-z
        .byte   $01 + i
        .endrepeat
        .byte   $83, $84, $85, $86, $87 ; { | } ~ DEL

CustomGlyphs:
        .byte   $00,$40,$20,$10,$08,$04,$02,$00 ; \
        .byte   $00,$00,$00,$00,$00,$00,$FF,$00 ; _
        .byte   $30,$18,$0C,$00,$00,$00,$00,$00 ; `
        .byte   $0C,$18,$18,$70,$18,$18,$0C,$00 ; {
        .byte   $18,$18,$18,$18,$18,$18,$18,$18 ; |
        .byte   $30,$18,$18,$0E,$18,$18,$30,$00 ; }
        .byte   $00,$00,$32,$4C,$00,$00,$00,$00 ; ~
        .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF ; DEL

        .segment "BSS"
rowMap:         .res C64_ROWS
rowSrcLo:       .res C64_ROWS
rowSrcHi:       .res C64_ROWS
rowComplex:     .res C64_ROWS
rowSave0:       .res C64_ROWS
rowSave1:       .res C64_ROWS
rowPaper:       .res C64_ROWS
rowCset:        .res C64_ROWS
rowDH:          .res C64_ROWS
