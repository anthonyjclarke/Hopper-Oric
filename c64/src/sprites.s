;==============================================================================
; sprites.s - C64 Enhanced: the sprite frog (V2) and fly (V3)
;
; In Enhanced play the game runs exactly as before: it still draws the frog
; (chars $3A-$3D) and the fly ($7C/$7D) in the Oric screen and checks
; collisions from the screen's contents. Only their glyphs are blank, so the
; characters don't show, and sprites are drawn where they are:
;
;   sprite 0  frog outline, hires black, 1 pixel up and left of the body
;   sprite 1  frog body, multicolour (green, light green, yellow top edge)
;   sprite 2  fly body, hires black
;   sprite 3  fly wings, hires light grey (two frames, flapping)
;
; Present (SprTarget) works out where the characters are, from frog_pos and
; fly_ptr, as it copies the screen, adding the lane's fine scroll (V4) on
; the river, where the frog rides a log or turtle. The frame interrupt
; (SprTick) moves the sprites there: a move of a few pixels (riding) is
; taken at once, a hop is eased in over a few frames with a little arc, and
; a jump of more than 4 characters (a new frog) is taken at once.
;
; The images are tools/frog_sprites.py's (sprites.inc), at $8400 (blocks
; 16-29). Code and variables sit in HIDATA ($9000+), out of main memory.
;==============================================================================

        .include "c64.inc"

        .import rowMap, rowCtl2, rowSave0, DrawFrog, SetFrogGfxDir, LendPageGlyphs, ParseRow
        .export SprSetup, SprTarget, SprTick, SetFrogGfxC64, SplatDrawC64
        .export AttractStart, AttractPresent, ParseRowAtt, attractOn

SPR_BLOCK       = ($8400 - $8000) / 64  ; first image block (16)
SPR_PTRS        = VIC_SCREEN + $3F8
FRAME_SPLAT     = 4
FLY_FRAMES      = SPR_BLOCK + 10
FAR             = 33                    ; a move this big or more is not a hop
TEXT_TOP        = FIRST_TEXT_LINE - 1   ; sprite Y of text row 0 (a sprite shows from raster Y+1)
TEXT_LEFT       = 24 - 8                ; sprite X of Oric column 0 (VIC -1)

VIC_SPR_X       = $D000
VIC_SPR_XMSB    = $D010
VIC_SPR_YEXP    = $D017
VIC_SPR_PRIO    = $D01B
VIC_SPR_MC      = $D01C
VIC_SPR_XEXP    = $D01D
VIC_SPR_MC0     = $D025
VIC_SPR_MC1     = $D026
VIC_SPR_COL     = $D027

        .segment "SPRDATA"
        .include "sprites.inc"

        .segment "HIDATA"

;------------------------------------------------------------------------------
; SetFrogGfxC64 - the game's SetFrogGfx (patched at its start, $0F20). In
; Classic it runs as before. In Enhanced play it picks the sprite frame for
; frog_dir instead and leaves the frog's characters blank.
; SplatDrawC64 - SetSplatGfx's jsr DrawFrog ($211B): the splat frame, and
; the characters blanked again, then DrawFrog.
;------------------------------------------------------------------------------
SetFrogGfxC64:
        bit     zMcPlay
        bmi     @enh
        ldx     #$1F                    ; the bytes the patch replaced
        lda     frog_dir
        jmp     SetFrogGfxDir
@enh:   ldx     frog_dir                ; 0 (no move) keeps the frame, as the
        beq     BlankFrog               ; game keeps the glyphs
        cpx     #5
        bcs     BlankFrog
        dex
        stx     sprFrame
BlankFrog:
        lda     #0
        ldx     #$1F
:       sta     CHARSET+$3A*8,x
        dex
        bpl     :-
        rts

SplatDrawC64:
        bit     zMcPlay
        bpl     :+
        lda     #FRAME_SPLAT
        sta     sprFrame
        jsr     BlankFrog
:       jmp     DrawFrog

