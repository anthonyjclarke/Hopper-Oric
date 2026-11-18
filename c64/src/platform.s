;==============================================================================
; platform.s - start-up, zero page, and the hooks the patched game calls
;
; The .prg loads at $0801 with the game image right behind the BASIC stub.
; Start moves the image down to $0500, where it ran on the Oric, takes the
; machine over (BASIC and KERNAL banked out, own IRQ/NMI), shows the
; start-up picture, builds the font
; the Oric ROM would have left at CHARSET, and jumps to ColdStart.
;==============================================================================

        .include "c64.inc"

        .import UnpackPicture, ShowPicture
        .import InitVideo, InitTiming, InitInput, InitSound, SetRowMap, Idle, IdleParse
        .import ColdStart, InitGame, SoundMenu, CreditsIntro, DrawHiScoreTable
        .import CheckMenuKeys, AttractLoop, StartGame
        .import StepFrog, LoseLife, L118A
        .import PROG_START, PROG_END
        .import __GAME_LOAD__, __GAME_RUN__, __GAME_SIZE__, __BSS_RUN__, __BSS_SIZE__
        .export Start
        .export InitGameC64, RomIrqOn, ReadRomKey, ReadMenuKey
        .export SoundMenuC64, CreditsIntroC64, HiscoreTableC64, TitleTickC64, EraseFlyC64
        .export StepFrogC64, CarryFrogC64

        .assert PROG_START = $0500, error, "the game must run at $0500"
        .assert PROG_END = $30D5, error, "the game must end at $30D4"
        .assert __GAME_RUN__ = $0500, error, "GAME segment must run at $0500"

        .segment "CODE"

