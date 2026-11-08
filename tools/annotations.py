"""Names, comments and code/data hints for HOPPER.

tools/gen_source.py reads this file to turn the raw disassembly into readable
source. Addresses are the original load addresses ($0500-$30D4).
"""

FILE_HEADER = """
;==============================================================================
; HOPPER - Oric-1 - Personal Software Services (P.S.S.), Coventry
; Author (from the in-game credits): A.J. Clarke
;
; A Frogger-style game: guide the frog across three lanes of traffic, over a
; snake-patrolled bank, then across a river by riding logs and turtles, and
; into one of five homes at the top. Fill all five homes to clear a sheet.
;
; Reconstructed source, disassembled from the original tape image HOPPER.TAP.
; `make verify` rebuilds the TAP from this file and checks that it is
; byte-identical to the original.
;
; Memory: one machine-code block loaded at $0500-$30D4 and auto-run at $0500.
; The game uses the Oric's 40x28 TEXT screen with redefined characters, talks
; to the 6522 VIA and AY-3-8912 sound chip directly, and leaves the ROM's
; interrupt handler running for the keyboard buffer used by the menus.
;
; Labels: sub_XXXX / LXXXX / DXXXX are still-unnamed subroutines, branch
; targets and data; the XXXX is the original address. Every instruction also
; carries its original address in the comment column, to match the emulator's
; debugger.
;==============================================================================
"""

# --------------------------------------------------------------------------
# Entry points the tracer cannot discover by itself
# --------------------------------------------------------------------------
ENTRIES = [
    0x0500,   # tape autorun entry
    0x0560,   # NMI (RESET button) handler, installed at $022B
]

# Code that nothing in the game calls (left over from development).
DEAD_CODE = [
    (0x13A0, "a print-character routine (CR = next line); never called"),
    (0x15E0, "an earlier snake initialisation; never called"),
    (0x1670, "an earlier snake-erase routine; never called"),
    (0x1E80, "a delay loop; never called"),
    (0x1EC0, "a lane-gap countdown; never called"),
]

