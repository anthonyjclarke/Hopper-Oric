;==============================================================================
; vars.inc - HOPPER variables (zero page, page 4) and fixed screen locations
; Several zero-page bytes are reused as temporaries by different routines;
; the name reflects the main use.
;==============================================================================

; --- zero page ---------------------------------------------------------------
tmp0            = $00           ; temporary / loop counter
key_state       = $01           ; ReadKeys result: one bit per control key
tmp2            = $02
tmp3            = $03           ; also turtle-speed frame counter
tmp4            = $04           ; also snake-speed frame counter
tmp5            = $05
tmp6            = $06
ROM_CURPTR      = $12           ; Oric-1 ROM: cursor screen address (2 bytes)
ay_table        = $14           ; LoadAYRegs table pointer (2 bytes)
fly_on          = $20           ; fly showing (also copy-loop pointer)
fly_timer       = $21           ; fly timer (2 bytes; also pointers)
zp_23           = $23           ; copy-loop pointer high byte
fly_ptr         = $2B           ; screen address of the fly (2 bytes)
last_dir        = $2F           ; previous move, for key repeat suppression
ptr30           = $30           ; general screen pointer (2 bytes, high = $31)
frog_dir        = $31           ; 0 none, 1 up, 2 down, 3 left, 4 right
frog_pos        = $32           ; screen address of frog's top-left cell (2 bytes)
step_size       = $34           ; StepFrog: bytes to move
old_pos         = $35           ; frog_pos before the hop (2 bytes)
key_mask        = $37           ; ANDed with frog_dir in GetMove ($FF)
tick_count      = $38           ; timer periods; TIME drops every 32
lane_index      = $3A           ; MainLoop lane counter (6..0)
snake_col       = $3B           ; snake column
snake_row       = $3C           ; screen address of row 15 (2 bytes)
snake_dir       = $3F           ; 1 = moving left, 2 = moving right
lane_timer      = $40           ; 7 bytes, one per lane, counts to lane_speeds
hop_sound       = $50           ; hop sound step (0 = off)
warble_level    = $51           ; fly warble pitch step
warble_dir      = $52           ; fly warble direction
note_time       = $53           ; frames left on current note
tune_pos        = $54           ; offset into the tune
note_octave     = $55
note_num        = $56
tempo_count     = $57
note_period     = $58
tune_tempo      = $59
tune_ptr        = $5A           ; current tune (2 bytes)
tune_len        = $5C
rand_seed       = $D0           ; 4-byte random seed $D0-$D3
sound_mode      = $FF           ; 0 = off, 1 = quiet, 2 = loud

; --- Oric-1 ROM page-2 system variables ---------------------------------------
ROM_SCRATCH     = $020F         ; temporary used by ViaMaskBits
ROM_CURCOL      = $0269         ; ROM cursor column
ROM_KEY         = $02DF         ; last key from ROM IRQ scan, bit 7 = new key

; --- page 4 game variables -----------------------------------------------------
; Spawners for rows 23, 17, 20 (cars) and 4 (logs): state = which character
; of the object to place next (0 = placing the gap), len = repeat count for
; the middle part, first = 1 on the first gap, gap = gap countdown.
r23_state       = $0400
r23_len         = $0401
r23_first       = $0402
r23_gap         = $0403
r17_state       = $0404
r17_len         = $0405
r17_first       = $0406
r17_gap         = $0407
r20_state       = $0408
r20_len         = $0409
r20_first       = $040A
r20_gap         = $040B
sheet           = $040C         ; sheet number, 1 = first
r17_gap_min     = $040D         ; minimum gaps between cars
r20_gap_min     = $040E
r23_gap_min     = $040F
game_delay      = $0410         ; FrameDelay length; drops every 8th sheet
frog_row        = $0411         ; 0 = start, 1-4 road, 5-8 river, 9 = home
frog_col        = $0412         ; frog column
r4_state        = $0414
r4_len          = $0415
r4_first        = $0416
r4_gap          = $0417
r4_gap_min      = $0418
r4_len_min      = $041A
under_frog      = $0420         ; 4 screen cells hidden by the frog
turtle_frame    = $0428         ; 0-6; 5 and 6 = under water
turtle_phase    = $0429         ; 0 start, 1 diving, 2 surfacing
frogs_home      = $0430         ; homes filled this sheet (5 = done)
turtle_speed    = $0460         ; frame mask for AnimateTurtles
snake_speed     = $0461         ; frame mask for MoveSnake
pause_flag      = $0462

; --- other memory ------------------------------------------------------------
DEV_MONITOR     = $A800         ; see NmiHandler
HISCORES        = $BA00         ; hi-score table (in alternate-charset RAM)
STATUS_ROW      = SCREEN+27*40  ; status line
SCORE_DIGITS    = STATUS_ROW+8  ; six score digits after the "00"
TIME_DIGITS     = STATUS_ROW+21
LIVES_DIGIT     = STATUS_ROW+30
SHEET_DIGITS    = STATUS_ROW+38
