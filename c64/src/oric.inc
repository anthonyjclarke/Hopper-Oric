;==============================================================================
; oric.inc - Oric-1 hardware and memory map used by HOPPER (C64 port)
;
; C64: a copy of src/oric.inc with two changes, marked C64. The VIA addresses
; stay: the game still writes to them, which on the C64 is harmless RAM
; ($0300-$030F, BASIC/KERNAL vectors, unused with the ROMs banked out).
;==============================================================================

; --- 6522 VIA at $0300 -------------------------------------------------------
; Port B: bits 0-2 keyboard row select, bit 3 key-pressed sense, bit 4 printer
;         strobe, bit 7 tape out.  Port A: printer data / AY-3-8912 data bus.
; CA2/CB2 drive the AY BC1/BDIR lines (via PCR) to latch register / write data.
VIA_ORB         = $0300         ; port B data
VIA_ORA         = $0301         ; port A data (with handshake)
VIA_DDRB        = $0302         ; port B data direction
VIA_DDRA        = $0303         ; port A data direction
VIA_T1CL        = $0304         ; timer 1 counter low
VIA_T1CH        = $0305         ; timer 1 counter high
VIA_T1LL        = $0306         ; timer 1 latch low
VIA_T1LH        = $0307         ; timer 1 latch high
VIA_T2CL        = $0308         ; timer 2 counter low
VIA_T2CH        = $0309         ; timer 2 counter high
VIA_SR          = $030A         ; shift register
VIA_ACR         = $030B         ; auxiliary control
VIA_PCR         = $030C         ; peripheral control (AY BC1/BDIR on CA2/CB2)
VIA_IFR         = $030D         ; interrupt flags
VIA_IER         = $030E         ; interrupt enable
VIA_ORA_NH      = $030F         ; port A data, no handshake

; --- Oric-1 ROM (v1.0) page-2 system variables --------------------------------
NMI_VECTOR      = $022B         ; Oric-1: NMI (RESET button) jumps via JMP here

; --- Video memory (TEXT mode) ---------------------------------------------
CHARSET         = $B000         ; C64: $B400 on the Oric; the VIC needs 2K alignment
ALTCHARS        = $B800         ; alternate character set (unused; HISCORES lives here)
SCREEN          = $BB80         ; 40 x 28 text screen
SCREEN_COLS     = 40

; --- C64: glyph width ------------------------------------------------------------
; Oric characters are 6 pixels wide, C64 characters 8. W6 widens one glyph
; row by doubling its two middle pixels (abcdef -> abccddef), so edges that
; join to the next character keep their one-pixel width.
.define W6(v) (((((v) & $38) << 2) | (((v) & $0C) << 1) | ((v) & $07)) & $FF)