# --------------------------------------------------------------------------
# Code labels
# --------------------------------------------------------------------------
LABELS = {
    0x0500: "ColdStart",
    0x0540: "WarmStart",
    0x055D: "StartGame",
    0x0560: "NmiHandler",
    0x05A0: "CheckPause",
    0x0948: "RestoreCharset",
    0x09D0: "Random8",
    0x09D8: "ClearScreen",
    0x09F0: "RandomNext",
    0x0A00: "InitGame",
    0x0B00: "ScrollRow7Left",
    0x0B20: "ScrollRow13Left",
    0x0B40: "ScrollRow4Right",
    0x0B5E: "ScrollRow10Right",
    0x0B7C: "ScrollRow17Left",
    0x0B90: "ScrollRow20Right",
    0x0BAA: "ScrollRow23Left",
    0x0BC0: "SpawnRow23",
    0x0C60: "SpawnRow17",
    0x0D05: "WrapRow7",
    0x0D10: "WrapRow13",
    0x0D20: "WrapRow10",
    0x0D30: "SpawnRow20",
    0x0DB8: "FrameDelay",
    0x0DCA: "CheckLanding",
    0x0DF0: "Delay48",
    0x0DF2: "DelayX",
    0x0E80: "ReadKeys",
    0x0EB0: "KeysToDir",
    0x0F00: "DrawFrog",
    0x0F20: "SetFrogGfx",
    0x0F70: "StepFrog",
    0x0FE0: "CheckFrogBounds",
    0x1000: "NewGame",
    0x1004: "NewLife",
    0x100D: "MainLoop",
    0x1032: "LaneLoop",
    0x1100: "SaveUnderFrog",
    0x1110: "GetMove",
    0x1130: "RestoreUnderFrog",
    0x1140: "AnimateTurtles",
    0x1180: "CarryFrog",
    0x1200: "ResetSheet",
    0x123C: "PrefillLanes",
    0x1260: "EraseFrogIfRoad",
    0x126B: "EraseFrog",
    0x1280: "RedrawFrogIfRoad",
    0x12B0: "SpawnRow4",
    0x132D: "FrogDies",
    0x1330: "LoseLife",
    0x13C0: "CheckRoadHit",
    0x13E0: "CheckTurtleDive",
    0x1400: "MoveFrog",
    0x145B: "StartSheet",
    0x14A0: "FrogHome",
    0x1502: "AddScore",
    0x1570: "DrawHomeFrog",
    0x15B0: "PlaceFrogAtStart",
    0x1600: "MoveSnake",
    0x16A0: "TimeTick",
    0x16E0: "LoadAYRegs",
    0x1700: "SheetComplete",
    0x1800: "SetTurtleFrame",
    0x1AA0: "DrawTitleBar",
    0x1AD0: "GameOver",
    0x1B00: "CheckHiScore",
    0x1B79: "NameKeyLoop",
    0x1BCB: "ShowHiScores",
    0x1C00: "DrawHiScoreTable",
    0x1CA0: "PutChar",
    0x1D00: "DrawMenuPrompt",
    0x1D30: "ShowEnterName",
    0x1D40: "ClearEnterName",
    0x1D50: "CheckTimeLow",
    0x1DA0: "ServiceTimer",
    0x1E10: "FlyBonus",
    0x1E48: "BonusBeep",
    0x1F00: "DrawScenery",
    0x1F60: "SilenceAll",
    0x1F90: "SoundWrite",
    0x1FAD: "AYWrite",
    0x1FE2: "ViaMaskBits",
    0x2000: "DrawPlayfield",
    0x209F: "InitTimers",
    0x20C0: "TimeBonus",
    0x2110: "SetSplatGfx",
    0x211F: "DeathSoundInit",
    0x2136: "FlashRows",
    0x2170: "DeathSequence",
    0x21DB: "RestoreRowColours",
    0x2230: "FlyWarble",
    0x2280: "SoundMenu",
    0x2778: "CreditsIntro",
    0x27C4: "CreditsHop",
    0x2802: "CreditsDrop",
    0x2811: "CreditsDelay",
    0x2900: "TitleScroll",
    0x2940: "AttractMode",
    0x2948: "AttractLoop",
    0x299F: "CheckMenuKeys",
    0x29C0: "UpdateFly",
    0x2A1B: "EraseFly",
    0x2A25: "CheckFlySpot",
    0x2A35: "CheckFlyEaten",
    0x2A80: "HomeJingle",
    0x2AE8: "CreditsEnd",
    0x2B00: "MusicTick",
    0x2B50: "PickTune",
    0x2B82: "PlaySheetTune",
    0x2F30: "ControlsMenu",
    0x3085: "MarkSoundChoice",
    # odd targets
    0x0FD6: "BadTarget_0FD6",
    0x296D: "BadTarget_296D",
}

