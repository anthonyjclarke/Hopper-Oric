;==============================================================================
; sound.s - the AY-3-8912's registers played on the SID
;
; The game writes AY registers through AYWrite (and LoadAYRegs, SoundWrite on
; top of it), so the SID is driven from the same register writes:
;
;   AY                                  SID
;   R0-R5  tone period, channels A-C    voices 1-3 frequency
;   R6     noise period                 frequency of a voice playing noise
;   R7     mixer (tone / noise per ch)  waveform: pulse 50%, noise or off
;   R8-R10 level 0-15                   sustain level, gate
;   R11-R13 envelope                    not used by the game (kept only)
;
; Frequency: an AY tone of period P plays at 1 MHz / (16 P); the SID value
; for f is f * 2^24 / clock, so SID = 1064276 / P on PAL, 1025275 / P on
; NTSC. Periods under 4 (above 15 kHz) are silent, as they were on the Oric.
; Level: the SID has no per-voice volume, so the level is the voice's
; sustain, with the shortest attack, decay and release. A louder level
; restarts the envelope; a softer one lets it decay to the new sustain.
;==============================================================================

        .include "c64.inc"

        .export InitSound, AyWriteC64

WAVE_PULSE      = $40
WAVE_NOISE      = $80
GATE            = $01

        .segment "CODE"

InitSound:
        lda     #0
        ldx     #$18
@clr:   sta     SID,x
        dex
        bpl     @clr
        ldx     #15
@regs:  sta     ayRegs,x
        dex
        bpl     @regs
        sta     curLevel
        sta     curLevel+1
        sta     curLevel+2
        lda     #$FF                    ; mixer: everything off until the game sets it
        sta     ayRegs+7
        ldx     #0
        ldy     #3
@voice: lda     #$08                    ; pulse width 50%
        sta     SID+3,x
        lda     #$00                    ; attack 2 ms, decay 6 ms
        sta     SID+5,x
        sta     SID+6,x                 ; sustain 0, release 6 ms
        txa
        clc
        adc     #7
        tax
        dey
        bne     @voice
        lda     #$0F
        sta     SID_VOLUME
        rts

;------------------------------------------------------------------------------
; AyWriteC64 - replaces AYWrite: AY register A = X. Clobbers A, X, Y.
;------------------------------------------------------------------------------
AyWriteC64:
        cmp     #16
        bcs     @r
        tay
        txa
        sta     ayRegs,y
        cpy     #6
        bcc     @tone
        beq     @all
        cpy     #7
        beq     @mixer
        cpy     #11
        bcs     @r
        tya                             ; R8-R10
        sec
        sbc     #8
        tax
        jmp     SetLevel
@tone:  tya
        lsr     a
        tax
        jmp     SetFreq
@mixer: ldx     #0
        jsr     SetWave
        ldx     #1
        jsr     SetWave
        ldx     #2
        jmp     SetWave
@all:   ldx     #0
        jsr     SetFreq
        ldx     #1
        jsr     SetFreq
        ldx     #2
        jmp     SetFreq
@r:     rts

; Waveform for voice X from the mixer (bits active low): noise if its noise
; is on, else pulse if its tone is on, else none.
WaveOf:
        lda     ayRegs+7
        and     NoiseBit,x
        beq     @noise
        lda     ayRegs+7
        and     ToneBit,x
        beq     @tone
        lda     #0
        rts
@noise: lda     #WAVE_NOISE
        rts
@tone:  lda     #WAVE_PULSE
        rts

; New mixer setting for voice X: waveform, gate and frequency.
SetWave:
        jsr     WaveOf
        sta     wave,x
        ldy     VoiceOfs,x
        lda     curLevel,x
        beq     @off
        lda     wave,x
        beq     @off
        ora     #GATE
        bne     @set
@off:   lda     wave,x
@set:   sta     SID+4,y
        jmp     SetFreq

; Level register for voice X changed.
SetLevel:
        lda     ayRegs+8,x
        and     #$10
        beq     :+
        lda     #0                      ; envelope mode: the game's envelope
        beq     @lvl                    ; period is 0, i.e. at once silent
:       lda     ayRegs+8,x
        and     #$0F
@lvl:   ldy     VoiceOfs,x
        cmp     curLevel,x
        beq     @r
        bcc     @softer
        ; louder (or from silence): set sustain and restart the envelope
        sta     curLevel,x
        asl     a
        asl     a
        asl     a
        asl     a
        sta     SID+6,y
        jsr     WaveOf
        sta     wave,x
        sta     SID+4,y                 ; gate off
        beq     @r                      ; no waveform: stays off
        ora     #GATE
        sta     SID+4,y
@r:     rts
@softer:
        sta     curLevel,x
        cmp     #0
        beq     @gateOff
        asl     a
        asl     a
        asl     a
        asl     a
        sta     SID+6,y
        rts
@gateOff:
        lda     wave,x
        sta     SID+4,y
        rts

; Frequency of voice X from its tone period (or the noise period when it
; plays noise).
SetFreq:
        lda     wave,x
        cmp     #WAVE_NOISE
        bne     @tone
        lda     ayRegs+6
        and     #$1F
        sta     divs
        lda     #0
        sta     divs+1
        beq     @calc
@tone:  txa
        asl     a
        tay
        lda     ayRegs,y
        sta     divs
        lda     ayRegs+1,y
        and     #$0F
        sta     divs+1
@calc:  ldy     VoiceOfs,x
        lda     divs+1
        bne     @div
        lda     divs
        cmp     #4
        bcc     @silent
        cmp     #17
        bcs     @div
        lda     #$FF                    ; above the SID's top note
        sta     SID+0,y
        sta     SID+1,y
        rts
@silent:
        lda     #0
        sta     SID+0,y
        sta     SID+1,y
        rts
@div:   stx     voice
        lda     zIsPAL
        beq     @ntsc
        lda     #<1064276
        sta     divd
        lda     #>1064276
        sta     divd+1
        lda     #^1064276
        bne     @go
@ntsc:  lda     #<1025275
        sta     divd
        lda     #>1025275
        sta     divd+1
        lda     #^1025275
@go:    sta     divd+2
        jsr     Divide
        ldx     voice
        ldy     VoiceOfs,x
        lda     divd
        sta     SID+0,y
        lda     divd+1
        sta     SID+1,y
        rts

; divd (24 bits) /= divs (16 bits). Remainder in rem.
Divide:
        lda     #0
        sta     rem
        sta     rem+1
        ldx     #24
@bit:   asl     divd
        rol     divd+1
        rol     divd+2
        rol     rem
        rol     rem+1
        lda     rem
        sec
        sbc     divs
        tay
        lda     rem+1
        sbc     divs+1
        bcc     @next
        sta     rem+1
        sty     rem
        inc     divd
@next:  dex
        bne     @bit
        rts

        .segment "RODATA"
VoiceOfs:       .byte   0, 7, 14
ToneBit:        .byte   $01, $02, $04
NoiseBit:       .byte   $08, $10, $20

        .segment "BSS"
ayRegs:         .res 16
curLevel:       .res 3
wave:           .res 3
divd:           .res 3
divs:           .res 2
rem:            .res 2
voice:          .res 1
