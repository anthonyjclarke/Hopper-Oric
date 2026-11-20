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
        .import SetFontC64
        .import InitVideo, InitTiming, InitInput, InitSound, SetRowMap, Idle, IdleParse
        .import ColdStart, InitGame, SoundMenu, CreditsIntro, DrawHiScoreTable
        .import CheckMenuKeys, AttractLoop, StartGame, ControlsMenu, ClearScreen, credits_text
        .import Unpack, LendPageGlyphs, PageData, AttractStart
        .import PAGE_KEY_LEFT, PAGE_KEY_RIGHT, PAGE_KEY_UP, PAGE_KEY_DOWN
        .import StepFrog, LoseLife, L118A
        .import GameOver, SilenceAll, CreditsEnd
        .import PROG_START, PROG_END
        .import __GAME_LOAD__, __GAME_RUN__, __GAME_SIZE__, __BSS_RUN__, __BSS_SIZE__
        .export Start
        .export InitGameC64, RomIrqOn, ReadRomKey, ReadMenuKey
        .export SoundMenuC64, CreditsIntroC64, HiscoreTableC64, TitleTickC64, EraseFlyC64
        .export StepFrogC64, CarryFrogC64, TakeF1, QuitGameC64
        .export CreditsEndC64, versionShown, MenuKeyC64

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
        lda     #$FF                    ; power up in Enhanced; RESTORE keeps
        sta     zEnhanced               ; the choice (only Start sets it)
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
        jsr     ClearScreen             ; the page leaves before its frame pieces
        lda     #MAP_GAME               ; go back (SetRowMap), not as { } ~ |
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
; F1 flips the version here (Present catches most of them, this the F1
; that arrives just after): the game's key waits never see F1.
ReadRomKey:
        jsr     Idle
        lda     ROM_KEY
        cmp     #KEY_F1 | $80
        bne     :+
        jsr     TakeF1
:       lda     ROM_KEY                 ; the callers branch on these flags
        rts

;------------------------------------------------------------------------------
; TakeF1 - F1 in ROM_KEY on a front-end screen: take it out, so no key wait
; of the game sees it, and flip the version only where the version line is
; on the screen (versionShown): the credits and instructions, once the frog
; has laid them down (CreditsEndC64). Called by Present (every screen while
; the ROM IRQ is on: menus, credits, hi-scores, name entry) and ReadRomKey.
; Clobbers A, X, Y and the video temporaries, as Present does.
;------------------------------------------------------------------------------
TakeF1:
        lda     #0
        sta     ROM_KEY
        lda     versionShown
        bne     :+
        rts
:       jsr     ClearScreen             ; flip, the font with it (V7), and show
        lda     zEnhanced               ; the instructions again in the new look:
        eor     #$FF                    ; Classic's frog-laid credits or the
        sta     zEnhanced               ; Enhanced page. The stack is reset, as
        jsr     SetFontC64              ; for 3 (MenuKeyC64); the screen is
        jsr     SilenceAll              ; cleared first, so no frame shows the
                                        ; page in the other font
        lda     #HOOK_NONE
        sta     zWaitHook
        ldx     #$FF
        txs
        cli
        jmp     AttractLoop

;------------------------------------------------------------------------------
; QuitGameC64 - RUN/STOP in play (C64 Remix): end the game as if the last
; life were lost, without the death: GAME OVER, the hi-score check (the score
; so far counts), the hi-score table. ReadKeysC64 jumps here from the game's
; key reads (play and pause); the game never returns from GameOver, so the
; stack is reset.
;------------------------------------------------------------------------------
QuitGameC64:
        ldx     #$FF
        txs
        jsr     SilenceAll
        cli
        jmp     GameOver

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
        bit     zEnhanced
        bpl     :+
        jmp     EnhancedPage
:       jmp     CreditsIntro

;------------------------------------------------------------------------------
; EnhancedPage - in Enhanced, the credits and instructions as one page drawn
; at once (layout C, tools/instructions_page.py) in place of the frog laying
; down the original's: the page into the Oric screen, the chosen key names
; into its keycaps, its frame pieces into six borrowed codes
; (LendPageGlyphs; SetRowMap returns them), then CreditsEnd: the title frog
; and the jingle. F1 works at once (versionShown); 1, 2 and 3 as on the
; original page.
;------------------------------------------------------------------------------
        .segment "HIDATA"
EnhancedPage:
        lda     #<PageData
        sta     zSrc
        lda     #>PageData
        sta     zSrc+1
        lda     #<SCREEN
        ldx     #>SCREEN
        jsr     Unpack
        lda     credits_text+569        ; the names ControlsMenu keeps there
        ora     #$80                    ; (inverse: the keycap)
        sta     SCREEN + PAGE_KEY_LEFT
        lda     credits_text+573
        ora     #$80
        sta     SCREEN + PAGE_KEY_RIGHT
        lda     credits_text+541
        ora     #$80
        sta     SCREEN + PAGE_KEY_UP
        lda     credits_text+601
        ora     #$80
        sta     SCREEN + PAGE_KEY_DOWN
        jsr     LendPageGlyphs
        lda     #1
        sta     versionShown
        jmp     CreditsEnd
        .segment "CODE"

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
        lda     titleSteps              ; the screen's first tick: F1, the
        ora     titleSteps+1            ; Enhanced attract screen (sprites.s)
        bne     :+
        jsr     AttractStart