;------------------------------------------------------------------------------
; SprSetup - from SetRowMap: sprites off, and in Enhanced play their colours
; and modes set up for SprTick.
;------------------------------------------------------------------------------
SprSetup:
        lda     #0
        sta     VIC_SPR_ENA
        sta     frogVis
        sta     flyVis
        sta     hopK
        bit     zMcPlay
        bpl     @r
        sta     VIC_SPR_PRIO            ; in front of the characters
        sta     VIC_SPR_XEXP
        sta     VIC_SPR_YEXP
        lda     #%00000010              ; the frog's body is multicolour
        sta     VIC_SPR_MC
        lda     #COL_LGREEN
        sta     VIC_SPR_MC0
        lda     #COL_YELLOW
        sta     VIC_SPR_MC1
        ldx     #3
:       lda     SprColours,x
        sta     VIC_SPR_COL,x
        dex
        bpl     :-
        lda     #$FF                    ; the next target is taken at once
        sta     frogY
@r:     rts

;------------------------------------------------------------------------------
; SprTarget - end of Present, Enhanced play: where the frog and the fly are,
; as just copied to the VIC screen. Clobbers A, X, Y, zPtr, zTmp2.
;------------------------------------------------------------------------------
SprTarget:
        lda     #0                      ; frogVis / flyVis are only written
        sta     newVis                  ; once, at the end: cleared here, the
        sta     newVis+1                ; frame IRQ could see them off and
        lda     frog_pos                ; hide the sprites for a frame
        sta     zPtr
        lda     frog_pos+1
        sta     zPtr+1
        jsr     PosOf
        bcs     @fly
        lda     frog_row                ; the river (5-8): ride the lane's
        cmp     #5                      ; fine scroll
        bcc     :+
        cmp     #9
        bcs     :+
        lda     rowCtl2,y
        and     #7
        clc
        adc     posX
        sta     posX
        bcc     :+
        inc     posXH
:       lda     posX
        sta     frogTX
        lda     posXH
        sta     frogTXH
        lda     posY
        sta     frogTY
        lda     #1
        sta     newVis
@fly:   lda     fly_ptr+1               ; $0000 when no fly is showing
        beq     @r
        sta     zPtr+1
        lda     fly_ptr
        sta     zPtr
        ldy     #0                      ; and the fly's first character there
        lda     (zPtr),y                ; (fly_on doubles as a copy pointer)
        cmp     #$7C
        bne     @r
        jsr     PosOf
        bcs     @r
        lda     posX
        sta     flyX
        lda     posXH
        sta     flyXH
        lda     posY
        sta     flyY
        lda     #1
        sta     newVis+1
@r:     lda     newVis
        sta     frogVis
        lda     newVis+1
        sta     flyVis
        rts

; PosOf - zPtr = an Oric screen address: posX/posXH/posY = the sprite
; position of that cell, Y = its C64 row, C = 0. C = 1 if the row isn't
; shown, or doesn't show the playfield (it starts with a character: the
; sheet-start signs on a cleared screen).
PosOf:
        sec
        lda     zPtr
        sbc     #<SCREEN
        sta     zPtr
        lda     zPtr+1
        sbc     #>SCREEN
        sta     zPtr+1
        ldx     #0                      ; X = row, zPtr = column
@div:   lda     zPtr
        sec
        sbc     #COLS
        tay
        lda     zPtr+1
        sbc     #0
        bcc     @col
        sta     zPtr+1
        sty     zPtr
        inx
        bne     @div
@col:   stx     zTmp2
        ldy     #C64_ROWS-1
@find:  lda     rowMap,y
        cmp     zTmp2
        beq     @row
        dey
        bpl     @find
        sec
        rts
@row:   lda     rowSave0,y
        and     #$60
        beq     :+
        sec
        rts
:       tya
        asl     a
        asl     a
        asl     a
        adc     #TEXT_TOP               ; (C = 0)
        sta     posY
        lda     #0
        sta     posXH
        lda     zPtr                    ; column * 8 + TEXT_LEFT
        asl     a
        asl     a
        asl     a
        rol     posXH
        adc     #TEXT_LEFT              ; (C = 0 from the rol)
        sta     posX
        bcc     :+
        inc     posXH