;------------------------------------------------------------------------------
; Start - SYS 2061 lands here (through the stub's jmp).
;------------------------------------------------------------------------------
Start:
        sei
        cld
        ldx     #$FF
        txs
        lda     #MEM_IO_ONLY
        sta     CPU_PORT
        lda     #$7F
        sta     CIA1_ICR                ; no CIA interrupts
        sta     CIA2_ICR
        lda     CIA1_ICR
        lda     CIA2_ICR
        lda     #0
        sta     VIC_IRQ_MASK

        ; move the game image from behind the stub to $0500 (upwards: the
        ; destination is below the source)
        lda     #<__GAME_LOAD__
        sta     zSrc
        lda     #>__GAME_LOAD__
        sta     zSrc+1
        lda     #<__GAME_RUN__
        sta     zDst
        lda     #>__GAME_RUN__
        sta     zDst+1
        ldx     #>__GAME_SIZE__
        ldy     #0
@page:  lda     (zSrc),y
        sta     (zDst),y
        iny
        bne     @page
        inc     zSrc+1
        inc     zDst+1
        dex
        bne     @page
        ldx     #<__GAME_SIZE__
        beq     @moved
@tail:  lda     (zSrc),y
        sta     (zDst),y
        iny
        dex
        bne     @tail
@moved:
        ; clear the platform's BSS
        lda     #<__BSS_RUN__
        sta     zDst
        lda     #>__BSS_RUN__
        sta     zDst+1
        lda     #0
        tay
        ldx     #>__BSS_SIZE__
        beq     @bssTail
@bssPage:
        sta     (zDst),y
        iny
        bne     @bssPage
        inc     zDst+1
        dex
        bne     @bssPage
@bssTail:
        ldx     #<__BSS_SIZE__
        beq     @bssDone
@bssByte:
        sta     (zDst),y
        iny
        dex
        bne     @bssByte
@bssDone:
        lda     #$40                    ; RTI at $022B until ColdStart sets
        sta     NMI_VECTOR              ; the Oric's RESET jump there
        lda     #1
        sta     zRomIrq                 ; the Oric ROM IRQ is on at power-up
        lda     #0
        sta     zBlink
        sta     zIdleTick
        sta     zRR
        sta     zLastPresent
        sta     zLastPresent+1
        sta     zLastPresent+2
        jsr     UnpackPicture           ; into bank 3, kept for the attract loop
.ifndef AUTOTEST
        jsr     ShowPicture             ; the start-up picture (intro.s)
.endif
        jsr     InitVideo
        jsr     InitInput
        jsr     InitSound
        jsr     InitTiming
        cli
        jmp     ColdStart

;------------------------------------------------------------------------------
; Hooks called from the patched game (see c64/src/hopper.s)
;------------------------------------------------------------------------------

; NewGame: the Oric masked its ROM IRQ for the whole game (sei); here the
; raster IRQ keeps running and only the ROM's jobs stop.
InitGameC64:
        lda     #0
        sta     zRomIrq
        sta     zWaitHook
        lda     #MAP_GAME
        jsr     SetRowMap
        jmp     InitGame

;------------------------------------------------------------------------------
; EraseFlyC64 - the Oric's EraseFly: two spaces at (fly_ptr),y. With no fly
; showing, fly_ptr is $0000 (CheckFlyEaten erases on every frog that reaches
; the home row, and SheetComplete clears it), so on the Oric the spaces went
; into tmp0 and key_state at $00/$01. On the C64 $00/$01 is the 6510's port:
; $20 there switches BASIC, KERNAL and I/O in and the machine hangs in the
; KERNAL. Here the same two spaces go to tmp0 and key_state where they live
; now ($07/$08). Returns A = $20, Y = 1, as EraseFly did.
;------------------------------------------------------------------------------
EraseFlyC64:
        lda     #$20
        ldy     fly_ptr+1
        bne     @screen
        sta     tmp0                    ; fly_ptr = $00xx: the Oric's zero page
        sta     key_state
        ldy     #1
        rts
@screen:
        ldy     #$00
        sta     (fly_ptr),y
        iny
        sta     (fly_ptr),y
        rts

;------------------------------------------------------------------------------
; The frog's side edges (C64 Remix; docs/remix.md). frog_col is the frog's
; screen column - 1. The Oric killed the frog at frog_col 1 and $25, so it
; died on reaching column 2 or covering column 39, the playfield's own edge
; columns. Here the frog may stand there (CheckFrogBounds allows 1-$25):
;
; StepFrogC64 - a sideways hop that would leave columns 2-39 is not made;
; the frog turns and stays. Replaces jsr StepFrog in MoveFrog.
;------------------------------------------------------------------------------
StepFrogC64:
        lda     frog_dir
        cmp     #3                      ; left: lands at frog_col - 2
        bne     @right
        lda     frog_col
        cmp     #3
        bcc     @stay
        bcs     @step
@right: cmp     #4                      ; right: lands at frog_col + 2
        bne     @step
        lda     frog_col
        cmp     #$24
        bcs     @stay
@step:  jmp     StepFrog
@stay:  rts

;------------------------------------------------------------------------------
; CarryFrogC64 - CarryFrog's start: when lane X scrolls and the frog is on
; it, a log or turtle carrying the frog past column 2 or 39 kills it where it
; stands, before it moves, so the splat stays in the playfield and never
; covers the paper attribute in column 1 (or the next row's column 0).
;------------------------------------------------------------------------------
CarryFrogC64:
        clc
        txa
        adc     #2
        cmp     frog_row
        bne     @r
        cmp     #5                      ; rows 5-8 are the river
        bcc     @go
        lsr     a                       ; C = 1: rows 5, 7 move left
        lda     frog_col
        bcs     @left
        cmp     #$25                    ; covering column 39
        bcs     @off
        bcc     @go
@left:  cmp     #2                      ; at column 2
        bcc     @off
@go:    jmp     L118A
@off:   jmp     LoseLife
@r:     rts

; InitTimers: the ROM IRQ is back (it was a cli and the VIA timer 1 setup).
RomIrqOn:
        lda     #$FF                    ; a key still held from play is not new
        sta     zLastKey
        lda     #1
        sta     zRomIrq
        rts

; The four key-wait loops: draw the screen now and then, then lda ROM_KEY.
ReadRomKey:
        jsr     Idle
        lda     ROM_KEY
        rts

; The controls menu's key wait: as ReadRomKey, parsing rows in between.
ReadMenuKey:
        jsr     IdleParse
        lda     ROM_KEY
        rts

SoundMenuC64:
        lda     #MAP_MENU
        jsr     SetRowMap
        jmp     SoundMenu

CreditsIntroC64:
        lda     #MAP_CREDITS
        jsr     SetRowMap
        jmp     CreditsIntro

HiscoreTableC64:
        lda     #0                      ; TitleTickC64 times the table from here
        sta     titleSteps
        sta     titleSteps+1
        lda     #MAP_HISCORE
        jsr     SetRowMap
        jmp     DrawHiScoreTable

;------------------------------------------------------------------------------
; TitleTickC64 - replaces the jsr CheckMenuKeys in TitleScroll, the loop that
; scrolls the hi-score title. On the Oric it ran until a key; here, after
; about 15 s, the start-up picture comes back and the attract loop goes
; round again: picture, credits and instructions, hi-scores. 1 or fire on
; the picture starts a game.
;------------------------------------------------------------------------------
TitleTickC64:
        inc     titleSteps
        bne     :+
        inc     titleSteps+1
:       lda     titleSteps+1
        cmp     #>TITLE_STEPS
        bcc     @keys
        bne     @picture
        lda     titleSteps
        cmp     #<TITLE_STEPS
        bcs     @picture
@keys:  jmp     CheckMenuKeys
@picture:
        pla                             ; not back into TitleScroll
        pla
        jsr     ShowPicture
        tax
        lda     #0
        sta     ROM_KEY
        lda     #$FF                    ; a key still down is not new
        sta     zLastKey
        cli
        txa
        beq     :+
        jmp     StartGame
:       jmp     AttractLoop

        .segment "BSS"
titleSteps:     .res 2