:       inc     titleSteps
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
        beq     @attract
        jmp     StartGame
@attract:
        jmp     AttractLoop

;------------------------------------------------------------------------------
; DrawVersionLine - the version line at versionAt (row 17 of the credits,
; between the address and the instructions; the only screen that shows it):
;   [F1] VERSION   CLASSIC   ENHANCED
; in cyan, the chosen version inverse (a white bar), the other in blue. Sets
; versionShown, which lets F1 flip the version until the next SetRowMap.
;------------------------------------------------------------------------------
DrawVersionLine:
        lda     versionAt
        sta     zDst
        lda     versionAt+1
        sta     zDst+1
        lda     #1
        sta     versionShown
        ldy     #39
:       lda     VersionText,y
        sta     (zDst),y
        dey
        bpl     :-
        ldy     #VERSION_CLASSIC        ; the chosen word inverse, white ink
        bit     zEnhanced
        bpl     :+
        ldy     #VERSION_ENHANCED
:       dey
        lda     #7
        sta     (zDst),y
        iny
:       lda     (zDst),y
        cmp     #$20                    ; the attribute after the word ends it
        bcc     @r
        ora     #$80
        sta     (zDst),y
        iny
        bne     :-
@r:     rts

        .segment "RODATA"

VERSION_CLASSIC  = 17                   ; first column of each word's bar
VERSION_ENHANCED = 27
VersionText:
        .byte   "   ", 6, "[F1] VERSION", 4, " CLASSIC ", 4, " ENHANCED ", 7, "  "
        .assert * - VersionText = 40, error, "the version line must be 40 columns"

        .segment "BSS"
versionShown:   .res 1          ; a version line is on the screen (0 after SetRowMap)
versionAt:      .res 2          ; where DrawVersionLine draws
titleSteps:     .res 2

;------------------------------------------------------------------------------
; CreditsEndC64 - replaces the jsr CreditsEnd in CreditsIntro, once the frog
; has laid down the credits: add the RUN/STOP line to the instructions, row
; 19 above P - PAUSE (C64 Remix: RUN/STOP ends a game), and the version line
; between the address and the instructions, then the title frog and jingle.
;------------------------------------------------------------------------------
        .segment "HIDATA"
CreditsEndC64:
        lda     #4                      ; blue ink, as the other keys
        sta     SCREEN + 19*40 + 6
        ldx     #RUNSTOP_LEN - 1
:       lda     RunStopText,x
        sta     SCREEN + 19*40 + 7,x    ; above P - PAUSE
        dex
        bpl     :-
        lda     #<(SCREEN + 17*40)
        sta     versionAt
        lda     #>(SCREEN + 17*40)
        sta     versionAt+1
        jsr     DrawVersionLine
        lda     #7                      ; and 3 for new keys under the blinking
        sta     SCREEN + 27*40 + 14     ; PRESS [1] TO START: white ink over the
        ldx     #NEWKEYS_LEN - 1        ; row's blink attribute, so it holds (Remix)
:       lda     NewKeysText,x
        sta     SCREEN + 27*40 + 15,x
        dex
        bpl     :-
        jmp     CreditsEnd

RunStopText:
        .byte   "RUN/STOP - QUIT GAME"
RUNSTOP_LEN = * - RunStopText
NewKeysText:
        .byte   "PRESS [3] FOR NEW KEYS"
NEWKEYS_LEN = * - NewKeysText

;------------------------------------------------------------------------------
; MenuKeyC64 - replaces the jsr ReadRomKey in CheckMenuKeys, the key check of
; the attract loop (picture, credits, hi-scores). 3 redefines the keys (C64
; Remix): the controls menu on a cleared screen, entered as if 2 had been
; pressed, then the attract loop again from the credits, which show the new
; keys. The stack is reset: CheckMenuKeys is called from several depths.
; Anything else returns as ReadRomKey, flags from A.
;------------------------------------------------------------------------------
MenuKeyC64:
        jsr     ReadRomKey
        cmp     #'3' | $80
        beq     @redefine
        ora     #0                      ; the callers branch on these flags
        rts
@redefine:
        ldx     #$FF
        txs
        jsr     SilenceAll
        cli
        jsr     ClearScreen
        lda     #MAP_MENU
        jsr     SetRowMap
        lda     #'2' | $80              ; ControlsMenu's key wait takes this:
        sta     ROM_KEY                 ; straight into RedefineKeys
        jsr     ControlsMenu
        jmp     AttractLoop