# --------------------------------------------------------------------------
# Data blocks: start -> (name, size, format, header comment)
#   format: glyph[:firstchar] | text | bytes[:n] | word | auto
# --------------------------------------------------------------------------
BLOCKS = {
    0x0600: ("udg_graphics", 0x128, "glyph:5B",
             "Character graphics for chars $5B-$7F: scenery, logs, cars, snake,\n"
             "turtles, fly. InitGame copies $0600-$07FF to CHARSET+$5B*8\n"
             "(the copy carries on into the tables below, which land harmlessly\n"
             "in the alternate character set)."),
    0x0728: ("udg_symbols", 80, "glyph:21",
             "Character graphics for chars $21-$2A (copied to CHARSET+$21*8)."),
    0x0778: ("status_template", 40, "text",
             "Status line shown on row 27. Control codes: $01-$07 ink colour."),
    0x07A0: ("home_wall_cols", 28, "bytes:14",
             "Columns of the hedge between the five homes on rows 1-2 (char $7F)."),
    0x07C8: ("row_colours", 56, "bytes:14",
             "Attribute pair (ink, paper) written to columns 0-1 of each of the\n"
             "28 screen rows: $00-$07 = ink colour, $10-$17 = paper colour."),
    0x0800: ("hiscore_inks", 9, "bytes",
             "Ink colour for each hi-score table row (indexed by digit '1'-'8')."),
    0x0810: ("note_periods", 12, "bytes:12",
             "AY tone periods for one octave (low byte), shifted right per octave."),
    0x0820: ("ay_game_regs", 14, "bytes:14",
             "AY register values 0-13 loaded at the start of a sheet."),
    0x0830: ("tune_ptrs", 8, "word",
             "Four in-game tunes; PickTune chooses one at random."),
    0x0840: ("tune_params", 8, "bytes:2",
             "Per tune: tempo, tune length in bytes."),
    0x0850: ("lane_init", 228, "bytes:38",
             "Initial contents of rows 7, 8, 10, 11, 13, 14 (river lanes),\n"
             "38 characters each (columns 2-39)."),
    0x0940: ("lane_speeds_init", 7, "bytes",
             "Initial lane speeds (frames between moves) for lanes 0-6."),
    0x0980: ("ay_quiet_regs", 14, "bytes:14",
             "AY register values 0-13: all channels quiet."),
    0x09A0: ("timer2_reload", 2, "bytes",
             "VIA timer 2 reload value ($606B) - the game's time base."),
    0x09C0: ("lane_speeds", 7, "bytes",
             "Working lane speeds; the lanes speed up as sheets are cleared."),
    0x0E00: ("frog_gfx", 128, "glyph",
             "The frog as 2x2 characters ($3A-$3D), four directions x 32 bytes:\n"
             "up, down, left, right. SetFrogGfx copies one set to CHARSET+$3A*8."),
    0x0EE0: ("key_rows", 5, "bytes",
             "Keyboard matrix row for each control key (left, right, up, down,\n"
             "pause). ControlsMenu overwrites these three tables."),
    0x0EE5: ("key_cols", 5, "bytes", "Column mask for each control key."),
    0x0EEA: ("key_bits", 5, "bytes", "Bit reported in key_state for each key."),
    0x0F10: ("frog_offsets", 4, "bytes",
             "Screen offsets of the frog's four characters: 0, 1, 40, 41."),
    0x0F15: ("frog_chars", 4, "bytes", "Character codes of the frog."),
    0x0F5C: ("row_steps_up", 9, "bytes",
             "Screen bytes to move up from each frog row (80 = two text rows)."),
    0x0F65: ("row_steps_down", 10, "bytes",
             "Screen bytes to move down from each frog row."),
    0x1540: ("home_gfx", 32, "glyph",
             "Graphics for a frog sitting in its home: chars $2B-$2C, then $2E-$2F.\n"
             "CreditsEnd also uses them as the title-screen frog."),
    0x1560: ("home_chars", 4, "bytes", "Character codes of the frog in its home."),
    0x15D0: ("snake_left", 5, "bytes", "Snake characters, moving left."),
    0x15D5: ("snake_right", 5, "bytes", "Snake characters, moving right."),
    0x16C0: ("keys_set1", 15, "bytes",
             "Key tables for control choice 1 (Z X ' /), copied to key_rows."),
    0x16D0: ("keys_set2", 15, "bytes",
             "Key tables for control choice 2 (, . A Z), copied to key_rows."),
    0x17C0: ("scenery_sheet", 21, "text", "\"SHEET NO\" sign drawn on rows 20-21."),
    0x17D5: ("scenery_score", 22, "text", "\"SCORE\" sign drawn on rows 23-24."),
    0x17F0: ("scenery_ready", 11, "text", "\"READY\" sign drawn on rows 14-15."),
    0x1898: ("controls_text", 0x66, "text",
             "Control-selection screen; $0D = new line, $FF = end."),
    0x1900: ("turtle_frames", 7 * 48, "glyph:6E",
             "Seven animation frames (6 characters each) for the diving turtles,\n"
             "copied to CHARSET+$6E*8 by SetTurtleFrame."),
    0x1A50: ("title_bar", 80, "text", "Title bar for rows 0-1 (double height)."),
    0x1AB0: ("game_over_text", 15, "text", "GAME OVER (double height)."),
    0x1CB0: ("menu_prompt", 0x41, "text",
             "Attract-mode prompt. Note the original typo \"INSTRUCTONS\"."),
    0x1D10: ("enter_name_text", 28, "text", "Shown when a new hi-score is entered."),
    0x1E53: ("bonus_pitches", 12, "bytes", "Tone periods for the fly bonus sound."),
    0x1E9E: ("hop_pitches", 13, "bytes", "Tone periods for the hop sound (steps 2-10)."),
    0x2207: ("splat_gfx", 32, "glyph", "Squashed-frog graphics for the death sequence."),
    0x22FF: ("hiscore_init", 0x100, "text",
             "Initial hi-score table, copied to ALTCHARS+$1FF at cold start.\n"
             "Eight entries of 28 bytes: 8-character score, then name ending $0D."),
    0x2400: ("credits_text", 0x2C8, "text",
             "Credits and instructions, four characters per frog hop (two on the\n"
             "upper row, two on the lower). CreditsIntro makes a frog hop around\n"
             "the screen and leave these behind it. ControlsMenu patches the key\n"
             "names in place."),
    0x26C8: ("credits_path", 0xAA, "bytes:16",
             "Direction of each credits hop (2 = down, 3 = left, 4 = right),\n"
             "$FF = end."),
    0x2A78: ("fly_cols", 5, "bytes", "Screen column (low byte, row 0) of each home for the fly."),
    0x2AC0: ("jingle_pitches", 32, "bytes:16", "Tone periods for the frog-home jingle."),
    0x2C00: ("tune0", 0x74, "bytes:2",
             "In-game tune 0: pairs of (note 1-12 or 0 = rest, octave<<4 | length).\n"
             "MusicTick advances before reading, so the first pair is never played."),
    0x2C80: ("tune1", 0x54, "bytes:2", "In-game tune 1."),
    0x2D00: ("sound_menu_text", 0xBA, "text",
             "Sound selection screen (double-height lines, $00 = end)."),
    0x2DBE: ("tune2", 0x8A, "bytes:2", "In-game tune 2."),
    0x2E80: ("tune3", 0xAA, "bytes:2", "In-game tune 3."),
    0x2FD7: ("status_save", 39, "text",
             "Copy of the status line, kept while the screen is redrawn."),
    0x3000: ("sheet_tune", 0x57, "bytes:3",
             "Tune played at the start of each sheet: 29 steps x 3 channels."),
    0x3058: ("sheet_tune_lens", 29, "bytes", "Length of each sheet-tune step."),
}