:       clc
        rts

;------------------------------------------------------------------------------
; SprTick - the frame interrupt, Enhanced play: move the sprites and set
; their registers. Clobbers A, X, Y.
;------------------------------------------------------------------------------
SprTick:
        lda     #0
        sta     sprEna
        sta     sprMsb
        lda     frogVis
        bne     :+
        jmp     @fly
:

        ; dx = frogTX - frogX (16 bits), dy = frogTY - frogY
        sec
        lda     frogTX
        sbc     frogX
        sta     dx
        lda     frogTXH
        sbc     frogXH
        beq     @dxPos
        cmp     #$FF
        bne     @snap
        lda     dx
        cmp     #256-FAR+1
        bcc     @snap
        bcs     @dy
@dxPos: lda     dx
        cmp     #FAR
        bcs     @snap
@dy:    sec
        lda     frogTY
        sbc     frogY
        sta     dy
        bcs     :+
        cmp     #256-FAR+1
        bcc     @snap
        bcs     @near
:       cmp     #FAR
        bcs     @snap
@near:  lda     dy                      ; riding: a few pixels sideways
        bne     @hop
        lda     dx
        clc
        adc     #3
        cmp     #7
        bcs     @hop
        bcc     @take                   ; (an arc under way runs out)
@snap:  lda     #0                      ; far: a new frog, no arc
        sta     hopK
@take:  lda     frogTX
        sta     frogX
        lda     frogTXH
        sta     frogXH
        lda     frogTY
        sta     frogY
        jmp     @show
@hop:   lda     hopK
        bne     :+
        lda     #HOP_FRAMES             ; a new hop: the arc starts
        sta     hopK
:       lda     dx                      ; halve the distance each frame
        jsr     Half
        clc
        adc     frogX
        sta     frogX
        txa
        adc     frogXH
        sta     frogXH
        lda     dy
        jsr     Half
        clc
        adc     frogY
        sta     frogY

@show:  ldx     hopK
        beq     :+
        dec     hopK
:       lda     frogY                   ; Y - the arc
        sec
        sbc     HopLift,x
        sta     VIC_SPR_X+3             ; body (sprite 1)
        sbc     #1                      ; (C = 1)
        sta     VIC_SPR_X+1             ; outline (sprite 0)
        lda     frogX
        sta     VIC_SPR_X+2
        lda     frogXH
        beq     :+
        lda     #%00000010
        sta     sprMsb
:       lda     frogX                   ; outline X = body X - 1
        sec
        sbc     #1
        sta     VIC_SPR_X+0
        lda     frogXH
        sbc     #0
        beq     :+
        lda     sprMsb
        ora     #%00000001
        sta     sprMsb
:       lda     sprFrame
        asl     a
        adc     #SPR_BLOCK              ; (C = 0)
        sta     SPR_PTRS+1
        adc     #1
        sta     SPR_PTRS+0
        lda     #%00000011
        sta     sprEna

@fly:   lda     flyVis
        beq     @set
        lda     flyX
        sta     VIC_SPR_X+4
        sta     VIC_SPR_X+6
        lda     flyXH
        beq     :+
        lda     sprMsb
        ora     #%00001100
        sta     sprMsb
:       lda     zTick                   ; bob a pixel every 8 frames
        lsr     a
        lsr     a
        lsr     a
        and     #1
        clc
        adc     flyY
        sta     VIC_SPR_X+5
        sta     VIC_SPR_X+7
        lda     zTick                   ; flap every 4 frames
        and     #%00000100
        lsr     a
        adc     #FLY_FRAMES             ; (C = 0)
        sta     SPR_PTRS+2
        adc     #1
        sta     SPR_PTRS+3
        lda     sprEna
        ora     #%00001100
        sta     sprEna
@set:   lda     sprMsb
        sta     VIC_SPR_XMSB
        lda     sprEna
        sta     VIC_SPR_ENA
        rts

; Half - A = a signed distance: A/X = the signed 16-bit step toward it, half
; the distance (all of it from 1 or -1).
Half:
        ldx     #0
        cmp     #$80
        bcc     @pos
        dex                             ; negative
        cmp     #$FF
        beq     @r
        sec
        ror     a
        rts
