;==============================================================================
; HOPPER - Commodore 64 port of the Oric-1 game by A.J. Clarke (P.S.S., 1983)
;
; This is src/hopper.s with the hardware replaced, nothing else. Every byte of
; the game stays at its Oric address ($0500-$30D4), so the pointers the game
; builds from immediate bytes and both original bugs work unchanged. The Oric
; screen ($BB80), hi-score table ($BA00) and font save area ($3100) are at
; their Oric addresses in C64 RAM; only the character set moves (CHARSET is
; $B000 here, see c64/src/oric.inc).
;
; Each change is marked `; C64:` and listed in docs/porting.md. They are:
;   - glyph bytes widened from 6 to 8 pixels (W6, c64/src/oric.inc);
;   - tmp0/key_state moved off $00/$01, the 6510's I/O port (vars.inc);
;   - VIA, AY and ROM-keyboard code replaced by jumps or calls into the
;     platform layer (c64/src/*.s), each within the bytes it replaces;
;   - sei at NewGame and in LoadAYRegs made nop: the platform's raster
;     interrupt must keep running during play (the Oric ROM IRQ's on/off
;     state is tracked by InitGameC64 / RomIrqOn instead);
;   - calls that tell the platform which screen is up (SetRowMap), and the
;     key waits and busy loops call the platform so it can draw the screen.
;
; Original addresses stay in the comment column; `make c64-diff` lists every
; byte that differs from the Oric program.
;==============================================================================

        .include "oric.inc"
        .include "vars.inc"

        .import ReadKeysC64, FrameDelayC64, DelayXC64, T2Check, AyWriteC64
        .import InitGameC64, RomIrqOn, ReadRomKey, ReadMenuKey
        .import SoundMenuC64, CreditsIntroC64, HiscoreTableC64, AttractWait, RedefineKeys
        .import TitleTickC64, EraseFlyC64, StepFrogC64, CarryFrogC64
        .export CheckMenuKeys, ColdStart, InitGame, SoundMenu, CreditsIntro, DrawHiScoreTable, ServiceTimer
        .export PROG_START, PROG_END, key_rows, key_cols, key_bits
        .export keys_set2, key_name_left, key_name_right, key_name_up, key_name_down
        .export ControlsWaitKey, AttractLoop, StartGame
        .export StepFrog, LoseLife, L118A
        .export GameOver, SilenceAll, HiscoreScreen, lane_speeds

        .segment "GAME"
PROG_START:

;------------------------------------------------------------------------------
; ColdStart - tape autorun entry. Runs once.
; Saves the ROM character set (chars $20-$7F) to $3100, points the NMI (RESET
; button) at NmiHandler, and copies the default hi-score table to ALTCHARS+$1FF
; (alternate-charset RAM, unused in this game, which survives a warm start).
;------------------------------------------------------------------------------
ColdStart:
        lda     #$00                    ; 0500
        sta     fly_on                  ; 0502
        sta     fly_timer+1             ; 0504
        lda     #>(CHARSET+$100)        ; 0506  C64: CHARSET moved
        sta     fly_timer               ; 0508
        lda     #$31                    ; 050A
        sta     zp_23                   ; 050C
        ldy     #$00                    ; 050E
L0510:
        lda     (fly_on),y              ; 0510  save ROM font $B500-$B7FF to $3100
        sta     (fly_timer+1),y         ; 0512
        dey                             ; 0514
        bne     L0510                   ; 0515
        inc     fly_timer               ; 0517
        inc     zp_23                   ; 0519
        lda     fly_timer               ; 051B
        cmp     #>(CHARSET+$400)        ; 051D  C64: CHARSET moved
        bne     L0510                   ; 051F
        lda     #$4C                    ; 0521  NMI_VECTOR = JMP NmiHandler
        sta     NMI_VECTOR              ; 0523
        lda     #$60                    ; 0526
        sta     NMI_VECTOR+1            ; 0528
        lda     #$05                    ; 052B
        sta     NMI_VECTOR+2            ; 052D
        ldx     #$00                    ; 0530
L0532:
        lda     hiscore_init,x          ; 0532  default hi-scores to ALTCHARS+$1FF
        sta     HISCORES-1,x            ; 0535
        dex                             ; 0538
        bne     L0532                   ; 0539
        nop                             ; 053B
        nop                             ; 053C
        nop                             ; 053D
        nop                             ; 053E
        nop                             ; 053F

;------------------------------------------------------------------------------
; WarmStart - also reached from NmiHandler.
; $12/$13 are the ROM's cursor address: pointing it at $C0C0 (ROM) stops the
; ROM interrupt handler's cursor blink from writing to the screen.
;------------------------------------------------------------------------------
WarmStart:
        nop                             ; 0540
        nop                             ; 0541
        nop                             ; 0542
        nop                             ; 0543
        nop                             ; 0544
        sei                             ; 0545
        lda     #$C0                    ; 0546
        sta     ROM_CURPTR              ; 0548
        sta     ROM_CURPTR+1            ; 054A
        cli                             ; 054C
        jsr     ClearScreen             ; 054D
        jsr     SoundMenuC64            ; 0550  C64: menu rows
        nop                             ; 0553
        jsr     MarkSoundChoice         ; 0554
        jsr     ControlsMenu            ; 0557
        jsr     AttractMode             ; 055A
StartGame:
        jmp     NewGame                 ; 055D

;------------------------------------------------------------------------------
; NmiHandler - RESET button pressed.
; Silences the sound, restores the ROM character set, then waits about two
; seconds. If key_state is $28 during that time it jumps to $A800 (probably a
; development monitor the author kept in memory; nothing is there normally),
; otherwise it restarts the game at WarmStart.
;------------------------------------------------------------------------------
NmiHandler:
        jsr     ClearScreen             ; 0560
        sei                             ; 0563
        lda     #$07                    ; 0564
        sta     VIA_DDRB                ; 0566
        jsr     RestoreCharset          ; 0569
        jsr     SilenceAll              ; 056C
        lda     #$00                    ; 056F
        sta     hop_sound               ; 0571
L0573:
        jsr     ReadKeys                ; 0573
        lda     key_state               ; 0576
        cmp     #$28                    ; 0578
        bne     L0582                   ; 057A
        jsr     InitTimers              ; 057C  keys $28 held: silence and leave
        jmp     DEV_MONITOR             ; 057F  -> development monitor? (see header)
L0582:
        ldx     #$01                    ; 0582
        jsr     DelayX                  ; 0584
        dec     hop_sound               ; 0587
        bne     L0573                   ; 0589
        jsr     InitTimers              ; 058B
        jmp     WarmStart               ; 058E
        .res    15, $EA                 ; 0591

;------------------------------------------------------------------------------
; CheckPause - if the pause key is pressed, silence the sound and wait
; until it is released and pressed again.
;------------------------------------------------------------------------------
CheckPause:
        jsr     ReadKeys                ; 05A0
        lda     key_state               ; 05A3
        bmi     L05A8                   ; 05A5
        rts                             ; 05A7
L05A8:
        jsr     SilenceAll              ; 05A8
        sta     pause_flag              ; 05AB
L05AE:
        ldx     #$30                    ; 05AE
        jsr     DelayX                  ; 05B0
        jsr     ReadKeys                ; 05B3
        lda     key_state               ; 05B6
        bmi     L05C1                   ; 05B8
        lda     #$00                    ; 05BA
        sta     pause_flag              ; 05BC
        beq     L05AE                   ; 05BF
L05C1:
        lda     pause_flag              ; 05C1
        bne     L05AE                   ; 05C4
        ldx     #$60                    ; 05C6
        jsr     DelayX                  ; 05C8
        rts                             ; 05CB
        .res    52, $EA                 ; 05CC

;------------------------------------------------------------------------------
; Character graphics for chars $5B-$7F: scenery, logs, cars, snake,
; turtles, fly. InitGame copies $0600-$07FF to CHARSET+$5B*8
; (the copy carries on into the tables below, which land harmlessly
; in the alternate character set).
;------------------------------------------------------------------------------
udg_graphics:
        .byte   W6(%00000000)           ; 0600 ......  char $5B
        .byte   W6(%00000000)           ; 0601 ......
        .byte   W6(%00000000)           ; 0602 ......
        .byte   W6(%00000001)           ; 0603 .....#
        .byte   W6(%00110010)           ; 0604 ##..#.
        .byte   W6(%00001100)           ; 0605 ..##..
        .byte   W6(%00000000)           ; 0606 ......
        .byte   W6(%00000000)           ; 0607 ......
        .byte   W6(%00000000)           ; 0608 ......  char $5C
        .byte   W6(%00000000)           ; 0609 ......
        .byte   W6(%00000000)           ; 060A ......
        .byte   W6(%00100001)           ; 060B #....#
        .byte   W6(%00010010)           ; 060C .#..#.
        .byte   W6(%00001100)           ; 060D ..##..
        .byte   W6(%00000000)           ; 060E ......
        .byte   W6(%00000000)           ; 060F ......
        .byte   W6(%00000000)           ; 0610 ......  char $5D
        .byte   W6(%00000000)           ; 0611 ......
        .byte   W6(%00000000)           ; 0612 ......
        .byte   W6(%00110110)           ; 0613 ##.##.
        .byte   W6(%00001111)           ; 0614 ..####
        .byte   W6(%00000110)           ; 0615 ...##.
        .byte   W6(%00000000)           ; 0616 ......
        .byte   W6(%00000000)           ; 0617 ......
        .byte   W6(%00000000)           ; 0618 ......  char $5E
        .byte   W6(%00000000)           ; 0619 ......
        .byte   W6(%00000000)           ; 061A ......
        .byte   W6(%00011011)           ; 061B .##.##
        .byte   W6(%00111100)           ; 061C ####..
        .byte   W6(%00011000)           ; 061D .##...
        .byte   W6(%00000000)           ; 061E ......
        .byte   W6(%00000000)           ; 061F ......
        .byte   W6(%00000000)           ; 0620 ......  char $5F
        .byte   W6(%00000000)           ; 0621 ......
        .byte   W6(%00000000)           ; 0622 ......
        .byte   W6(%00100000)           ; 0623 #.....
        .byte   W6(%00010011)           ; 0624 .#..##
        .byte   W6(%00001100)           ; 0625 ..##..
        .byte   W6(%00000000)           ; 0626 ......
        .byte   W6(%00000000)           ; 0627 ......
        .byte   W6(%00001111)           ; 0628 ..####  char $60
        .byte   W6(%00001000)           ; 0629 ..#...
        .byte   W6(%00010011)           ; 062A .#..##
        .byte   W6(%00010000)           ; 062B .#....
        .byte   W6(%00011011)           ; 062C .##.##
        .byte   W6(%00100000)           ; 062D #.....
        .byte   W6(%00110111)           ; 062E ##.###
        .byte   W6(%00100000)           ; 062F #.....
        .byte   W6(%00111111)           ; 0630 ######  char $61
        .byte   W6(%00000000)           ; 0631 ......
        .byte   W6(%00101111)           ; 0632 #.####
        .byte   W6(%00000000)           ; 0633 ......
        .byte   W6(%00001110)           ; 0634 ..###.
        .byte   W6(%00000000)           ; 0635 ......
        .byte   W6(%00110011)           ; 0636 ##..##
        .byte   W6(%00000000)           ; 0637 ......
        .byte   W6(%00111100)           ; 0638 ####..  char $62
        .byte   W6(%00000100)           ; 0639 ...#..
        .byte   W6(%00111010)           ; 063A ###.#.
        .byte   W6(%00001010)           ; 063B ..#.#.
        .byte   W6(%00001010)           ; 063C ..#.#.
        .byte   W6(%00010001)           ; 063D .#...#
        .byte   W6(%00110001)           ; 063E ##...#
        .byte   W6(%00010001)           ; 063F .#...#
        .byte   W6(%00100000)           ; 0640 #.....  char $63
        .byte   W6(%00110111)           ; 0641 ##.###
        .byte   W6(%00100000)           ; 0642 #.....
        .byte   W6(%00010011)           ; 0643 .#..##
        .byte   W6(%00010000)           ; 0644 .#....
        .byte   W6(%00010011)           ; 0645 .#..##
        .byte   W6(%00001000)           ; 0646 ..#...
        .byte   W6(%00001111)           ; 0647 ..####
        .byte   W6(%00000000)           ; 0648 ......  char $64
        .byte   W6(%00110011)           ; 0649 ##..##
        .byte   W6(%00000000)           ; 064A ......
        .byte   W6(%00001110)           ; 064B ..###.
        .byte   W6(%00000000)           ; 064C ......
        .byte   W6(%00101111)           ; 064D #.####
        .byte   W6(%00000000)           ; 064E ......
        .byte   W6(%00111111)           ; 064F ######
        .byte   W6(%00010001)           ; 0650 .#...#  char $65
        .byte   W6(%00110001)           ; 0651 ##...#
        .byte   W6(%00010001)           ; 0652 .#...#
        .byte   W6(%00001010)           ; 0653 ..#.#.
        .byte   W6(%00001010)           ; 0654 ..#.#.
        .byte   W6(%00111010)           ; 0655 ###.#.
        .byte   W6(%00000100)           ; 0656 ...#..
        .byte   W6(%00111100)           ; 0657 ####..
        .byte   W6(%00000000)           ; 0658 ......  char $66
        .byte   W6(%00000111)           ; 0659 ...###
        .byte   W6(%00011111)           ; 065A .#####
        .byte   W6(%00100000)           ; 065B #.....
        .byte   W6(%00101110)           ; 065C #.###.
        .byte   W6(%00101110)           ; 065D #.###.
        .byte   W6(%00101110)           ; 065E #.###.
        .byte   W6(%00101110)           ; 065F #.###.
        .byte   W6(%00000000)           ; 0660 ......  char $67
        .byte   W6(%00000000)           ; 0661 ......
        .byte   W6(%00111111)           ; 0662 ######
        .byte   W6(%00001111)           ; 0663 ..####
        .byte   W6(%00010111)           ; 0664 .#.###
        .byte   W6(%00010111)           ; 0665 .#.###
        .byte   W6(%00010111)           ; 0666 .#.###
        .byte   W6(%00010111)           ; 0667 .#.###
        .byte   W6(%00110000)           ; 0668 ##....  char $68
        .byte   W6(%00010111)           ; 0669 .#.###
        .byte   W6(%00111111)           ; 066A ######
        .byte   W6(%00000000)           ; 066B ......
        .byte   W6(%00100111)           ; 066C #..###
        .byte   W6(%00010111)           ; 066D .#.###
        .byte   W6(%00010111)           ; 066E .#.###
        .byte   W6(%00010111)           ; 066F .#.###
        .byte   W6(%00000000)           ; 0670 ......  char $69
        .byte   W6(%00110000)           ; 0671 ##....
        .byte   W6(%00111000)           ; 0672 ###...
        .byte   W6(%00000100)           ; 0673 ...#..
        .byte   W6(%00110010)           ; 0674 ##..#.
        .byte   W6(%00111010)           ; 0675 ###.#.
        .byte   W6(%00111010)           ; 0676 ###.#.
        .byte   W6(%00111010)           ; 0677 ###.#.
        .byte   W6(%00101110)           ; 0678 #.###.  char $6A
        .byte   W6(%00101110)           ; 0679 #.###.
        .byte   W6(%00101110)           ; 067A #.###.
        .byte   W6(%00101110)           ; 067B #.###.
        .byte   W6(%00100000)           ; 067C #.....
        .byte   W6(%00011111)           ; 067D .#####
        .byte   W6(%00000111)           ; 067E ...###
        .byte   W6(%00000000)           ; 067F ......
        .byte   W6(%00010111)           ; 0680 .#.###  char $6B
        .byte   W6(%00010111)           ; 0681 .#.###
        .byte   W6(%00010111)           ; 0682 .#.###
        .byte   W6(%00010111)           ; 0683 .#.###
        .byte   W6(%00001111)           ; 0684 ..####
        .byte   W6(%00111111)           ; 0685 ######
        .byte   W6(%00000000)           ; 0686 ......
        .byte   W6(%00000000)           ; 0687 ......
        .byte   W6(%00010111)           ; 0688 .#.###  char $6C
        .byte   W6(%00010111)           ; 0689 .#.###
        .byte   W6(%00010111)           ; 068A .#.###
        .byte   W6(%00100111)           ; 068B #..###
        .byte   W6(%00000000)           ; 068C ......
        .byte   W6(%00111111)           ; 068D ######
        .byte   W6(%00010111)           ; 068E .#.###
        .byte   W6(%00110000)           ; 068F ##....
        .byte   W6(%00111010)           ; 0690 ###.#.  char $6D
        .byte   W6(%00111010)           ; 0691 ###.#.
        .byte   W6(%00111010)           ; 0692 ###.#.
        .byte   W6(%00110010)           ; 0693 ##..#.
        .byte   W6(%00000100)           ; 0694 ...#..
        .byte   W6(%00111000)           ; 0695 ###...
        .byte   W6(%00110000)           ; 0696 ##....
        .byte   W6(%00000000)           ; 0697 ......
        .byte   W6(%00000000)           ; 0698 ......  char $6E
        .byte   W6(%00000000)           ; 0699 ......
        .byte   W6(%00000000)           ; 069A ......
        .byte   W6(%00000000)           ; 069B ......
        .byte   W6(%00000000)           ; 069C ......
        .byte   W6(%00000000)           ; 069D ......
        .byte   W6(%00011001)           ; 069E .##..#
        .byte   W6(%00111111)           ; 069F ######
        .byte   W6(%00011000)           ; 06A0 .##...  char $6F
        .byte   W6(%00001101)           ; 06A1 ..##.#
        .byte   W6(%00000111)           ; 06A2 ...###
        .byte   W6(%00000111)           ; 06A3 ...###
        .byte   W6(%00011111)           ; 06A4 .#####
        .byte   W6(%00111111)           ; 06A5 ######
        .byte   W6(%00111111)           ; 06A6 ######
        .byte   W6(%00111111)           ; 06A7 ######
        .byte   W6(%00000110)           ; 06A8 ...##.  char $70
        .byte   W6(%00101100)           ; 06A9 #.##..
        .byte   W6(%00111000)           ; 06AA ###...
        .byte   W6(%00111000)           ; 06AB ###...
        .byte   W6(%00111000)           ; 06AC ###...
        .byte   W6(%00111000)           ; 06AD ###...
        .byte   W6(%00111000)           ; 06AE ###...
        .byte   W6(%00111110)           ; 06AF #####.
        .byte   W6(%00111111)           ; 06B0 ######  char $71
        .byte   W6(%00011001)           ; 06B1 .##..#
        .byte   W6(%00000000)           ; 06B2 ......
        .byte   W6(%00000000)           ; 06B3 ......
        .byte   W6(%00000000)           ; 06B4 ......
        .byte   W6(%00000000)           ; 06B5 ......
        .byte   W6(%00000000)           ; 06B6 ......
        .byte   W6(%00000000)           ; 06B7 ......
        .byte   W6(%00111111)           ; 06B8 ######  char $72
        .byte   W6(%00111111)           ; 06B9 ######
        .byte   W6(%00111111)           ; 06BA ######
        .byte   W6(%00011111)           ; 06BB .#####
        .byte   W6(%00000111)           ; 06BC ...###
        .byte   W6(%00000111)           ; 06BD ...###
        .byte   W6(%00001101)           ; 06BE ..##.#
        .byte   W6(%00011000)           ; 06BF .##...
        .byte   W6(%00111110)           ; 06C0 #####.  char $73
        .byte   W6(%00111000)           ; 06C1 ###...
        .byte   W6(%00111000)           ; 06C2 ###...
        .byte   W6(%00111000)           ; 06C3 ###...
        .byte   W6(%00111000)           ; 06C4 ###...
        .byte   W6(%00111000)           ; 06C5 ###...
        .byte   W6(%00101100)           ; 06C6 #.##..
        .byte   W6(%00000110)           ; 06C7 ...##.
        .byte   W6(%00000000)           ; 06C8 ......  char $74
        .byte   W6(%00001110)           ; 06C9 ..###.
        .byte   W6(%00001111)           ; 06CA ..####
        .byte   W6(%00010111)           ; 06CB .#.###
        .byte   W6(%00110111)           ; 06CC ##.###
        .byte   W6(%00110111)           ; 06CD ##.###
        .byte   W6(%00110111)           ; 06CE ##.###
        .byte   W6(%00110111)           ; 06CF ##.###
        .byte   W6(%00000000)           ; 06D0 ......  char $75
        .byte   W6(%00001110)           ; 06D1 ..###.
        .byte   W6(%00011111)           ; 06D2 .#####
        .byte   W6(%00011111)           ; 06D3 .#####
        .byte   W6(%00011111)           ; 06D4 .#####
        .byte   W6(%00011111)           ; 06D5 .#####
        .byte   W6(%00011111)           ; 06D6 .#####
        .byte   W6(%00111111)           ; 06D7 ######
        .byte   W6(%00000000)           ; 06D8 ......  char $76
        .byte   W6(%00000000)           ; 06D9 ......
        .byte   W6(%00111111)           ; 06DA ######
        .byte   W6(%00111111)           ; 06DB ######
        .byte   W6(%00111111)           ; 06DC ######
        .byte   W6(%00111111)           ; 06DD ######
        .byte   W6(%00111111)           ; 06DE ######
        .byte   W6(%00111111)           ; 06DF ######
        .byte   W6(%00000000)           ; 06E0 ......  char $77
        .byte   W6(%00011110)           ; 06E1 .####.
        .byte   W6(%00111111)           ; 06E2 ######
        .byte   W6(%00111111)           ; 06E3 ######
        .byte   W6(%00111111)           ; 06E4 ######
        .byte   W6(%00111111)           ; 06E5 ######
        .byte   W6(%00111111)           ; 06E6 ######
        .byte   W6(%00111111)           ; 06E7 ######
        .byte   W6(%00110111)           ; 06E8 ##.###  char $78
        .byte   W6(%00110111)           ; 06E9 ##.###
        .byte   W6(%00110111)           ; 06EA ##.###
        .byte   W6(%00110111)           ; 06EB ##.###
        .byte   W6(%00010111)           ; 06EC .#.###
        .byte   W6(%00001111)           ; 06ED ..####
        .byte   W6(%00001110)           ; 06EE ..###.
        .byte   W6(%00000000)           ; 06EF ......
        .byte   W6(%00111111)           ; 06F0 ######  char $79
        .byte   W6(%00011111)           ; 06F1 .#####
        .byte   W6(%00011111)           ; 06F2 .#####
        .byte   W6(%00011111)           ; 06F3 .#####
        .byte   W6(%00011111)           ; 06F4 .#####
        .byte   W6(%00011111)           ; 06F5 .#####
        .byte   W6(%00001110)           ; 06F6 ..###.
        .byte   W6(%00000000)           ; 06F7 ......
        .byte   W6(%00111111)           ; 06F8 ######  char $7A
        .byte   W6(%00111111)           ; 06F9 ######
        .byte   W6(%00111111)           ; 06FA ######
        .byte   W6(%00111111)           ; 06FB ######
        .byte   W6(%00111111)           ; 06FC ######
        .byte   W6(%00111111)           ; 06FD ######
        .byte   W6(%00000000)           ; 06FE ......
        .byte   W6(%00000000)           ; 06FF ......
        .byte   W6(%00111111)           ; 0700 ######  char $7B
        .byte   W6(%00111111)           ; 0701 ######
        .byte   W6(%00111111)           ; 0702 ######
        .byte   W6(%00111111)           ; 0703 ######
        .byte   W6(%00111111)           ; 0704 ######
        .byte   W6(%00111111)           ; 0705 ######
        .byte   W6(%00011110)           ; 0706 .####.
        .byte   W6(%00000000)           ; 0707 ......
        .byte   W6(%00001000)           ; 0708 ..#...  char $7C
        .byte   W6(%00000101)           ; 0709 ...#.#
        .byte   W6(%00010011)           ; 070A .#..##
        .byte   W6(%00111110)           ; 070B #####.
        .byte   W6(%00111101)           ; 070C ####.#
        .byte   W6(%00011000)           ; 070D .##...
        .byte   W6(%00000101)           ; 070E ...#.#
        .byte   W6(%00001000)           ; 070F ..#...
        .byte   W6(%00110001)           ; 0710 ##...#  char $7D
        .byte   W6(%00101110)           ; 0711 #.###.
        .byte   W6(%00010100)           ; 0712 .#.#..
        .byte   W6(%00101010)           ; 0713 #.#.#.
        .byte   W6(%00010110)           ; 0714 .#.##.
        .byte   W6(%00101100)           ; 0715 #.##..
        .byte   W6(%00011110)           ; 0716 .####.
        .byte   W6(%00110001)           ; 0717 ##...#
        .byte   W6(%11111111)           ; 0718 ######  char $7E
        .byte   W6(%11111111)           ; 0719 ######
        .byte   W6(%11111111)           ; 071A ######
        .byte   W6(%11111111)           ; 071B ######
        .byte   W6(%11111111)           ; 071C ######
        .byte   W6(%11111111)           ; 071D ######
        .byte   W6(%11111111)           ; 071E ######
        .byte   W6(%11111111)           ; 071F ######
        .byte   W6(%00010001)           ; 0720 .#...#  char $7F
        .byte   W6(%00101010)           ; 0721 #.#.#.
        .byte   W6(%00010101)           ; 0722 .#.#.#
        .byte   W6(%00001010)           ; 0723 ..#.#.
        .byte   W6(%00001010)           ; 0724 ..#.#.
        .byte   W6(%00010101)           ; 0725 .#.#.#
        .byte   W6(%00101010)           ; 0726 #.#.#.
        .byte   W6(%00010001)           ; 0727 .#...#

;------------------------------------------------------------------------------
; Character graphics for chars $21-$2A (copied to CHARSET+$21*8).
;------------------------------------------------------------------------------
udg_symbols:
        .byte   W6(%00000000)           ; 0728 ......  char $21
        .byte   W6(%00000110)           ; 0729 ...##.
        .byte   W6(%00001110)           ; 072A ..###.
        .byte   W6(%00001110)           ; 072B ..###.
        .byte   W6(%00011110)           ; 072C .####.
        .byte   W6(%00011111)           ; 072D .#####
        .byte   W6(%00011111)           ; 072E .#####
        .byte   W6(%00011111)           ; 072F .#####
        .byte   W6(%00000000)           ; 0730 ......  char $22
        .byte   W6(%00000000)           ; 0731 ......
        .byte   W6(%00011110)           ; 0732 .####.
        .byte   W6(%00011110)           ; 0733 .####.
        .byte   W6(%00001100)           ; 0734 ..##..
        .byte   W6(%00111111)           ; 0735 ######
        .byte   W6(%00111111)           ; 0736 ######
        .byte   W6(%00111111)           ; 0737 ######
        .byte   W6(%00000000)           ; 0738 ......  char $23
        .byte   W6(%00000000)           ; 0739 ......
        .byte   W6(%00011111)           ; 073A .#####
        .byte   W6(%00101010)           ; 073B #.#.#.
        .byte   W6(%00101010)           ; 073C #.#.#.
        .byte   W6(%00111111)           ; 073D ######
        .byte   W6(%00111111)           ; 073E ######
        .byte   W6(%00111111)           ; 073F ######
        .byte   W6(%00000000)           ; 0740 ......  char $24
        .byte   W6(%00000100)           ; 0741 ...#..
        .byte   W6(%00001100)           ; 0742 ..##..
        .byte   W6(%00010100)           ; 0743 .#.#..
        .byte   W6(%00111111)           ; 0744 ######
        .byte   W6(%00100000)           ; 0745 #.....
        .byte   W6(%00101000)           ; 0746 #.#...
        .byte   W6(%00111000)           ; 0747 ###...
        .byte   W6(%00111111)           ; 0748 ######  char $25
        .byte   W6(%00111111)           ; 0749 ######
        .byte   W6(%00111111)           ; 074A ######
        .byte   W6(%00001100)           ; 074B ..##..
        .byte   W6(%00111100)           ; 074C ####..
        .byte   W6(%00011110)           ; 074D .####.
        .byte   W6(%00011111)           ; 074E .#####
        .byte   W6(%00011111)           ; 074F .#####
        .byte   W6(%00011111)           ; 0750 .#####  char $26
        .byte   W6(%00011111)           ; 0751 .#####
        .byte   W6(%00011111)           ; 0752 .#####
        .byte   W6(%00011110)           ; 0753 .####.
        .byte   W6(%00001110)           ; 0754 ..###.
        .byte   W6(%00001110)           ; 0755 ..###.
        .byte   W6(%00000110)           ; 0756 ...##.
        .byte   W6(%00000000)           ; 0757 ......
        .byte   W6(%00111111)           ; 0758 ######  char $27
        .byte   W6(%00111111)           ; 0759 ######
        .byte   W6(%00111111)           ; 075A ######
        .byte   W6(%00001100)           ; 075B ..##..
        .byte   W6(%00011110)           ; 075C .####.
        .byte   W6(%00011110)           ; 075D .####.
        .byte   W6(%00000000)           ; 075E ......
        .byte   W6(%00000000)           ; 075F ......
        .byte   W6(%00111111)           ; 0760 ######  char $28
        .byte   W6(%00111111)           ; 0761 ######
        .byte   W6(%00111111)           ; 0762 ######
        .byte   W6(%00101010)           ; 0763 #.#.#.
        .byte   W6(%00101010)           ; 0764 #.#.#.
        .byte   W6(%00011111)           ; 0765 .#####
        .byte   W6(%00000000)           ; 0766 ......
        .byte   W6(%00000000)           ; 0767 ......
        .byte   W6(%00111000)           ; 0768 ###...  char $29
        .byte   W6(%00101000)           ; 0769 #.#...
        .byte   W6(%00100000)           ; 076A #.....
        .byte   W6(%00111111)           ; 076B ######
        .byte   W6(%00010100)           ; 076C .#.#..
        .byte   W6(%00001100)           ; 076D ..##..
        .byte   W6(%00000100)           ; 076E ...#..
        .byte   W6(%00000000)           ; 076F ......
        .byte   W6(%00011111)           ; 0770 .#####  char $2A
        .byte   W6(%00011111)           ; 0771 .#####
        .byte   W6(%00011110)           ; 0772 .####.
        .byte   W6(%00111100)           ; 0773 ####..
        .byte   W6(%00001100)           ; 0774 ..##..
        .byte   W6(%00111111)           ; 0775 ######
        .byte   W6(%00111111)           ; 0776 ######
        .byte   W6(%00111111)           ; 0777 ######

;------------------------------------------------------------------------------
; Status line shown on row 27. Control codes: $01-$07 ink colour.
;------------------------------------------------------------------------------
status_template:
        .byte   "SCORE      00",$01,"TIME 99",$04,"LIVES 5",$05 ; 0778
        .byte   "SHEET  1",$00,$FF                        ; 0796

;------------------------------------------------------------------------------
; Columns of the hedge between the five homes on rows 1-2 (char $7F).
;------------------------------------------------------------------------------
home_wall_cols:
        .byte   $00,$01,$02,$03,$06,$07,$08,$09,$0A,$0D,$0E,$0F,$10,$11 ; 07A0
        .byte   $14,$15,$16,$17,$18,$1B,$1C,$1D,$1E,$1F,$22,$23,$24,$25 ; 07AE
        .byte   $26,$27,$FF                               ; 07BC
        .res    9, $FF                  ; 07BF

;------------------------------------------------------------------------------
; Attribute pair (ink, paper) written to columns 0-1 of each of the
; 28 screen rows: $00-$07 = ink colour, $10-$17 = paper colour.
;------------------------------------------------------------------------------
row_colours:
        .byte   $02,$14,$02,$14,$02,$14,$00,$14,$00,$14,$00,$14,$00,$14 ; 07C8
        .byte   $01,$14,$01,$14,$00,$14,$03,$14,$03,$14,$00,$14,$01,$14 ; 07D6
        .byte   $01,$14,$00,$13,$00,$13,$06,$10,$06,$10,$07,$10,$04,$10 ; 07E4
        .byte   $04,$10,$07,$10,$03,$10,$03,$10,$00,$12,$00,$12,$00,$17 ; 07F2

;------------------------------------------------------------------------------
; Ink colour for each hi-score table row (indexed by digit '1'-'8').
;------------------------------------------------------------------------------
hiscore_inks:
        .byte   $01,$02,$03,$04,$05,$06,$02,$03           ; 0800
        .byte   $04                                       ; 0808
        .res    7, $FF                  ; 0809

;------------------------------------------------------------------------------
; AY tone periods for one octave (low byte), shifted right per octave.
;------------------------------------------------------------------------------
note_periods:
        .byte   $EF,$E2,$D5,$C9,$BD,$B3,$A8,$9F,$96,$8E,$86,$7E ; 0810
        .res    4, $FF                  ; 081C

;------------------------------------------------------------------------------
; AY register values 0-13 loaded at the start of a sheet.
;------------------------------------------------------------------------------
ay_game_regs:
        .byte   $00,$00,$00,$00,$00,$00,$1F,$F8,$02,$02,$02,$00,$00,$00 ; 0820
        .byte   $00,$00                                   ; 082E

;------------------------------------------------------------------------------
; Four in-game tunes; PickTune chooses one at random.
;------------------------------------------------------------------------------
tune_ptrs:
        .word   $2C00                   ; 0830
        .word   $2C80                   ; 0832
        .word   $2DBE                   ; 0834
        .word   $2E80                   ; 0836
        .res    8, $FF                  ; 0838

;------------------------------------------------------------------------------
; Per tune: tempo, tune length in bytes.
;------------------------------------------------------------------------------
tune_params:
        .byte   $01,$74                                   ; 0840
        .byte   $01,$54                                   ; 0842
        .byte   $01,$8A                                   ; 0844
        .byte   $01,$AA                                   ; 0846
        .res    8, $FF                  ; 0848

;------------------------------------------------------------------------------
; Initial contents of rows 7, 8, 10, 11, 13, 14 (river lanes),
; 38 characters each (columns 2-39).
;------------------------------------------------------------------------------
lane_init:
        .byte   $6E,$6F,$70,$6E,$6F,$70,$20,$20,$20,$20,$20,$20,$6E,$6F,$70,$6E,$6F,$70,$6E,$6F,$70,$20,$20,$20,$6E,$6F,$70,$6E,$6F,$70,$6E,$6F,$70,$20,$20,$6E,$6F,$70 ; 0850
        .byte   $71,$72,$73,$71,$72,$73,$20,$20,$20,$20,$20,$20,$71,$72,$73,$71,$72,$73,$71,$72,$73,$20,$20,$20,$71,$72,$73,$71,$72,$73,$71,$72,$73,$20,$20,$71,$72,$73 ; 0876
        .byte   $20,$60,$61,$61,$61,$61,$61,$62,$20,$20,$20,$20,$60,$61,$61,$61,$61,$61,$61,$61,$62,$20,$20,$20,$20,$60,$61,$61,$61,$61,$61,$62,$20,$20,$20,$20,$20,$20 ; 089C
        .byte   $20,$63,$64,$64,$64,$64,$64,$65,$20,$20,$20,$20,$63,$64,$64,$64,$64,$64,$64,$64,$65,$20,$20,$20,$20,$63,$64,$64,$64,$64,$64,$65,$20,$20,$20,$20,$20,$20 ; 08C2
        .byte   $61,$61,$61,$61,$61,$62,$20,$20,$20,$20,$20,$20,$60,$61,$61,$61,$62,$20,$20,$20,$20,$60,$61,$61,$61,$61,$61,$61,$62,$20,$20,$20,$20,$20,$20,$60,$61,$61 ; 08E8
        .byte   $64,$64,$64,$64,$64,$65,$20,$20,$20,$20,$20,$20,$63,$64,$64,$64,$65,$20,$20,$20,$20,$63,$64,$64,$64,$64,$64,$64,$65,$20,$20,$20,$20,$20,$20,$63,$64,$64 ; 090E
        .res    12, $20                 ; 0934

;------------------------------------------------------------------------------
; Initial lane speeds (frames between moves) for lanes 0-6.
;------------------------------------------------------------------------------
lane_speeds_init:
        .byte   $0B,$05,$07,$05,$07,$0D,$06               ; 0940
        .byte   $20                                       ; 0947

;------------------------------------------------------------------------------
; RestoreCharset - copy the saved ROM font at $3100 back to CHARSET+$20*8.
;------------------------------------------------------------------------------
RestoreCharset:
        nop                             ; 0948
        nop                             ; 0949
        nop                             ; 094A
        nop                             ; 094B
        nop                             ; 094C
        nop                             ; 094D
        nop                             ; 094E
        nop                             ; 094F
        lda     #$00                    ; 0950
        sta     fly_on                  ; 0952
        sta     fly_timer+1             ; 0954
        lda     #>(CHARSET+$100)        ; 0956  C64: CHARSET moved
        sta     fly_timer               ; 0958
        lda     #$31                    ; 095A
        sta     zp_23                   ; 095C
        ldy     #$00                    ; 095E
L0960:
        lda     (fly_timer+1),y         ; 0960
        sta     (fly_on),y              ; 0962
        dey                             ; 0964
        bne     L0960                   ; 0965
        inc     fly_timer               ; 0967
        inc     zp_23                   ; 0969
        lda     fly_timer               ; 096B
        cmp     #>(CHARSET+$400)        ; 096D  C64: CHARSET moved
        bne     L0960                   ; 096F
        rts                             ; 0971
        .res    14, $20                 ; 0972

;------------------------------------------------------------------------------
; AY register values 0-13: all channels quiet.
;------------------------------------------------------------------------------
ay_quiet_regs:
        .byte   $00,$00,$00,$00,$00,$00,$1F,$F8,$00,$00,$00,$00,$00,$00 ; 0980
        .byte   $00,$00,$20                               ; 098E
        .res    15, $20                 ; 0991

;------------------------------------------------------------------------------
; VIA timer 2 reload value ($606B) - the game's time base.
;------------------------------------------------------------------------------
timer2_reload:
        .byte   $6B,$60                                   ; 09A0
        .res    30, $20                 ; 09A2

;------------------------------------------------------------------------------
; Working lane speeds; the lanes speed up as sheets are cleared.
;------------------------------------------------------------------------------
lane_speeds:
        .byte   $0B,$05,$07,$05,$07,$0D,$06               ; 09C0
        .byte   $03,$20                                   ; 09C7
        .res    7, $20                  ; 09C9

;------------------------------------------------------------------------------
; Random8 - next random number, returns 0-7 in A.
;------------------------------------------------------------------------------
Random8:
        jsr     RandomNext              ; 09D0
        lda     rand_seed+2             ; 09D3
        and     #$07                    ; 09D5
        rts                             ; 09D7

;------------------------------------------------------------------------------
; ClearScreen - fill the whole text screen with spaces.
;------------------------------------------------------------------------------
ClearScreen:
        ldy     #$00                    ; 09D8
        lda     #$20                    ; 09DA
L09DC:
        sta     SCREEN+0*40+0,y         ; 09DC
        sta     SCREEN+3*40+8,y         ; 09DF
        sta     SCREEN+9*40+24,y        ; 09E2
        sta     SCREEN+16*40+0,y        ; 09E5
        sta     SCREEN+22*40+16,y       ; 09E8
        dey                             ; 09EB
        bne     L09DC                   ; 09EC
        rts                             ; 09EE
        .byte   $FF                                       ; 09EF

;------------------------------------------------------------------------------
; RandomNext - steps the random seed at rand_seed ($D0-$D3).
; Callers read rand_seed+1 or rand_seed+2.
;------------------------------------------------------------------------------
RandomNext:
        ldy     #$29                    ; 09F0
        ldx     #$FC                    ; 09F2
L09F4:
        tya                             ; 09F4
        ldy     rand_seed+4,x           ; 09F5
        adc     rand_seed+4,x           ; 09F7
        sta     rand_seed+4,x           ; 09F9
        inx                             ; 09FB
        bne     L09F4                   ; 09FC
        rts                             ; 09FE
        .byte   $FF                                       ; 09FF

;------------------------------------------------------------------------------
; InitGame - set up a new game: status line, character graphics,
; playfield, sound, timers, lane speeds and all game variables.
;------------------------------------------------------------------------------
InitGame:
        ldx     #$26                    ; 0A00
L0A02:
        lda     status_template,x       ; 0A02
        sta     status_save,x           ; 0A05
        dex                             ; 0A08
        bpl     L0A02                   ; 0A09
        jsr     ClearScreen             ; 0A0B
        jsr     DrawScenery             ; 0A0E
        lda     CHARSET+$21*8+3         ; 0A11  font already loaded?
        cmp     #W6($0E)                ; 0A14  C64: widened glyph byte
        beq     L0A3B                   ; 0A16
        lda     #$D8                    ; 0A18
        sta     ptr30                   ; 0A1A
        lda     #>(CHARSET+$5B*8)       ; 0A1C  C64: CHARSET moved
        sta     frog_dir                ; 0A1E
        lda     #$00                    ; 0A20
        sta     frog_pos                ; 0A22
        lda     #$06                    ; 0A24
        sta     frog_pos+1              ; 0A26
L0A28:
        ldy     #$00                    ; 0A28
L0A2A:
        lda     (frog_pos),y            ; 0A2A  copy $0600-$07FF -> CHARSET+$5B*8
        sta     (ptr30),y               ; 0A2C
        iny                             ; 0A2E
        bne     L0A2A                   ; 0A2F
        inc     frog_dir                ; 0A31
        inc     frog_pos+1              ; 0A33
        lda     frog_pos+1              ; 0A35
        cmp     #$08                    ; 0A37
        bne     L0A28                   ; 0A39
L0A3B:
        jsr     DrawPlayfield           ; 0A3B
        ldx     #$00                    ; 0A3E
L0A40:
        lda     status_template,x       ; 0A40
        sta     STATUS_ROW+2,x          ; 0A43
        inx                             ; 0A46
        cpx     #$26                    ; 0A47
        bne     L0A40                   ; 0A49
        ldx     #$06                    ; 0A4B
L0A4D:
        lda     lane_speeds_init,x      ; 0A4D
        sta     lane_speeds,x           ; 0A50
        dex                             ; 0A53
        bpl     L0A4D                   ; 0A54
        ldx     #$80                    ; 0A56
        ldy     #$09                    ; 0A58
        jsr     LoadAYRegs              ; 0A5A
        lda     #$FF                    ; 0A5D
        sta     key_mask                ; 0A5F
        nop                             ; 0A61
        nop                             ; 0A62
        nop                             ; 0A63
        nop                             ; 0A64
        lda     #$00                    ; 0A65
        sta     VIA_ACR                 ; 0A67
        lda     timer2_reload           ; 0A6A
        sta     VIA_T2CL                ; 0A6D
        lda     timer2_reload+1         ; 0A70
        sta     VIA_T2CH                ; 0A73
        ldy     #$00                    ; 0A76
        ldx     #$08                    ; 0A78
L0A7A:
        sty     hop_sound,x             ; 0A7A
        dex                             ; 0A7C
        bpl     L0A7A                   ; 0A7D
        lda     #$02                    ; 0A7F
        sta     tune_tempo              ; 0A81
        nop                             ; 0A83
        nop                             ; 0A84
        ldx     #$30                    ; 0A85
L0A87:
        lda     #$00                    ; 0A87
        sta     r23_state,x             ; 0A89
        dex                             ; 0A8C
        bne     L0A87                   ; 0A8D
        lda     #$01                    ; 0A8F
        sta     r23_first               ; 0A91
        sta     r20_first               ; 0A94
        sta     r17_first               ; 0A97
        ldx     #$4F                    ; 0A9A
L0A9C:
        lda     udg_symbols,x           ; 0A9C  chars $21-$2A
        sta     CHARSET+$21*8,x         ; 0A9F
        dex                             ; 0AA2
        bpl     L0A9C                   ; 0AA3
        lda     #$07                    ; 0AA5
        sta     r17_gap_min             ; 0AA7
        nop                             ; 0AAA
        nop                             ; 0AAB
        nop                             ; 0AAC
        sta     r23_gap_min             ; 0AAD
        lda     #$0D                    ; 0AB0
        sta     game_delay              ; 0AB2
        lda     #$01                    ; 0AB5
        sta     frog_dir                ; 0AB7
        lda     #$7C                    ; 0AB9
        sta     frog_pos                ; 0ABB
        lda     #$BF                    ; 0ABD
        sta     frog_pos+1              ; 0ABF
        jsr     ResetSheet              ; 0AC1
        lda     #$01                    ; 0AC4
        sta     sheet                   ; 0AC6
        lda     #$00                    ; 0AC9
        sta     fly_on                  ; 0ACB
        sta     fly_timer               ; 0ACD
        sta     fly_timer+1             ; 0ACF
        sta     fly_ptr                 ; 0AD1
        sta     fly_ptr+1               ; 0AD3
        lda     #$02                    ; 0AD5
        sta     snake_dir               ; 0AD7
        lda     #$01                    ; 0AD9
        sta     snake_col               ; 0ADB
        lda     #$D8                    ; 0ADD
        sta     snake_row               ; 0ADF
        lda     #$BD                    ; 0AE1
        sta     snake_row+1             ; 0AE3
        lda     #$07                    ; 0AE5
        sta     warble_dir              ; 0AE7
        sta     warble_level            ; 0AE9
        lda     #$1F                    ; 0AEB
        sta     turtle_speed            ; 0AED
        lda     #$07                    ; 0AF0
        sta     snake_speed             ; 0AF2
        jsr     PickTune                ; 0AF5
        nop                             ; 0AF8
        nop                             ; 0AF9
        nop                             ; 0AFA
        nop                             ; 0AFB
        nop                             ; 0AFC
        nop                             ; 0AFD
        nop                             ; 0AFE
        rts                             ; 0AFF

;------------------------------------------------------------------------------
; Lane scrollers. Each moves a two-row lane one column; the river lanes
; (rows 7, 10, 13) wrap round, the others are fed by the Spawn routines.
;------------------------------------------------------------------------------
ScrollRow7Left:
        lda     SCREEN+7*40+2           ; 0B00
        sta     tmp0                    ; 0B03
        lda     SCREEN+8*40+2           ; 0B05
        sta     key_state               ; 0B08
        ldy     #$00                    ; 0B0A
L0B0C:
        lda     SCREEN+7*40+3,y         ; 0B0C
        sta     SCREEN+7*40+2,y         ; 0B0F
        lda     SCREEN+8*40+3,y         ; 0B12
        sta     SCREEN+8*40+2,y         ; 0B15
        iny                             ; 0B18
        cpy     #$26                    ; 0B19
        bne     L0B0C                   ; 0B1B
        jmp     WrapRow7                ; 0B1D

ScrollRow13Left:
        lda     SCREEN+13*40+2          ; 0B20
        sta     tmp0                    ; 0B23
        lda     SCREEN+14*40+2          ; 0B25
        sta     key_state               ; 0B28
        ldy     #$00                    ; 0B2A
L0B2C:
        lda     SCREEN+13*40+3,y        ; 0B2C
        sta     SCREEN+13*40+2,y        ; 0B2F
        lda     SCREEN+14*40+3,y        ; 0B32
        sta     SCREEN+14*40+2,y        ; 0B35
        iny                             ; 0B38
        cpy     #$26                    ; 0B39
        bne     L0B2C                   ; 0B3B
        jmp     WrapRow13               ; 0B3D

ScrollRow4Right:
        ldy     #$24                    ; 0B40
L0B42:
        lda     SCREEN+4*40+2,y         ; 0B42
        sta     SCREEN+4*40+3,y         ; 0B45
        lda     SCREEN+5*40+2,y         ; 0B48
        sta     SCREEN+5*40+3,y         ; 0B4B
        dey                             ; 0B4E
        bpl     L0B42                   ; 0B4F
        rts                             ; 0B51
        .res    12, $FF                 ; 0B52

ScrollRow10Right:
        lda     SCREEN+10*40+39         ; 0B5E
        sta     tmp0                    ; 0B61
        lda     SCREEN+11*40+39         ; 0B63
        sta     key_state               ; 0B66
        ldy     #$24                    ; 0B68
L0B6A:
        lda     SCREEN+10*40+2,y        ; 0B6A
        sta     SCREEN+10*40+3,y        ; 0B6D
        lda     SCREEN+11*40+2,y        ; 0B70
        sta     SCREEN+11*40+3,y        ; 0B73
        dey                             ; 0B76
        bpl     L0B6A                   ; 0B77
        jmp     WrapRow10               ; 0B79

ScrollRow17Left:
        ldy     #$00                    ; 0B7C
L0B7E:
        lda     SCREEN+17*40+3,y        ; 0B7E
        sta     SCREEN+17*40+2,y        ; 0B81
        lda     SCREEN+18*40+3,y        ; 0B84
        sta     SCREEN+18*40+2,y        ; 0B87
        iny                             ; 0B8A
        cpy     #$25                    ; 0B8B
        bne     L0B7E                   ; 0B8D
        rts                             ; 0B8F

ScrollRow20Right:
        ldy     #$24                    ; 0B90
L0B92:
        lda     SCREEN+20*40+2,y        ; 0B92
        sta     SCREEN+20*40+3,y        ; 0B95
        lda     SCREEN+21*40+2,y        ; 0B98
        sta     SCREEN+21*40+3,y        ; 0B9B
        dey                             ; 0B9E
        bpl     L0B92                   ; 0B9F
        lda     #$20                    ; 0BA1
        rts                             ; 0BA3
        .res    6, $FF                  ; 0BA4

ScrollRow23Left:
        ldy     #$00                    ; 0BAA
L0BAC:
        lda     SCREEN+23*40+3,y        ; 0BAC
        sta     SCREEN+23*40+2,y        ; 0BAF
        lda     SCREEN+24*40+3,y        ; 0BB2
        sta     SCREEN+24*40+2,y        ; 0BB5
        iny                             ; 0BB8
        cpy     #$25                    ; 0BB9
        bne     L0BAC                   ; 0BBB
        rts                             ; 0BBD
        .byte   $FF,$FF                                   ; 0BBE

;------------------------------------------------------------------------------
; SpawnRow23 / SpawnRow17 / SpawnRow20 / SpawnRow4 - feed new objects
; into a lane at its edge: a random-length gap of spaces, then the object's
; characters one column per call.
;------------------------------------------------------------------------------
SpawnRow23:
        lda     r23_state               ; 0BC0
        bne     L0BF6                   ; 0BC3
        lda     r23_first               ; 0BC5
        beq     L0BD8                   ; 0BC8
        dec     r23_first               ; 0BCA
        jsr     Random8                 ; 0BCD
        adc     r23_gap_min             ; 0BD0
        nop                             ; 0BD3
        sta     r23_gap                 ; 0BD4
        nop                             ; 0BD7
L0BD8:
        lda     #$20                    ; 0BD8
        sta     SCREEN+23*40+39         ; 0BDA
        sta     SCREEN+24*40+39         ; 0BDD
        dec     r23_gap                 ; 0BE0
        lda     r23_gap                 ; 0BE3
        bmi     L0BE9                   ; 0BE6
        rts                             ; 0BE8
L0BE9:
        inc     r23_state               ; 0BE9
        jsr     RandomNext              ; 0BEC
        lda     rand_seed+1             ; 0BEF
        and     #$03                    ; 0BF1
        sta     r23_len                 ; 0BF3
L0BF6:
        lda     r23_state               ; 0BF6
        cmp     #$01                    ; 0BF9
        bne     L0C0B                   ; 0BFB
        lda     #$74                    ; 0BFD
        sta     SCREEN+23*40+39         ; 0BFF
        lda     #$78                    ; 0C02
        sta     SCREEN+24*40+39         ; 0C04
        inc     r23_state               ; 0C07
        rts                             ; 0C0A
L0C0B:
        cmp     #$02                    ; 0C0B
        bne     L0C1D                   ; 0C0D
        lda     #$75                    ; 0C0F
        sta     SCREEN+23*40+39         ; 0C11
        lda     #$79                    ; 0C14
        sta     SCREEN+24*40+39         ; 0C16
        inc     r23_state               ; 0C19
        rts                             ; 0C1C
L0C1D:
        cmp     #$03                    ; 0C1D
        bne     L0C3A                   ; 0C1F
        lda     #$76                    ; 0C21
        sta     SCREEN+23*40+39         ; 0C23
        lda     #$7A                    ; 0C26
        sta     SCREEN+24*40+39         ; 0C28
        dec     r23_len                 ; 0C2B
        bmi     L0C31                   ; 0C2E
        rts                             ; 0C30
L0C31:
        inc     r23_state               ; 0C31
        lda     #$00                    ; 0C34
        sta     r23_len                 ; 0C36
        rts                             ; 0C39
L0C3A:
        cmp     #$04                    ; 0C3A
        bne     L0C48                   ; 0C3C
        lda     #$77                    ; 0C3E
        sta     SCREEN+23*40+39         ; 0C40
        lda     #$7B                    ; 0C43
        sta     SCREEN+24*40+39         ; 0C45
L0C48:
        lda     #$00                    ; 0C48
        sta     r23_state               ; 0C4A
        lda     #$01                    ; 0C4D
        sta     r23_first               ; 0C4F
        nop                             ; 0C52
        nop                             ; 0C53
        nop                             ; 0C54
        nop                             ; 0C55
        nop                             ; 0C56
        rts                             ; 0C57
        .res    8, $55                  ; 0C58

SpawnRow17:
        lda     r17_state               ; 0C60
        bne     L0C96                   ; 0C63
        lda     r17_first               ; 0C65
        beq     L0C78                   ; 0C68
        dec     r17_first               ; 0C6A
        jsr     Random8                 ; 0C6D
        adc     r17_gap_min             ; 0C70
        nop                             ; 0C73
        sta     r17_gap                 ; 0C74
        nop                             ; 0C77
L0C78:
        lda     #$20                    ; 0C78
        sta     SCREEN+17*40+39         ; 0C7A
        sta     SCREEN+18*40+39         ; 0C7D
        dec     r17_gap                 ; 0C80
        lda     r17_gap                 ; 0C83
        bmi     L0C89                   ; 0C86
        rts                             ; 0C88
L0C89:
        inc     r17_state               ; 0C89
        jsr     RandomNext              ; 0C8C
        lda     rand_seed+1             ; 0C8F
        and     #$03                    ; 0C91
        sta     r17_len                 ; 0C93
L0C96:
        lda     r17_state               ; 0C96
        cmp     #$01                    ; 0C99
        bne     L0CAB                   ; 0C9B
        lda     #$21                    ; 0C9D
        sta     SCREEN+17*40+39         ; 0C9F
        lda     #$26                    ; 0CA2
        sta     SCREEN+18*40+39         ; 0CA4
        inc     r17_state               ; 0CA7
        rts                             ; 0CAA
L0CAB:
        cmp     #$02                    ; 0CAB
        bne     L0CBD                   ; 0CAD
        lda     #$22                    ; 0CAF
        sta     SCREEN+17*40+39         ; 0CB1
        lda     #$27                    ; 0CB4
        sta     SCREEN+18*40+39         ; 0CB6
        inc     r17_state               ; 0CB9
        rts                             ; 0CBC
L0CBD:
        cmp     #$03                    ; 0CBD
        bne     L0CDA                   ; 0CBF
        lda     #$23                    ; 0CC1
        sta     SCREEN+17*40+39         ; 0CC3
        lda     #$28                    ; 0CC6
        sta     SCREEN+18*40+39         ; 0CC8
        dec     r17_len                 ; 0CCB
        bmi     L0CD1                   ; 0CCE
        rts                             ; 0CD0
L0CD1:
        inc     r17_state               ; 0CD1
        lda     #$00                    ; 0CD4
        sta     r17_len                 ; 0CD6
        rts                             ; 0CD9
L0CDA:
        cmp     #$04                    ; 0CDA
        bne     L0CEC                   ; 0CDC
        lda     #$24                    ; 0CDE
        sta     SCREEN+17*40+39         ; 0CE0
        lda     #$29                    ; 0CE3
        sta     SCREEN+18*40+39         ; 0CE5
        inc     r17_state               ; 0CE8
        rts                             ; 0CEB
L0CEC:
        cmp     #$05                    ; 0CEC
        bne     L0CFC                   ; 0CEE
        lda     #$25                    ; 0CF0
        sta     SCREEN+17*40+39         ; 0CF2
        lda     #$2A                    ; 0CF5
        sta     SCREEN+18*40+39         ; 0CF7
        lda     #$00                    ; 0CFA
L0CFC:
        sta     r17_state               ; 0CFC
        lda     #$01                    ; 0CFF
        sta     r17_first               ; 0D01
        rts                             ; 0D04
WrapRow7:
        lda     tmp0                    ; 0D05
        sta     SCREEN+7*40+39          ; 0D07
        lda     key_state               ; 0D0A
        sta     SCREEN+8*40+39          ; 0D0C
        rts                             ; 0D0F
WrapRow13:
        lda     tmp0                    ; 0D10
        sta     SCREEN+13*40+39         ; 0D12
        lda     key_state               ; 0D15
        sta     SCREEN+14*40+39         ; 0D17
        rts                             ; 0D1A
        .res    5, $FF                  ; 0D1B
WrapRow10:
        lda     tmp0                    ; 0D20
        sta     SCREEN+10*40+2          ; 0D22
        lda     key_state               ; 0D25
        sta     SCREEN+11*40+2          ; 0D27
        rts                             ; 0D2A
        .res    5, $FF                  ; 0D2B

SpawnRow20:
        lda     r20_state               ; 0D30
        bne     L0D66                   ; 0D33
        lda     r20_first               ; 0D35
        beq     L0D48                   ; 0D38
        dec     r20_first               ; 0D3A
        jsr     Random8                 ; 0D3D
        adc     r20_gap_min             ; 0D40
        nop                             ; 0D43
        sta     r20_gap                 ; 0D44
        nop                             ; 0D47
L0D48:
        lda     #$20                    ; 0D48
        sta     SCREEN+20*40+2          ; 0D4A
        sta     SCREEN+21*40+2          ; 0D4D
        dec     r20_gap                 ; 0D50
        lda     r20_gap                 ; 0D53
        bmi     L0D59                   ; 0D56
        rts                             ; 0D58
L0D59:
        inc     r20_state               ; 0D59
        jsr     RandomNext              ; 0D5C
        lda     rand_seed+1             ; 0D5F
        and     #$03                    ; 0D61
        sta     r20_len                 ; 0D63
L0D66:
        lda     r20_state               ; 0D66
        cmp     #$01                    ; 0D69
        bne     L0D7B                   ; 0D6B
        lda     #$69                    ; 0D6D
        sta     SCREEN+20*40+2          ; 0D6F
        lda     #$6D                    ; 0D72
        sta     SCREEN+21*40+2          ; 0D74
        inc     r20_state               ; 0D77
        rts                             ; 0D7A
L0D7B:
        cmp     #$02                    ; 0D7B
        bne     L0D8D                   ; 0D7D
        lda     #$68                    ; 0D7F
        sta     SCREEN+20*40+2          ; 0D81
        lda     #$6C                    ; 0D84
        sta     SCREEN+21*40+2          ; 0D86
        inc     r20_state               ; 0D89
        rts                             ; 0D8C
L0D8D:
        cmp     #$03                    ; 0D8D
        bne     L0D9F                   ; 0D8F
        lda     #$67                    ; 0D91
        sta     SCREEN+20*40+2          ; 0D93
        lda     #$6B                    ; 0D96
        sta     SCREEN+21*40+2          ; 0D98
        inc     r20_state               ; 0D9B
        rts                             ; 0D9E
L0D9F:
        cmp     #$04                    ; 0D9F
        bne     L0DAD                   ; 0DA1
        lda     #$66                    ; 0DA3
        sta     SCREEN+20*40+2          ; 0DA5
        lda     #$6A                    ; 0DA8
        sta     SCREEN+21*40+2          ; 0DAA
L0DAD:
        lda     #$00                    ; 0DAD
        sta     r20_state               ; 0DAF
        lda     #$01                    ; 0DB2
        sta     r20_first               ; 0DB4
        rts                             ; 0DB7

;------------------------------------------------------------------------------
; FrameDelay - busy-wait game_delay x 256 loops, servicing the timer.
;------------------------------------------------------------------------------
FrameDelay:
        jmp     FrameDelayC64           ; 0DB8  C64: timed wait, draws the screen
        ldy     #$00                    ; 0DBB
L0DBD:
        nop                             ; 0DBD
        dey                             ; 0DBE
        bne     L0DBD                   ; 0DBF
        jsr     ServiceTimer            ; 0DC1
        nop                             ; 0DC4
        nop                             ; 0DC5
        dex                             ; 0DC6
        bne     L0DBD                   ; 0DC7
        rts                             ; 0DC9

;------------------------------------------------------------------------------
; CheckLanding - after a hop: frog row 9 = reached a home; on the river
; rows (5-8) the frog drowns if any of its four cells is water (a space).
;------------------------------------------------------------------------------
CheckLanding:
        lda     frog_row                ; 0DCA
        cmp     #$09                    ; 0DCD
        bne     L0DD4                   ; 0DCF
        jmp     FrogHome                ; 0DD1
L0DD4:
        clc                             ; 0DD4
        cmp     #$05                    ; 0DD5
        bcs     L0DDA                   ; 0DD7
        rts                             ; 0DD9
L0DDA:
        ldx     #$03                    ; 0DDA
L0DDC:
        ldy     frog_offsets,x          ; 0DDC
        lda     (frog_pos),y            ; 0DDF
        cmp     #$20                    ; 0DE1
        beq     L0DE9                   ; 0DE3
        dex                             ; 0DE5
        bpl     L0DDC                   ; 0DE6
        rts                             ; 0DE8
L0DE9:
        jmp     FrogDies                ; 0DE9
        .res    4, $FF                  ; 0DEC

;------------------------------------------------------------------------------
; Delay48 / DelayX - busy-wait X x 256 loops (Delay48: X = 48).
;------------------------------------------------------------------------------
Delay48:
        ldx     #$30                    ; 0DF0

DelayX:
        jmp     DelayXC64               ; 0DF2  C64: timed wait, draws the screen
L0DF4 := * - 1                  ; 0DF4: inside the jmp above (only the dead loop uses it)
        bne     L0DF4                   ; 0DF5
        dex                             ; 0DF7
        bne     DelayX                  ; 0DF8
        rts                             ; 0DFA
        .res    5, $FF                  ; 0DFB

;------------------------------------------------------------------------------
; The frog as 2x2 characters ($3A-$3D), four directions x 32 bytes:
; up, down, left, right. SetFrogGfx copies one set to CHARSET+$3A*8.
;------------------------------------------------------------------------------
frog_gfx:
        .byte   W6(%00000011)           ; 0E00 ....##  +0
        .byte   W6(%00100111)           ; 0E01 #..###
        .byte   W6(%00100111)           ; 0E02 #..###
        .byte   W6(%00110101)           ; 0E03 ##.#.#
        .byte   W6(%00110101)           ; 0E04 ##.#.#
        .byte   W6(%00011111)           ; 0E05 .#####
        .byte   W6(%00011111)           ; 0E06 .#####
        .byte   W6(%00001111)           ; 0E07 ..####
        .byte   W6(%00110000)           ; 0E08 ##....  +8
        .byte   W6(%00111001)           ; 0E09 ###..#
        .byte   W6(%00111001)           ; 0E0A ###..#
        .byte   W6(%00101011)           ; 0E0B #.#.##
        .byte   W6(%00101011)           ; 0E0C #.#.##
        .byte   W6(%00111110)           ; 0E0D #####.
        .byte   W6(%00111110)           ; 0E0E #####.
        .byte   W6(%00111100)           ; 0E0F ####..
        .byte   W6(%00001111)           ; 0E10 ..####  +16
        .byte   W6(%00001111)           ; 0E11 ..####
        .byte   W6(%00001111)           ; 0E12 ..####
        .byte   W6(%00000111)           ; 0E13 ...###
        .byte   W6(%00100111)           ; 0E14 #..###
        .byte   W6(%00111110)           ; 0E15 #####.
        .byte   W6(%00011100)           ; 0E16 .###..
        .byte   W6(%00000000)           ; 0E17 ......
        .byte   W6(%00111100)           ; 0E18 ####..  +24
        .byte   W6(%00111100)           ; 0E19 ####..
        .byte   W6(%00111100)           ; 0E1A ####..
        .byte   W6(%00111000)           ; 0E1B ###...
        .byte   W6(%00111001)           ; 0E1C ###..#
        .byte   W6(%00011111)           ; 0E1D .#####
        .byte   W6(%00001110)           ; 0E1E ..###.
        .byte   W6(%00000000)           ; 0E1F ......
        .byte   W6(%00000000)           ; 0E20 ......  +32
        .byte   W6(%00011100)           ; 0E21 .###..
        .byte   W6(%00111110)           ; 0E22 #####.
        .byte   W6(%00100111)           ; 0E23 #..###
        .byte   W6(%00000111)           ; 0E24 ...###
        .byte   W6(%00001111)           ; 0E25 ..####
        .byte   W6(%00001111)           ; 0E26 ..####
        .byte   W6(%00001111)           ; 0E27 ..####
        .byte   W6(%00000000)           ; 0E28 ......  +40
        .byte   W6(%00001110)           ; 0E29 ..###.
        .byte   W6(%00011111)           ; 0E2A .#####
        .byte   W6(%00111001)           ; 0E2B ###..#
        .byte   W6(%00111000)           ; 0E2C ###...
        .byte   W6(%00111100)           ; 0E2D ####..
        .byte   W6(%00111100)           ; 0E2E ####..
        .byte   W6(%00111100)           ; 0E2F ####..
        .byte   W6(%00001111)           ; 0E30 ..####  +48
        .byte   W6(%00011111)           ; 0E31 .#####
        .byte   W6(%00011111)           ; 0E32 .#####
        .byte   W6(%00110101)           ; 0E33 ##.#.#
        .byte   W6(%00110101)           ; 0E34 ##.#.#
        .byte   W6(%00100111)           ; 0E35 #..###
        .byte   W6(%00100111)           ; 0E36 #..###
        .byte   W6(%00000011)           ; 0E37 ....##
        .byte   W6(%00111100)           ; 0E38 ####..  +56
        .byte   W6(%00111110)           ; 0E39 #####.
        .byte   W6(%00111110)           ; 0E3A #####.
        .byte   W6(%00101011)           ; 0E3B #.#.##
        .byte   W6(%00101011)           ; 0E3C #.#.##
        .byte   W6(%00111001)           ; 0E3D ###..#
        .byte   W6(%00111001)           ; 0E3E ###..#
        .byte   W6(%00110000)           ; 0E3F ##....
        .byte   W6(%00000000)           ; 0E40 ......  +64
        .byte   W6(%00111100)           ; 0E41 ####..
        .byte   W6(%00001110)           ; 0E42 ..###.
        .byte   W6(%00000111)           ; 0E43 ...###
        .byte   W6(%00001111)           ; 0E44 ..####
        .byte   W6(%00011111)           ; 0E45 .#####
        .byte   W6(%00110011)           ; 0E46 ##..##
        .byte   W6(%00111111)           ; 0E47 ######
        .byte   W6(%00000000)           ; 0E48 ......  +72
        .byte   W6(%00011100)           ; 0E49 .###..
        .byte   W6(%00000110)           ; 0E4A ...##.
        .byte   W6(%00110110)           ; 0E4B ##.##.
        .byte   W6(%00111110)           ; 0E4C #####.
        .byte   W6(%00111100)           ; 0E4D ####..
        .byte   W6(%00111000)           ; 0E4E ###...
        .byte   W6(%00111000)           ; 0E4F ###...
        .byte   W6(%00111111)           ; 0E50 ######  +80
        .byte   W6(%00110011)           ; 0E51 ##..##
        .byte   W6(%00011111)           ; 0E52 .#####
        .byte   W6(%00001111)           ; 0E53 ..####
        .byte   W6(%00000111)           ; 0E54 ...###
        .byte   W6(%00001110)           ; 0E55 ..###.
        .byte   W6(%00111100)           ; 0E56 ####..
        .byte   W6(%00000000)           ; 0E57 ......
        .byte   W6(%00111000)           ; 0E58 ###...  +88
        .byte   W6(%00111000)           ; 0E59 ###...
        .byte   W6(%00111100)           ; 0E5A ####..
        .byte   W6(%00111110)           ; 0E5B #####.
        .byte   W6(%00110110)           ; 0E5C ##.##.
        .byte   W6(%00000110)           ; 0E5D ...##.
        .byte   W6(%00011100)           ; 0E5E .###..
        .byte   W6(%00000000)           ; 0E5F ......
        .byte   W6(%00000000)           ; 0E60 ......  +96
        .byte   W6(%00001110)           ; 0E61 ..###.
        .byte   W6(%00011000)           ; 0E62 .##...
        .byte   W6(%00011011)           ; 0E63 .##.##
        .byte   W6(%00011111)           ; 0E64 .#####
        .byte   W6(%00001111)           ; 0E65 ..####
        .byte   W6(%00000111)           ; 0E66 ...###
        .byte   W6(%00000011)           ; 0E67 ....##
        .byte   W6(%00000000)           ; 0E68 ......  +104
        .byte   W6(%00001111)           ; 0E69 ..####
        .byte   W6(%00011100)           ; 0E6A .###..
        .byte   W6(%00111000)           ; 0E6B ###...
        .byte   W6(%00111100)           ; 0E6C ####..
        .byte   W6(%00111110)           ; 0E6D #####.
        .byte   W6(%00110011)           ; 0E6E ##..##
        .byte   W6(%00111111)           ; 0E6F ######
        .byte   W6(%00000111)           ; 0E70 ...###  +112
        .byte   W6(%00000111)           ; 0E71 ...###
        .byte   W6(%00001111)           ; 0E72 ..####
        .byte   W6(%00011111)           ; 0E73 .#####
        .byte   W6(%00011011)           ; 0E74 .##.##
        .byte   W6(%00011000)           ; 0E75 .##...
        .byte   W6(%00001110)           ; 0E76 ..###.
        .byte   W6(%00000000)           ; 0E77 ......
        .byte   W6(%00111111)           ; 0E78 ######  +120
        .byte   W6(%00110011)           ; 0E79 ##..##
        .byte   W6(%00111110)           ; 0E7A #####.
        .byte   W6(%00111100)           ; 0E7B ####..
        .byte   W6(%00111000)           ; 0E7C ###...
        .byte   W6(%00011100)           ; 0E7D .###..
        .byte   W6(%00001111)           ; 0E7E ..####
        .byte   W6(%00000000)           ; 0E7F ......

;------------------------------------------------------------------------------
; ReadKeys - scan the five control keys through the VIA and AY port A,
; returning a bit for each pressed key in key_state (see key_bits).
;------------------------------------------------------------------------------
ReadKeys:
        jmp     ReadKeysC64             ; 0E80  C64: CIA keyboard + joystick
        nop                             ; 0E83  C64: pad
        sta     key_state               ; 0E84
L0E86:
        lda     key_rows,x              ; 0E86
        sta     VIA_ORB                 ; 0E89
        lda     key_cols,x              ; 0E8C
        stx     tmp0                    ; 0E8F
        ldy     #$0E                    ; 0E91
        tax                             ; 0E93
        tya                             ; 0E94
        jsr     AYWrite                 ; 0E95
        ldx     tmp0                    ; 0E98
        lda     #$08                    ; 0E9A
        bit     VIA_ORB                 ; 0E9C
        beq     L0EA8                   ; 0E9F
        lda     key_bits,x              ; 0EA1
        ora     key_state               ; 0EA4
        sta     key_state               ; 0EA6
L0EA8:
        dex                             ; 0EA8
        bpl     L0E86                   ; 0EA9
        rts                             ; 0EAB
        .res    4, $FF                  ; 0EAC

;------------------------------------------------------------------------------
; KeysToDir - convert key_state to frog_dir (0 none, 1 up, 2 down, 3 left, 4 right).
;------------------------------------------------------------------------------
KeysToDir:
        jsr     ReadKeys                ; 0EB0
        lda     key_state               ; 0EB3
        cmp     #$20                    ; 0EB5
        bne     L0EBE                   ; 0EB7
        lda     #$03                    ; 0EB9
        sta     frog_dir                ; 0EBB
        rts                             ; 0EBD
L0EBE:
        cmp     #$10                    ; 0EBE
        bne     L0EC7                   ; 0EC0
        lda     #$04                    ; 0EC2
        sta     frog_dir                ; 0EC4
        rts                             ; 0EC6
L0EC7:
        cmp     #$04                    ; 0EC7
        bne     L0ED0                   ; 0EC9
        lda     #$01                    ; 0ECB
        sta     frog_dir                ; 0ECD
        rts                             ; 0ECF
L0ED0:
        cmp     #$08                    ; 0ED0
        bne     L0ED9                   ; 0ED2
        lda     #$02                    ; 0ED4
        sta     frog_dir                ; 0ED6
        rts                             ; 0ED8
L0ED9:
        lda     #$00                    ; 0ED9
        sta     frog_dir                ; 0EDB
        rts                             ; 0EDD
        .byte   $FF,$FF                                   ; 0EDE

;------------------------------------------------------------------------------
; Keyboard matrix row for each control key (left, right, down, up,
; pause: key_bits $08 is down and $04 up, see KeysToDir). ControlsMenu
; overwrites these three tables.
; C64: key_rows holds the CIA1 port A column select, key_cols the port B
; row mask (see ReadKeysC64 in c64/src/input.s).
;------------------------------------------------------------------------------
key_rows:
        .byte   $FD,$FB,$EF,$EF,$DF                       ; 0EE0  C64: CIA1 port A column select (Z X M K P)

;------------------------------------------------------------------------------
; Column mask for each control key.
;------------------------------------------------------------------------------
key_cols:
        .byte   $10,$80,$10,$20,$02                       ; 0EE5  C64: CIA1 port B row mask

;------------------------------------------------------------------------------
; Bit reported in key_state for each key.
;------------------------------------------------------------------------------
key_bits:
        .byte   $20,$10,$08,$04,$80                       ; 0EEA
        .byte   $FF,$00,$FF                               ; 0EEF
        .res    14, $FF                 ; 0EF2

;------------------------------------------------------------------------------
; DrawFrog - draw the frog's 2x2 characters at frog_pos.
;------------------------------------------------------------------------------
DrawFrog:
        ldx     #$03                    ; 0F00
L0F02:
        ldy     frog_offsets,x          ; 0F02
        lda     frog_chars,x            ; 0F05
        sta     (frog_pos),y            ; 0F08
        dex                             ; 0F0A
        bpl     L0F02                   ; 0F0B
        rts                             ; 0F0D
        .byte   $FF,$FF                                   ; 0F0E

;------------------------------------------------------------------------------
; Screen offsets of the frog's four characters: 0, 1, 40, 41.
;------------------------------------------------------------------------------
frog_offsets:
        .byte   $00,$01,$28,$29                           ; 0F10
        .byte   $FF                                       ; 0F14

;------------------------------------------------------------------------------
; Character codes of the frog.
;------------------------------------------------------------------------------
frog_chars:
        .byte   $3A,$3B,$3C,$3D                           ; 0F15
        .res    7, $FF                  ; 0F19

;------------------------------------------------------------------------------
; SetFrogGfx - load the frog graphics for frog_dir into chars $3A-$3D.
;------------------------------------------------------------------------------
SetFrogGfx:
        ldx     #$1F                    ; 0F20
        lda     frog_dir                ; 0F22
        cmp     #$01                    ; 0F24
        bne     L0F32                   ; 0F26
L0F28:
        lda     frog_gfx,x              ; 0F28
        sta     CHARSET+$3A*8,x         ; 0F2B
        dex                             ; 0F2E
        bpl     L0F28                   ; 0F2F
        rts                             ; 0F31
L0F32:
        cmp     #$02                    ; 0F32
        bne     L0F40                   ; 0F34
L0F36:
        lda     frog_gfx+32,x           ; 0F36
        sta     CHARSET+$3A*8,x         ; 0F39
        dex                             ; 0F3C
        bpl     L0F36                   ; 0F3D
        rts                             ; 0F3F
L0F40:
        cmp     #$03                    ; 0F40
        bne     L0F4E                   ; 0F42
L0F44:
        lda     frog_gfx+64,x           ; 0F44
        sta     CHARSET+$3A*8,x         ; 0F47
        dex                             ; 0F4A
        bpl     L0F44                   ; 0F4B
        rts                             ; 0F4D
L0F4E:
        cmp     #$04                    ; 0F4E
        bne     L0F5B                   ; 0F50
L0F52:
        lda     frog_gfx+96,x           ; 0F52
        sta     CHARSET+$3A*8,x         ; 0F55
        dex                             ; 0F58
        bpl     L0F52                   ; 0F59
L0F5B:
        rts                             ; 0F5B

;------------------------------------------------------------------------------
; Screen bytes to move up from each frog row (80 = two text rows).
;------------------------------------------------------------------------------
row_steps_up:
        .byte   $50,$78,$78,$50,$50,$78,$78,$78           ; 0F5C
        .byte   $78                                       ; 0F64

;------------------------------------------------------------------------------
; Screen bytes to move down from each frog row.
;------------------------------------------------------------------------------
row_steps_down:
        .byte   $50,$50,$78,$78,$50,$50,$78,$78           ; 0F65
        .byte   $78,$78                                   ; 0F6D
        .byte   $78                                       ; 0F6F

;------------------------------------------------------------------------------
; StepFrog - move frog_pos one hop in frog_dir, updating frog_row / frog_col.
;------------------------------------------------------------------------------
StepFrog:
        lda     frog_dir                ; 0F70
        cmp     #$01                    ; 0F72
        bne     L0F8F                   ; 0F74
        ldx     frog_row                ; 0F76
        lda     row_steps_up,x          ; 0F79
        sta     step_size               ; 0F7C
        sec                             ; 0F7E
        lda     frog_pos                ; 0F7F
        sbc     step_size               ; 0F81
        sta     frog_pos                ; 0F83
        lda     frog_pos+1              ; 0F85
        sbc     #$00                    ; 0F87
        sta     frog_pos+1              ; 0F89
        inc     frog_row                ; 0F8B
        rts                             ; 0F8E
L0F8F:
        cmp     #$02                    ; 0F8F
        bne     L0FAC                   ; 0F91
        ldx     frog_row                ; 0F93
        lda     row_steps_down,x        ; 0F96
        sta     step_size               ; 0F99
        clc                             ; 0F9B
        lda     frog_pos                ; 0F9C
        adc     step_size               ; 0F9E
        sta     frog_pos                ; 0FA0
        lda     frog_pos+1              ; 0FA2
        adc     #$00                    ; 0FA4
        sta     frog_pos+1              ; 0FA6
        dec     frog_row                ; 0FA8
        rts                             ; 0FAB
L0FAC:
        cmp     #$03                    ; 0FAC
        bne     L0FC4                   ; 0FAE
        sec                             ; 0FB0
        lda     frog_pos                ; 0FB1
        sbc     #$02                    ; 0FB3
        sta     frog_pos                ; 0FB5
        lda     frog_pos+1              ; 0FB7
        sbc     #$00                    ; 0FB9
        sta     frog_pos+1              ; 0FBB
        dec     frog_col                ; 0FBD
        dec     frog_col                ; 0FC0
        rts                             ; 0FC3
L0FC4:
        cmp     #$04                    ; 0FC4
        bne     L0FDB                   ; 0FC6
        clc                             ; 0FC8
        lda     frog_pos                ; 0FC9
        adc     #$02                    ; 0FCB
        sta     frog_pos                ; 0FCD
        lda     frog_pos+1              ; 0FCF
        adc     #$00                    ; 0FD1
        sta     frog_pos+1              ; 0FD3
        inc     frog_col                ; 0FD5
BadTarget_0FD6 := * - 2          ; 0FD6: target inside instruction above
        inc     frog_col                ; 0FD8
L0FDB:
        rts                             ; 0FDB
        .res    4, $FF                  ; 0FDC

;------------------------------------------------------------------------------
; CheckFrogBounds - kill the frog if it has gone off the screen.
; NOTE: an original bug. The `bcs` below branches to $0FD6, the middle of an
; `inc` instruction. The byte there is $12, an illegal opcode that locks up
; an NMOS 6502. It only runs when frog_row >= 10, which the game never allows.
;------------------------------------------------------------------------------
CheckFrogBounds:
        lda     frog_row                ; 0FE0
        bpl     L0FE8                   ; 0FE3
        jmp     FrogDies                ; 0FE5
L0FE8:
        clc                             ; 0FE8
        lda     frog_row                ; 0FE9
        cmp     #$0A                    ; 0FEC
        bcs     BadTarget_0FD6          ; 0FEE  BUG: branches into an instruction (see header)
        lda     frog_col                ; 0FF0
        cmp     #$01                    ; 0FF3  C64: was #$02: column 2 is playfield (Remix)
        bpl     L0FFA                   ; 0FF5
L0FF7:
        jmp     LoseLife                ; 0FF7
L0FFA:
        clc                             ; 0FFA
        cmp     #$26                    ; 0FFB  C64: was #$25: column 39 is playfield (Remix)
        bpl     L0FF7                   ; 0FFD
        rts                             ; 0FFF

;------------------------------------------------------------------------------
; NewGame / MainLoop. Each pass: fly warble, fly, keyboard, frog
; movement, delay, turtles, music, pause, then each of the seven lanes when its
; timer expires, then the snake and the turtles' dive animation.
;------------------------------------------------------------------------------
NewGame:
        nop                             ; 1000  C64: was sei: raster IRQ must run
        jsr     InitGameC64             ; 1001  C64: ROM IRQ off, game rows
NewLife:
        ldx     #$FE                    ; 1004  reset stack: death paths jump back here
        txs                             ; 1006
        lda     #$07                    ; 1007
        sta     VIA_DDRB                ; 1009
        nop                             ; 100C
MainLoop:
        jsr     FlyWarble               ; 100D
        jsr     UpdateFly               ; 1010
        nop                             ; 1013
        jsr     CheckFrogBounds         ; 1014
        jsr     MoveFrog                ; 1017
        jsr     CheckFrogBounds         ; 101A
        jsr     FrameDelay              ; 101D
        jsr     CheckTurtleDive         ; 1020
        jsr     MusicTick               ; 1023
        jsr     CheckPause              ; 1026
        nop                             ; 1029
        nop                             ; 102A
        nop                             ; 102B
        nop                             ; 102C
        nop                             ; 102D
        nop                             ; 102E
        nop                             ; 102F
        ldx     #$06                    ; 1030
LaneLoop:
        stx     lane_index              ; 1032
        inc     lane_timer,x            ; 1034
        lda     lane_timer,x            ; 1036
        cmp     lane_speeds,x           ; 1038
        bne     L10A8                   ; 103B
        lda     #$00                    ; 103D
        sta     lane_timer,x            ; 103F
        cpx     #$06                    ; 1041
        bne     L1050                   ; 1043
        jsr     ScrollRow4Right         ; 1045
        jsr     CarryFrog               ; 1048
        jsr     SpawnRow4               ; 104B
        ldx     lane_index              ; 104E
L1050:
        cpx     #$05                    ; 1050
        bne     L105C                   ; 1052
        jsr     CarryFrog               ; 1054
        jsr     ScrollRow7Left          ; 1057
        ldx     lane_index              ; 105A
L105C:
        cpx     #$04                    ; 105C
        bne     L1068                   ; 105E
        jsr     CarryFrog               ; 1060
        jsr     ScrollRow10Right        ; 1063
        ldx     lane_index              ; 1066
L1068:
        cpx     #$03                    ; 1068
        bne     L1074                   ; 106A
        jsr     CarryFrog               ; 106C
        jsr     ScrollRow13Left         ; 106F
        ldx     lane_index              ; 1072
L1074:
        cpx     #$02                    ; 1074
        bne     L1086                   ; 1076
        jsr     EraseFrogIfRoad         ; 1078
        jsr     ScrollRow17Left         ; 107B
        jsr     SpawnRow17              ; 107E
        jsr     RedrawFrogIfRoad        ; 1081
        ldx     lane_index              ; 1084
L1086:
        cpx     #$01                    ; 1086
        bne     L1098                   ; 1088
        jsr     EraseFrogIfRoad         ; 108A
        jsr     ScrollRow20Right        ; 108D
        jsr     SpawnRow20              ; 1090
        jsr     RedrawFrogIfRoad        ; 1093
        ldx     lane_index              ; 1096
L1098:
        cpx     #$00                    ; 1098
        bne     L10A8                   ; 109A
        jsr     EraseFrogIfRoad         ; 109C
        jsr     ScrollRow23Left         ; 109F
        jsr     SpawnRow23              ; 10A2
        jsr     RedrawFrogIfRoad        ; 10A5
L10A8:
        jsr     ServiceTimer            ; 10A8
        ldx     lane_index              ; 10AB
        dex                             ; 10AD
        bpl     LaneLoop                ; 10AE
        inc     tmp4                    ; 10B0
        lda     tmp4                    ; 10B2
        and     snake_speed             ; 10B4
        cmp     snake_speed             ; 10B7
        bne     L10BF                   ; 10BA
        jsr     MoveSnake               ; 10BC
L10BF:
        lda     sheet                   ; 10BF
        cmp     #$02                    ; 10C2
        bmi     L10D5                   ; 10C4
        inc     tmp3                    ; 10C6
        lda     tmp3                    ; 10C8
        and     turtle_speed            ; 10CA
        cmp     turtle_speed            ; 10CD
        bne     L10D5                   ; 10D0
        jsr     AnimateTurtles          ; 10D2
L10D5:
        nop                             ; 10D5
        nop                             ; 10D6
        nop                             ; 10D7
        nop                             ; 10D8
        nop                             ; 10D9
        nop                             ; 10DA
        nop                             ; 10DB
        nop                             ; 10DC
        nop                             ; 10DD
        nop                             ; 10DE
        nop                             ; 10DF
        nop                             ; 10E0
        nop                             ; 10E1
        nop                             ; 10E2
        nop                             ; 10E3
        nop                             ; 10E4
        nop                             ; 10E5
        nop                             ; 10E6
        nop                             ; 10E7
        nop                             ; 10E8
        nop                             ; 10E9
        nop                             ; 10EA
        nop                             ; 10EB
        nop                             ; 10EC
        nop                             ; 10ED
        nop                             ; 10EE
        nop                             ; 10EF
        nop                             ; 10F0
        nop                             ; 10F1
        nop                             ; 10F2
        nop                             ; 10F3
        nop                             ; 10F4
        nop                             ; 10F5
        nop                             ; 10F6
        nop                             ; 10F7
        nop                             ; 10F8
        nop                             ; 10F9
        nop                             ; 10FA
        nop                             ; 10FB
        nop                             ; 10FC
        jmp     MainLoop                ; 10FD

;------------------------------------------------------------------------------
; SaveUnderFrog - copy the four screen cells under the frog to under_frog.
;------------------------------------------------------------------------------
SaveUnderFrog:
        ldx     #$03                    ; 1100
L1102:
        ldy     frog_offsets,x          ; 1102
        lda     (frog_pos),y            ; 1105
        sta     under_frog,x            ; 1107
        dex                             ; 110A
        bpl     L1102                   ; 110B
        rts                             ; 110D
        .byte   $EA,$EA                                   ; 110E

;------------------------------------------------------------------------------
; GetMove - read a direction, ignoring a key that is still held from the last hop.
;------------------------------------------------------------------------------
GetMove:
        jsr     KeysToDir               ; 1110
        lda     frog_dir                ; 1113
        and     key_mask                ; 1115
        cmp     last_dir                ; 1117
        bne     L1120                   ; 1119
        lda     #$00                    ; 111B
        sta     frog_dir                ; 111D
        rts                             ; 111F
L1120:
        sta     last_dir                ; 1120
        rts                             ; 1122
        .res    13, $FF                 ; 1123

;------------------------------------------------------------------------------
; RestoreUnderFrog - put back the four saved cells.
;------------------------------------------------------------------------------
RestoreUnderFrog:
        ldx     #$03                    ; 1130
L1132:
        ldy     frog_offsets,x          ; 1132
        lda     under_frog,x            ; 1135
        sta     (frog_pos),y            ; 1138
        dex                             ; 113A
        bpl     L1132                   ; 113B
        rts                             ; 113D
        .byte   $EA,$EA                                   ; 113E

;------------------------------------------------------------------------------
; AnimateTurtles - step the diving turtles through frames 0-6 and back.
;------------------------------------------------------------------------------
AnimateTurtles:
        lda     turtle_phase            ; 1140
        bne     L1148                   ; 1143
        inc     turtle_phase            ; 1145
L1148:
        lda     turtle_phase            ; 1148
        cmp     #$01                    ; 114B
        bne     L1168                   ; 114D
        jsr     SetTurtleFrame          ; 114F
        inc     turtle_frame            ; 1152
        lda     turtle_frame            ; 1155
        cmp     #$07                    ; 1158
        beq     L115D                   ; 115A
        rts                             ; 115C
L115D:
        lda     #$02                    ; 115D
        sta     turtle_phase            ; 115F
        lda     #$05                    ; 1162
        sta     turtle_frame            ; 1164
        rts                             ; 1167
L1168:
        jsr     SetTurtleFrame          ; 1168
        dec     turtle_frame            ; 116B
        lda     turtle_frame            ; 116E
        beq     L1174                   ; 1171
        rts                             ; 1173
L1174:
        lda     #$00                    ; 1174
        sta     turtle_phase            ; 1176
        lda     #$00                    ; 1179
        sta     turtle_frame            ; 117B
        rts                             ; 117E
        .byte   $FF                                       ; 117F

;------------------------------------------------------------------------------
; CarryFrog - when lane X scrolls and the frog is on it, move the frog too.
;------------------------------------------------------------------------------
CarryFrog:
        jmp     CarryFrogC64            ; 1180  C64: dies at the edge before it moves (Remix)
        nop                             ; 1183  C64: pad
        cmp     frog_row                ; 1184
        beq     L118A                   ; 1187
        rts                             ; 1189
L118A:
        sec                             ; 118A
        lda     frog_row                ; 118B
        cmp     #$05                    ; 118E
        bcs     L1193                   ; 1190
        rts                             ; 1192
L1193:
        cmp     #$05                    ; 1193
        bne     L11A8                   ; 1195
        sec                             ; 1197
        lda     frog_pos                ; 1198
        sbc     #$01                    ; 119A
        sta     frog_pos                ; 119C
        lda     frog_pos+1              ; 119E
        sbc     #$00                    ; 11A0
        sta     frog_pos+1              ; 11A2
        dec     frog_col                ; 11A4
        rts                             ; 11A7
L11A8:
        cmp     #$06                    ; 11A8
        bne     L11BD                   ; 11AA
        clc                             ; 11AC
        lda     frog_pos                ; 11AD
        adc     #$01                    ; 11AF
        sta     frog_pos                ; 11B1
        lda     frog_pos+1              ; 11B3
        adc     #$00                    ; 11B5
        sta     frog_pos+1              ; 11B7
        inc     frog_col                ; 11B9
        rts                             ; 11BC
L11BD:
        cmp     #$07                    ; 11BD
        bne     L11D2                   ; 11BF
        sec                             ; 11C1
        lda     frog_pos                ; 11C2
        sbc     #$01                    ; 11C4
        sta     frog_pos                ; 11C6
        lda     frog_pos+1              ; 11C8
        sbc     #$00                    ; 11CA
        sta     frog_pos+1              ; 11CC
        dec     frog_col                ; 11CE
        rts                             ; 11D1
L11D2:
        cmp     #$08                    ; 11D2
        bne     L11E6                   ; 11D4
        clc                             ; 11D6
        lda     frog_pos                ; 11D7
        adc     #$01                    ; 11D9
        sta     frog_pos                ; 11DB
        lda     frog_pos+1              ; 11DD
        adc     #$00                    ; 11DF
        sta     frog_pos+1              ; 11E1
        inc     frog_col                ; 11E3
L11E6:
        rts                             ; 11E6
        .byte   $FF,$20,$40,$11,$AD,$11,$04,$CD           ; 11E7
        .res    17, $FF                 ; 11EF

;------------------------------------------------------------------------------
; ResetSheet - put the frog at the start and run all lanes 49 times to fill them.
;------------------------------------------------------------------------------
ResetSheet:
        lda     #$13                    ; 1200
        sta     frog_col                ; 1202
        ldx     #$03                    ; 1205
L1207:
        lda     #$20                    ; 1207
        sta     under_frog,x            ; 1209
        dex                             ; 120C
        bpl     L1207                   ; 120D
        jsr     SetFrogGfx              ; 120F
        jsr     DrawFrog                ; 1212
        lda     #$01                    ; 1215
        sta     r4_first                ; 1217
        lda     #$04                    ; 121A
        sta     r4_gap_min              ; 121C
        lda     #$08                    ; 121F
        sta     r4_len_min              ; 1221
        jsr     SetFrogGfx              ; 1224
        jsr     DrawFrog                ; 1227
        lda     #$07                    ; 122A
        sta     r20_gap_min             ; 122C
        ldx     #$06                    ; 122F
        lda     #$00                    ; 1231
L1233:
        sta     lane_timer,x            ; 1233
        dex                             ; 1235
        bpl     L1233                   ; 1236
        lda     #$00                    ; 1238
        sta     lane_index              ; 123A

PrefillLanes:
        ldx     #$30                    ; 123C
L123E:
        stx     tmp0                    ; 123E
        jsr     ScrollRow4Right         ; 1240
        jsr     SpawnRow4               ; 1243
        jsr     ScrollRow17Left         ; 1246
        jsr     SpawnRow17              ; 1249
        jsr     ScrollRow20Right        ; 124C
        jsr     SpawnRow20              ; 124F
        jsr     ScrollRow23Left         ; 1252
        jsr     SpawnRow23              ; 1255
        ldx     tmp0                    ; 1258
        dex                             ; 125A
        bpl     L123E                   ; 125B
        nop                             ; 125D
        nop                             ; 125E
        rts                             ; 125F

;------------------------------------------------------------------------------
; EraseFrogIfRoad / RedrawFrogIfRoad - on the road rows (1-4) take the
; frog off the screen before a lane scrolls and put it back afterwards; if the
; cells are no longer empty a car has hit it.
;------------------------------------------------------------------------------
EraseFrogIfRoad:
        lda     frog_row                ; 1260
        bne     L1266                   ; 1263
L1265:
        rts                             ; 1265
L1266:
        sec                             ; 1266
        cmp     #$05                    ; 1267
        bpl     L1265                   ; 1269

EraseFrog:
        ldx     #$03                    ; 126B
L126D:
        ldy     frog_offsets,x          ; 126D
        lda     under_frog,x            ; 1270
        sta     (frog_pos),y            ; 1273
        dex                             ; 1275
        bpl     L126D                   ; 1276
        rts                             ; 1278
        .res    7, $EA                  ; 1279

RedrawFrogIfRoad:
        lda     frog_row                ; 1280
        bne     L1286                   ; 1283
L1285:
        rts                             ; 1285
L1286:
        sec                             ; 1286
        cmp     #$05                    ; 1287
        bpl     L1285                   ; 1289
        ldx     #$03                    ; 128B
L128D:
        ldy     frog_offsets,x          ; 128D
        lda     (frog_pos),y            ; 1290
        cmp     #$20                    ; 1292
        bne     L12A0                   ; 1294
        dex                             ; 1296
        bpl     L128D                   ; 1297
        jsr     DrawFrog                ; 1299
        rts                             ; 129C
        .byte   $EA,$EA,$EA                               ; 129D
L12A0:
        jmp     FrogDies                ; 12A0
        .res    13, $EA                 ; 12A3

SpawnRow4:
        lda     r4_state                ; 12B0
        bne     L12E6                   ; 12B3
        lda     r4_first                ; 12B5
        beq     L12C8                   ; 12B8
        dec     r4_first                ; 12BA
        jsr     Random8                 ; 12BD
        adc     r4_gap_min              ; 12C0
        nop                             ; 12C3
        sta     r4_gap                  ; 12C4
        nop                             ; 12C7
L12C8:
        lda     #$20                    ; 12C8
        sta     SCREEN+4*40+2           ; 12CA
        sta     SCREEN+5*40+2           ; 12CD
        dec     r4_gap                  ; 12D0
        lda     r4_gap                  ; 12D3
        bmi     L12D9                   ; 12D6
        rts                             ; 12D8
L12D9:
        inc     r4_state                ; 12D9
        jsr     Random8                 ; 12DC
        adc     r4_len_min              ; 12DF
        nop                             ; 12E2
        sta     r4_len                  ; 12E3
L12E6:
        lda     r4_state                ; 12E6
        cmp     #$01                    ; 12E9
        bne     L12FB                   ; 12EB
        lda     #$62                    ; 12ED
        sta     SCREEN+4*40+2           ; 12EF
        lda     #$65                    ; 12F2
        sta     SCREEN+5*40+2           ; 12F4
        inc     r4_state                ; 12F7
        rts                             ; 12FA
L12FB:
        cmp     #$02                    ; 12FB
        bne     L1313                   ; 12FD
        lda     #$61                    ; 12FF
        sta     SCREEN+4*40+2           ; 1301
        lda     #$64                    ; 1304
        sta     SCREEN+5*40+2           ; 1306
        dec     r4_len                  ; 1309
        bmi     L130F                   ; 130C
        rts                             ; 130E
L130F:
        inc     r4_state                ; 130F
        rts                             ; 1312
L1313:
        cmp     #$03                    ; 1313
        bne     L1321                   ; 1315
        lda     #$60                    ; 1317
        sta     SCREEN+4*40+2           ; 1319
        lda     #$63                    ; 131C
        sta     SCREEN+5*40+2           ; 131E
L1321:
        lda     #$00                    ; 1321
        sta     r4_state                ; 1323
        lda     #$01                    ; 1326
        sta     r4_first                ; 1328
        rts                             ; 132B
        .byte   $FF                                       ; 132C

;------------------------------------------------------------------------------
; FrogDies / LoseLife - death sequence, take a life, game over if none left,
; otherwise reset the frog and restart the main loop (the stack is reset).
;------------------------------------------------------------------------------
FrogDies:
        jsr     SaveUnderFrog           ; 132D
LoseLife:
        jsr     SilenceAll              ; 1330
        jsr     DeathSequence           ; 1333
        jsr     SilenceAll              ; 1336
        nop                             ; 1339
        ldx     #$10                    ; 133A
L133C:
        stx     tmp0                    ; 133C
        jsr     Delay48                 ; 133E
        ldx     tmp0                    ; 1341
        dex                             ; 1343
        bpl     L133C                   ; 1344
        lda     #$04                    ; 1346
        ldx     #$00                    ; 1348
        jsr     SoundWrite              ; 134A
        nop                             ; 134D
        nop                             ; 134E
        nop                             ; 134F
        nop                             ; 1350
        nop                             ; 1351
        nop                             ; 1352
        nop                             ; 1353
        lda     #$01                    ; 1354
        sta     frog_dir                ; 1356
        jsr     SetFrogGfx              ; 1358
        jsr     RestoreUnderFrog        ; 135B
        dec     LIVES_DIGIT             ; 135E  LIVES digit - 1
        lda     LIVES_DIGIT             ; 1361
        cmp     #$30                    ; 1364  reached '0'?
        bne     L136B                   ; 1366
        jmp     GameOver                ; 1368
L136B:
        jsr     RestoreUnderFrog        ; 136B
        jsr     PlaceFrogAtStart        ; 136E
        ldx     #$03                    ; 1371
        lda     #$20                    ; 1373
L1375:
        sta     under_frog,x            ; 1375
        dex                             ; 1378
        bpl     L1375                   ; 1379
        pla                             ; 137B
        pla                             ; 137C
        lda     #$01                    ; 137D
        sta     frog_dir                ; 137F
        ldx     #$80                    ; 1381
        ldy     #$09                    ; 1383
        jsr     LoadAYRegs              ; 1385
        jsr     PickTune                ; 1388
        jmp     NewLife                 ; 138B
        .res    18, $FF                 ; 138E

; ---- unreferenced code: a print-character routine (CR = next line); never called
L13A0:
        cmp     #$0D                    ; 13A0
        beq     L13A9                   ; 13A2
        sta     (tmp0),y                ; 13A4
        iny                             ; 13A6
        inx                             ; 13A7
        rts                             ; 13A8
L13A9:
        ldy     #$00                    ; 13A9
        ldx     #$00                    ; 13AB
        clc                             ; 13AD
        lda     tmp0                    ; 13AE
        adc     #$28                    ; 13B0
        sta     tmp0                    ; 13B2
        lda     key_state               ; 13B4
        adc     #$00                    ; 13B6
        sta     key_state               ; 13B8
        rts                             ; 13BA
        .res    5, $FF                  ; 13BB

;------------------------------------------------------------------------------
; CheckRoadHit - die if the frog has hopped into something on a road row.
;------------------------------------------------------------------------------
CheckRoadHit:
        lda     frog_row                ; 13C0
        bne     L13C6                   ; 13C3
L13C5:
        rts                             ; 13C5
L13C6:
        sec                             ; 13C6
        cmp     #$05                    ; 13C7
        bpl     L13C5                   ; 13C9
        ldx     #$03                    ; 13CB
L13CD:
        ldy     frog_offsets,x          ; 13CD
        lda     (frog_pos),y            ; 13D0
        cmp     #$20                    ; 13D2
        bne     L13DB                   ; 13D4
        dex                             ; 13D6
        bpl     L13CD                   ; 13D7
        rts                             ; 13D9
        .byte   $FF                                       ; 13DA
L13DB:
        jmp     FrogDies                ; 13DB
        .byte   $FF,$FF                                   ; 13DE

;------------------------------------------------------------------------------
; CheckTurtleDive - die if the frog is on the diving turtles (row 7) while they are under.
;------------------------------------------------------------------------------
CheckTurtleDive:
        lda     turtle_frame            ; 13E0
        cmp     #$05                    ; 13E3
        bmi     L13F4                   ; 13E5
        lda     frog_row                ; 13E7
        cmp     #$07                    ; 13EA
        bne     L13F4                   ; 13EC
        jsr     EraseFrog               ; 13EE
        jmp     LoseLife                ; 13F1
L13F4:
        rts                             ; 13F4
        .res    11, $FF                 ; 13F5

;------------------------------------------------------------------------------
; MoveFrog - read a move and hop: restore the background, step, save, check, draw, score.
;------------------------------------------------------------------------------
MoveFrog:
        jsr     GetMove                 ; 1400
        lda     frog_dir                ; 1403
        bne     L1408                   ; 1405
        rts                             ; 1407
L1408:
        lda     frog_pos                ; 1408
        sta     old_pos                 ; 140A
        lda     frog_pos+1              ; 140C
        sta     old_pos+1               ; 140E
        jsr     StepFrogC64             ; 1410  C64: no sideways hop off the playfield (Remix)
        ldx     #$03                    ; 1413
L1415:
        ldy     frog_offsets,x          ; 1415
        lda     under_frog,x            ; 1418
        sta     (old_pos),y             ; 141B
        dex                             ; 141D
        bpl     L1415                   ; 141E
        ldx     #$03                    ; 1420
L1422:
        ldy     frog_offsets,x          ; 1422
        lda     (frog_pos),y            ; 1425
        sta     under_frog,x            ; 1427
        dex                             ; 142A
        bpl     L1422                   ; 142B
        jsr     CheckRoadHit            ; 142D
        jsr     CheckFrogBounds         ; 1430
        jsr     CheckLanding            ; 1433
        jsr     SetFrogGfx              ; 1436
        jsr     DrawFrog                ; 1439
        lda     #$01                    ; 143C
        sta     hop_sound               ; 143E
        lda     frog_dir                ; 1440
        cmp     #$01                    ; 1442
        beq     L1447                   ; 1444
        rts                             ; 1446
L1447:
        ldx     #$05                    ; 1447
        nop                             ; 1449
        lda     #$01                    ; 144A
        jsr     AddScore                ; 144C
        rts                             ; 144F
        .byte   $A2,$26,$BD,$BA,$BF,$9D,$D7,$2F           ; 1450
        .byte   $CA,$10,$F7                               ; 1458

;------------------------------------------------------------------------------
; StartSheet - redraw everything for the next sheet and start play.
;------------------------------------------------------------------------------
StartSheet:
        jsr     PlaceFrogAtStart        ; 145B
        lda     #$01                    ; 145E
        sta     status_save+13          ; 1460
        lda     #$04                    ; 1463
        sta     status_save+21          ; 1465
        jsr     DrawPlayfield           ; 1468
        nop                             ; 146B
        nop                             ; 146C
        jsr     SetFrogGfx              ; 146D
        jsr     DrawFrog                ; 1470
        jsr     PrefillLanes            ; 1473
        nop                             ; 1476
        nop                             ; 1477
        nop                             ; 1478
        nop                             ; 1479
        nop                             ; 147A
        ldx     #$06                    ; 147B
L147D:
        lda     #$00                    ; 147D
        sta     lane_timer,x            ; 147F
        dex                             ; 1481
        bpl     L147D                   ; 1482
        ldx     #$26                    ; 1484
L1486:
        lda     status_save,x           ; 1486
        sta     STATUS_ROW+2,x          ; 1489
        dex                             ; 148C
        bpl     L1486                   ; 148D
        jmp     NewLife                 ; 148F
        .res    14, $FF                 ; 1492

;------------------------------------------------------------------------------
; FrogHome - frog reached a home: fly bonus, jingle, count homes, five = sheet complete.
;------------------------------------------------------------------------------
FrogHome:
        jsr     SilenceAll              ; 14A0
        jsr     CheckFlyEaten           ; 14A3
        nop                             ; 14A6
        nop                             ; 14A7
        nop                             ; 14A8
        nop                             ; 14A9
        nop                             ; 14AA
        nop                             ; 14AB
        nop                             ; 14AC
        nop                             ; 14AD
        nop                             ; 14AE
        nop                             ; 14AF
        nop                             ; 14B0
        jsr     DrawHomeFrog            ; 14B1
        nop                             ; 14B4
        jsr     HomeJingle              ; 14B5
        nop                             ; 14B8
        inc     frogs_home              ; 14B9
        lda     frogs_home              ; 14BC
        cmp     #$05                    ; 14BF
        bne     L14C6                   ; 14C1
        jmp     SheetComplete           ; 14C3
L14C6:
        jsr     PlaceFrogAtStart        ; 14C6
        nop                             ; 14C9
        nop                             ; 14CA
        nop                             ; 14CB
        nop                             ; 14CC
        nop                             ; 14CD
        nop                             ; 14CE
        nop                             ; 14CF
        nop                             ; 14D0
        nop                             ; 14D1
        nop                             ; 14D2
        nop                             ; 14D3
        nop                             ; 14D4
        nop                             ; 14D5
        nop                             ; 14D6
        nop                             ; 14D7
        nop                             ; 14D8
        nop                             ; 14D9
        nop                             ; 14DA
        nop                             ; 14DB
        nop                             ; 14DC
        nop                             ; 14DD
        nop                             ; 14DE
        nop                             ; 14DF
        nop                             ; 14E0
        nop                             ; 14E1
        lda     #$01                    ; 14E2
        ldx     #$04                    ; 14E4
        jsr     AddScore                ; 14E6
        jsr     DrawFrog                ; 14E9
        jmp     NewLife                 ; 14EC
        .res    17, $FF                 ; 14EF
        .byte   $A2,$06                                   ; 1500

;------------------------------------------------------------------------------
; AddScore - add A to score digit X (0-5 = the six digits after the
; first two on the status line), carrying into higher digits.
;------------------------------------------------------------------------------
AddScore:
        sta     tmp2                    ; 1502
        lda     SCORE_DIGITS,x          ; 1504
        cmp     #$20                    ; 1507
        bne     L150D                   ; 1509
        lda     #$30                    ; 150B
L150D:
        clc                             ; 150D
        adc     tmp2                    ; 150E
        cmp     #$3A                    ; 1510
        bmi     L151F                   ; 1512
        sec                             ; 1514
        sbc     #$0A                    ; 1515
        sta     SCORE_DIGITS,x          ; 1517
        lda     #$01                    ; 151A
        dex                             ; 151C
        bpl     AddScore                ; 151D
L151F:
        sta     SCORE_DIGITS,x          ; 151F
        rts                             ; 1522
        .res    5, $FF                  ; 1523
        .byte   $FE,$FF                                   ; 1528
        .res    22, $FF                 ; 152A

;------------------------------------------------------------------------------
; Graphics for a frog sitting in its home: chars $2B-$2C, then $2E-$2F.
; CreditsEnd also uses them as the title-screen frog.
;------------------------------------------------------------------------------
home_gfx:
        .byte   W6(%00000000)           ; 1540 ......  +0
        .byte   W6(%00000100)           ; 1541 ...#..
        .byte   W6(%00001010)           ; 1542 ..#.#.
        .byte   W6(%00001111)           ; 1543 ..####
        .byte   W6(%00010000)           ; 1544 .#....
        .byte   W6(%00011100)           ; 1545 .###..
        .byte   W6(%00001111)           ; 1546 ..####
        .byte   W6(%00001111)           ; 1547 ..####
        .byte   W6(%00000000)           ; 1548 ......  +8
        .byte   W6(%00001000)           ; 1549 ..#...
        .byte   W6(%00010100)           ; 154A .#.#..
        .byte   W6(%00111100)           ; 154B ####..
        .byte   W6(%00000010)           ; 154C ....#.
        .byte   W6(%00001110)           ; 154D ..###.
        .byte   W6(%00111100)           ; 154E ####..
        .byte   W6(%00111100)           ; 154F ####..
        .byte   W6(%00001111)           ; 1550 ..####  +16
        .byte   W6(%00010000)           ; 1551 .#....
        .byte   W6(%00010001)           ; 1552 .#...#
        .byte   W6(%00010001)           ; 1553 .#...#
        .byte   W6(%00001011)           ; 1554 ..#.##
        .byte   W6(%00001101)           ; 1555 ..##.#
        .byte   W6(%00001100)           ; 1556 ..##..
        .byte   W6(%00011101)           ; 1557 .###.#
        .byte   W6(%00111100)           ; 1558 ####..  +24
        .byte   W6(%00100010)           ; 1559 #...#.
        .byte   W6(%00100010)           ; 155A #...#.
        .byte   W6(%00100010)           ; 155B #...#.
        .byte   W6(%00110100)           ; 155C ##.#..
        .byte   W6(%00101100)           ; 155D #.##..
        .byte   W6(%00001100)           ; 155E ..##..
        .byte   W6(%00101110)           ; 155F #.###.

;------------------------------------------------------------------------------
; Character codes of the frog in its home.
;------------------------------------------------------------------------------
home_chars:
        .byte   $2B,$2C,$2E,$2F                           ; 1560
        .res    7, $FF                  ; 1564
        .byte   $04,$10,$FF,$FF,$FF                       ; 156B

;------------------------------------------------------------------------------
; DrawHomeFrog - draw a frog sitting in the home it reached.
;------------------------------------------------------------------------------
DrawHomeFrog:
        ldx     #$0F                    ; 1570
L1572:
        lda     home_gfx,x              ; 1572
        sta     CHARSET+$2B*8,x         ; 1575
        dex                             ; 1578
        bpl     L1572                   ; 1579
        ldx     #$0F                    ; 157B
L157D:
        lda     home_gfx+16,x           ; 157D
        sta     CHARSET+$2E*8,x         ; 1580
        dex                             ; 1583
        bpl     L157D                   ; 1584
        ldx     #$03                    ; 1586
L1588:
        ldy     frog_offsets,x          ; 1588
        lda     home_chars,x            ; 158B
        sta     (frog_pos),y            ; 158E
        dex                             ; 1590
        bpl     L1588                   ; 1591
        lda     #$01                    ; 1593
        sta     frog_dir                ; 1595
        rts                             ; 1597
        .res    24, $FF                 ; 1598

;------------------------------------------------------------------------------
; PlaceFrogAtStart - frog back to row 25, column 20, facing up.
;------------------------------------------------------------------------------
PlaceFrogAtStart:
        lda     #$7C                    ; 15B0
        sta     frog_pos                ; 15B2
        lda     #$BF                    ; 15B4
        sta     frog_pos+1              ; 15B6
        lda     #$00                    ; 15B8
        sta     frog_row                ; 15BA
        sta     ROM_KEY                 ; 15BD
        lda     #$13                    ; 15C0
        sta     frog_col                ; 15C2
        lda     #$01                    ; 15C5
        sta     frog_dir                ; 15C7
        jsr     SetFrogGfx              ; 15C9
        jsr     DrawFrog                ; 15CC
        rts                             ; 15CF

;------------------------------------------------------------------------------
; Snake characters, moving left.
;------------------------------------------------------------------------------
snake_left:
        .byte   $20,$5E,$5C,$5F,$20                       ; 15D0

;------------------------------------------------------------------------------
; Snake characters, moving right.
;------------------------------------------------------------------------------
snake_right:
        .byte   $20,$5B,$5C,$5D,$20                       ; 15D5
        .res    6, $55                  ; 15DA

; ---- unreferenced code: an earlier snake initialisation; never called
L15E0:
        lda     #$02                    ; 15E0
        sta     snake_dir               ; 15E2
        lda     #$01                    ; 15E4
        sta     snake_col               ; 15E6
        lda     #$D8                    ; 15E8
        sta     snake_row               ; 15EA
        lda     #$BD                    ; 15EC
        sta     snake_row+1             ; 15EE
        nop                             ; 15F0
        nop                             ; 15F1
        nop                             ; 15F2
        nop                             ; 15F3
        nop                             ; 15F4
        nop                             ; 15F5
        nop                             ; 15F6
        nop                             ; 15F7
        nop                             ; 15F8
        nop                             ; 15F9
        nop                             ; 15FA
        nop                             ; 15FB
        nop                             ; 15FC
        nop                             ; 15FD
        nop                             ; 15FE
        rts                             ; 15FF

;------------------------------------------------------------------------------
; MoveSnake - move the snake along the middle bank (row 15), bouncing at the ends.
;------------------------------------------------------------------------------
MoveSnake:
        lda     snake_dir               ; 1600
        cmp     #$01                    ; 1602
        bne     L162F                   ; 1604
        dec     snake_col               ; 1606
        lda     snake_col               ; 1608
        cmp     #$01                    ; 160A
        bne     L1615                   ; 160C
        lda     #$02                    ; 160E
        sta     snake_dir               ; 1610
        nop                             ; 1612
        nop                             ; 1613
        rts                             ; 1614
L1615:
        jsr     EraseFrogIfRoad         ; 1615
        ldx     #$05                    ; 1618
L161A:
        lda     snake_left,x            ; 161A
        pha                             ; 161D
        txa                             ; 161E
        adc     snake_col               ; 161F
        tay                             ; 1621
        pla                             ; 1622
        sta     (snake_row),y           ; 1623
        dex                             ; 1625
        bpl     L161A                   ; 1626
        jsr     RedrawFrogIfRoad        ; 1628
        nop                             ; 162B
        nop                             ; 162C
        nop                             ; 162D
        rts                             ; 162E
L162F:
        inc     snake_col               ; 162F
        lda     snake_col               ; 1631
        cmp     #$22                    ; 1633
        bne     L163E                   ; 1635
        lda     #$01                    ; 1637
        sta     snake_dir               ; 1639
        nop                             ; 163B
        nop                             ; 163C
        rts                             ; 163D
L163E:
        jsr     EraseFrogIfRoad         ; 163E
        ldx     #$04                    ; 1641
L1643:
        lda     snake_right,x           ; 1643
        pha                             ; 1646
        txa                             ; 1647
        adc     snake_col               ; 1648
        tay                             ; 164A
        pla                             ; 164B
        sta     (snake_row),y           ; 164C
        dex                             ; 164E
        bpl     L1643                   ; 164F
        jsr     RedrawFrogIfRoad        ; 1651
        rts                             ; 1654
        .res    4, $EA                  ; 1655
        .byte   $60,$EA                                   ; 1659
        .res    6, $EA                  ; 165B
        .byte   $60,$FF                                   ; 1661
        .res    13, $FF                 ; 1663

; ---- unreferenced code: an earlier snake-erase routine; never called
L1670:
        lda     snake_dir               ; 1670
        cmp     #$01                    ; 1672
        bne     L1688                   ; 1674
        lda     #$02                    ; 1676
        sta     snake_dir               ; 1678
L167A:
        ldx     #$03                    ; 167A
L167C:
        txa                             ; 167C
        adc     snake_col               ; 167D
        tay                             ; 167F
        lda     #$20                    ; 1680
        sta     (snake_row),y           ; 1682
        dex                             ; 1684
        bpl     L167C                   ; 1685
        rts                             ; 1687
L1688:
        lda     #$01                    ; 1688
        sta     snake_dir               ; 168A
        jmp     L167A                   ; 168C
        .res    17, $FF                 ; 168F

;------------------------------------------------------------------------------
; TimeTick - count TIME down by one.
;------------------------------------------------------------------------------
TimeTick:
        jsr     CheckTimeLow            ; 16A0
        ldx     #$01                    ; 16A3
L16A5:
        lda     TIME_DIGITS,x           ; 16A5
        cmp     #$30                    ; 16A8
        bne     L16B5                   ; 16AA
        lda     #$39                    ; 16AC
        sta     TIME_DIGITS,x           ; 16AE
        dex                             ; 16B1
        bpl     L16A5                   ; 16B2
        rts                             ; 16B4
L16B5:
        dec     TIME_DIGITS,x           ; 16B5
        rts                             ; 16B8
        .res    7, $FF                  ; 16B9

;------------------------------------------------------------------------------
; Key tables for control choice 1 (Z X ' /), copied to key_rows.
; C64: Z X K M, letters only (the / and @ keys move about with host keymaps).
;------------------------------------------------------------------------------
keys_set1:
        .byte   $FD,$FB,$EF,$EF,$DF,$10,$80,$10           ; 16C0  C64: Z X M K P (column, row mask)
        .byte   $20,$02,$20,$10,$08,$04,$80               ; 16C8
        .byte   $FF                                       ; 16CF

;------------------------------------------------------------------------------
; Key tables for control choice 2 (, . A Z), copied to key_rows.
; C64: choice 2 is "Redefine keys": RedefineKeys fills the columns and row
; masks from the keys pressed; these are only its starting values.
;------------------------------------------------------------------------------
keys_set2:
        .byte   $FD,$FD,$DF,$DF,$DF,$04,$10,$80           ; 16D0  C64: A Z , . P (column, row mask)
        .byte   $10,$02,$04,$08,$20,$10,$80               ; 16D8
        .byte   $FF                                       ; 16DF

;------------------------------------------------------------------------------
; LoadAYRegs - write 14 bytes at (X lo, Y hi) to AY registers 0-13.
;------------------------------------------------------------------------------
LoadAYRegs:
        php                             ; 16E0
        nop                             ; 16E1  C64: was sei
        stx     ay_table                ; 16E2
        sty     ay_table+1              ; 16E4
        ldy     #$00                    ; 16E6
L16E8:
        lda     (ay_table),y            ; 16E8
        tax                             ; 16EA
        tya                             ; 16EB
        pha                             ; 16EC
        jsr     AYWrite                 ; 16ED
        pla                             ; 16F0
        tay                             ; 16F1
        iny                             ; 16F2
        cpy     #$0E                    ; 16F3
        bne     L16E8                   ; 16F5
        plp                             ; 16F7
        rts                             ; 16F8
        .res    7, $FF                  ; 16F9

;------------------------------------------------------------------------------
; SheetComplete - all five homes full: time bonus, next sheet number,
; reset TIME, and make the game harder (faster lanes, snake and turtles).
;------------------------------------------------------------------------------
SheetComplete:
        jsr     TimeBonus               ; 1700
        ldx     #$10                    ; 1703
L1705:
        stx     tmp0                    ; 1705
        jsr     Delay48                 ; 1707
        ldx     tmp0                    ; 170A
        dex                             ; 170C
        bpl     L1705                   ; 170D
        jsr     PickTune                ; 170F
        inc     SHEET_DIGITS+1          ; 1712
        lda     SHEET_DIGITS+1          ; 1715
        cmp     #$3A                    ; 1718
        bne     L1733                   ; 171A
        lda     #$30                    ; 171C
        sta     SHEET_DIGITS+1          ; 171E
        lda     SHEET_DIGITS            ; 1721
        cmp     #$20                    ; 1724
        bne     L172D                   ; 1726
        lda     #$30                    ; 1728
        sta     SHEET_DIGITS            ; 172A
L172D:
        inc     SHEET_DIGITS            ; 172D
        sta     TIME_DIGITS             ; 1730
L1733:
        lda     #$39                    ; 1733
        sta     TIME_DIGITS+1           ; 1735
        sta     TIME_DIGITS             ; 1738
        nop                             ; 173B
        nop                             ; 173C
        ldx     #$26                    ; 173D
L173F:
        lda     STATUS_ROW+2,x          ; 173F
        sta     status_save,x           ; 1742
        dex                             ; 1745
        bpl     L173F                   ; 1746
        jsr     ClearScreen             ; 1748
        jsr     DrawScenery             ; 174B
        lda     #$00                    ; 174E
        sta     frogs_home              ; 1750
        nop                             ; 1753
        nop                             ; 1754
        inc     sheet                   ; 1755
        lda     sheet                   ; 1758
        and     #$03                    ; 175B
        cmp     #$03                    ; 175D
        beq     L1764                   ; 175F
L1761:
        jmp     L177A                   ; 1761
L1764:
        lda     sheet                   ; 1764
        cmp     #$08                    ; 1767
        bpl     L1761                   ; 1769
        ldx     #$06                    ; 176B
L176D:
        lda     lane_speeds,x           ; 176D
        cmp     #$03                    ; 1770
        beq     L1777                   ; 1772
        dec     lane_speeds,x           ; 1774
L1777:
        dex                             ; 1777
        bpl     L176D                   ; 1778
L177A:
        ldx     #$10                    ; 177A
L177C:
        stx     tmp0                    ; 177C
        jsr     Delay48                 ; 177E
        ldx     tmp0                    ; 1781
        dex                             ; 1783
        bpl     L177C                   ; 1784
        lda     #$00                    ; 1786
        sta     fly_on                  ; 1788
        sta     fly_timer               ; 178A
        sta     fly_timer+1             ; 178C
        sta     fly_ptr                 ; 178E
        sta     fly_ptr                 ; 1790
        sta     warble_level            ; 1792
        sta     warble_dir              ; 1794
        lda     sheet                   ; 1796
        and     #$07                    ; 1799
        cmp     #$07                    ; 179B
        bne     L17A8                   ; 179D
        lsr     turtle_speed            ; 179F
        lsr     snake_speed             ; 17A2
        dec     game_delay              ; 17A5
L17A8:
        jmp     StartSheet              ; 17A8
        .res    21, $EA                 ; 17AB

;------------------------------------------------------------------------------
; "SHEET NO" sign drawn on rows 20-21.
;------------------------------------------------------------------------------
scenery_sheet:
        .byte   $0A,$07,$10,"SHEET NO       ",$10,$00     ; 17C0
        .byte   $0A                                       ; 17D4

;------------------------------------------------------------------------------
; "SCORE" sign drawn on rows 23-24.
;------------------------------------------------------------------------------
scenery_score:
        .byte   $0A,$07,$10,"SCORE          ",$10,$00     ; 17D5
        .byte   $0A,$10                                   ; 17E9
        .byte   $0A,$FF,$FF,$FF,$FF                       ; 17EB

;------------------------------------------------------------------------------
; "READY" sign drawn on rows 14-15.
;------------------------------------------------------------------------------
scenery_ready:
        .byte   $0A,$04,$10,"READY",$0A,$10               ; 17F0
        .byte   $00                                       ; 17FA
        .res    5, $FF                  ; 17FB

;------------------------------------------------------------------------------
; SetTurtleFrame - copy turtle animation frame turtle_frame to chars $6E-$73.
;------------------------------------------------------------------------------
SetTurtleFrame:
        lda     turtle_frame            ; 1800
        bne     L1814                   ; 1803
        ldx     #$2F                    ; 1805
L1807:
        lda     turtle_frames,x         ; 1807
        sta     CHARSET+$6E*8,x         ; 180A
        dex                             ; 180D
        bpl     L1807                   ; 180E
        nop                             ; 1810
        nop                             ; 1811
        nop                             ; 1812
        rts                             ; 1813
L1814:
        cmp     #$01                    ; 1814
        bne     L182A                   ; 1816
        nop                             ; 1818
        nop                             ; 1819
        nop                             ; 181A
        ldx     #$2F                    ; 181B
L181D:
        lda     turtle_frames+48,x      ; 181D
        sta     CHARSET+$6E*8,x         ; 1820
        dex                             ; 1823
        bpl     L181D                   ; 1824
        nop                             ; 1826
        nop                             ; 1827
        nop                             ; 1828
        rts                             ; 1829
L182A:
        cmp     #$02                    ; 182A
        bne     L1840                   ; 182C
        nop                             ; 182E
        nop                             ; 182F
        nop                             ; 1830
        ldx     #$2F                    ; 1831
L1833:
        lda     turtle_frames+96,x      ; 1833
        sta     CHARSET+$6E*8,x         ; 1836
        dex                             ; 1839
        bpl     L1833                   ; 183A
        nop                             ; 183C
        nop                             ; 183D
        nop                             ; 183E
        rts                             ; 183F
L1840:
        cmp     #$03                    ; 1840
        bne     L1856                   ; 1842
        nop                             ; 1844
        nop                             ; 1845
        nop                             ; 1846
        ldx     #$2F                    ; 1847
L1849:
        lda     turtle_frames+144,x     ; 1849
        sta     CHARSET+$6E*8,x         ; 184C
        dex                             ; 184F
        bpl     L1849                   ; 1850
        nop                             ; 1852
        nop                             ; 1853
        nop                             ; 1854
        rts                             ; 1855
L1856:
        cmp     #$04                    ; 1856
        bne     L186C                   ; 1858
        nop                             ; 185A
        nop                             ; 185B
        nop                             ; 185C
        ldx     #$2F                    ; 185D
L185F:
        lda     turtle_frames+192,x     ; 185F
        sta     CHARSET+$6E*8,x         ; 1862
        dex                             ; 1865
        bpl     L185F                   ; 1866
        nop                             ; 1868
        nop                             ; 1869
        nop                             ; 186A
        rts                             ; 186B
L186C:
        cmp     #$05                    ; 186C
        bne     L1882                   ; 186E
        nop                             ; 1870
        nop                             ; 1871
        nop                             ; 1872
        ldx     #$2F                    ; 1873
L1875:
        lda     turtle_frames+240,x     ; 1875
        sta     CHARSET+$6E*8,x         ; 1878
        dex                             ; 187B
        bpl     L1875                   ; 187C
        nop                             ; 187E
        nop                             ; 187F
        nop                             ; 1880
        rts                             ; 1881
L1882:
        cmp     #$06                    ; 1882
        bne     L1897                   ; 1884
        nop                             ; 1886
        nop                             ; 1887
        nop                             ; 1888
        ldx     #$2F                    ; 1889
L188B:
        lda     turtle_frames+288,x     ; 188B
        sta     CHARSET+$6E*8,x         ; 188E
        dex                             ; 1891
        bpl     L188B                   ; 1892
        nop                             ; 1894
        nop                             ; 1895
        nop                             ; 1896
L1897:
        rts                             ; 1897

;------------------------------------------------------------------------------
; Control-selection screen; $0D = new line, $FF = end.
;------------------------------------------------------------------------------
controls_text:
        .byte   $01," Select your choice :-",$0D          ; 1898
        .byte   $0D                                       ; 18B0
        .byte   $17,$00,"LEFT",$10,$17,"RIGHT"            ; 18B1
        .byte   $10,$17,"UP",$10,$17,"DOWN"               ; 18BE
        .byte   $10,$0D                                   ; 18C8
        .byte   $0D                                       ; 18CA
        .byte   "1]  Z      X    K    M",$0D              ; 18CB  C64: letters only
        .byte   $0D                                       ; 18E2
        .byte   "2]  Redefine keys     ",$0D              ; 18E3  C64: RedefineKeys
        .byte   $00,$00,$00,$00                           ; 18FA
        .byte   $FF,$FF                                   ; 18FE

;------------------------------------------------------------------------------
; Seven animation frames (6 characters each) for the diving turtles,
; copied to CHARSET+$6E*8 by SetTurtleFrame.
;------------------------------------------------------------------------------
turtle_frames:
        .byte   W6(%00000000)           ; 1900 ......  char $6E
        .byte   W6(%00000000)           ; 1901 ......
        .byte   W6(%00000000)           ; 1902 ......
        .byte   W6(%00000000)           ; 1903 ......
        .byte   W6(%00000000)           ; 1904 ......
        .byte   W6(%00000000)           ; 1905 ......
        .byte   W6(%00011001)           ; 1906 .##..#
        .byte   W6(%00111111)           ; 1907 ######
        .byte   W6(%00011000)           ; 1908 .##...  char $6F
        .byte   W6(%00001101)           ; 1909 ..##.#
        .byte   W6(%00000111)           ; 190A ...###
        .byte   W6(%00000111)           ; 190B ...###
        .byte   W6(%00011111)           ; 190C .#####
        .byte   W6(%00111111)           ; 190D ######
        .byte   W6(%00111111)           ; 190E ######
        .byte   W6(%00111111)           ; 190F ######
        .byte   W6(%00000110)           ; 1910 ...##.  char $70
        .byte   W6(%00101100)           ; 1911 #.##..
        .byte   W6(%00111000)           ; 1912 ###...
        .byte   W6(%00111000)           ; 1913 ###...
        .byte   W6(%00111000)           ; 1914 ###...
        .byte   W6(%00111000)           ; 1915 ###...
        .byte   W6(%00111000)           ; 1916 ###...
        .byte   W6(%00111110)           ; 1917 #####.
        .byte   W6(%00111111)           ; 1918 ######  char $71
        .byte   W6(%00011001)           ; 1919 .##..#
        .byte   W6(%00000000)           ; 191A ......
        .byte   W6(%00000000)           ; 191B ......
        .byte   W6(%00000000)           ; 191C ......
        .byte   W6(%00000000)           ; 191D ......
        .byte   W6(%00000000)           ; 191E ......
        .byte   W6(%00000000)           ; 191F ......
        .byte   W6(%00111111)           ; 1920 ######  char $72
        .byte   W6(%00111111)           ; 1921 ######
        .byte   W6(%00111111)           ; 1922 ######
        .byte   W6(%00011111)           ; 1923 .#####
        .byte   W6(%00000111)           ; 1924 ...###
        .byte   W6(%00000111)           ; 1925 ...###
        .byte   W6(%00001101)           ; 1926 ..##.#
        .byte   W6(%00011000)           ; 1927 .##...
        .byte   W6(%00111110)           ; 1928 #####.  char $73
        .byte   W6(%00111000)           ; 1929 ###...
        .byte   W6(%00111000)           ; 192A ###...
        .byte   W6(%00111000)           ; 192B ###...
        .byte   W6(%00111000)           ; 192C ###...
        .byte   W6(%00111000)           ; 192D ###...
        .byte   W6(%00101100)           ; 192E #.##..
        .byte   W6(%00000110)           ; 192F ...##.
        .byte   W6(%00000000)           ; 1930 ......  char $74
        .byte   W6(%00000000)           ; 1931 ......
        .byte   W6(%00000000)           ; 1932 ......
        .byte   W6(%00000000)           ; 1933 ......
        .byte   W6(%00000000)           ; 1934 ......
        .byte   W6(%00000000)           ; 1935 ......
        .byte   W6(%00011000)           ; 1936 .##...
        .byte   W6(%00111001)           ; 1937 ###..#
        .byte   W6(%00000000)           ; 1938 ......  char $75
        .byte   W6(%00000001)           ; 1939 .....#
        .byte   W6(%00000111)           ; 193A ...###
        .byte   W6(%00000111)           ; 193B ...###
        .byte   W6(%00011111)           ; 193C .#####
        .byte   W6(%00111111)           ; 193D ######
        .byte   W6(%00111111)           ; 193E ######
        .byte   W6(%00111111)           ; 193F ######
        .byte   W6(%00000000)           ; 1940 ......  char $76
        .byte   W6(%00100000)           ; 1941 #.....
        .byte   W6(%00110000)           ; 1942 ##....
        .byte   W6(%00111000)           ; 1943 ###...
        .byte   W6(%00111000)           ; 1944 ###...
        .byte   W6(%00111000)           ; 1945 ###...
        .byte   W6(%00111000)           ; 1946 ###...
        .byte   W6(%00111100)           ; 1947 ####..
        .byte   W6(%00111001)           ; 1948 ###..#  char $77
        .byte   W6(%00011000)           ; 1949 .##...
        .byte   W6(%00000000)           ; 194A ......
        .byte   W6(%00000000)           ; 194B ......
        .byte   W6(%00000000)           ; 194C ......
        .byte   W6(%00000000)           ; 194D ......
        .byte   W6(%00000000)           ; 194E ......
        .byte   W6(%00000000)           ; 194F ......
        .byte   W6(%00111111)           ; 1950 ######  char $78
        .byte   W6(%00111111)           ; 1951 ######
        .byte   W6(%00111111)           ; 1952 ######
        .byte   W6(%00011111)           ; 1953 .#####
        .byte   W6(%00000111)           ; 1954 ...###
        .byte   W6(%00000111)           ; 1955 ...###
        .byte   W6(%00000001)           ; 1956 .....#
        .byte   W6(%00000000)           ; 1957 ......
        .byte   W6(%00111100)           ; 1958 ####..  char $79
        .byte   W6(%00111000)           ; 1959 ###...
        .byte   W6(%00111000)           ; 195A ###...
        .byte   W6(%00111000)           ; 195B ###...
        .byte   W6(%00111000)           ; 195C ###...
        .byte   W6(%00110000)           ; 195D ##....
        .byte   W6(%00100000)           ; 195E #.....
        .byte   W6(%00000000)           ; 195F ......
        .byte   W6(%00000000)           ; 1960 ......  char $7A
        .byte   W6(%00000000)           ; 1961 ......
        .byte   W6(%00000000)           ; 1962 ......
        .byte   W6(%00000000)           ; 1963 ......
        .byte   W6(%00000000)           ; 1964 ......
        .byte   W6(%00000000)           ; 1965 ......
        .byte   W6(%00000000)           ; 1966 ......
        .byte   W6(%00011001)           ; 1967 .##..#
        .byte   W6(%00000000)           ; 1968 ......  char $7B
        .byte   W6(%00000000)           ; 1969 ......
        .byte   W6(%00000000)           ; 196A ......
        .byte   W6(%00000111)           ; 196B ...###
        .byte   W6(%00001111)           ; 196C ..####
        .byte   W6(%00001111)           ; 196D ..####
        .byte   W6(%00011111)           ; 196E .#####
        .byte   W6(%00111111)           ; 196F ######
        .byte   W6(%00000000)           ; 1970 ......  char $7C
        .byte   W6(%00000000)           ; 1971 ......
        .byte   W6(%00000000)           ; 1972 ......
        .byte   W6(%00110000)           ; 1973 ##....
        .byte   W6(%00111000)           ; 1974 ###...
        .byte   W6(%00111000)           ; 1975 ###...
        .byte   W6(%00111000)           ; 1976 ###...
        .byte   W6(%00111000)           ; 1977 ###...
        .byte   W6(%00011001)           ; 1978 .##..#  char $7D
        .byte   W6(%00000000)           ; 1979 ......
        .byte   W6(%00000000)           ; 197A ......
        .byte   W6(%00000000)           ; 197B ......
        .byte   W6(%00000000)           ; 197C ......
        .byte   W6(%00000000)           ; 197D ......
        .byte   W6(%00000000)           ; 197E ......
        .byte   W6(%00000000)           ; 197F ......
        .byte   W6(%00111111)           ; 1980 ######  char $7E
        .byte   W6(%00011111)           ; 1981 .#####
        .byte   W6(%00001111)           ; 1982 ..####
        .byte   W6(%00001111)           ; 1983 ..####
        .byte   W6(%00000111)           ; 1984 ...###
        .byte   W6(%00000000)           ; 1985 ......
        .byte   W6(%00000000)           ; 1986 ......
        .byte   W6(%00000000)           ; 1987 ......
        .byte   W6(%00111000)           ; 1988 ###...  char $7F
        .byte   W6(%00111000)           ; 1989 ###...
        .byte   W6(%00111000)           ; 198A ###...
        .byte   W6(%00111000)           ; 198B ###...
        .byte   W6(%00110000)           ; 198C ##....
        .byte   W6(%00000000)           ; 198D ......
        .byte   W6(%00000000)           ; 198E ......
        .byte   W6(%00000000)           ; 198F ......
        .byte   W6(%00000000)           ; 1990 ......  char $80
        .byte   W6(%00000000)           ; 1991 ......
        .byte   W6(%00000000)           ; 1992 ......
        .byte   W6(%00000000)           ; 1993 ......
        .byte   W6(%00000000)           ; 1994 ......
        .byte   W6(%00000000)           ; 1995 ......
        .byte   W6(%00000000)           ; 1996 ......
        .byte   W6(%00000000)           ; 1997 ......
        .byte   W6(%00000000)           ; 1998 ......  char $81
        .byte   W6(%00000000)           ; 1999 ......
        .byte   W6(%00000000)           ; 199A ......
        .byte   W6(%00000000)           ; 199B ......
        .byte   W6(%00000111)           ; 199C ...###
        .byte   W6(%00001111)           ; 199D ..####
        .byte   W6(%00011111)           ; 199E .#####
        .byte   W6(%00011111)           ; 199F .#####
        .byte   W6(%00000000)           ; 19A0 ......  char $82
        .byte   W6(%00000000)           ; 19A1 ......
        .byte   W6(%00000000)           ; 19A2 ......
        .byte   W6(%00000000)           ; 19A3 ......
        .byte   W6(%00100000)           ; 19A4 #.....
        .byte   W6(%00110000)           ; 19A5 ##....
        .byte   W6(%00111000)           ; 19A6 ###...
        .byte   W6(%00111000)           ; 19A7 ###...
        .byte   W6(%00000000)           ; 19A8 ......  char $83
        .byte   W6(%00000000)           ; 19A9 ......
        .byte   W6(%00000000)           ; 19AA ......
        .byte   W6(%00000000)           ; 19AB ......
        .byte   W6(%00000000)           ; 19AC ......
        .byte   W6(%00000000)           ; 19AD ......
        .byte   W6(%00000000)           ; 19AE ......
        .byte   W6(%00000000)           ; 19AF ......
        .byte   W6(%00011111)           ; 19B0 .#####  char $84
        .byte   W6(%00011111)           ; 19B1 .#####
        .byte   W6(%00001111)           ; 19B2 ..####
        .byte   W6(%00000111)           ; 19B3 ...###
        .byte   W6(%00000000)           ; 19B4 ......
        .byte   W6(%00000000)           ; 19B5 ......
        .byte   W6(%00000000)           ; 19B6 ......
        .byte   W6(%00000000)           ; 19B7 ......
        .byte   W6(%00111000)           ; 19B8 ###...  char $85
        .byte   W6(%00111000)           ; 19B9 ###...
        .byte   W6(%00110000)           ; 19BA ##....
        .byte   W6(%00100000)           ; 19BB #.....
        .byte   W6(%00000000)           ; 19BC ......
        .byte   W6(%00000000)           ; 19BD ......
        .byte   W6(%00000000)           ; 19BE ......
        .byte   W6(%00000000)           ; 19BF ......
        .byte   W6(%00000000)           ; 19C0 ......  char $86
        .byte   W6(%00000000)           ; 19C1 ......
        .byte   W6(%00000000)           ; 19C2 ......
        .byte   W6(%00000000)           ; 19C3 ......
        .byte   W6(%00000000)           ; 19C4 ......
        .byte   W6(%00000000)           ; 19C5 ......
        .byte   W6(%00000000)           ; 19C6 ......
        .byte   W6(%00000000)           ; 19C7 ......
        .byte   W6(%00000000)           ; 19C8 ......  char $87
        .byte   W6(%00000000)           ; 19C9 ......
        .byte   W6(%00000000)           ; 19CA ......
        .byte   W6(%00000000)           ; 19CB ......
        .byte   W6(%00000000)           ; 19CC ......
        .byte   W6(%00000111)           ; 19CD ...###
        .byte   W6(%00001111)           ; 19CE ..####
        .byte   W6(%00001111)           ; 19CF ..####
        .byte   W6(%00000000)           ; 19D0 ......  char $88
        .byte   W6(%00000000)           ; 19D1 ......
        .byte   W6(%00000000)           ; 19D2 ......
        .byte   W6(%00000000)           ; 19D3 ......
        .byte   W6(%00000000)           ; 19D4 ......
        .byte   W6(%00100000)           ; 19D5 #.....
        .byte   W6(%00110000)           ; 19D6 ##....
        .byte   W6(%00110000)           ; 19D7 ##....
        .byte   W6(%00000000)           ; 19D8 ......  char $89
        .byte   W6(%00000000)           ; 19D9 ......
        .byte   W6(%00000000)           ; 19DA ......
        .byte   W6(%00000000)           ; 19DB ......
        .byte   W6(%00000000)           ; 19DC ......
        .byte   W6(%00000000)           ; 19DD ......
        .byte   W6(%00000000)           ; 19DE ......
        .byte   W6(%00000000)           ; 19DF ......
        .byte   W6(%00001111)           ; 19E0 ..####  char $8A
        .byte   W6(%00001111)           ; 19E1 ..####
        .byte   W6(%00000111)           ; 19E2 ...###
        .byte   W6(%00000000)           ; 19E3 ......
        .byte   W6(%00000000)           ; 19E4 ......
        .byte   W6(%00000000)           ; 19E5 ......
        .byte   W6(%00000000)           ; 19E6 ......
        .byte   W6(%00000000)           ; 19E7 ......
        .byte   W6(%00110000)           ; 19E8 ##....  char $8B
        .byte   W6(%00110000)           ; 19E9 ##....
        .byte   W6(%00100000)           ; 19EA #.....
        .byte   W6(%00000000)           ; 19EB ......
        .byte   W6(%00000000)           ; 19EC ......
        .byte   W6(%00000000)           ; 19ED ......
        .byte   W6(%00000000)           ; 19EE ......
        .byte   W6(%00000000)           ; 19EF ......
        .byte   W6(%00000000)           ; 19F0 ......  char $8C
        .byte   W6(%00000000)           ; 19F1 ......
        .byte   W6(%00000000)           ; 19F2 ......
        .byte   W6(%00000000)           ; 19F3 ......
        .byte   W6(%00000000)           ; 19F4 ......
        .byte   W6(%00000000)           ; 19F5 ......
        .byte   W6(%00000000)           ; 19F6 ......
        .byte   W6(%00000000)           ; 19F7 ......
        .byte   W6(%00000000)           ; 19F8 ......  char $8D
        .byte   W6(%00000000)           ; 19F9 ......
        .byte   W6(%00000000)           ; 19FA ......
        .byte   W6(%00000000)           ; 19FB ......
        .byte   W6(%00000000)           ; 19FC ......
        .byte   W6(%00000000)           ; 19FD ......
        .byte   W6(%00000011)           ; 19FE ....##
        .byte   W6(%00000111)           ; 19FF ...###
        .byte   W6(%00000000)           ; 1A00 ......  char $8E
        .byte   W6(%00000000)           ; 1A01 ......
        .byte   W6(%00000000)           ; 1A02 ......
        .byte   W6(%00000000)           ; 1A03 ......
        .byte   W6(%00000000)           ; 1A04 ......
        .byte   W6(%00000000)           ; 1A05 ......
        .byte   W6(%00100000)           ; 1A06 #.....
        .byte   W6(%00110000)           ; 1A07 ##....
        .byte   W6(%00000000)           ; 1A08 ......  char $8F
        .byte   W6(%00000000)           ; 1A09 ......
        .byte   W6(%00000000)           ; 1A0A ......
        .byte   W6(%00000000)           ; 1A0B ......
        .byte   W6(%00000000)           ; 1A0C ......
        .byte   W6(%00000000)           ; 1A0D ......
        .byte   W6(%00000000)           ; 1A0E ......
        .byte   W6(%00000000)           ; 1A0F ......
        .byte   W6(%00000011)           ; 1A10 ....##  char $90
        .byte   W6(%00000111)           ; 1A11 ...###
        .byte   W6(%00000000)           ; 1A12 ......
        .byte   W6(%00000000)           ; 1A13 ......
        .byte   W6(%00000000)           ; 1A14 ......
        .byte   W6(%00000000)           ; 1A15 ......
        .byte   W6(%00000000)           ; 1A16 ......
        .byte   W6(%00000000)           ; 1A17 ......
        .byte   W6(%00100000)           ; 1A18 #.....  char $91
        .byte   W6(%00110000)           ; 1A19 ##....
        .byte   W6(%00000000)           ; 1A1A ......
        .byte   W6(%00000000)           ; 1A1B ......
        .byte   W6(%00000000)           ; 1A1C ......
        .byte   W6(%00000000)           ; 1A1D ......
        .byte   W6(%00000000)           ; 1A1E ......
        .byte   W6(%00000000)           ; 1A1F ......
        .byte   W6(%00000000)           ; 1A20 ......  char $92
        .byte   W6(%00000000)           ; 1A21 ......
        .byte   W6(%00000000)           ; 1A22 ......
        .byte   W6(%00000000)           ; 1A23 ......
        .byte   W6(%00000000)           ; 1A24 ......
        .byte   W6(%00000000)           ; 1A25 ......
        .byte   W6(%00000000)           ; 1A26 ......
        .byte   W6(%00000000)           ; 1A27 ......
        .byte   W6(%00000000)           ; 1A28 ......  char $93
        .byte   W6(%00000000)           ; 1A29 ......
        .byte   W6(%00000000)           ; 1A2A ......
        .byte   W6(%00000010)           ; 1A2B ....#.
        .byte   W6(%00001000)           ; 1A2C ..#...
        .byte   W6(%00000000)           ; 1A2D ......
        .byte   W6(%00010011)           ; 1A2E .#..##
        .byte   W6(%00000111)           ; 1A2F ...###
        .byte   W6(%00000000)           ; 1A30 ......  char $94
        .byte   W6(%00000000)           ; 1A31 ......
        .byte   W6(%00000000)           ; 1A32 ......
        .byte   W6(%00100000)           ; 1A33 #.....
        .byte   W6(%00001000)           ; 1A34 ..#...
        .byte   W6(%00000000)           ; 1A35 ......
        .byte   W6(%00100010)           ; 1A36 #...#.
        .byte   W6(%00110000)           ; 1A37 ##....
        .byte   W6(%00000000)           ; 1A38 ......  char $95
        .byte   W6(%00000000)           ; 1A39 ......
        .byte   W6(%00000000)           ; 1A3A ......
        .byte   W6(%00000000)           ; 1A3B ......
        .byte   W6(%00000000)           ; 1A3C ......
        .byte   W6(%00000000)           ; 1A3D ......
        .byte   W6(%00000000)           ; 1A3E ......
        .byte   W6(%00000000)           ; 1A3F ......
        .byte   W6(%00000111)           ; 1A40 ...###  char $96
        .byte   W6(%00010011)           ; 1A41 .#..##
        .byte   W6(%00000000)           ; 1A42 ......
        .byte   W6(%00001000)           ; 1A43 ..#...
        .byte   W6(%00000010)           ; 1A44 ....#.
        .byte   W6(%00000000)           ; 1A45 ......
        .byte   W6(%00000000)           ; 1A46 ......
        .byte   W6(%00000000)           ; 1A47 ......
        .byte   W6(%00110000)           ; 1A48 ##....  char $97
        .byte   W6(%00100010)           ; 1A49 #...#.
        .byte   W6(%00000000)           ; 1A4A ......
        .byte   W6(%00001000)           ; 1A4B ..#...
        .byte   W6(%00100000)           ; 1A4C #.....
        .byte   W6(%00000000)           ; 1A4D ......
        .byte   W6(%00000000)           ; 1A4E ......
        .byte   W6(%00000000)           ; 1A4F ......

;------------------------------------------------------------------------------
; Title bar for rows 0-1 (double height).
;------------------------------------------------------------------------------
title_bar:
        .byte   $14,$07,$0A,"PSS ***** HOPPER  HI SCORES *****   "," ",$14 ; 1A50
        .byte   $07,$0A,"PSS ***** HOPPER  HI SCORES *****   "," " ; 1A79

;------------------------------------------------------------------------------
; DrawTitleBar - draw the two-row title bar.
;------------------------------------------------------------------------------
DrawTitleBar:
        ldx     #$4F                    ; 1AA0
L1AA2:
        lda     title_bar,x             ; 1AA2
        sta     SCREEN+0*40+0,x         ; 1AA5
        dex                             ; 1AA8
        bpl     L1AA2                   ; 1AA9
        rts                             ; 1AAB
        .res    4, $FF                  ; 1AAC

;------------------------------------------------------------------------------
; GAME OVER (double height).
;------------------------------------------------------------------------------
game_over_text:
        .byte   $0E,$11,$07,"GAME OVER",$08,$02           ; 1AB0
        .byte   $14                                       ; 1ABE
        .res    17, $FF                 ; 1ABF

;------------------------------------------------------------------------------
; GameOver - show GAME OVER, pause, restore the font and go to the hi-score check.
;------------------------------------------------------------------------------
GameOver:
        lda     #$0A                    ; 1AD0
        ldx     #$00                    ; 1AD2
        jsr     SoundWrite              ; 1AD4
        ldx     #$0E                    ; 1AD7
L1AD9:
        lda     game_over_text,x        ; 1AD9
        sta     SCREEN+0*40+14,x        ; 1ADC
        sta     SCREEN+1*40+14,x        ; 1ADF
        dex                             ; 1AE2
        bpl     L1AD9                   ; 1AE3
        lda     #$06                    ; 1AE5
        sta     tmp0                    ; 1AE7
L1AE9:
        ldx     #$00                    ; 1AE9
        jsr     DelayX                  ; 1AEB
        dec     tmp0                    ; 1AEE
        bne     L1AE9                   ; 1AF0
        jsr     RestoreCharset          ; 1AF2
        jsr     InitTimers              ; 1AF5
        jmp     CheckHiScore            ; 1AF8
        .res    5, $FF                  ; 1AFB

;------------------------------------------------------------------------------
; CheckHiScore - compare the score with the table at ALTCHARS+$200; if it
; qualifies, insert it, ask for a name (read from the ROM key buffer) and show
; the table. Then enter attract mode.
;------------------------------------------------------------------------------
CheckHiScore:
        lda     #$00                    ; 1B00
        sta     fly_on                  ; 1B02
        lda     #$BA                    ; 1B04
        sta     fly_timer               ; 1B06
L1B08:
        ldy     #$07                    ; 1B08
        sec                             ; 1B0A
L1B0B:
        lda     (fly_on),y              ; 1B0B
        sbc     SCORE_DIGITS-1,y        ; 1B0D
        dey                             ; 1B10
        bpl     L1B0B                   ; 1B11
        bcc     L1B27                   ; 1B13
        lda     fly_on                  ; 1B15
        clc                             ; 1B17
        adc     #$1C                    ; 1B18
        sta     fly_on                  ; 1B1A
        sec                             ; 1B1C
        cmp     #$C5                    ; 1B1D
        bcc     L1B08                   ; 1B1F
        nop                             ; 1B21
        nop                             ; 1B22
        nop                             ; 1B23
        jmp     ShowHiScores            ; 1B24
L1B27:
        lda     fly_on                  ; 1B27
        cmp     #$C4                    ; 1B29
        beq     L1B3A                   ; 1B2B
        ldx     #$C4                    ; 1B2D
L1B2F:
        dex                             ; 1B2F
        lda     HISCORES,x              ; 1B30
        sta     HISCORES+28,x           ; 1B33
        cpx     fly_on                  ; 1B36
        bne     L1B2F                   ; 1B38
L1B3A:
        ldx     fly_on                  ; 1B3A
        lda     #$0D                    ; 1B3C
        sta     HISCORES+8,x            ; 1B3E
        ldy     #$07                    ; 1B41
L1B43:
        lda     SCORE_DIGITS-1,y        ; 1B43
        sta     (fly_on),y              ; 1B46
        dey                             ; 1B48
        bne     L1B43                   ; 1B49
        jsr     ClearScreen             ; 1B4B
        jsr     ShowEnterName           ; 1B4E
        jsr     HiscoreTableC64         ; 1B51  C64: hi-score rows
        lda     #$00                    ; 1B54
        sta     ROM_CURCOL              ; 1B56
        nop                             ; 1B59
        lda     ROM_CURPTR              ; 1B5A
        sec                             ; 1B5C
        sbc     #$3D                    ; 1B5D
        sta     ROM_CURPTR              ; 1B5F
        bcs     L1B65                   ; 1B61
        dec     ROM_CURPTR+1            ; 1B63
L1B65:
        ldx     #$27                    ; 1B65
L1B67:
        lda     #$20                    ; 1B67
        nop                             ; 1B69
        sta     STATUS_ROW,x            ; 1B6A
        dex                             ; 1B6D
        bpl     L1B67                   ; 1B6E
        cli                             ; 1B70
        lda     #$BA                    ; 1B71
        sta     fly_timer               ; 1B73
        lda     #$08                    ; 1B75
        sta     fly_timer+1             ; 1B77
NameKeyLoop:
        jsr     ReadRomKey              ; 1B79  C64: draws the screen, then lda ROM_KEY
        bpl     NameKeyLoop             ; 1B7C
        and     #$7F                    ; 1B7E
        pha                             ; 1B80
        lda     #$00                    ; 1B81
        sta     ROM_KEY                 ; 1B83
        pla                             ; 1B86
        ldy     #$00                    ; 1B87
        cmp     #$7F                    ; 1B89
        bne     L1BA5                   ; 1B8B
        dec     fly_timer+1             ; 1B8D
        lda     fly_timer+1             ; 1B8F
        cmp     #$07                    ; 1B91
        bne     L1B9A                   ; 1B93
        inc     fly_timer+1             ; 1B95
        jmp     NameKeyLoop             ; 1B97
L1B9A:
        lda     #$20                    ; 1B9A
        sta     (ROM_CURPTR),y          ; 1B9C
        dec     ROM_CURPTR              ; 1B9E
        sta     (ROM_CURPTR),y          ; 1BA0
        jmp     NameKeyLoop             ; 1BA2
L1BA5:
        cmp     #$0D                    ; 1BA5
        beq     L1BC7                   ; 1BA7
        sec                             ; 1BA9
        cmp     #$20                    ; 1BAA
        bcs     L1BB1                   ; 1BAC
        jmp     NameKeyLoop             ; 1BAE
L1BB1:
        ldy     fly_timer+1             ; 1BB1
        cpy     #$1B                    ; 1BB3
        bne     L1BBA                   ; 1BB5
        jmp     NameKeyLoop             ; 1BB7
L1BBA:
        sta     (fly_on),y              ; 1BBA
        inc     fly_timer+1             ; 1BBC
        ldy     #$00                    ; 1BBE
        sta     (ROM_CURPTR),y          ; 1BC0
        inc     ROM_CURPTR              ; 1BC2
        jmp     NameKeyLoop             ; 1BC4
L1BC7:
        ldy     fly_timer+1             ; 1BC7
        sta     (fly_on),y              ; 1BC9
ShowHiScores:
        nop                             ; 1BCB  C64: was sei (SetRowMap runs next)
        jsr     ClearScreen             ; 1BCC
        jsr     DrawTitleBar            ; 1BCF
        jsr     HiscoreTableC64         ; 1BD2  C64: hi-score rows
        ldx     #$4F                    ; 1BD5
L1BD7:
        lda     #$20                    ; 1BD7
        nop                             ; 1BD9
        sta     SCREEN+26*40+0,x        ; 1BDA
        dex                             ; 1BDD
        bpl     L1BD7                   ; 1BDE
        jsr     DrawMenuPrompt          ; 1BE0
        jsr     ClearEnterName          ; 1BE3
        jmp     BadTarget_296D          ; 1BE6  jumps 1 byte into `jsr ClearScreen` at $296B: runs ORA #$20 / LDY #$1A
        .res    23, $FF                 ; 1BE9

;------------------------------------------------------------------------------
; DrawHiScoreTable - print the eight hi-score entries.
;------------------------------------------------------------------------------
DrawHiScoreTable:
        lda     #$00                    ; 1C00
        sta     frog_pos+1              ; 1C02
        lda     #$20                    ; 1C04
        sta     ptr30                   ; 1C06
        lda     #$BC                    ; 1C08
        sta     frog_dir                ; 1C0A
        lda     #$31                    ; 1C0C
        sta     frog_pos                ; 1C0E
L1C10:
        ldy     #$00                    ; 1C10
        ldx     frog_pos                ; 1C12
        lda     hiscore_inks-'1',x      ; 1C14
        jsr     PutChar                 ; 1C17
        ldx     frog_pos+1              ; 1C1A
        lda     #$20                    ; 1C1C
        jsr     PutChar                 ; 1C1E
        jsr     PutChar                 ; 1C21
        lda     frog_pos                ; 1C24
        jsr     PutChar                 ; 1C26
        lda     #$3E                    ; 1C29
        jsr     PutChar                 ; 1C2B
        lda     #$20                    ; 1C2E
        jsr     PutChar                 ; 1C30
        lda     #$08                    ; 1C33
        sta     old_pos                 ; 1C35
L1C37:
        lda     HISCORES,x              ; 1C37
        jsr     PutChar                 ; 1C3A
        inx                             ; 1C3D
        dec     old_pos                 ; 1C3E
        bne     L1C37                   ; 1C40
        lda     #$20                    ; 1C42
        jsr     PutChar                 ; 1C44
        lda     #$2D                    ; 1C47
        jsr     PutChar                 ; 1C49
        jsr     PutChar                 ; 1C4C
        jsr     PutChar                 ; 1C4F
        lda     #$20                    ; 1C52
        jsr     PutChar                 ; 1C54
L1C57:
        lda     HISCORES,x              ; 1C57
        cmp     #$0D                    ; 1C5A
        beq     L1C64                   ; 1C5C
        jsr     PutChar                 ; 1C5E
        inx                             ; 1C61
        bne     L1C57                   ; 1C62
L1C64:
        lda     ptr30                   ; 1C64
        clc                             ; 1C66
        adc     #$50                    ; 1C67
        sta     ptr30                   ; 1C69
        bcc     L1C6F                   ; 1C6B
        inc     frog_dir                ; 1C6D
L1C6F:
        inc     frog_pos                ; 1C6F
        nop                             ; 1C71
        nop                             ; 1C72
        nop                             ; 1C73
        nop                             ; 1C74
        beq     L1C93                   ; 1C75
        lda     frog_pos+1              ; 1C77
        cmp     fly_on                  ; 1C79
        bne     L1C87                   ; 1C7B
        lda     ptr30                   ; 1C7D
        sta     ROM_CURPTR              ; 1C7F
        lda     frog_dir                ; 1C81
        sta     ROM_CURPTR+1            ; 1C83
        lda     frog_pos+1              ; 1C85
L1C87:
        clc                             ; 1C87
        adc     #$1C                    ; 1C88
        sta     frog_pos+1              ; 1C8A
        cmp     #$E0                    ; 1C8C
        beq     L1C93                   ; 1C8E
        jmp     L1C10                   ; 1C90
L1C93:
        rts                             ; 1C93
        .res    12, $20                 ; 1C94

;------------------------------------------------------------------------------
; PutChar - store A at ($30),Y and advance Y.
;------------------------------------------------------------------------------
PutChar:
        sta     (ptr30),y               ; 1CA0
        iny                             ; 1CA2
        rts                             ; 1CA3
        .res    12, $FF                 ; 1CA4

;------------------------------------------------------------------------------
; Attract-mode prompt. Note the original typo "INSTRUCTONS".
;------------------------------------------------------------------------------
menu_prompt:
        .byte   "PRESS [1] FOR A NEW GAME            ","          [2] FOR INSTRUCTONS" ; 1CB0
        .byte   $00,$FF                                   ; 1CF1
        .res    13, $FF                 ; 1CF3

;------------------------------------------------------------------------------
; DrawMenuPrompt - draw the attract-mode prompt and scroll the title bar.
;------------------------------------------------------------------------------
DrawMenuPrompt:
        ldx     #$40                    ; 1D00
L1D02:
        lda     menu_prompt,x           ; 1D02
        sta     SCREEN+26*40+2,x        ; 1D05
        dex                             ; 1D08
        bpl     L1D02                   ; 1D09
        jmp     TitleScroll             ; 1D0B
        .byte   $55,$55                                   ; 1D0E

;------------------------------------------------------------------------------
; Shown when a new hi-score is entered.
;------------------------------------------------------------------------------
enter_name_text:
        .byte   $0C,$04,$13,"PLEASE ENTER YOUR NAME",$07,$10 ; 1D10
        .byte   $08                                       ; 1D2B
        .byte   $00,$FF,$FF,$FF                           ; 1D2C

ShowEnterName:
        ldx     #$1B                    ; 1D30
L1D32:
        lda     enter_name_text,x       ; 1D32
        sta     SCREEN+23*40+7,x        ; 1D35
        dex                             ; 1D38
        bpl     L1D32                   ; 1D39
        jsr     DrawTitleBar            ; 1D3B
        rts                             ; 1D3E
        .byte   $FF                                       ; 1D3F

ClearEnterName:
        ldx     #$1B                    ; 1D40
        lda     #$20                    ; 1D42
L1D44:
        sta     SCREEN+23*40+7,x        ; 1D44
        dex                             ; 1D47
        bpl     L1D44                   ; 1D48
        rts                             ; 1D4A
        .res    5, $FF                  ; 1D4B

;------------------------------------------------------------------------------
; CheckTimeLow - warning tone when TIME gets low; when it hits 00, lose a life.
;------------------------------------------------------------------------------
CheckTimeLow:
        lda     TIME_DIGITS             ; 1D50
        cmp     #$30                    ; 1D53
        bne     L1D82                   ; 1D55
        lda     TIME_DIGITS+1           ; 1D57
        cmp     #$30                    ; 1D5A
        beq     L1D83                   ; 1D5C
        lda     #$09                    ; 1D5E
        ldx     #$07                    ; 1D60
        jsr     SoundWrite              ; 1D62
        lda     #$02                    ; 1D65
        ldx     #$14                    ; 1D67
        jsr     SoundWrite              ; 1D69
        ldx     #$0C                    ; 1D6C
        jsr     DelayX                  ; 1D6E
        lda     #$02                    ; 1D71
        ldx     #$00                    ; 1D73
        jsr     SoundWrite              ; 1D75
        lda     #$0C                    ; 1D78
        sta     STATUS_ROW+15           ; 1D7A
        lda     #$08                    ; 1D7D
        sta     STATUS_ROW+23           ; 1D7F
L1D82:
        rts                             ; 1D82
L1D83:
        lda     #$01                    ; 1D83
        sta     STATUS_ROW+15           ; 1D85
        lda     #$04                    ; 1D88
        sta     STATUS_ROW+23           ; 1D8A
        lda     #$39                    ; 1D8D
        sta     TIME_DIGITS             ; 1D8F
        sta     TIME_DIGITS+1           ; 1D92
        lda     #$09                    ; 1D95
        ldx     #$07                    ; 1D97
        jsr     SoundWrite              ; 1D99
        jmp     LoseLife                ; 1D9C
        .byte   $FF                                       ; 1D9F

;------------------------------------------------------------------------------
; ServiceTimer - called often. When VIA timer 2 has run out: reload it,
; tick TIME every 32 periods, and step the hop sound.
;------------------------------------------------------------------------------
ServiceTimer:
        stx     tmp0                    ; 1DA0
        lda     #$20                    ; 1DA2
        jsr     T2Check                 ; 1DA4  C64: Z = 0 when VIA timer 2 has run out
        bne     L1DAA                   ; 1DA7
        rts                             ; 1DA9
L1DAA:
        lda     timer2_reload           ; 1DAA
        sta     VIA_T2CL                ; 1DAD
        lda     timer2_reload+1         ; 1DB0
        sta     VIA_T2CH                ; 1DB3
        inc     tick_count              ; 1DB6
        lda     tick_count              ; 1DB8
        and     #$1F                    ; 1DBA
        cmp     #$1F                    ; 1DBC
        bne     L1DC3                   ; 1DBE
        jsr     TimeTick                ; 1DC0
L1DC3:
        lda     hop_sound               ; 1DC3
        bne     L1DCA                   ; 1DC5
        ldx     tmp0                    ; 1DC7
        rts                             ; 1DC9
L1DCA:
        cmp     #$01                    ; 1DCA
        bne     L1DDC                   ; 1DCC
        nop                             ; 1DCE
        nop                             ; 1DCF
        nop                             ; 1DD0
        nop                             ; 1DD1
        nop                             ; 1DD2
        nop                             ; 1DD3
        nop                             ; 1DD4
        lda     #$08                    ; 1DD5
        ldx     #$02                    ; 1DD7
        jsr     SoundWrite              ; 1DD9
L1DDC:
        inc     hop_sound               ; 1DDC
        lda     hop_sound               ; 1DDE
        cmp     #$0B                    ; 1DE0
        bne     L1DF2                   ; 1DE2
        lda     #$00                    ; 1DE4
        sta     hop_sound               ; 1DE6
        lda     #$08                    ; 1DE8
        ldx     #$00                    ; 1DEA
        jsr     SoundWrite              ; 1DEC
        ldx     tmp0                    ; 1DEF
        rts                             ; 1DF1
L1DF2:
        ldx     hop_sound               ; 1DF2
        lda     hop_pitches,x           ; 1DF4
        tax                             ; 1DF7
        lda     #$00                    ; 1DF8
        jsr     SoundWrite              ; 1DFA
        lda     hop_sound               ; 1DFD
        nop                             ; 1DFF
        ldx     tmp0                    ; 1E00
        rts                             ; 1E02
        .res    13, $FF                 ; 1E03

;------------------------------------------------------------------------------
; FlyBonus - frog ate the fly: random bonus counted into the score with beeps.
;------------------------------------------------------------------------------
FlyBonus:
        lda     #$07                    ; 1E10
        ldx     #$F8                    ; 1E12
        jsr     SoundWrite              ; 1E14
        lda     #$09                    ; 1E17
        ldx     #$03                    ; 1E19
        jsr     SoundWrite              ; 1E1B
        jsr     RandomNext              ; 1E1E
        lda     rand_seed+2             ; 1E21
        and     #$03                    ; 1E23
        clc                             ; 1E25
        adc     #$07                    ; 1E26
        tay                             ; 1E28
L1E29:
        sty     tmp0                    ; 1E29
        ldx     #$04                    ; 1E2B
        lda     #$01                    ; 1E2D
        jsr     AddScore                ; 1E2F
        jsr     BonusBeep               ; 1E32
        jsr     Delay48                 ; 1E35
        jsr     Delay48                 ; 1E38
        ldy     tmp0                    ; 1E3B
        dey                             ; 1E3D
        bpl     L1E29                   ; 1E3E
        lda     #$09                    ; 1E40
        ldx     #$00                    ; 1E42
        jsr     SoundWrite              ; 1E44
        rts                             ; 1E47

BonusBeep:
        ldy     tmp0                    ; 1E48
        lda     #$02                    ; 1E4A
        ldx     bonus_pitches,y         ; 1E4C
        jsr     SoundWrite              ; 1E4F
        rts                             ; 1E52

;------------------------------------------------------------------------------
; Tone periods for the fly bonus sound.
;------------------------------------------------------------------------------
bonus_pitches:
        .byte   $50,$70,$50,$60,$70,$80,$60,$50           ; 1E53
        .byte   $40,$60,$70,$40                           ; 1E5B
        .res    33, $FF                 ; 1E5F

; ---- unreferenced code: a delay loop; never called
L1E80:
        ldx     #$20                    ; 1E80
L1E82:
        stx     tmp0                    ; 1E82
        jsr     Delay48                 ; 1E84
        ldx     tmp0                    ; 1E87
        dex                             ; 1E89
        bpl     L1E82                   ; 1E8A
        rts                             ; 1E8C
        .res    17, $FF                 ; 1E8D

;------------------------------------------------------------------------------
; Tone periods for the hop sound (steps 2-10).
;------------------------------------------------------------------------------
hop_pitches:
        .byte   $FF,$FF,$80,$A0,$C0,$D0,$E0,$F0           ; 1E9E
        .byte   $E0,$D0,$C0,$A0,$80                       ; 1EA6
        .res    21, $00                 ; 1EAB

; ---- unreferenced code: a lane-gap countdown; never called
L1EC0:
        lda     r17_gap_min             ; 1EC0
        beq     L1EC8                   ; 1EC3
        dec     r17_gap_min             ; 1EC5
L1EC8:
        lda     r20_gap_min             ; 1EC8
        beq     L1ED0                   ; 1ECB
        dec     r20_gap_min             ; 1ECD
L1ED0:
        lda     r23_gap_min             ; 1ED0
        beq     L1ED8                   ; 1ED3
        dec     r23_gap_min             ; 1ED5
L1ED8:
        lda     r4_len_min              ; 1ED8
        beq     L1EE0                   ; 1EDB
        dec     r4_len_min              ; 1EDD
L1EE0:
        lda     r4_gap_min              ; 1EE0
        cmp     #$1B                    ; 1EE3
        bne     L1EEA                   ; 1EE5
        inc     r4_gap_min              ; 1EE7
L1EEA:
        rts                             ; 1EEA
        .res    21, $FF                 ; 1EEB

;------------------------------------------------------------------------------
; DrawScenery - draw the signs, play the sheet tune.
;------------------------------------------------------------------------------
DrawScenery:
        ldx     #$0A                    ; 1F00
L1F02:
        lda     scenery_ready,x         ; 1F02
        sta     SCREEN+14*40+13,x       ; 1F05
        sta     SCREEN+15*40+13,x       ; 1F08
        dex                             ; 1F0B
        bpl     L1F02                   ; 1F0C
        ldx     #$14                    ; 1F0E
L1F10:
        lda     scenery_sheet,x         ; 1F10
        sta     SCREEN+20*40+13,x       ; 1F13
        sta     SCREEN+21*40+13,x       ; 1F16
        dex                             ; 1F19
        bpl     L1F10                   ; 1F1A
        ldx     #$15                    ; 1F1C
L1F1E:
        lda     scenery_score,x         ; 1F1E
        sta     SCREEN+24*40+13,x       ; 1F21
        sta     SCREEN+25*40+13,x       ; 1F24
        dex                             ; 1F27
        bpl     L1F1E                   ; 1F28
        ldx     #$02                    ; 1F2A
L1F2C:
        lda     status_save+35,x        ; 1F2C
        sta     SCREEN+20*40+26,x       ; 1F2F
        sta     SCREEN+21*40+26,x       ; 1F32
        dex                             ; 1F35
        bpl     L1F2C                   ; 1F36
        ldx     #$07                    ; 1F38
L1F3A:
        lda     status_save+6,x         ; 1F3A
        sta     SCREEN+24*40+23,x       ; 1F3D
        sta     SCREEN+25*40+23,x       ; 1F40
        dex                             ; 1F43
        bpl     L1F3A                   ; 1F44
        ldx     #$20                    ; 1F46
        ldy     #$08                    ; 1F48
        jsr     LoadAYRegs              ; 1F4A
        jsr     PlaySheetTune           ; 1F4D
        rts                             ; 1F50
        .res    15, $FF                 ; 1F51

;------------------------------------------------------------------------------
; SilenceAll - set the volume of all three AY channels to 0.
;------------------------------------------------------------------------------
SilenceAll:
        lda     #$08                    ; 1F60
        ldx     #$00                    ; 1F62
        jsr     AYWrite                 ; 1F64
        lda     #$09                    ; 1F67
        ldx     #$00                    ; 1F69
        jsr     AYWrite                 ; 1F6B
        lda     #$0A                    ; 1F6E
        ldx     #$00                    ; 1F70
        jsr     AYWrite                 ; 1F72
        rts                             ; 1F75
        .res    26, $FF                 ; 1F76

;------------------------------------------------------------------------------
; SoundWrite - write AY register A = X, honouring the sound option:
; off (no write), quiet (as given) or loud (volume registers doubled).
;------------------------------------------------------------------------------
SoundWrite:
        ldy     sound_mode              ; 1F90
        beq     L1FE1                   ; 1F92
        cpy     #$01                    ; 1F94
        beq     L1FAA                   ; 1F96
        cmp     #$0A                    ; 1F98
        beq     L1FA4                   ; 1F9A
        cmp     #$09                    ; 1F9C
        beq     L1FA4                   ; 1F9E
        cmp     #$08                    ; 1FA0
        bne     L1FAA                   ; 1FA2
L1FA4:
        pha                             ; 1FA4
        txa                             ; 1FA5
        asl     a                       ; 1FA6
        nop                             ; 1FA7
        tax                             ; 1FA8
        pla                             ; 1FA9
L1FAA:
        jmp     AYWrite                 ; 1FAA

;------------------------------------------------------------------------------
; AYWrite - write value X to AY register A. Drives the BC1/BDIR lines
; through the VIA PCR (CA2/CB2) - see ViaMaskBits.
;------------------------------------------------------------------------------
AYWrite:
        jmp     AyWriteC64              ; 1FAD  C64: AY registers to the SID
        nop                             ; 1FB0  C64: pad
        nop                             ; 1FB1  C64: pad
        cmp     #$07                    ; 1FB2
        bne     L1FBC                   ; 1FB4
        txa                             ; 1FB6
        ora     #$40                    ; 1FB7
        jmp     L1FBD                   ; 1FB9
L1FBC:
        txa                             ; 1FBC
L1FBD:
        pha                             ; 1FBD
        ldx     #$0C                    ; 1FBE
        ldy     #$EE                    ; 1FC0
        lda     #$11                    ; 1FC2
        jsr     ViaMaskBits             ; 1FC4
        ldy     #$CC                    ; 1FC7
        lda     #$11                    ; 1FC9
        jsr     ViaMaskBits             ; 1FCB
        pla                             ; 1FCE
        sta     VIA_ORA_NH              ; 1FCF
        ldy     #$EC                    ; 1FD2
        lda     #$11                    ; 1FD4
        jsr     ViaMaskBits             ; 1FD6
        ldy     #$CC                    ; 1FD9
        lda     #$11                    ; 1FDB
        jsr     ViaMaskBits             ; 1FDD
        plp                             ; 1FE0
L1FE1:
        rts                             ; 1FE1

;------------------------------------------------------------------------------
; ViaMaskBits - VIA register X = (VIA register X AND A) OR Y.
;------------------------------------------------------------------------------
ViaMaskBits:
        php                             ; 1FE2
        sei                             ; 1FE3
        and     VIA_ORB,x               ; 1FE4
        sta     ROM_SCRATCH             ; 1FE7
        tya                             ; 1FEA
        ora     ROM_SCRATCH             ; 1FEB
        sta     VIA_ORB,x               ; 1FEE
        plp                             ; 1FF1
        rts                             ; 1FF2
        .byte   "`UUUUUUUUUUUU"                           ; 1FF3

;------------------------------------------------------------------------------
; DrawPlayfield - clear the screen and draw colours, homes, banks and lanes.
;------------------------------------------------------------------------------
DrawPlayfield:
        jsr     ClearScreen             ; 2000
        lda     #$80                    ; 2003
        sta     ptr30                   ; 2005
        lda     #$BB                    ; 2007
        sta     frog_dir                ; 2009
        ldx     #$00                    ; 200B
L200D:
        ldy     #$00                    ; 200D
        lda     row_colours,x           ; 200F
        sta     (ptr30),y               ; 2012
        lda     row_colours+1,x         ; 2014
        iny                             ; 2017
        sta     (ptr30),y               ; 2018
        inx                             ; 201A
        inx                             ; 201B
        nop                             ; 201C
        clc                             ; 201D
        lda     ptr30                   ; 201E
        adc     #$28                    ; 2020
        sta     ptr30                   ; 2022
        lda     frog_dir                ; 2024
        adc     #$00                    ; 2026
        sta     frog_dir                ; 2028
        cmp     #$C0                    ; 202A
        bne     L200D                   ; 202C
        ldx     #$00                    ; 202E
        lda     #$7F                    ; 2030
L2032:
        ldy     home_wall_cols,x        ; 2032
        sta     SCREEN+1*40+2,y         ; 2035
        sta     SCREEN+2*40+2,y         ; 2038
        inx                             ; 203B
        cpx     #$1C                    ; 203C
        bne     L2032                   ; 203E
        ldx     #$00                    ; 2040
L2042:
        sta     SCREEN+0*40+2,x         ; 2042
        inx                             ; 2045
        cpx     #$26                    ; 2046
        bne     L2042                   ; 2048
        lda     #$01                    ; 204A
        sta     frog_dir                ; 204C
        jsr     SetFrogGfx              ; 204E
        nop                             ; 2051
        nop                             ; 2052
        nop                             ; 2053
        nop                             ; 2054
        nop                             ; 2055
        nop                             ; 2056
        ldx     #$00                    ; 2057
L2059:
        lda     #$2D                    ; 2059
        sta     SCREEN+19*40+2,x        ; 205B
        sta     SCREEN+22*40+2,x        ; 205E
        inx                             ; 2061
        cpx     #$26                    ; 2062
        bne     L2059                   ; 2064
        ldx     #$00                    ; 2066
L2068:
        nop                             ; 2068
        nop                             ; 2069
        nop                             ; 206A
        nop                             ; 206B
        nop                             ; 206C
        nop                             ; 206D
        nop                             ; 206E
        nop                             ; 206F
        nop                             ; 2070
        nop                             ; 2071
        nop                             ; 2072
        nop                             ; 2073
        lda     lane_init,x             ; 2074
        sta     SCREEN+7*40+2,x         ; 2077
        lda     lane_init+38,x          ; 207A
        sta     SCREEN+8*40+2,x         ; 207D
        lda     lane_init+76,x          ; 2080
        sta     SCREEN+10*40+2,x        ; 2083
        lda     lane_init+114,x         ; 2086
        sta     SCREEN+11*40+2,x        ; 2089
        lda     lane_init+152,x         ; 208C
        sta     SCREEN+13*40+2,x        ; 208F
        lda     lane_init+190,x         ; 2092
        sta     SCREEN+14*40+2,x        ; 2095
        inx                             ; 2098
        cpx     #$26                    ; 2099
        bne     L2068                   ; 209B
        rts                             ; 209D
        .byte   $55                                       ; 209E

;------------------------------------------------------------------------------
; InitTimers - enable VIA timer 1 free-run interrupts for the ROM (keyboard, ~100Hz).
;------------------------------------------------------------------------------
InitTimers:
        cli                             ; 209F
        jsr     RomIrqOn                ; 20A0  C64: ROM IRQ (keyboard) back on
        and     #$7F                    ; 20A3
        ora     #$40                    ; 20A5
        sta     VIA_ACR                 ; 20A7
        lda     #$C0                    ; 20AA
        sta     VIA_IER                 ; 20AC
        lda     #$10                    ; 20AF
        sta     VIA_T1LL                ; 20B1
        sta     VIA_T1CL                ; 20B4
        lda     #$27                    ; 20B7
        sta     VIA_T1LH                ; 20B9
        sta     VIA_T1CH                ; 20BC
        rts                             ; 20BF

;------------------------------------------------------------------------------
; TimeBonus - add the remaining TIME to the score, one unit at a time, with a beep.
;------------------------------------------------------------------------------
TimeBonus:
        lda     TIME_DIGITS+1           ; 20C0
        lda     #$01                    ; 20C3
        ldx     #$05                    ; 20C5
        jsr     AddScore                ; 20C7
        lda     #$08                    ; 20CA
        ldx     #$03                    ; 20CC
        jsr     SoundWrite              ; 20CE
        lda     #$00                    ; 20D1
        ldx     #$80                    ; 20D3
        jsr     SoundWrite              ; 20D5
        jsr     Delay48                 ; 20D8
        lda     #$08                    ; 20DB
        ldx     #$00                    ; 20DD
        jsr     SoundWrite              ; 20DF
        jsr     Delay48                 ; 20E2
        dec     TIME_DIGITS+1           ; 20E5
        lda     TIME_DIGITS+1           ; 20E8
        cmp     #$2F                    ; 20EB
        bne     TimeBonus               ; 20ED
        dec     TIME_DIGITS             ; 20EF
        lda     TIME_DIGITS             ; 20F2
        cmp     #$2F                    ; 20F5
        beq     L2101                   ; 20F7
        lda     #$39                    ; 20F9
        sta     TIME_DIGITS+1           ; 20FB
        jmp     TimeBonus               ; 20FE
L2101:
        lda     #$30                    ; 2101
        sta     TIME_DIGITS             ; 2103
        sta     TIME_DIGITS+1           ; 2106
        jsr     SilenceAll              ; 2109
        rts                             ; 210C
        .byte   $FF,$FF,$FF                               ; 210D

SetSplatGfx:
        ldx     #$1F                    ; 2110
L2112:
        lda     splat_gfx,x             ; 2112
        sta     CHARSET+$3A*8,x         ; 2115
        dex                             ; 2118
        bpl     L2112                   ; 2119
        jsr     DrawFrog                ; 211B
        rts                             ; 211E

DeathSoundInit:
        lda     #$08                    ; 211F
        ldx     #$03                    ; 2121
        jsr     SoundWrite              ; 2123
        lda     #$00                    ; 2126
        sta     tmp0                    ; 2128
        sta     key_state               ; 212A
        sta     tmp4                    ; 212C
        lda     #$07                    ; 212E
        ldx     #$F8                    ; 2130
        jsr     SoundWrite              ; 2132
        rts                             ; 2135

FlashRows:
        lda     #$80                    ; 2136
        sta     tmp2                    ; 2138
        lda     #$BB                    ; 213A
        sta     tmp3                    ; 213C
        ldx     #$00                    ; 213E
L2140:
        lda     tmp5                    ; 2140
        bne     L2152                   ; 2142
        ldy     #$00                    ; 2144
        lda     #$00                    ; 2146
        sta     (tmp2),y                ; 2148
        iny                             ; 214A
        lda     #$17                    ; 214B
        sta     (tmp2),y                ; 214D
        jmp     L215D                   ; 214F
L2152:
        ldy     #$00                    ; 2152
        lda     #$07                    ; 2154
        sta     (tmp2),y                ; 2156
        iny                             ; 2158
        lda     #$10                    ; 2159
        sta     (tmp2),y                ; 215B
L215D:
        clc                             ; 215D
        lda     tmp2                    ; 215E
        adc     #$28                    ; 2160
        sta     tmp2                    ; 2162
        lda     tmp3                    ; 2164
        adc     #$00                    ; 2166
        sta     tmp3                    ; 2168
        inx                             ; 216A
        cpx     #$1C                    ; 216B
        bne     L2140                   ; 216D
        rts                             ; 216F

;------------------------------------------------------------------------------
; DeathSequence - squashed frog, falling tone and flashing screen colours.
;------------------------------------------------------------------------------
DeathSequence:
        jsr     DeathSoundInit          ; 2170
        jsr     SetSplatGfx             ; 2173
L2176:
        lda     tmp0                    ; 2176
        clc                             ; 2178
        adc     #$03                    ; 2179
        sta     tmp0                    ; 217B
        bcc     L2199                   ; 217D
        lda     #$00                    ; 217F
        sta     tmp0                    ; 2181
        lda     key_state               ; 2183
        clc                             ; 2185
        adc     #$01                    ; 2186
        sta     key_state               ; 2188
        cmp     #$03                    ; 218A
        bne     L2199                   ; 218C
        lda     #$08                    ; 218E
        ldx     #$00                    ; 2190
        jsr     SoundWrite              ; 2192
        jsr     RestoreRowColours       ; 2195
        rts                             ; 2198
L2199:
        lda     key_state               ; 2199
        eor     #$03                    ; 219B
        tax                             ; 219D
        lda     #$08                    ; 219E
        jsr     SoundWrite              ; 21A0
        ldx     tmp0                    ; 21A3
        lda     #$00                    ; 21A5
        jsr     SoundWrite              ; 21A7
        ldx     key_state               ; 21AA
        lda     #$01                    ; 21AC
        jsr     SoundWrite              ; 21AE
        inc     tmp6                    ; 21B1
        lda     tmp6                    ; 21B3
        and     #$07                    ; 21B5
        cmp     #$07                    ; 21B7
        bne     L21D3                   ; 21B9
        inc     tmp4                    ; 21BB
        lda     tmp4                    ; 21BD
        and     #$01                    ; 21BF
        cmp     #$01                    ; 21C1
        bne     L21CC                   ; 21C3
        lda     #$01                    ; 21C5
        sta     tmp5                    ; 21C7
        jmp     L21D0                   ; 21C9
L21CC:
        lda     #$00                    ; 21CC
        sta     tmp5                    ; 21CE
L21D0:
        jsr     FlashRows               ; 21D0
L21D3:
        ldx     #$06                    ; 21D3
        jsr     DelayX                  ; 21D5
        jmp     L2176                   ; 21D8

RestoreRowColours:
        lda     #$80                    ; 21DB
        sta     tmp0                    ; 21DD
        lda     #$BB                    ; 21DF
        sta     key_state               ; 21E1
        ldx     #$00                    ; 21E3
L21E5:
        ldy     #$00                    ; 21E5
        lda     row_colours,x           ; 21E7
        sta     (tmp0),y                ; 21EA
        iny                             ; 21EC
        lda     row_colours+1,x         ; 21ED
        sta     (tmp0),y                ; 21F0
        iny                             ; 21F2
        inx                             ; 21F3
        inx                             ; 21F4
        clc                             ; 21F5
        lda     tmp0                    ; 21F6
        adc     #$28                    ; 21F8
        sta     tmp0                    ; 21FA
        lda     key_state               ; 21FC
        adc     #$00                    ; 21FE
        sta     key_state               ; 2200
        cmp     #$C0                    ; 2202
        bne     L21E5                   ; 2204
        rts                             ; 2206

;------------------------------------------------------------------------------
; Squashed-frog graphics for the death sequence.
;------------------------------------------------------------------------------
splat_gfx:
        .byte   W6(%00000000)           ; 2207 ......  +0
        .byte   W6(%00000000)           ; 2208 ......
        .byte   W6(%00110000)           ; 2209 ##....
        .byte   W6(%00001100)           ; 220A ..##..
        .byte   W6(%00001111)           ; 220B ..####
        .byte   W6(%00000111)           ; 220C ...###
        .byte   W6(%00000101)           ; 220D ...#.#
        .byte   W6(%00000111)           ; 220E ...###
        .byte   W6(%00000000)           ; 220F ......  +8
        .byte   W6(%00000000)           ; 2210 ......
        .byte   W6(%00000011)           ; 2211 ....##
        .byte   W6(%00001100)           ; 2212 ..##..
        .byte   W6(%00111100)           ; 2213 ####..
        .byte   W6(%00111000)           ; 2214 ###...
        .byte   W6(%00101000)           ; 2215 #.#...
        .byte   W6(%00111000)           ; 2216 ###...
        .byte   W6(%00000110)           ; 2217 ...##.  +16
        .byte   W6(%00000111)           ; 2218 ...###
        .byte   W6(%00000110)           ; 2219 ...##.
        .byte   W6(%00001010)           ; 221A ..#.#.
        .byte   W6(%00110001)           ; 221B ##...#
        .byte   W6(%00110000)           ; 221C ##....
        .byte   W6(%00000000)           ; 221D ......
        .byte   W6(%00000000)           ; 221E ......
        .byte   W6(%00011000)           ; 221F .##...  +24
        .byte   W6(%00111000)           ; 2220 ###...
        .byte   W6(%00011000)           ; 2221 .##...
        .byte   W6(%00010100)           ; 2222 .#.#..
        .byte   W6(%00100011)           ; 2223 #...##
        .byte   W6(%00000011)           ; 2224 ....##
        .byte   W6(%00000000)           ; 2225 ......
        .byte   W6(%00000000)           ; 2226 ......
        .byte   $FF,$55                                   ; 2227
        .res    7, $55                  ; 2229

;------------------------------------------------------------------------------
; FlyWarble - rising and falling tone while the fly is showing.
;------------------------------------------------------------------------------
FlyWarble:
        lda     fly_on                  ; 2230
        beq     L2269                   ; 2232
        lda     #$09                    ; 2234
        ldx     #$01                    ; 2236
        jsr     SoundWrite              ; 2238
        lda     warble_dir              ; 223B
        bne     L2255                   ; 223D
        inc     warble_level            ; 223F
        lda     warble_level            ; 2241
        cmp     #$08                    ; 2243
        bne     L224C                   ; 2245
        lda     #$01                    ; 2247
        sta     warble_dir              ; 2249
        rts                             ; 224B
L224C:
        asl     a                       ; 224C
        asl     a                       ; 224D
        tax                             ; 224E
        lda     #$02                    ; 224F
        jsr     SoundWrite              ; 2251
        rts                             ; 2254
L2255:
        dec     warble_level            ; 2255
        lda     warble_level            ; 2257
        bne     L2260                   ; 2259
        lda     #$00                    ; 225B
        sta     warble_dir              ; 225D
        rts                             ; 225F
L2260:
        asl     a                       ; 2260
        asl     a                       ; 2261
        tax                             ; 2262
        lda     #$02                    ; 2263
        jsr     SoundWrite              ; 2265
        rts                             ; 2268
L2269:
        lda     #$09                    ; 2269
        ldx     #$00                    ; 226B
        jsr     SoundWrite              ; 226D
        rts                             ; 2270
        .byte   $FF,$55                                   ; 2271
        .res    13, $55                 ; 2273

;------------------------------------------------------------------------------
; SoundMenu - draw the sound menu and wait for 1, 2 or 3 (sets sound_mode).
;------------------------------------------------------------------------------
SoundMenu:
        ldx     #$00                    ; 2280
        ldy     #$00                    ; 2282
        lda     #$D0                    ; 2284
        sta     tmp0                    ; 2286
        lda     #$BB                    ; 2288
        sta     key_state               ; 228A
L228C:
        lda     sound_menu_text,x       ; 228C
        cmp     #$0D                    ; 228F
        bne     L22A5                   ; 2291
        ldy     #$00                    ; 2293
        clc                             ; 2295
        lda     tmp0                    ; 2296
        adc     #$28                    ; 2298
        sta     tmp0                    ; 229A
        lda     key_state               ; 229C
        adc     #$00                    ; 229E
        sta     key_state               ; 22A0
        jmp     L22AC                   ; 22A2
L22A5:
        cmp     #$00                    ; 22A5
        beq     L22B0                   ; 22A7
        sta     (tmp0),y                ; 22A9
        iny                             ; 22AB
L22AC:
        inx                             ; 22AC
        jmp     L228C                   ; 22AD
L22B0:
        cli                             ; 22B0
L22B1:
        jsr     ReadRomKey              ; 22B1  C64: draws the screen, then lda ROM_KEY
        beq     L22B1                   ; 22B4
        and     #$7F                    ; 22B6
        cmp     #$31                    ; 22B8
        bne     L22C6                   ; 22BA
        lda     #$00                    ; 22BC
        sta     sound_mode              ; 22BE
        sta     ROM_KEY                 ; 22C0
        jmp     L22E6                   ; 22C3
L22C6:
        cmp     #$32                    ; 22C6
        bne     L22D6                   ; 22C8
        lda     #$01                    ; 22CA
        sta     sound_mode              ; 22CC
        lda     #$00                    ; 22CE
        sta     ROM_KEY                 ; 22D0
        jmp     L22E6                   ; 22D3
L22D6:
        cmp     #$33                    ; 22D6
        bne     L22E7                   ; 22D8
        lda     #$02                    ; 22DA
        sta     sound_mode              ; 22DC
        lda     #$00                    ; 22DE
        sta     ROM_KEY                 ; 22E0
        jmp     L22E6                   ; 22E3
L22E6:
        rts                             ; 22E6
L22E7:
        lda     #$00                    ; 22E7
        sta     ROM_KEY                 ; 22E9
        jmp     L22B1                   ; 22EC
        .byte   $FF,$55                                   ; 22EF
        .res    14, $55                 ; 22F1

;------------------------------------------------------------------------------
; Initial hi-score table, copied to ALTCHARS+$1FF at cold start.
; Eight entries of 28 bytes: 8-character score, then name ending $0D.
;------------------------------------------------------------------------------
hiscore_init:
        .byte   "U    1000P.S.S.",$0D                     ; 22FF
        .byte   "                  900P.S.S.",$0D         ; 230F
        .byte   "                  800P.S.S.",$0D         ; 232B
        .byte   "                  700P.S.S.",$0D         ; 2347
        .byte   "                  600P.S.S.",$0D         ; 2363
        .byte   "                  500P.S.S.",$0D         ; 237F
        .byte   "                  400P.S.S.",$0D         ; 239B
        .byte   "                  300P.S.S.",$0D         ; 23B7
        .byte   "                  200P.S.S.",$0D         ; 23D3
        .byte   "                "                        ; 23EF
        .byte   $20                                       ; 23FF

;------------------------------------------------------------------------------
; Credits and instructions, four characters per frog hop (two on the
; upper row, two on the lower). CreditsIntro makes a frog hop around
; the screen and leave these behind it. ControlsMenu patches the key
; names in place.
;------------------------------------------------------------------------------
credits_text:
        .byte   $01," ",$01,"  P  ER  SO  NA  L   SO  FT  WA  RE ","  S  ER  VI  CE  S   PR  ES  EN  TS "," ..                                 " ; 2400
        .byte   " ",$0A,"R",$0A,"R",$0A                   ; 246F
        .byte   "E",$0A,"E",$0A,"P",$0A                   ; 2475
        .byte   "P",$0A,"P",$0A,"P",$0A                   ; 247B
        .byte   "O",$0A,"O",$0A,"H",$0A                   ; 2481
        .byte   "H",$02," ",$02,"                     ",$01 ; 2487
        .byte   "A",$01," UT  HO  R   ",$05,"A",$05       ; 24A1
        .byte   " .J  .C  LA  RK  E                  "," D   VE  ER  ES   R  TS  GH  RI  L  "," AL              P.  S.  S.  ,      ","                                 ,  "," AD  RO  N   TO  AN  ST  Y   NE  TO ","  S  52   4          CO  VE  NT  RY " ; 24B3
        .byte   "  C  V6   5  DG                     ","                  -  ns  io  ct  ru "," st  In  ",$04,"P",$04 ; 258B
        .byte   "  -   P  AU  SE   O  N\  OF  F      ","             P    U   -   '         "," T   EF   L   -  ",$04,"Z",$04 ; 25DF
        .byte   " ",$04,"X",$04,"  -   R  IG  HT           /   -   D "," OW  N                   T   AR  ST " ; 263B
        .byte   " O    T  1]   [  SS  RE  ",$0C,"P",$0C,$03," " ; 2687
        .byte   $03,"      ",$12,$12,$12,$17              ; 26A5
        .byte   $12,$12,$12,$12,$17,$12                   ; 26B0
        .byte   $12,$12,$10,$10,$10,$10                   ; 26B6
        .byte   $10,$10,$10,$10,$10,$10                   ; 26BC
        .byte   $10,$10,$10,$10,$10,$10                   ; 26C2

;------------------------------------------------------------------------------
; Direction of each credits hop (2 = down, 3 = left, 4 = right),
; $FF = end.
;------------------------------------------------------------------------------
credits_path:
        .byte   $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04 ; 26C8
        .byte   $04,$04,$04,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03 ; 26D8
        .byte   $03,$03,$03,$03,$03,$02,$02,$04,$04,$04,$04,$04,$04,$04,$04,$04 ; 26E8
        .byte   $04,$04,$04,$04,$02,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03 ; 26F8
        .byte   $02,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$02 ; 2708
        .byte   $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$04,$04,$04 ; 2718
        .byte   $04,$04,$04,$04,$04,$04,$04,$02,$03,$03,$03,$03,$03,$03,$03,$03 ; 2728
        .byte   $03,$03,$03,$03,$03,$03,$02,$04,$04,$04,$04,$04,$04,$04,$04,$04 ; 2738
        .byte   $04,$04,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$04 ; 2748
        .byte   $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$02,$03,$03 ; 2758
        .byte   $03,$03,$03,$03,$03,$03,$03,$03,$03,$FF   ; 2768
        .byte   $7F,$7F,$10,$10,$10,$10                   ; 2772

;------------------------------------------------------------------------------
; CreditsIntro - a frog hops round the screen leaving the credits behind it.
;------------------------------------------------------------------------------
CreditsIntro:
        jsr     ClearScreen             ; 2778
        lda     #$80                    ; 277B
        sta     frog_pos                ; 277D
        lda     #$BB                    ; 277F
        sta     frog_pos+1              ; 2781
        lda     #$00                    ; 2783
        sta     old_pos                 ; 2785
        lda     #$24                    ; 2787
        sta     old_pos+1               ; 2789
        lda     #$00                    ; 278B
        sta     step_size               ; 278D
L278F:
        jsr     CheckMenuKeys           ; 278F
        ldy     step_size               ; 2792
        lda     credits_path,y          ; 2794
        sta     frog_dir                ; 2797
        cmp     #$FF                    ; 2799
        beq     L27C0                   ; 279B
        lda     frog_pos                ; 279D
        sta     key_mask                ; 279F
        lda     frog_pos+1              ; 27A1
        sta     tick_count              ; 27A3
        jsr     CreditsHop              ; 27A5
        jsr     CreditsDrop             ; 27A8
        jsr     CreditsDelay            ; 27AB
        clc                             ; 27AE
        lda     old_pos                 ; 27AF
        adc     #$04                    ; 27B1
        sta     old_pos                 ; 27B3
        lda     old_pos+1               ; 27B5
        adc     #$00                    ; 27B7
        sta     old_pos+1               ; 27B9
        inc     step_size               ; 27BB
        jmp     L278F                   ; 27BD
L27C0:
        jsr     CreditsEnd              ; 27C0
        rts                             ; 27C3

CreditsHop:
        lda     frog_dir                ; 27C4
        cmp     #$02                    ; 27C6
        bne     L27DE                   ; 27C8
        clc                             ; 27CA
        lda     frog_pos                ; 27CB
        adc     #$50                    ; 27CD
        sta     frog_pos                ; 27CF
        lda     frog_pos+1              ; 27D1
        adc     #$00                    ; 27D3
        sta     frog_pos+1              ; 27D5
L27D7:
        jsr     SetFrogGfx              ; 27D7
        jsr     DrawFrog                ; 27DA
        rts                             ; 27DD
L27DE:
        cmp     #$03                    ; 27DE
        bne     L27F2                   ; 27E0
        sec                             ; 27E2
        lda     frog_pos                ; 27E3
        sbc     #$02                    ; 27E5
        sta     frog_pos                ; 27E7
        lda     frog_pos+1              ; 27E9
        sbc     #$00                    ; 27EB
        sta     frog_pos+1              ; 27ED
        jmp     L27D7                   ; 27EF
L27F2:
        clc                             ; 27F2
        lda     frog_pos                ; 27F3
        adc     #$02                    ; 27F5
        sta     frog_pos                ; 27F7
        lda     frog_pos+1              ; 27F9
        adc     #$00                    ; 27FB
        sta     frog_pos+1              ; 27FD
        jmp     L27D7                   ; 27FF

CreditsDrop:
        ldx     #$03                    ; 2802
L2804:
        txa                             ; 2804
        tay                             ; 2805
        lda     (old_pos),y             ; 2806
        ldy     frog_offsets,x          ; 2808
        sta     (key_mask),y            ; 280B
        dex                             ; 280D
        bpl     L2804                   ; 280E
        rts                             ; 2810

CreditsDelay:
        ldx     #$30                    ; 2811
        jmp     DelayXC64               ; 2813  C64: timed wait
L2815 := * - 1                  ; 2815: inside the jmp above
        bne     L2815                   ; 2816
        dex                             ; 2818
        bne     L2815                   ; 2819
        rts                             ; 281B
        .byte   $FF,$7F                                   ; 281C
        .res    15, $7F                 ; 281E
        .res    7, $00                  ; 282D
        .byte   $0A,$00,$00,$06,$0A,$01,$06,$00           ; 2834
        .byte   $00,$06,$0A,$01,$0A,$00,$00,$06           ; 283C
        .byte   $0A,$01,$06,$00,$00,$06,$0A,$01           ; 2844
        .byte   $0B,$00,$00,$06,$0A,$01,$0A,$00           ; 284C
        .byte   $00,$06,$0A,$01,$08,$00,$00,$08           ; 2854
        .byte   $0B,$01,$08,$00,$00,$08,$0B,$01           ; 285C
        .byte   $0B,$00,$00,$08,$0B,$01,$0A,$00           ; 2864
        .byte   $00,$08,$0B,$01,$08,$00,$00,$08           ; 286C
        .byte   $0B,$01,$03,$00,$00,$03,$00,$00           ; 2874
        .byte   $01,$00,$00,$0B,$00,$00,$0A,$00           ; 287C
        .byte   $00,$08,$00,$00,$06,$0A,$01,$55           ; 2884
        .res    28, $02                 ; 288C
        .byte   $06,$02                                   ; 28A8
        .res    34, $02                 ; 28AA
        .res    36, $55                 ; 28CC
        .res    16, $02                 ; 28F0

;------------------------------------------------------------------------------
; TitleScroll - scroll the title bar sideways forever, checking for menu keys.
;------------------------------------------------------------------------------
TitleScroll:
        sei                             ; 2900
        lda     #$C0                    ; 2901
        sta     ROM_CURPTR              ; 2903
        sta     ROM_CURPTR+1            ; 2905
        cli                             ; 2907
L2908:
        lda     SCREEN+0*40+3           ; 2908
        pha                             ; 290B
        lda     SCREEN+1*40+3           ; 290C
        pha                             ; 290F
        lda     #$20                    ; 2910
        sta     SCREEN+0*40+3           ; 2912
        sta     SCREEN+1*40+3           ; 2915
        ldy     #$00                    ; 2918
L291A:
        lda     SCREEN+0*40+4,y         ; 291A
        sta     SCREEN+0*40+3,y         ; 291D
        lda     SCREEN+1*40+4,y         ; 2920
        sta     SCREEN+1*40+3,y         ; 2923
        iny                             ; 2926
        cpy     #$21                    ; 2927
        bne     L291A                   ; 2929
        pla                             ; 292B
        sta     SCREEN+1*40+36          ; 292C
        pla                             ; 292F
        sta     SCREEN+0*40+36          ; 2930
        ldx     #$45                    ; 2933
        jsr     DelayX                  ; 2935
        jsr     TitleTickC64            ; 2938  C64: CheckMenuKeys, then the picture after ~15 s
        jmp     L2908                   ; 293B
        .byte   $FF,$FF                                   ; 293E

;------------------------------------------------------------------------------
; AttractMode - loop: credits screen, wait, hi-score table, wait.
;------------------------------------------------------------------------------
AttractMode:
        sei                             ; 2940
        lda     #$C0                    ; 2941
        sta     ROM_CURPTR              ; 2943
        sta     ROM_CURPTR+1            ; 2945
        cli                             ; 2947
AttractLoop:
        lda     #$00                    ; 2948
        sta     tmp0                    ; 294A
        sta     key_state               ; 294C
        sta     tmp2                    ; 294E
        jsr     ClearScreen             ; 2950
        jsr     CreditsIntroC64         ; 2953  C64: credits rows
L2956:
        jsr     AttractWait             ; 2956  C64: the same ~18 s, timed, CheckMenuKeys polled
        nop                             ; 2959  C64: pad (was the counting loop)
        nop                             ; 295A  C64: pad (was the counting loop)
        nop                             ; 295B  C64: pad (was the counting loop)
        nop                             ; 295C  C64: pad (was the counting loop)
        nop                             ; 295D  C64: pad (was the counting loop)
        nop                             ; 295E  C64: pad (was the counting loop)
        nop                             ; 295F  C64: pad (was the counting loop)
        nop                             ; 2960  C64: pad (was the counting loop)
        nop                             ; 2961  C64: pad (was the counting loop)
        nop                             ; 2962  C64: pad (was the counting loop)
        nop                             ; 2963  C64: pad (was the counting loop)
        nop                             ; 2964  C64: pad (was the counting loop)
        nop                             ; 2965  C64: pad (was the counting loop)
        nop                             ; 2966  C64: pad (was the counting loop)
        nop                             ; 2967  C64: pad (was the counting loop)
        nop                             ; 2968  C64: pad (was the counting loop)
        nop                             ; 2969  C64: pad (was the counting loop)
        nop                             ; 296A  C64: pad (was the counting loop)
HiscoreScreen:                          ; C64: label only (F1 on the picture)
        jsr     ClearScreen             ; 296B
BadTarget_296D := * - 1          ; 296D: target inside instruction above
        jsr     DrawTitleBar            ; 296E
        jsr     HiscoreTableC64         ; 2971  C64: hi-score rows
        jsr     DrawMenuPrompt          ; 2974
        sei                             ; 2977
        lda     #$C0                    ; 2978
        sta     ROM_CURPTR              ; 297A
        sta     ROM_CURPTR+1            ; 297C
        cli                             ; 297E
        lda     #$00                    ; 297F
        sta     tmp0                    ; 2981
        sta     key_state               ; 2983
        sta     tmp2                    ; 2985
L2987:
        inc     tmp0                    ; 2987
        php                             ; 2989
        jsr     CheckMenuKeys           ; 298A
        plp                             ; 298D
        bne     L2987                   ; 298E
        inc     key_state               ; 2990
        bne     L2987                   ; 2992
        inc     tmp2                    ; 2994
        lda     tmp2                    ; 2996
        cmp     #$08                    ; 2998
        bne     L2987                   ; 299A
        jmp     AttractLoop             ; 299C

;------------------------------------------------------------------------------
; CheckMenuKeys - 1 = start a game, 2 = show the instructions again.
;------------------------------------------------------------------------------
CheckMenuKeys:
        jsr     ReadRomKey              ; 299F  C64: draws the screen, then lda ROM_KEY
        beq     L29B9                   ; 29A2
        ldx     #$00                    ; 29A4
        stx     ROM_KEY                 ; 29A6
        and     #$7F                    ; 29A9
        cmp     #$31                    ; 29AB
        bne     L29B2                   ; 29AD
        jmp     StartGame               ; 29AF  '1' -> start a game
L29B2:
        cmp     #$32                    ; 29B2
        bne     L29B9                   ; 29B4
        jmp     AttractLoop             ; 29B6  '2' -> instructions
L29B9:
        rts                             ; 29B9
        .byte   $D0,$03,$4C,$48,$29,$60                   ; 29BA

;------------------------------------------------------------------------------
; UpdateFly - from sheet 3, a fly appears in a random empty home for a while.
;------------------------------------------------------------------------------
UpdateFly:
        lda     sheet                   ; 29C0
        cmp     #$03                    ; 29C3
        bpl     L29C8                   ; 29C5
        rts                             ; 29C7
L29C8:
        lda     fly_on                  ; 29C8
        beq     L29E3                   ; 29CA
        inc     fly_timer               ; 29CC
        lda     fly_timer               ; 29CE
        cmp     #$F0                    ; 29D0
        bne     L2A1A                   ; 29D2
        jsr     EraseFly                ; 29D4
        lda     #$00                    ; 29D7
        sta     fly_on                  ; 29D9
        sta     fly_timer               ; 29DB
        sta     fly_timer+1             ; 29DD
        sta     fly_ptr                 ; 29DF
        sta     fly_ptr+1               ; 29E1
L29E3:
        inc     fly_timer               ; 29E3
        bne     L2A1A                   ; 29E5
        inc     fly_timer+1             ; 29E7
        lda     fly_timer+1             ; 29E9
        cmp     #$01                    ; 29EB
        bne     L2A1A                   ; 29ED
L29EF:
        lda     #$01                    ; 29EF
        sta     fly_on                  ; 29F1
        lda     #$28                    ; 29F3
        jsr     Random8                 ; 29F5
        cmp     #$05                    ; 29F8
        bpl     L29EF                   ; 29FA
        tax                             ; 29FC
        lda     fly_cols,x              ; 29FD
        sta     fly_ptr                 ; 2A00
        lda     #$BB                    ; 2A02
        sta     fly_ptr+1               ; 2A04
        jsr     CheckFlySpot            ; 2A06
        lda     #$7C                    ; 2A09
        ldy     #$00                    ; 2A0B
        sta     (fly_ptr),y             ; 2A0D
        lda     #$7D                    ; 2A0F
        iny                             ; 2A11
        sta     (fly_ptr),y             ; 2A12
        lda     #$00                    ; 2A14
        sta     fly_timer               ; 2A16
        sta     fly_timer+1             ; 2A18
L2A1A:
        rts                             ; 2A1A

EraseFly:
        jmp     EraseFlyC64             ; 2A1B  C64: no fly -> fly_ptr is $0000, see EraseFlyC64
        nop                             ; 2A1E  C64: pad
        nop                             ; 2A1F  C64: pad
        nop                             ; 2A20  C64: pad
        nop                             ; 2A21  C64: pad
        nop                             ; 2A22  C64: pad
        nop                             ; 2A23  C64: pad
        nop                             ; 2A24  C64: pad

CheckFlySpot:
        ldy     #$00                    ; 2A25
        lda     (fly_ptr),y             ; 2A27
        cmp     #$20                    ; 2A29
        bne     L29EF                   ; 2A2B
        iny                             ; 2A2D
        lda     (fly_ptr),y             ; 2A2E
        cmp     #$20                    ; 2A30
        bne     L29EF                   ; 2A32
        rts                             ; 2A34

;------------------------------------------------------------------------------
; CheckFlyEaten - frog entered a home: bonus if the fly was there; die if the home was full.
;------------------------------------------------------------------------------
CheckFlyEaten:
        lda     frog_pos                ; 2A35
        cmp     fly_ptr                 ; 2A37
        bne     L2A55                   ; 2A39
        lda     #$20                    ; 2A3B
        sta     under_frog              ; 2A3D
        sta     under_frog+1            ; 2A40
        jsr     Delay48                 ; 2A43
        nop                             ; 2A46
        nop                             ; 2A47
        nop                             ; 2A48
        nop                             ; 2A49
        nop                             ; 2A4A
        nop                             ; 2A4B
        jsr     FlyBonus                ; 2A4C
        nop                             ; 2A4F
        nop                             ; 2A50
        nop                             ; 2A51
        nop                             ; 2A52
        nop                             ; 2A53
        nop                             ; 2A54
L2A55:
        jsr     EraseFly                ; 2A55
        lda     #$00                    ; 2A58
        sta     fly_on                  ; 2A5A
        sta     fly_timer               ; 2A5C
        sta     fly_timer+1             ; 2A5E
        sta     fly_ptr                 ; 2A60
        sta     fly_ptr+1               ; 2A62
        ldx     #$03                    ; 2A64
L2A66:
        ldy     frog_offsets,x          ; 2A66
        lda     (frog_pos),y            ; 2A69
        cmp     #$20                    ; 2A6B
        bne     L2A74                   ; 2A6D
        dex                             ; 2A6F
        bpl     L2A66                   ; 2A70
        bmi     L2A77                   ; 2A72
L2A74:
        jmp     FrogDies                ; 2A74
L2A77:
        rts                             ; 2A77

;------------------------------------------------------------------------------
; Screen column (low byte, row 0) of each home for the fly.
;------------------------------------------------------------------------------
fly_cols:
        .byte   $AE,$B5,$BC,$C3,$CA                       ; 2A78
        .byte   $9B,$FF,$55                               ; 2A7D

;------------------------------------------------------------------------------
; HomeJingle - tune played when a frog gets home.
;------------------------------------------------------------------------------
HomeJingle:
        lda     #$0A                    ; 2A80
        ldx     #$04                    ; 2A82
        jsr     SoundWrite              ; 2A84
        lda     #$05                    ; 2A87
        ldx     #$01                    ; 2A89
        jsr     SoundWrite              ; 2A8B
        lda     #$00                    ; 2A8E
        sta     tmp0                    ; 2A90
L2A92:
        ldy     tmp0                    ; 2A92
        ldx     jingle_pitches,y        ; 2A94
        lda     #$04                    ; 2A97
        jsr     SoundWrite              ; 2A99
        ldx     #$03                    ; 2A9C
        jsr     DelayX                  ; 2A9E
        inc     tmp0                    ; 2AA1
        lda     tmp0                    ; 2AA3
        cmp     #$20                    ; 2AA5
        bne     L2A92                   ; 2AA7
        lda     #$0A                    ; 2AA9
        ldx     #$00                    ; 2AAB
        jsr     SoundWrite              ; 2AAD
        lda     #$05                    ; 2AB0
        ldx     #$00                    ; 2AB2
        jsr     SoundWrite              ; 2AB4
        rts                             ; 2AB7
        .res    8, $55                  ; 2AB8

;------------------------------------------------------------------------------
; Tone periods for the frog-home jingle.
;------------------------------------------------------------------------------
jingle_pitches:
        .byte   $D0,$D0,$E0,$E0,$EA,$EA,$F0,$F0,$FF,$FF,$F0,$F0,$EA,$EA,$E0,$E0 ; 2AC0
        .byte   $D0,$D0,$C0,$B0,$A0,$90,$80,$70,$60,$50,$40,$30,$20,$10,$00,$02 ; 2AD0
        .byte   $01,$55                                   ; 2AE0
        .res    6, $55                  ; 2AE2

;------------------------------------------------------------------------------
; CreditsEnd - quiet the AY, show the title frog and play the jingle.
;------------------------------------------------------------------------------
CreditsEnd:
        ldx     #$80                    ; 2AE8
        ldy     #$09                    ; 2AEA
        jsr     LoadAYRegs              ; 2AEC
        ldx     #$1F                    ; 2AEF
L2AF1:
        lda     home_gfx,x              ; 2AF1
        sta     CHARSET+$3A*8,x         ; 2AF4
        dex                             ; 2AF7
        bpl     L2AF1                   ; 2AF8
        jsr     HomeJingle              ; 2AFA
        rts                             ; 2AFD
        .byte   $FF,$FF                                   ; 2AFE

;------------------------------------------------------------------------------
; MusicTick - step the in-game background tune.
;------------------------------------------------------------------------------
MusicTick:
        inc     tempo_count             ; 2B00
        lda     tempo_count             ; 2B02
        cmp     tune_tempo              ; 2B04
        bne     L2B4F                   ; 2B06
        lda     #$00                    ; 2B08
        sta     tempo_count             ; 2B0A
        dec     note_time               ; 2B0C
        bpl     L2B4F                   ; 2B0E
        inc     tune_pos                ; 2B10
        inc     tune_pos                ; 2B12
        lda     tune_pos                ; 2B14
        cmp     tune_len                ; 2B16
        beq     PickTune                ; 2B18
        lda     #$0A                    ; 2B1A
        ldx     #$03                    ; 2B1C
        jsr     SoundWrite              ; 2B1E
        ldy     tune_pos                ; 2B21
        lda     (tune_ptr),y            ; 2B23
        sta     note_num                ; 2B25
        iny                             ; 2B27
        lda     (tune_ptr),y            ; 2B28
        nop                             ; 2B2A
        pha                             ; 2B2B
        lsr     a                       ; 2B2C
        lsr     a                       ; 2B2D
        lsr     a                       ; 2B2E
        lsr     a                       ; 2B2F
        sta     note_octave             ; 2B30
        pla                             ; 2B32
        and     #$0F                    ; 2B33
        sta     note_time               ; 2B35
        ldy     note_num                ; 2B37
        beq     L2B7A                   ; 2B39
        dey                             ; 2B3B
        lda     note_periods,y          ; 2B3C
L2B3F:
        dec     note_octave             ; 2B3F
        bmi     L2B47                   ; 2B41
        lsr     a                       ; 2B43
        jmp     L2B3F                   ; 2B44
L2B47:
        sta     note_period             ; 2B47
        tax                             ; 2B49
        lda     #$04                    ; 2B4A
        jsr     SoundWrite              ; 2B4C
L2B4F:
        rts                             ; 2B4F

;------------------------------------------------------------------------------
; PickTune - choose one of the four in-game tunes at random.
;------------------------------------------------------------------------------
PickTune:
        jsr     RandomNext              ; 2B50
        lda     rand_seed+1             ; 2B53
        and     #$03                    ; 2B55
        sta     tmp0                    ; 2B57
        asl     a                       ; 2B59
        tax                             ; 2B5A
        lda     tune_ptrs,x             ; 2B5B
        sta     tune_ptr                ; 2B5E
        lda     tune_ptrs+1,x           ; 2B60
        sta     tune_ptr+1              ; 2B63
        lda     tune_params,x           ; 2B65
        sta     tune_tempo              ; 2B68
        lda     tune_params+1,x         ; 2B6A
        sta     tune_len                ; 2B6D
        lda     #$00                    ; 2B6F
        sta     tune_pos                ; 2B71
        sta     note_octave             ; 2B73
        sta     note_time               ; 2B75
        sta     tempo_count             ; 2B77
        rts                             ; 2B79
L2B7A:
        lda     #$04                    ; 2B7A
        ldx     #$00                    ; 2B7C
        jsr     SoundWrite              ; 2B7E
        rts                             ; 2B81

;------------------------------------------------------------------------------
; PlaySheetTune - play the three-channel tune at sheet_tune.
;------------------------------------------------------------------------------
PlaySheetTune:
        lda     #$00                    ; 2B82
        sta     fly_on                  ; 2B84
        lda     #$30                    ; 2B86
        sta     fly_timer               ; 2B88
        lda     #$00                    ; 2B8A
        sta     tmp0                    ; 2B8C
L2B8E:
        ldy     #$02                    ; 2B8E
L2B90:
        sty     tmp3                    ; 2B90
        lda     (fly_on),y              ; 2B92
        beq     L2BEE                   ; 2B94
        tay                             ; 2B96
        dey                             ; 2B97
        ldx     note_periods,y          ; 2B98
        lda     tmp3                    ; 2B9B
        asl     a                       ; 2B9D
        jsr     SoundWrite              ; 2B9E
        clc                             ; 2BA1
        lda     tmp3                    ; 2BA2
        adc     #$08                    ; 2BA4
        ldx     #$02                    ; 2BA6
        jsr     SoundWrite              ; 2BA8
L2BAB:
        ldy     tmp3                    ; 2BAB
        dey                             ; 2BAD
        bpl     L2B90                   ; 2BAE
        ldy     tmp0                    ; 2BB0
        lda     sheet_tune_lens,y       ; 2BB2
        sta     tmp2                    ; 2BB5
L2BB7:
        ldx     #$15                    ; 2BB7
        jsr     DelayXC64               ; 2BB9  C64: was a DelayX-style loop (X = $15)
L2BBB := * - 1                  ; 2BBB: inside the jsr above (unused now)
        nop                             ; 2BBC  C64: pad
        nop                             ; 2BBD  C64: pad
        nop                             ; 2BBE  C64: pad
        nop                             ; 2BBF  C64: pad
        nop                             ; 2BC0  C64: pad
        dec     tmp2                    ; 2BC1
        bpl     L2BB7                   ; 2BC3
        ldx     #$80                    ; 2BC5
        ldy     #$09                    ; 2BC7
        jsr     LoadAYRegs              ; 2BC9
        ldx     #$02                    ; 2BCC
        stx     tmp2                    ; 2BCE
L2BD0:
        ldx     #$15                    ; 2BD0
        jsr     DelayXC64               ; 2BD2  C64: was a DelayX-style loop (X = $15)
L2BD4 := * - 1                  ; 2BD4: inside the jsr above (unused now)
        nop                             ; 2BD5  C64: pad
        nop                             ; 2BD6  C64: pad
        nop                             ; 2BD7  C64: pad
        nop                             ; 2BD8  C64: pad
        nop                             ; 2BD9  C64: pad
        dec     tmp2                    ; 2BDA
        bpl     L2BD0                   ; 2BDC
        lda     fly_on                  ; 2BDE
        clc                             ; 2BE0
        adc     #$03                    ; 2BE1
        sta     fly_on                  ; 2BE3
        inc     tmp0                    ; 2BE5
        lda     tmp0                    ; 2BE7
        cmp     #$1D                    ; 2BE9
        bne     L2B8E                   ; 2BEB
        rts                             ; 2BED
L2BEE:
        tya                             ; 2BEE
        clc                             ; 2BEF
        adc     #$08                    ; 2BF0
        ldx     #$00                    ; 2BF2
        jsr     SoundWrite              ; 2BF4
        jmp     L2BAB                   ; 2BF7
        .byte   $FF,$55                                   ; 2BFA
        .res    4, $55                  ; 2BFC

;------------------------------------------------------------------------------
; In-game tune 0: pairs of (note 1-12 or 0 = rest, octave<<4 | length).
; MusicTick advances before reading, so the first pair is never played.
;------------------------------------------------------------------------------
tune0:
        .byte   $FF,$FF                                   ; 2C00
        .byte   $0A,$02                                   ; 2C02
        .byte   $00,$02                                   ; 2C04
        .byte   $0A,$02                                   ; 2C06
        .byte   $00,$02                                   ; 2C08
        .byte   $0C,$02                                   ; 2C0A
        .byte   $00,$02                                   ; 2C0C
        .byte   $02,$12                                   ; 2C0E
        .byte   $00,$02                                   ; 2C10
        .byte   $0A,$02                                   ; 2C12
        .byte   $00,$02                                   ; 2C14
        .byte   $02,$12                                   ; 2C16
        .byte   $00,$02                                   ; 2C18
        .byte   $0C,$02                                   ; 2C1A
        .byte   $00,$02                                   ; 2C1C
        .byte   $05,$02                                   ; 2C1E
        .byte   $00,$02                                   ; 2C20
        .byte   $0A,$02                                   ; 2C22
        .byte   $00,$02                                   ; 2C24
        .byte   $0A,$02                                   ; 2C26
        .byte   $00,$02                                   ; 2C28
        .byte   $0C,$02                                   ; 2C2A
        .byte   $00,$02                                   ; 2C2C
        .byte   $02,$12                                   ; 2C2E
        .byte   $00,$02                                   ; 2C30
        .byte   $0A,$06                                   ; 2C32
        .byte   $00,$02                                   ; 2C34
        .byte   $09,$06                                   ; 2C36
        .byte   $00,$02                                   ; 2C38
        .byte   $0A,$02                                   ; 2C3A
        .byte   $00,$02                                   ; 2C3C
        .byte   $0A,$02                                   ; 2C3E
        .byte   $00,$02                                   ; 2C40
        .byte   $0C,$02                                   ; 2C42
        .byte   $00,$02                                   ; 2C44
        .byte   $02,$12                                   ; 2C46
        .byte   $00,$02                                   ; 2C48
        .byte   $04,$12                                   ; 2C4A
        .byte   $00,$02                                   ; 2C4C
        .byte   $02,$12                                   ; 2C4E
        .byte   $00,$02                                   ; 2C50
        .byte   $0C,$02                                   ; 2C52
        .byte   $00,$02                                   ; 2C54
        .byte   $0A,$02                                   ; 2C56
        .byte   $00,$02                                   ; 2C58
        .byte   $09,$02                                   ; 2C5A
        .byte   $00,$02                                   ; 2C5C
        .byte   $05,$02                                   ; 2C5E
        .byte   $00,$02                                   ; 2C60
        .byte   $07,$02                                   ; 2C62
        .byte   $00,$02                                   ; 2C64
        .byte   $09,$02                                   ; 2C66
        .byte   $00,$02                                   ; 2C68
        .byte   $0A,$06                                   ; 2C6A
        .byte   $00,$02                                   ; 2C6C
        .byte   $0A,$06                                   ; 2C6E
        .byte   $00,$0F                                   ; 2C70
        .byte   $00,$0F                                   ; 2C72
        .res    12, $FF                 ; 2C74

;------------------------------------------------------------------------------
; In-game tune 1.
;------------------------------------------------------------------------------
tune1:
        .byte   $FF,$FF                                   ; 2C80
        .byte   $0A,$02                                   ; 2C82
        .byte   $00,$02                                   ; 2C84
        .byte   $0A,$02                                   ; 2C86
        .byte   $00,$02                                   ; 2C88
        .byte   $0A,$02                                   ; 2C8A
        .byte   $00,$02                                   ; 2C8C
        .byte   $03,$18                                   ; 2C8E
        .byte   $00,$02                                   ; 2C90
        .byte   $03,$18                                   ; 2C92
        .byte   $00,$02                                   ; 2C94
        .byte   $05,$18                                   ; 2C96
        .byte   $00,$02                                   ; 2C98
        .byte   $05,$18                                   ; 2C9A
        .byte   $00,$02                                   ; 2C9C
        .byte   $0A,$1E                                   ; 2C9E
        .byte   $00,$02                                   ; 2CA0
        .byte   $07,$12                                   ; 2CA2
        .byte   $00,$02                                   ; 2CA4
        .byte   $03,$12                                   ; 2CA6
        .byte   $00,$02                                   ; 2CA8
        .byte   $03,$12                                   ; 2CAA
        .byte   $00,$02                                   ; 2CAC
        .byte   $07,$14                                   ; 2CAE
        .byte   $00,$02                                   ; 2CB0
        .byte   $03,$12                                   ; 2CB2
        .byte   $00,$02                                   ; 2CB4
        .byte   $0C,$08                                   ; 2CB6
        .byte   $00,$02                                   ; 2CB8
        .byte   $08,$1F                                   ; 2CBA
        .byte   $08,$13                                   ; 2CBC
        .byte   $00,$02                                   ; 2CBE
        .byte   $08,$13                                   ; 2CC0
        .byte   $00,$02                                   ; 2CC2
        .byte   $05,$14                                   ; 2CC4
        .byte   $00,$02                                   ; 2CC6
        .byte   $01,$12                                   ; 2CC8
        .byte   $00,$02                                   ; 2CCA
        .byte   $03,$1F                                   ; 2CCC
        .byte   $03,$11                                   ; 2CCE
        .byte   $00,$0F                                   ; 2CD0
        .byte   $00,$0F                                   ; 2CD2
        .byte   $00,$04,$FF                               ; 2CD4
        .res    10, $FF                 ; 2CD7
        .res    31, $55                 ; 2CE1

;------------------------------------------------------------------------------
; Sound selection screen (double-height lines, $00 = end).
;------------------------------------------------------------------------------
sound_menu_text:
        .byte   $0E,$01," PRESS",$02,$0A,"[1] "           ; 2D00
        .byte   $03,"FOR NO SOUND ",$0D                   ; 2D0E
        .byte   $0E," ",$01,"PRESS",$0A,$02               ; 2D1D
        .byte   "[1]",$03," FOR NO SOUND ",$0D            ; 2D27
        .byte   $0A,"        ",$05,"[2] ",$06,"FOR QUIET SOUND " ; 2D3A
        .byte   $0D                                       ; 2D59
        .byte   $0A,"        ",$05,"[2]",$06," FOR QUIET SOUND " ; 2D5A
        .byte   $0D                                       ; 2D79
        .byte   $0A,"       ",$02," [3] ",$01,"FOR LOUD SOUND " ; 2D7A
        .byte   $0D                                       ; 2D98
        .byte   $0A,"     ",$02,"   [3] ",$01,"FOR LOUD SOUND " ; 2D99
        .byte   $0D                                       ; 2DB7
        .byte   $0D                                       ; 2DB8
        .byte   $00                                       ; 2DB9
        .byte   $FF,$55,$55,$55                           ; 2DBA

;------------------------------------------------------------------------------
; In-game tune 2.
;------------------------------------------------------------------------------
tune2:
        .byte   $FF,$FF                                   ; 2DBE
        .byte   $0A,$02                                   ; 2DC0
        .byte   $00,$02                                   ; 2DC2
        .byte   $07,$0C                                   ; 2DC4
        .byte   $00,$04                                   ; 2DC6
        .byte   $07,$02                                   ; 2DC8
        .byte   $00,$02                                   ; 2DCA
        .byte   $08,$02                                   ; 2DCC
        .byte   $00,$02                                   ; 2DCE
        .byte   $0A,$02                                   ; 2DD0
        .byte   $00,$02                                   ; 2DD2
        .byte   $07,$14                                   ; 2DD4
        .byte   $00,$04                                   ; 2DD6
        .byte   $07,$14                                   ; 2DD8
        .byte   $00,$04                                   ; 2DDA
        .byte   $03,$18                                   ; 2DDC
        .byte   $00,$08                                   ; 2DDE
        .byte   $0A,$02                                   ; 2DE0
        .byte   $00,$02                                   ; 2DE2
        .byte   $07,$0C                                   ; 2DE4
        .byte   $00,$02                                   ; 2DE6
        .byte   $07,$02                                   ; 2DE8
        .byte   $00,$02                                   ; 2DEA
        .byte   $08,$02                                   ; 2DEC
        .byte   $00,$02                                   ; 2DEE
        .byte   $07,$02                                   ; 2DF0
        .byte   $00,$02                                   ; 2DF2
        .byte   $0A,$04                                   ; 2DF4
        .byte   $00,$04                                   ; 2DF6
        .byte   $0A,$04                                   ; 2DF8
        .byte   $00,$04                                   ; 2DFA
        .byte   $08,$08                                   ; 2DFC
        .byte   $00,$08                                   ; 2DFE
        .byte   $08,$02                                   ; 2E00
        .byte   $00,$02                                   ; 2E02
        .byte   $05,$0C                                   ; 2E04
        .byte   $00,$04                                   ; 2E06
        .byte   $05,$02                                   ; 2E08
        .byte   $00,$02                                   ; 2E0A
        .byte   $07,$02                                   ; 2E0C
        .byte   $00,$02                                   ; 2E0E
        .byte   $08,$02                                   ; 2E10
        .byte   $00,$02                                   ; 2E12
        .byte   $0A,$02                                   ; 2E14
        .byte   $00,$02                                   ; 2E16
        .byte   $07,$0C                                   ; 2E18
        .byte   $00,$04                                   ; 2E1A
        .byte   $07,$02                                   ; 2E1C
        .byte   $00,$02                                   ; 2E1E
        .byte   $09,$02                                   ; 2E20
        .byte   $00,$02                                   ; 2E22
        .byte   $07,$02                                   ; 2E24
        .byte   $00,$02                                   ; 2E26
        .byte   $05,$02                                   ; 2E28
        .byte   $00,$02                                   ; 2E2A
        .byte   $0A,$04                                   ; 2E2C
        .byte   $00,$04                                   ; 2E2E
        .byte   $07,$02                                   ; 2E30
        .byte   $00,$02                                   ; 2E32
        .byte   $09,$02                                   ; 2E34
        .byte   $00,$02                                   ; 2E36
        .byte   $05,$04                                   ; 2E38
        .byte   $00,$04                                   ; 2E3A
        .byte   $0C,$02                                   ; 2E3C
        .byte   $00,$02                                   ; 2E3E
        .byte   $0A,$0D                                   ; 2E40
        .byte   $0A,$0D                                   ; 2E42
        .byte   $00,$04                                   ; 2E44
        .byte   $00,$0A                                   ; 2E46
        .byte   $09,$12,$00,$02,$0A,$18,$00,$02           ; 2E48
        .byte   $08,$14,$00,$02,$07,$12,$00,$02           ; 2E50
        .byte   $05,$18,$00,$02,$05,$14,$00,$02           ; 2E58
        .byte   $05,$12,$00,$02,$03,$1E,$00,$04           ; 2E60
        .byte   $00,$0F,$FF                               ; 2E68
        .res    21, $FF                 ; 2E6B

;------------------------------------------------------------------------------
; In-game tune 3.
;------------------------------------------------------------------------------
tune3:
        .byte   $0A,$12                                   ; 2E80
        .byte   $00,$02                                   ; 2E82
        .byte   $0C,$02                                   ; 2E84
        .byte   $00,$02                                   ; 2E86
        .byte   $03,$12                                   ; 2E88
        .byte   $00,$02                                   ; 2E8A
        .byte   $02,$12                                   ; 2E8C
        .byte   $00,$02                                   ; 2E8E
        .byte   $0C,$02                                   ; 2E90
        .byte   $00,$02                                   ; 2E92
        .byte   $05,$16                                   ; 2E94
        .byte   $00,$02                                   ; 2E96
        .byte   $05,$16                                   ; 2E98
        .byte   $00,$02                                   ; 2E9A
        .byte   $05,$12                                   ; 2E9C
        .byte   $00,$02                                   ; 2E9E
        .byte   $07,$12                                   ; 2EA0
        .byte   $00,$02                                   ; 2EA2
        .byte   $02,$12                                   ; 2EA4
        .byte   $00,$02                                   ; 2EA6
        .byte   $03,$12                                   ; 2EA8
        .byte   $00,$02                                   ; 2EAA
        .byte   $0C,$06                                   ; 2EAC
        .byte   $00,$02                                   ; 2EAE
        .byte   $0C,$06                                   ; 2EB0
        .byte   $00,$02                                   ; 2EB2
        .byte   $0C,$02                                   ; 2EB4
        .byte   $00,$02                                   ; 2EB6
        .byte   $03,$12                                   ; 2EB8
        .byte   $00,$02                                   ; 2EBA
        .byte   $02,$12                                   ; 2EBC
        .byte   $00,$02                                   ; 2EBE
        .byte   $0C,$02                                   ; 2EC0
        .byte   $00,$02                                   ; 2EC2
        .byte   $0A,$02                                   ; 2EC4
        .byte   $00,$02                                   ; 2EC6
        .byte   $0A,$12                                   ; 2EC8
        .byte   $00,$02                                   ; 2ECA
        .byte   $09,$12                                   ; 2ECC
        .byte   $00,$02                                   ; 2ECE
        .byte   $07,$12                                   ; 2ED0
        .byte   $00,$02                                   ; 2ED2
        .byte   $05,$12                                   ; 2ED4
        .byte   $00,$02                                   ; 2ED6
        .byte   $03,$12                                   ; 2ED8
        .byte   $00,$02                                   ; 2EDA
        .byte   $0C,$02                                   ; 2EDC
        .byte   $00,$02                                   ; 2EDE
        .byte   $0A,$12                                   ; 2EE0
        .byte   $00,$02                                   ; 2EE2
        .byte   $0C,$02                                   ; 2EE4
        .byte   $00,$02                                   ; 2EE6
        .byte   $03,$12                                   ; 2EE8
        .byte   $00,$02                                   ; 2EEA
        .byte   $02,$12                                   ; 2EEC
        .byte   $00,$02                                   ; 2EEE
        .byte   $0C,$02                                   ; 2EF0
        .byte   $00,$02                                   ; 2EF2
        .byte   $05,$16                                   ; 2EF4
        .byte   $00,$02                                   ; 2EF6
        .byte   $05,$16                                   ; 2EF8
        .byte   $00,$02                                   ; 2EFA
        .byte   $05,$12                                   ; 2EFC
        .byte   $00,$02                                   ; 2EFE
        .byte   $07,$12                                   ; 2F00
        .byte   $00,$02                                   ; 2F02
        .byte   $02,$12                                   ; 2F04
        .byte   $00,$02                                   ; 2F06
        .byte   $03,$12                                   ; 2F08
        .byte   $00,$02                                   ; 2F0A
        .byte   $0C,$06                                   ; 2F0C
        .byte   $00,$02                                   ; 2F0E
        .byte   $0C,$06                                   ; 2F10
        .byte   $00,$02                                   ; 2F12
        .byte   $0C,$02                                   ; 2F14
        .byte   $00,$02                                   ; 2F16
        .byte   $03,$12                                   ; 2F18
        .byte   $00,$02                                   ; 2F1A
        .byte   $02,$12                                   ; 2F1C
        .byte   $00,$02                                   ; 2F1E
        .byte   $0C,$02                                   ; 2F20
        .byte   $00,$02                                   ; 2F22
        .byte   $0A,$1F                                   ; 2F24
        .byte   $0A,$11                                   ; 2F26
        .byte   $00,$0F                                   ; 2F28
        .res    6, $55                  ; 2F2A

;------------------------------------------------------------------------------
; ControlsMenu - choose a key set and patch the key tables and the instructions.
;------------------------------------------------------------------------------
ControlsMenu:
        ldx     #$00                    ; 2F30
        ldy     #$00                    ; 2F32
        lda     #$08                    ; 2F34
        sta     tmp0                    ; 2F36
        lda     #$BE                    ; 2F38
        sta     key_state               ; 2F3A
L2F3C:
        lda     controls_text,x         ; 2F3C
        cmp     #$0D                    ; 2F3F
        bne     L2F55                   ; 2F41
        ldy     #$00                    ; 2F43
        clc                             ; 2F45
        lda     tmp0                    ; 2F46
        adc     #$28                    ; 2F48
        sta     tmp0                    ; 2F4A
        lda     key_state               ; 2F4C
        adc     #$00                    ; 2F4E
        sta     key_state               ; 2F50
        jmp     L2F5C                   ; 2F52
L2F55:
        cmp     #$FF                    ; 2F55
        beq     L2F60                   ; 2F57
        sta     (tmp0),y                ; 2F59
        iny                             ; 2F5B
L2F5C:
        inx                             ; 2F5C
        jmp     L2F3C                   ; 2F5D
L2F60:
        cli                             ; 2F60
L2F61:
ControlsWaitKey:                        ; C64: RedefineKeys returns here
        jsr     ReadMenuKey             ; 2F61  C64: draws (and parses) the screen, then lda ROM_KEY
        beq     L2F61                   ; 2F64
        ldx     #$00                    ; 2F66
        stx     ROM_KEY                 ; 2F68
        and     #$7F                    ; 2F6B
        cmp     #$31                    ; 2F6D
        bne     L2F91                   ; 2F6F
        ldx     #$0E                    ; 2F71
L2F73:
        lda     keys_set1,x             ; 2F73
        sta     key_rows,x              ; 2F76
        dex                             ; 2F79
        bpl     L2F73                   ; 2F7A
        lda     #$5A                    ; 2F7C
        sta     credits_text+569        ; 2F7E
        lda     #$58                    ; 2F81
        sta     credits_text+573        ; 2F83
        lda     #'K'                    ; 2F86  C64: up is K
        sta     credits_text+541        ; 2F88
        lda     #'M'                    ; 2F8B  C64: down is M
        sta     credits_text+601        ; 2F8D
        rts                             ; 2F90
L2F91:
        jsr     RedefineKeys            ; 2F91  C64: '2' = redefine (else back to L2F61)
        nop                             ; 2F94
        ldx     #$0E                    ; 2F95
L2F97:
        lda     keys_set2,x             ; 2F97
        sta     key_rows,x              ; 2F9A
        dex                             ; 2F9D
        bpl     L2F97                   ; 2F9E
        key_name_left := *+1            ; C64: RedefineKeys sets these four names
        lda     #$2C                    ; 2FA0
        sta     credits_text+569        ; 2FA2
        key_name_right := *+1
        lda     #$2E                    ; 2FA5
        sta     credits_text+573        ; 2FA7
        key_name_up := *+1
        lda     #$41                    ; 2FAA
        sta     credits_text+541        ; 2FAC
        key_name_down := *+1
        lda     #$5A                    ; 2FAF
        sta     credits_text+601        ; 2FB1
        rts                             ; 2FB4
        .byte   $FF,$55                                   ; 2FB5
        .res    32, $55                 ; 2FB7

;------------------------------------------------------------------------------
; Copy of the status line, kept while the screen is redrawn.
;------------------------------------------------------------------------------
status_save:
        .byte   "SCORE      00",$01,"TIME 99",$04,"LIVES 5",$05 ; 2FD7
        .byte   "SHEET  1",$00                            ; 2FF5
        .byte   $55,$55                                   ; 2FFE

;------------------------------------------------------------------------------
; Tune played at the start of each sheet: 29 steps x 3 channels.
;------------------------------------------------------------------------------
sheet_tune:
        .byte   $0A,$00,$00                               ; 3000
        .byte   $06,$0A,$01                               ; 3003
        .byte   $06,$00,$00                               ; 3006
        .byte   $06,$0A,$01                               ; 3009
        .byte   $0A,$00,$00                               ; 300C
        .byte   $06,$0A,$01                               ; 300F
        .byte   $06,$00,$00                               ; 3012
        .byte   $06,$0A,$01                               ; 3015
        .byte   $0B,$00,$00                               ; 3018
        .byte   $06,$0A,$01                               ; 301B
        .byte   $0A,$00,$00                               ; 301E
        .byte   $06,$0A,$01                               ; 3021
        .byte   $08,$00,$00                               ; 3024
        .byte   $08,$0B,$01                               ; 3027
        .byte   $08,$00,$00                               ; 302A
        .byte   $08,$0B,$01                               ; 302D
        .byte   $0B,$00,$00                               ; 3030
        .byte   $08,$0B,$01                               ; 3033
        .byte   $0A,$00,$00                               ; 3036
        .byte   $08,$0B,$01                               ; 3039
        .byte   $08,$00,$00                               ; 303C
        .byte   $08,$0B,$01                               ; 303F
        .byte   $03,$00,$00                               ; 3042
        .byte   $03,$00,$00                               ; 3045
        .byte   $01,$00,$00                               ; 3048
        .byte   $0B,$00,$00                               ; 304B
        .byte   $0A,$00,$00                               ; 304E
        .byte   $08,$00,$00                               ; 3051
        .byte   $06,$0A,$01                               ; 3054
        .byte   $55                                       ; 3057

;------------------------------------------------------------------------------
; Length of each sheet-tune step.
;------------------------------------------------------------------------------
sheet_tune_lens:
        .byte   $02,$02,$02,$02,$02,$02,$02,$02           ; 3058
        .byte   $02,$02,$02,$02,$02,$02,$02,$02           ; 3060
        .byte   $02,$02,$02,$02,$02,$02,$02,$02           ; 3068
        .byte   $02,$02,$02,$02,$08                       ; 3070
        .byte   $04,$04,$02                               ; 3075
        .res    8, $02                  ; 3078
        .byte   $20,$FF,$FF,$FF,$FF                       ; 3080

;------------------------------------------------------------------------------
; MarkSoundChoice - highlight the chosen sound option on the menu screen.
;------------------------------------------------------------------------------
MarkSoundChoice:
        lda     #$0A                    ; 3085
        sta     SCREEN+2*40+0           ; 3087
        sta     SCREEN+3*40+0           ; 308A
        lda     #$0E                    ; 308D
        ldx     sound_mode              ; 308F
        bne     L309A                   ; 3091
        sta     SCREEN+2*40+13          ; 3093
        sta     SCREEN+3*40+14          ; 3096
        rts                             ; 3099
L309A:
        cpx     #$01                    ; 309A
        bne     L30A5                   ; 309C
        sta     SCREEN+4*40+13          ; 309E
        sta     SCREEN+5*40+14          ; 30A1
        rts                             ; 30A4
L30A5:
        sta     SCREEN+6*40+13          ; 30A5
        sta     SCREEN+7*40+13          ; 30A8
        rts                             ; 30AB
        .res    5, $55                  ; 30AC
        .byte   $FC,$55                                   ; 30B1
        .res    34, $55                 ; 30B3

PROG_END:
