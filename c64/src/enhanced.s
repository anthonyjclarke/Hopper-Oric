;==============================================================================
; enhanced.s - the C64 Enhanced look (docs/enhanced.md), on while zEnhanced
; is set. Nothing here changes what the game reads: it only changes how the
; Oric screen's codes are drawn.
;
; V1, multicolour lanes (docs/enhanced_graphics.md): on the play screen, lane
; rows use a second character set at CHARSET_MC, built from the game's own
; glyphs at CHARSET. A glyph's pixel pairs become multicolour: both set ->
; the cell's colour RAM (the lane's ink + 8), one set -> $D022 (shade),
; neither -> paper. In the top row of characters of a lane, the topmost full
; pair of each pixel column becomes $D023 (highlight). The hedge ($7F) is a
; drawn leaf pattern. The raster IRQ sets $D022/$D023 per row (rowMc1/2).
;
; The game changes three groups of glyphs while it runs (the frog, the home
; frogs, the turtle frames); McDynamic notices and converts them again, so
; no game byte is patched for this.
;==============================================================================

        .include "c64.inc"

        .import rowMap, rowCset, curMap
        .export McRowSetup, McBuild, McDynamic, rowMc1, rowMc2, mcStale

        .segment "CODE"

;------------------------------------------------------------------------------
; McRowSetup - for FastRow / ParseRow: A = the C64 ink of simple row X.
; On a lane row of the play screen in Enhanced, returns A = ink + 8
; (multicolour) and selects CS_MC and the lane's $D022/$D023; otherwise
; returns A unchanged and CS_NORMAL. Preserves X; clobbers Y.
;------------------------------------------------------------------------------
McRowSetup:
        pha
        lda     #CS_NORMAL
        sta     rowCset,x
        bit     zMcPlay
        bpl     @hires
        ldy     rowMap,x
        lda     LaneShade,y
        beq     @hires                  ; 0: not a lane row
        sta     rowMc1,x
        lda     LaneLight,y
        sta     rowMc2,x
        lda     #CS_MC
        sta     rowCset,x
        pla
        ora     #8
        rts
@hires: pla
        rts

;------------------------------------------------------------------------------
; McInit - from the first McBuild: the conversion tables. McPairs: a hires byte's four
; pixel pairs as multicolour (%11 both set, %01 one, %00 none). McFull: the
; full pairs only, as %11.
;------------------------------------------------------------------------------
McInit:
        ldx     #0
@byte:  stx     zTmp0
        lda     #0
        sta     zTmp1
        sta     zTmp2
        ldy     #4
@pair:  asl     zTmp1
        asl     zTmp1
        asl     zTmp2
        asl     zTmp2
        lda     #0
        asl     zTmp0
        rol     a
        asl     zTmp0
        rol     a                       ; A = this pair, 0-3
        beq     @next
        cmp     #3
        bne     @half
        lda     zTmp1
        ora     #3
        sta     zTmp1
        lda     zTmp2
        ora     #3
        sta     zTmp2
        bne     @next
@half:  inc     zTmp1                   ; %01
@next:  dey
        bne     @pair
        lda     zTmp1
        sta     McPairs,x
        lda     zTmp2
        sta     McFull,x
        inx
        bne     @byte
        rts

;------------------------------------------------------------------------------
; McBuild - the whole multicolour set: codes $00-$1F blank, $20-$7F
; converted from CHARSET, $80-$FF the hires inverse half (only cells with
; colour RAM below 8 use it, and they draw it as hires). About 30,000
; cycles; run once per game, from Present, when mcStale is set.
;------------------------------------------------------------------------------
McBuild:
        lda     mcInited                ; the tables, the first time
        bne     :+
        jsr     McInit
        inc     mcInited
:       lda     #0
        sta     mcStale
        tax
@blank: sta     CHARSET_MC,x
        inx
        bne     @blank
@inv:   lda     CHARSET+$400,x
        sta     CHARSET_MC+$400,x
        lda     CHARSET+$500,x
        sta     CHARSET_MC+$500,x
        lda     CHARSET+$600,x
        sta     CHARSET_MC+$600,x
        lda     CHARSET+$700,x
        sta     CHARSET_MC+$700,x
        inx
        bne     @inv
        ldx     #$20
@ch:    jsr     McChar
        inx
        bpl     @ch
        ldx     #DYN_COUNT-1            ; the watched glyphs as built