@pos:   cmp     #2
        bcc     @r
        lsr     a
@r:     rts

HOP_FRAMES      = 6
HopLift:        .byte   0, 1, 3, 4, 4, 3, 2     ; by frames left
SprColours:     .byte   COL_BLACK, COL_GREEN, COL_BLACK, COL_LGREY

;------------------------------------------------------------------------------
; The Enhanced attract screen (F1): the hi-score screen dressed up, in
; Enhanced only. AttractStart - the first tick of TitleScroll on the screen
; (TitleTickC64): lines of the page's borrowed '~' glyph under the title
; (row 2) and round the scroller (rows 23, 25), the scroller row (24) blank,
; the frog sprites (V2's images) set up, attractOn set. SetRowMap clears
; attractOn (any new screen), SprSetup the sprites, ReturnPageGlyphs the '~'.
; AttractPresent - end of Present while attractOn: for each frame since the last call the scroller's fine scroll (row 24, in
; 38 columns: rowCtl2 of C64 row 21) and the frog's hop along row 19, which
; the frame interrupt (SprTick) eases with its arc. Rows 19 and 24 are
; chosen so the frog's sprite DMA is over before the scroller row's IRQ.
;------------------------------------------------------------------------------
ATT_SCROLL      = 24                    ; Oric rows
ATT_SCROLL_C64  = 21                    ; its C64 row (the hi-score map hides 3, 20, 21)
ATT_FROG_C64    = 18                    ; Oric row 19
HOP_GAP         = 25                    ; frames between hops
ATT_COLS        = 39                    ; title colour cells (VIC columns 0-38)

AttractStart:
        bit     zEnhanced
        bmi     :+
        rts
:       jsr     LendPageGlyphs
        ldx     #COLS-1
:       lda     #'~'
        sta     SCREEN+2*40,x
        sta     SCREEN+23*40,x
        sta     SCREEN+25*40,x
        lda     #' '
        sta     SCREEN+ATT_SCROLL*40,x
        dex
        bne     :-
        lda     #6                      ; Oric ink cyan under the title, blue
        sta     SCREEN+2*40             ; round the scroller
        lda     #4
        sta     SCREEN+23*40
        sta     SCREEN+25*40
        lda     #0
        sta     scrollPos
        sta     hopK
        sta     flyVis
        sta     VIC_SPR_PRIO            ; the frog as in play (SprSetup)
        sta     VIC_SPR_XEXP
        sta     VIC_SPR_YEXP
        lda     #7
        sta     scrollFine
        lda     #%00000010
        sta     VIC_SPR_MC
        lda     #COL_LGREEN
        sta     VIC_SPR_MC0
        lda     #COL_YELLOW
        sta     VIC_SPR_MC1
        lda     SprColours
        sta     VIC_SPR_COL
        lda     SprColours+1
        sta     VIC_SPR_COL+1
        lda     #3                      ; facing right
        sta     sprFrame
        lda     #$FF                    ; the first target is taken at once
        sta     frogY
        lda     #2
        sta     attCol
        jsr     AttFrogTarget
        lda     #HOP_GAP
        sta     attHop
        lda     zTick
        sta     attTick
        lda     #1
        sta     frogVis
        sta     attractOn
        rts

AttractPresent:
        lda     zTick                   ; frames since the last call (up to 8)
        sec
        sbc     attTick
        beq     @title
        cmp     #9
        bcc     :+
        lda     #8
:       sta     attN
        lda     zTick
        sta     attTick
@frame: dec     scrollFine              ; the scroller, a pixel a frame
        bpl     :+
        lda     #7
        sta     scrollFine
        jsr     ScrollStep
:       dec     attHop                  ; the frog, a hop every HOP_GAP frames
        bne     :+
        lda     #HOP_GAP
        sta     attHop
        lda     attCol
        clc
        adc     #2
        cmp     #37
        bcc     @col
        lda     #2                      ; back to the left (a jump: no arc)