# Operand expressions for references that are clearer as an offset.
EXPR = {
    0x07CF: "hiscore_inks-'1'",
    0x07C9: "row_colours+1",
    0x0831: "tune_ptrs+1",
    0x0841: "tune_params+1",
}

# --------------------------------------------------------------------------
# Routine header comments
# --------------------------------------------------------------------------
BLOCK_COMMENTS = {
    0x0500: """ColdStart - tape autorun entry. Runs once.
Saves the ROM character set (chars $20-$7F) to $3100, points the NMI (RESET
button) at NmiHandler, and copies the default hi-score table to ALTCHARS+$1FF
(alternate-charset RAM, unused in this game, which survives a warm start).""",
    0x0540: """WarmStart - also reached from NmiHandler.
$12/$13 are the ROM's cursor address: pointing it at $C0C0 (ROM) stops the
ROM interrupt handler's cursor blink from writing to the screen.""",
    0x0560: """NmiHandler - RESET button pressed.
Silences the sound, restores the ROM character set, then waits about two
seconds. If key_state is $28 during that time it jumps to $A800 (probably a
development monitor the author kept in memory; nothing is there normally),
otherwise it restarts the game at WarmStart.""",
    0x05A0: """CheckPause - if the pause key is pressed, silence the sound and wait
until it is released and pressed again.""",
    0x0948: "RestoreCharset - copy the saved ROM font at $3100 back to CHARSET+$20*8.",
    0x09D0: "Random8 - next random number, returns 0-7 in A.",
    0x09D8: "ClearScreen - fill the whole text screen with spaces.",
    0x09F0: """RandomNext - steps the random seed at rand_seed ($D0-$D3).
Callers read rand_seed+1 or rand_seed+2.""",
    0x0A00: """InitGame - set up a new game: status line, character graphics,
playfield, sound, timers, lane speeds and all game variables.""",
    0x0B00: """Lane scrollers. Each moves a two-row lane one column; the river lanes
(rows 7, 10, 13) wrap round, the others are fed by the Spawn routines.""",
    0x0BC0: """SpawnRow23 / SpawnRow17 / SpawnRow20 / SpawnRow4 - feed new objects
into a lane at its edge: a random-length gap of spaces, then the object's
characters one column per call.""",
    0x0DB8: "FrameDelay - busy-wait game_delay x 256 loops, servicing the timer.",
    0x0DCA: """CheckLanding - after a hop: frog row 9 = reached a home; on the river
rows (5-8) the frog drowns if any of its four cells is water (a space).""",
    0x0DF0: "Delay48 / DelayX - busy-wait X x 256 loops (Delay48: X = 48).",
    0x0E80: """ReadKeys - scan the five control keys through the VIA and AY port A,
returning a bit for each pressed key in key_state (see key_bits).""",
    0x0EB0: "KeysToDir - convert key_state to frog_dir (0 none, 1 up, 2 down, 3 left, 4 right).",
    0x0F00: "DrawFrog - draw the frog's 2x2 characters at frog_pos.",
    0x0F20: "SetFrogGfx - load the frog graphics for frog_dir into chars $3A-$3D.",
    0x0F70: "StepFrog - move frog_pos one hop in frog_dir, updating frog_row / frog_col.",
    0x0FE0: """CheckFrogBounds - kill the frog if it has gone off the screen.
NOTE: an original bug. The `bcs` below branches to $0FD6, the middle of an
`inc` instruction. The byte there is $12, an illegal opcode that locks up
an NMOS 6502. It only runs when frog_row >= 10, which the game never allows.""",
    0x1000: """NewGame / MainLoop. Each pass: fly warble, fly, keyboard, frog
movement, delay, turtles, music, pause, then each of the seven lanes when its
timer expires, then the snake and the turtles' dive animation.""",
    0x1100: "SaveUnderFrog - copy the four screen cells under the frog to under_frog.",
    0x1110: "GetMove - read a direction, ignoring a key that is still held from the last hop.",
    0x1130: "RestoreUnderFrog - put back the four saved cells.",
    0x1140: "AnimateTurtles - step the diving turtles through frames 0-6 and back.",
    0x1180: "CarryFrog - when lane X scrolls and the frog is on it, move the frog too.",
    0x1200: "ResetSheet - put the frog at the start and run all lanes 49 times to fill them.",
    0x1260: """EraseFrogIfRoad / RedrawFrogIfRoad - on the road rows (1-4) take the
frog off the screen before a lane scrolls and put it back afterwards; if the
cells are no longer empty a car has hit it.""",
    0x132D: """FrogDies / LoseLife - death sequence, take a life, game over if none left,
otherwise reset the frog and restart the main loop (the stack is reset).""",
    0x13C0: "CheckRoadHit - die if the frog has hopped into something on a road row.",
    0x13E0: "CheckTurtleDive - die if the frog is on the diving turtles (row 7) while they are under.",
    0x1400: "MoveFrog - read a move and hop: restore the background, step, save, check, draw, score.",
    0x145B: "StartSheet - redraw everything for the next sheet and start play.",
    0x14A0: "FrogHome - frog reached a home: fly bonus, jingle, count homes, five = sheet complete.",
    0x1502: """AddScore - add A to score digit X (0-5 = the six digits after the
first two on the status line), carrying into higher digits.""",
    0x1570: "DrawHomeFrog - draw a frog sitting in the home it reached.",
    0x15B0: "PlaceFrogAtStart - frog back to row 25, column 20, facing up.",
    0x1600: "MoveSnake - move the snake along the middle bank (row 15), bouncing at the ends.",
    0x16A0: "TimeTick - count TIME down by one.",
    0x16E0: "LoadAYRegs - write 14 bytes at (X lo, Y hi) to AY registers 0-13.",
    0x1700: """SheetComplete - all five homes full: time bonus, next sheet number,
reset TIME, and make the game harder (faster lanes, snake and turtles).""",
    0x1800: "SetTurtleFrame - copy turtle animation frame turtle_frame to chars $6E-$73.",
    0x1AA0: "DrawTitleBar - draw the two-row title bar.",
    0x1AD0: "GameOver - show GAME OVER, pause, restore the font and go to the hi-score check.",
    0x1B00: """CheckHiScore - compare the score with the table at ALTCHARS+$200; if it
qualifies, insert it, ask for a name (read from the ROM key buffer) and show
the table. Then enter attract mode.""",
    0x1C00: "DrawHiScoreTable - print the eight hi-score entries.",
    0x1CA0: "PutChar - store A at ($30),Y and advance Y.",
    0x1D00: "DrawMenuPrompt - draw the attract-mode prompt and scroll the title bar.",
    0x1D50: "CheckTimeLow - warning tone when TIME gets low; when it hits 00, lose a life.",
    0x1DA0: """ServiceTimer - called often. When VIA timer 2 has run out: reload it,
tick TIME every 32 periods, and step the hop sound.""",
    0x1E10: "FlyBonus - frog ate the fly: random bonus counted into the score with beeps.",
    0x1F00: "DrawScenery - draw the signs, play the sheet tune.",
    0x1F60: "SilenceAll - set the volume of all three AY channels to 0.",
    0x1F90: """SoundWrite - write AY register A = X, honouring the sound option:
off (no write), quiet (as given) or loud (volume registers doubled).""",
    0x1FAD: """AYWrite - write value X to AY register A. Drives the BC1/BDIR lines
through the VIA PCR (CA2/CB2) - see ViaMaskBits.""",
    0x1FE2: "ViaMaskBits - VIA register X = (VIA register X AND A) OR Y.",
    0x2000: "DrawPlayfield - clear the screen and draw colours, homes, banks and lanes.",
    0x209F: "InitTimers - enable VIA timer 1 free-run interrupts for the ROM (keyboard, ~100Hz).",
    0x20C0: "TimeBonus - add the remaining TIME to the score, one unit at a time, with a beep.",
    0x2170: "DeathSequence - squashed frog, falling tone and flashing screen colours.",
    0x2230: "FlyWarble - rising and falling tone while the fly is showing.",
    0x2280: "SoundMenu - draw the sound menu and wait for 1, 2 or 3 (sets sound_mode).",
    0x2778: "CreditsIntro - a frog hops round the screen leaving the credits behind it.",
    0x2900: "TitleScroll - scroll the title bar sideways forever, checking for menu keys.",
    0x2940: "AttractMode - loop: credits screen, wait, hi-score table, wait.",
    0x299F: "CheckMenuKeys - 1 = start a game, 2 = show the instructions again.",
    0x29C0: "UpdateFly - from sheet 3, a fly appears in a random empty home for a while.",
    0x2A35: "CheckFlyEaten - frog entered a home: bonus if the fly was there; die if the home was full.",
    0x2A80: "HomeJingle - tune played when a frog gets home.",
    0x2AE8: "CreditsEnd - quiet the AY, show the title frog and play the jingle.",
    0x2B00: "MusicTick - step the in-game background tune.",
    0x2B50: "PickTune - choose one of the four in-game tunes at random.",
    0x2B82: "PlaySheetTune - play the three-channel tune at sheet_tune.",
    0x2F30: "ControlsMenu - choose a key set and patch the key tables and the instructions.",
    0x3085: "MarkSoundChoice - highlight the chosen sound option on the menu screen.",
}

