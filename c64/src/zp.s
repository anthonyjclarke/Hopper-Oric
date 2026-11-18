;==============================================================================
; zp.s - the platform's zero page ($60-$CF; the game uses $02-$5C, $D0-$D3,
; $FF at their Oric addresses). Declared in c64.inc.
;==============================================================================

        .exportzp zTmp0, zTmp1, zTmp2, zPtr, zSrc, zDst, zCol
        .exportzp zTick, zIsPAL, zRomIrq, zBlink, zIdleTick
        .exportzp zNow, zDeadline, zWait, zDebt, zLastPresent, zT2Dl, zWaitHook
        .exportzp zRow, zInk, zPaper, zMode, zRowBg, zComplex, zRowDH, zFg, zBg, zGlyph
        .exportzp zRR, zNeedRefresh, zLastKey, zJoyIdle

        .segment "ZEROPAGE"
zTmp0:          .res 1
zTmp1:          .res 1
zTmp2:          .res 1
zPtr:           .res 2
zSrc:           .res 2          ; video: Oric row
zDst:           .res 2          ; video: VIC row
zCol:           .res 2          ; video: colour RAM row
zTick:          .res 1          ; frames, from the raster IRQ
zIsPAL:         .res 1          ; 1 = PAL, 0 = NTSC
zRomIrq:        .res 1          ; 1 while the Oric code has its ROM IRQ on
zBlink:         .res 1          ; blink phase: 1 = blinking cells hidden
zIdleTick:      .res 1          ; zTick at the last Idle Present
zNow:           .res 3          ; ReadClock
zDeadline:      .res 3          ; WaitCycles
zWait:          .res 3
zDebt:          .res 2          ; overrun carried into the next wait
zLastPresent:   .res 3
zT2Dl:          .res 3          ; VIA timer 2 runs out at this clock
zWaitHook:      .res 1          ; what WaitCycles calls meanwhile (HOOK_*)
zRow:           .res 1          ; ParseRow state
zInk:           .res 1
zPaper:         .res 1
zMode:          .res 1
zRowBg:         .res 1
zComplex:       .res 1
zRowDH:         .res 1
zFg:            .res 1
zBg:            .res 1
zGlyph:         .res 1
zRR:            .res 1          ; ParseNextRow's row
zNeedRefresh:   .res 1          ; a row turned double height
zLastKey:       .res 1          ; ScanRomKey edge detection
zJoyIdle:       .res 1