@seen:  stx     mcIdx
        lda     DynCodes,x
        jsr     GlyphPtr
        lda     mcIdx
        asl     a
        asl     a
        asl     a
        tax
        ldy     #0
:       lda     (zPtr),y
        sta     mcSeen,x
        inx
        iny
        cpy     #8
        bne     :-
        ldx     mcIdx
        dex
        bpl     @seen
        lda     turtle_frame            ; turtles and frog are current
        sta     mcTurtle
        ldx     #31
:       lda     CHARSET+$3A*8,x
        sta     mcFrog,x
        dex
        bpl     :-
        rts

;------------------------------------------------------------------------------
; McDynamic - from Present, on the play screen in Enhanced: build the set
; if a new game asked for it, else convert again the glyphs the game has
; rewritten since the last pass. Turtles: the game's own turtle_frame. The
; frog ($3A-$3D: direction, splat, frog in a home): its 32 bytes compared.
; The sentinels every pass, the home frogs every 8th (DynCodes). About 650
; cycles when nothing changed.
;------------------------------------------------------------------------------
McDynamic:
        lda     mcStale
        beq     :+
        jmp     McBuild
:       lda     turtle_frame
        cmp     mcTurtle
        beq     @frog
        sta     mcTurtle
        ldx     #$6E
:       jsr     McChar
        inx
        cpx     #$74
        bne     :-
@frog:  ldx     #31
        ldy     #0
@fcmp:  lda     CHARSET+$3A*8,x
        cmp     mcFrog,x
        beq     :+
        sta     mcFrog,x
        iny
:       dex
        bpl     @fcmp
        tya
        beq     @slow
        ldx     #$3A
:       jsr     McChar
        inx
        cpx     #$3E
        bne     :-
@slow:  ldx     #DYN_SENTINELS-1        ; the sentinels every pass, the
        dec     mcSlow                  ; home frogs every 8th
        bpl     @code
        lda     #7
        sta     mcSlow
        ldx     #DYN_COUNT-1
@code:  stx     mcIdx
        lda     DynCodes,x
        jsr     GlyphPtr
        lda     mcIdx
        asl     a
        asl     a
        asl     a
        tax                             ; mcSeen index
        ldy     #0
        sty     mcDiff
@cmp:   lda     (zPtr),y
        cmp     mcSeen,x
        beq     :+
        sta     mcSeen,x
        inc     mcDiff
:       inx
        iny
        cpy     #8
        bne     @cmp
        lda     mcDiff
        beq     @next
        ldx     mcIdx
        cpx     #DYN_SENTINELS
        bcs     :+
        jmp     McBuild                 ; the game's graphics came in: all
:       lda     DynCodes,x
        tax
        jsr     McChar
@next:  ldx     mcIdx
        dex
        bpl     @code
@r:     rts

; zPtr = CHARSET + A * 8 (A = $00-$7F). Clobbers A.
GlyphPtr:
        sta     zPtr
        lda     #0
        sta     zPtr+1
        asl     zPtr
        rol     zPtr+1
        asl     zPtr
        rol     zPtr+1
        asl     zPtr
        rol     zPtr+1
        lda     zPtr+1
        clc
        adc     #>CHARSET               ; CHARSET is page aligned
        sta     zPtr+1
        rts

;------------------------------------------------------------------------------
; McChar - convert CHARSET glyph X ($20-$7F) into CHARSET_MC. Preserves X;
; clobbers A, Y, zTmp0-zTmp2, zSrc, zPtr.
;------------------------------------------------------------------------------
McChar:
        stx     mcCode
        lda     #0
        sta     zSrc+1
        txa
        asl     a
        rol     zSrc+1
        asl     a
        rol     zSrc+1
        asl     a
        rol     zSrc+1
        sta     zSrc
        sta     zPtr
        lda     zSrc+1
        clc
        adc     #>CHARSET_MC
        sta     zPtr+1
        lda     zSrc+1
        adc     #>CHARSET
        sta     zSrc+1
        ldy     #7
        cpx     #HEDGE_CODE
        bne     @conv
@leaf:  lda     LeafGlyph,y
        sta     (zPtr),y
        dey
        bpl     @leaf
        rts
@conv:  lda     McEdge,x
        sta     zTmp2                   ; highlight the top contour?
        lda     #0
        sta     zTmp1                   ; full pairs seen so far, as %11
        ldy     #0