# --------------------------------------------------------------------------
# Inline comments
# --------------------------------------------------------------------------
COMMENTS = {
    0x0510: "save ROM font $B500-$B7FF to $3100",
    0x0521: "NMI_VECTOR = JMP NmiHandler",
    0x0532: "default hi-scores to ALTCHARS+$1FF",
    0x057C: "keys $28 held: silence and leave",
    0x057F: "-> development monitor? (see header)",
    0x0A11: "font already loaded?",
    0x0A2A: "copy $0600-$07FF -> CHARSET+$5B*8",
    0x0A9C: "chars $21-$2A",
    0x0FEE: "BUG: branches into an instruction (see header)",
    0x1004: "reset stack: death paths jump back here",
    0x135E: "LIVES digit - 1",
    0x1364: "reached '0'?",
    0x1B79: "wait for a key from the ROM key buffer",
    0x1BE6: "jumps 1 byte into `jsr ClearScreen` at $296B: runs ORA #$20 / LDY #$1A",
    0x296B: "",
    0x29AF: "'1' -> start a game",
    0x29B6: "'2' -> instructions",
}

# --------------------------------------------------------------------------
# External symbols (zero page, page 2-4 variables, hardware). Kept in
# vars.inc / oric.inc; listed here so the generator uses the names.
# --------------------------------------------------------------------------
SYMBOLS = {
    # zero page
    0x00: "tmp0", 0x01: "key_state", 0x02: "tmp2", 0x03: "tmp3", 0x04: "tmp4",
    0x05: "tmp5", 0x06: "tmp6",
    0x12: "ROM_CURPTR", 0x13: "ROM_CURPTR+1",
    0x14: "ay_table", 0x15: "ay_table+1",
    0x20: "fly_on", 0x21: "fly_timer", 0x22: "fly_timer+1", 0x23: "zp_23",
    0x2B: "fly_ptr", 0x2C: "fly_ptr+1",
    0x2F: "last_dir",
    0x30: "ptr30", 0x31: "frog_dir",
    0x32: "frog_pos", 0x33: "frog_pos+1",
    0x34: "step_size", 0x35: "old_pos", 0x36: "old_pos+1",
    0x37: "key_mask", 0x38: "tick_count",
    0x3A: "lane_index",
    0x3B: "snake_col", 0x3C: "snake_row", 0x3D: "snake_row+1", 0x3F: "snake_dir",
    0x40: "lane_timer",
    0x50: "hop_sound",
    0x51: "warble_level", 0x52: "warble_dir",
    0x53: "note_time", 0x54: "tune_pos", 0x55: "note_octave", 0x56: "note_num",
    0x57: "tempo_count", 0x58: "note_period", 0x59: "tune_tempo",
    0x5A: "tune_ptr", 0x5B: "tune_ptr+1", 0x5C: "tune_len",
    0xD1: "rand_seed+1", 0xD2: "rand_seed+2", 0xD4: "rand_seed+4",
    0xFF: "sound_mode",
    # page 2 (Oric-1 ROM system variables)
    0x020F: "ROM_SCRATCH", 0x0269: "ROM_CURCOL", 0x02DF: "ROM_KEY",
    0x022B: "NMI_VECTOR", 0x022C: "NMI_VECTOR+1", 0x022D: "NMI_VECTOR+2",
    # VIA
    0x0300: "VIA_ORB", 0x0302: "VIA_DDRB", 0x0304: "VIA_T1CL", 0x0305: "VIA_T1CH",
    0x0306: "VIA_T1LL", 0x0307: "VIA_T1LH", 0x0308: "VIA_T2CL", 0x0309: "VIA_T2CH",
    0x030B: "VIA_ACR", 0x030D: "VIA_IFR", 0x030E: "VIA_IER", 0x030F: "VIA_ORA_NH",
    # page 4 game variables
    0x0400: "r23_state", 0x0401: "r23_len", 0x0402: "r23_first", 0x0403: "r23_gap",
    0x0404: "r17_state", 0x0405: "r17_len", 0x0406: "r17_first", 0x0407: "r17_gap",
    0x0408: "r20_state", 0x0409: "r20_len", 0x040A: "r20_first", 0x040B: "r20_gap",
    0x040C: "sheet", 0x040D: "r17_gap_min", 0x040E: "r20_gap_min", 0x040F: "r23_gap_min",
    0x0410: "game_delay", 0x0411: "frog_row", 0x0412: "frog_col",
    0x0414: "r4_state", 0x0415: "r4_len", 0x0416: "r4_first", 0x0417: "r4_gap",
    0x0418: "r4_gap_min", 0x041A: "r4_len_min",
    0x0420: "under_frog", 0x0421: "under_frog+1",
    0x0428: "turtle_frame", 0x0429: "turtle_phase",
    0x0430: "frogs_home",
    0x0460: "turtle_speed", 0x0461: "snake_speed", 0x0462: "pause_flag",
    # other memory
    0xA800: "DEV_MONITOR",
    0xB9FF: "HISCORES-1", 0xBA00: "HISCORES", 0xBA08: "HISCORES+8", 0xBA1C: "HISCORES+28",
    0xBFB8: "STATUS_ROW", 0xBFBA: "STATUS_ROW+2", 0xBFBF: "SCORE_DIGITS-1",
    0xBFC0: "SCORE_DIGITS", 0xBFC7: "STATUS_ROW+15",
    0xBFCD: "TIME_DIGITS", 0xBFCE: "TIME_DIGITS+1", 0xBFCF: "STATUS_ROW+23",
    0xBFD6: "LIVES_DIGIT", 0xBFDE: "SHEET_DIGITS", 0xBFDF: "SHEET_DIGITS+1",
}

DATA_SPLITS = []
