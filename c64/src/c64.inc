;==============================================================================
; c64.inc - shared declarations for the platform modules
;==============================================================================

        .include "oric.inc"
        .include "vars.inc"
        .include "hw.inc"

; --- platform zero page ($60-$CF; the game uses $02-$5C, $D0-$D3, $FF) --------
        .importzp zTmp0, zTmp1, zTmp2, zPtr
        .importzp zSrc, zDst, zCol
        .importzp zTick, zIsPAL, zRomIrq, zBlink, zIdleTick
        .importzp zNow, zDeadline, zWait, zDebt, zLastPresent, zT2Dl, zWaitHook
        .importzp zRow, zInk, zPaper, zMode, zRowBg, zComplex, zRowDH, zFg, zBg, zGlyph
        .importzp zRR, zNeedRefresh, zLastKey, zJoyIdle, zEnhanced

; --- what WaitCycles calls while it waits (zWaitHook)
HOOK_NONE       = 0
HOOK_SERVICE    = 1             ; ServiceTimer: FrameDelay
HOOK_MENUKEYS   = 2             ; CheckMenuKeys: AttractWait

; --- row maps (SetRowMap argument) ----------------------------------------------
MAP_MENU        = 0
MAP_CREDITS     = 1
MAP_HISCORE     = 2
MAP_GAME        = 3

; --- keys ScanRomKey reports beyond the Oric's ASCII (ROM_KEY = code + $80)
KEY_F1          = $01           ; flips Classic / Enhanced on the home screen

; --- Oric timings in C64 cycles (one C64 cycle is treated as one Oric
; microsecond; PAL runs 1.5% slow, NTSC 2.3% fast, as the code itself does)
DELAYX_UNIT     = 1286          ; one DelayX count: 256 x (dey, bne) + dex, bne
FRAMEDELAY_UNIT = 1823          ; one FrameDelay count: 256 x (nop, dey, bne) + ServiceTimer
T2_PERIOD       = $606B         ; timer2_reload: the game's time base
PRESENT_GAP     = 19000         ; at most one Present per frame inside waits
PARSE_COST      = 4000          ; time a ParseRow needs, for idle-time parsing
MAX_DEBT        = 40000         ; overrun carried into the next wait, at most
IDLE_TICKS      = 4             ; key-wait loops draw every 4th frame
TITLE_STEPS     = 170           ; hi-score title scroll steps before the picture (~15 s)
