;==============================================================================
; hw.inc - C64 hardware registers and the port's memory layout
;==============================================================================

; --- 6510 port ----------------------------------------------------------------
CPU_PORT        = $01
MEM_IO_ONLY     = $35           ; RAM everywhere except I/O at $D000 (no BASIC/KERNAL)
MEM_CHARROM     = $33           ; character ROM at $D000 (to copy the font)

; --- hardware vectors (RAM under the KERNAL) ---------------------------------
VEC_NMI         = $FFFA
VEC_RESET       = $FFFC
VEC_IRQ         = $FFFE

; --- VIC-II -------------------------------------------------------------------
VIC_CTRL1       = $D011
VIC_RASTER      = $D012
VIC_SPR_ENA     = $D015
VIC_CTRL2       = $D016
VIC_MEMSETUP    = $D018
VIC_IRQ_FLAG    = $D019
VIC_IRQ_MASK    = $D01A
VIC_BORDER      = $D020
VIC_BG0         = $D021
VIC_BG1         = $D022         ; multicolour: shade (Enhanced)
VIC_BG2         = $D023         ; multicolour: highlight (Enhanced)

; --- CIA ----------------------------------------------------------------------
CIA1_PRA        = $DC00         ; keyboard column select (write) / joystick 2 (read)
CIA1_PRB        = $DC01         ; keyboard row read / joystick 1
CIA1_DDRA       = $DC02
CIA1_DDRB       = $DC03
CIA1_ICR        = $DC0D
CIA2_PRA        = $DD00         ; bits 0-1: VIC bank, inverted
CIA2_DDRA       = $DD02
CIA2_TALO       = $DD04
CIA2_TAHI       = $DD05
CIA2_TBLO       = $DD06
CIA2_TBHI       = $DD07
CIA2_ICR        = $DD0D
CIA2_CRA        = $DD0E
CIA2_CRB        = $DD0F

; --- SID ----------------------------------------------------------------------
SID             = $D400         ; voice n at SID + 7n: freq lo/hi, pw lo/hi, ctrl, AD, SR
SID_VOLUME      = $D418

; --- memory layout --------------------------------------------------------------
; The game keeps its Oric addresses: code $0500-$30D4, page-4 variables,
; font save $3100-$33FF, hi-scores $BA00, the Oric screen at $BB80. The
; platform code sits from $3400. The VIC uses bank 2 ($8000-$BFFF), so it
; can see the game's character set at CHARSET ($B000) directly.
GAME_START      = $0500
VIC_BANK_BITS   = %01           ; $DD00 bits 0-1 for bank 2
VIC_SCREEN      = $8000         ; what the VIC shows: 40x25 codes, from Present
CHARSET_DHTOP   = $A000         ; double-height top halves (+ inverse)
CHARSET_DHBOT   = $A800         ; double-height bottom halves (+ inverse)
CHARSET_MC      = $8800         ; Enhanced: multicolour lane glyphs (enhanced.s); not $9000-$9FFF,
                                ; where the VIC sees the character ROM
COLOUR_RAM      = $D800

; $D018: screen at bank + 0, character set per row
D018_NORMAL     = ((VIC_SCREEN - $8000) / $400) << 4 | ((CHARSET - $8000) / $800) << 1
D018_DHTOP      = ((VIC_SCREEN - $8000) / $400) << 4 | ((CHARSET_DHTOP - $8000) / $800) << 1
D018_DHBOT      = ((VIC_SCREEN - $8000) / $400) << 4 | ((CHARSET_DHBOT - $8000) / $800) << 1
D018_MC         = ((VIC_SCREEN - $8000) / $400) << 4 | ((CHARSET_MC - $8000) / $800) << 1

ORIC_ROWS       = 28
C64_ROWS        = 25
COLS            = 40

; Character set for each row (index into D018 table)
CS_NORMAL       = 0
CS_DHTOP        = 1
CS_DHBOT        = 2
CS_MC           = 3             ; Enhanced lane rows

; Raster: first text line of row 0 (25 rows, YSCROLL = 3)
FIRST_TEXT_LINE = 51
FRAME_IRQ_LINE  = 251           ; bottom border

; C64 colours
COL_BLACK       = 0
COL_WHITE       = 1
COL_RED         = 2
COL_CYAN        = 3
COL_PURPLE      = 4
COL_GREEN       = 5
COL_BLUE        = 6
COL_YELLOW      = 7
COL_ORANGE      = 8
COL_BROWN       = 9
COL_LRED        = 10
COL_DGREY       = 11
COL_GREY        = 12
COL_LGREEN      = 13
COL_LBLUE       = 14
COL_LGREY       = 15