@row:   lda     (zSrc),y
        tax
        lda     zTmp2
        beq     @plain
        lda     McFull,x
        sta     zTmp0
        lda     zTmp1
        eor     #$FF
        and     zTmp0                   ; full pairs not seen above: the edge
        and     #$55
        eor     McPairs,x               ; %11 -> %10 there ($D023)
        pha
        lda     zTmp1
        ora     zTmp0
        sta     zTmp1
        pla
        jmp     @put
@plain: lda     McPairs,x
@put:   sta     (zPtr),y
        iny
        cpy     #8
        bne     @row
        ldx     mcCode
        rts

        .segment "RODATA"

HEDGE_CODE      = $7F

; 1 for the codes on the top row of a lane (logs $60-$62, turtles $6E-$70,
; trucks $21-$25, blue cars $66-$69, yellow cars $74-$77): their top
; contour takes the highlight.
McEdge:
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $00
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $10
        .byte   0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $20
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $30
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $40
        .byte   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0    ; $50
        .byte   1, 1, 1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1    ; $60
        .byte   1, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0    ; $70

; The hedge: leaves, mostly green (colour RAM), light green ($D022) and a
; little brown ($D023). The last row is green or paper only.
LeafGlyph:
        .byte   %11011111, %11110001, %01111111, %11101101
        .byte   %11110111, %00111110, %11011111, %11110011

; Per Oric row: $D022 (shade) and $D023 (highlight); shade 0 = not a lane.
; Every lane colour is one of the Oric's eight inks, the only colours a
; multicolour cell's colour RAM can take.
LaneShade:
        .byte   COL_LGREEN, COL_LGREEN, COL_LGREEN, 0          ; 0-2 hedge, 3
        .byte   COL_BROWN, COL_BROWN, 0                        ; 4-5 black logs
        .byte   COL_BROWN, COL_BROWN, 0                        ; 7-8 turtles
        .byte   COL_ORANGE, COL_ORANGE, 0                      ; 10-11 yellow logs
        .byte   COL_BROWN, COL_BROWN                           ; 13-14 red logs
        .byte   0, 0                                           ; 15-16 median
        .byte   COL_GREY, COL_GREY, 0                          ; 17-18 trucks
        .byte   COL_GREY, COL_GREY, 0                          ; 20-21 cars
        .byte   COL_GREY, COL_GREY                             ; 23-24 cars
        .byte   0, 0, 0                                        ; 25-27
LaneLight:
        .byte   COL_BROWN, COL_BROWN, COL_BROWN, 0
        .byte   COL_ORANGE, COL_ORANGE, 0
        .byte   COL_LRED, COL_LRED, 0
        .byte   COL_WHITE, COL_WHITE, 0
        .byte   COL_LRED, COL_LRED
        .byte   0, 0
        .byte   COL_WHITE, COL_WHITE, 0
        .byte   COL_WHITE, COL_WHITE, 0
        .byte   COL_WHITE, COL_WHITE
        .byte   0, 0, 0
        .assert * - LaneLight = ORIC_ROWS, error, "one entry per Oric row"

; Watched glyphs. First the sentinels, checked every pass: a glyph from each
; block InitGame copies in (udg_symbols, udg_graphics). The set is first
; built when the play screen's row map is set, before InitGame has copied
; them; when one changes the whole set is built again. Then the home frogs
; (DrawHomeFrog), checked every 8th pass, which arrive the first time a frog
; gets home.
DynCodes:
        .byte   $21, $61, $75
DYN_SENTINELS = * - DynCodes
        .byte   $2B, $2C, $2E, $2F
DYN_COUNT = * - DynCodes

        .segment "BSS"
McPairs:        .res 256        ; McInit
McFull:         .res 256
mcStale:        .res 1          ; set by SetRowMap: build the set before use
mcInited:       .res 1          ; McInit has run
mcCode:         .res 1
mcIdx:          .res 1
mcDiff:         .res 1
mcSeen:         .res DYN_COUNT * 8
mcTurtle:       .res 1          ; turtle_frame at the last conversion
mcFrog:         .res 32         ; the frog's glyphs at the last conversion
mcSlow:         .res 1          ; passes until the slow list
rowMc1:         .res C64_ROWS   ; $D022 per C64 row (read by the raster IRQ)
rowMc2:         .res C64_ROWS   ; $D023