@col:   sta     attCol
        jsr     AttFrogTarget
:       dec     attN
        bne     @frame
        lda     scrollFine              ; 38 columns, the fine scroll
        sta     rowCtl2+ATT_SCROLL_C64
@title: rts

; ParseRowAtt - Present's parse of a complex row (ParseRow), then, on the
; attract screen and right after title row 1, AttractTitle: the title's
; letters in the colour cycle, (zTick / 2) mod 12 rolling along, over the
; colours the parse just wrote.
ParseRowAtt:
        jsr     ParseRow
        lda     attractOn
        beq     :+
        lda     zRow
        cmp     #1
        beq     AttractTitle
:       rts
AttractTitle:
        lda     zTick
        lsr     a
:       cmp     #12
        bcc     :+
        sbc     #12
        bcs     :-
:       tay
        ldx     #0
@cell:  lda     AttCycle,y
        sta     COLOUR_RAM,x
        sta     COLOUR_RAM+40,x
        dey
        bpl     :+
        ldy     #11
:       inx
        cpx     #ATT_COLS
        bne     @cell
        rts

; ScrollStep - the scroller row one character left, the next one of
; ScrollText at its right end; the Oric row and the VIC row together, so
; the new characters show with the new fine scroll.
ScrollStep:
        ldx     #1
:       lda     SCREEN+ATT_SCROLL*40+1,x
        sta     SCREEN+ATT_SCROLL*40,x
        inx
        cpx     #COLS-1
        bne     :-
        ldy     scrollPos
        lda     ScrollText,y
        bne     :+
        ldy     #0
        lda     ScrollText
:       iny
        sty     scrollPos
        sta     SCREEN+ATT_SCROLL*40+COLS-1
        ldx     #COLS-2                 ; Oric columns 1-39 -> VIC 0-38
:       lda     SCREEN+ATT_SCROLL*40+1,x
        sta     VIC_SCREEN+ATT_SCROLL_C64*40,x
        dex
        bpl     :-
        rts

; AttFrogTarget - the frog's sprite target: column attCol of Oric row 19.
AttFrogTarget:
        lda     #0
        sta     frogTXH
        lda     attCol
        asl     a
        asl     a
        asl     a
        rol     frogTXH
        adc     #TEXT_LEFT              ; (C = 0 from the rol)
        sta     frogTX
        bcc     :+
        inc     frogTXH
:       lda     #ATT_FROG_C64*8+TEXT_TOP
        sta     frogTY
        rts

AttCycle:       .byte   COL_PURPLE, COL_LBLUE, COL_CYAN, COL_LGREEN, COL_YELLOW, COL_WHITE
                .byte   COL_WHITE, COL_YELLOW, COL_LGREEN, COL_CYAN, COL_LBLUE, COL_PURPLE
ScrollText:     .byte   "HOPPER  -  BY A.J.CLARKE  -  P.S.S. 1983  -  NOW ON THE COMMODORE 64  -  "
                .byte   "PRESS 1 TO PLAY, 2 FOR THE INSTRUCTIONS, 3 FOR NEW KEYS  -  ", 0
attractOn:      .byte   0
attTick:        .byte   0
attN:           .byte   0
attHop:         .byte   0
attCol:         .byte   0
scrollPos:      .byte   0
scrollFine:     .byte   0

; Variables (RAM: HIDATA is loaded, and nothing else uses it)
sprFrame:       .byte   0       ; 0-3 up, down, left, right; 4 splat
frogVis:        .byte   0
frogTX:         .byte   0
frogTXH:        .byte   0
frogTY:         .byte   0
frogX:          .byte   0
frogXH:         .byte   0
frogY:          .byte   0
hopK:           .byte   0
flyVis:         .byte   0
flyX:           .byte   0
flyXH:          .byte   0
flyY:           .byte   0
posX:           .byte   0
posXH:          .byte   0
posY:           .byte   0
dx:             .byte   0
dy:             .byte   0
sprEna:         .byte   0
sprMsb:         .byte   0
newVis:         .byte   0, 0    ; SprTarget's frogVis, flyVis until its end
