//==================================================================
// outline-64 — interlude: text-mode plasma + raster bars
//
// Two visual layers over the pad + build-up music arc:
//
//   1. PLASMA — diagonal colour bars scrolling through color RAM.
//      A 256-byte wave scrolls horizontally; each 40-col row has
//      a staggered phase offset, creating a diagonal bar pattern.
//      Half the rows update each frame (packed 2×4-bit per byte)
//      to fit PAL budget.
//
//   2. RASTER BARS — 6 horizontal bars in the border, colours
//      cycling per beat. IRQ chain (main -> 6 bars -> main) flips
//      border at each bar's raster position.
//
// Memory:
//   $8000-$84FF  code + tables (5 pages)
//   $1000-$125D  intro music tables (inherited)
//
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const SPR_EN     = $d015
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const SPR_X      = $d000
.const SPR_MSB    = $d010
.const SPR_PRIO   = $d01b
.const SPR_XEXP   = $d01d
.const SPR_YEXP   = $d017
.const SPR_MC     = $d01c
.const SPR_COL    = $d027
.const SPR_PTRS   = $07f8
.const IRQ_VEC    = $fffe

.const INTRO_MUSIC_PLAY = $119e

.const SCREEN    = $0400
.const COL_RAM   = $d800

.const BEAT_PERIOD   = 24         // frames per beat — was 20, loosened for breathing room
.const BUILDUP_BEAT  = 6          // pad ends, bass+filter+bars in — was 4
.const TRANSITION_BEAT = 16       // pefchain advances at zp_beat_count == this — was 10
.const FILT_CUT_LO   = $70        // bumped from $40 to $70 so V1 bass
                                   // isn't rolled off as hard at the
                                   // SPARKED drop — the user heard the
                                   // dark cutoff as "music slowing
                                   // down". Starting brighter lets the
                                   // sweep feel like opening up an
                                   // already-energetic mix rather than
                                   // dragging an underwater bass into
                                   // existence.
.const FILT_CUT_STEP = $16        // softer sweep over more beats

// Sprite-letter line B — "SPARKED " drops in on the buildup, bounces
// briefly, then flies up before the transition. 8 sprites, 1 char each,
// hires, no expand. Shape pointers $80..$87 → $2000..$21C0.
.const SPR_TARGET_Y    = 154      // raster row 13 top — letters sit above the "now AI WROTE the code" reveal
.const SPR_SPAWN_Y     = 0        // off-screen above; falls into place
.const PHASE_OFF       = 0
.const PHASE_FLY_IN    = 1
.const PHASE_BOUNCE    = 2
.const PHASE_FLY_OUT   = 3
.const PHASE_DONE      = 4        // terminal — sprites stay off, no
                                   // further animation. Set by sp_out
                                   // after FLY_OUT completes so sp_off's
                                   // "BUILDUP_BEAT reached?" check
                                   // doesn't re-arm a second drop.
.const FLY_IN_LEN      = 32       // frames between first letter dropping and last letter settling
.const FLY_OUT_LEN     = 20

.const zp_beat_phase = $f4
.const zp_filt_cut   = $f5
.const zp_beat_count = $f6
.const zp_xphase     = $f7        // global plasma X phase (per-frame)
.const zp_plasma_tgl = $f8
.const zp_bar_clr_ofs= $f9
.const zp_wave_phs   = $fa        // per-row cell phase tracker
.const zp_yphase     = $fb        // global plasma Y phase (slower)
.const zp_tmp        = $fc
.const zp_y_contrib  = $fd        // per-row precomputed Y wave value

// Fire phase — merged from hush. Runs after the SPARKED buildup.
.const FIRE_TRIGGER_BEAT = 16     // plasma → fire switch at this beat
.const FIRE_DURATION      = 250   // frames of fire before transition
.const FIRE_SWAP_FRAME    = 120   // banner text swap (phase 1 → phase 2)
.const FIRE_MSG_TOP       = 10    // banner sits on rows 10-12
.const FIRE_MSG_ROWS      = 3
.const FIRE_FADE_START    = 200   // volume fade begins
.const zp_fire_frame      = $f3   // fire phase frame counter (outside EFO ZP claim $f4-$fd) 

* = $8000 "Interlude"

//==================================================================
// setup
//==================================================================
setup:
        lda #$3c
        sta $dd02
        lda #%00010100
        sta VIC_MEM
        lda #$1b
        sta VIC_CTRL1
        lda #$08
        sta VIC_CTRL2
        lda #$00
        sta SPR_EN
        sta VIC_BORDER
        sta VIC_BG

        // V3 off during pad ($D418 bit 7 = 1 mutes V3) so the resident
        // K-S-K-S kit doesn't fire and the V3 arp drops out — leaves
        // ONLY V2 lead audible (V1 is muted via $D404 = 0 below).
        // Music-box pad feel under the typewriter confession. IRQ
        // flips bit 7 back off at BUILDUP_BEAT so drums + arp slam
        // in WITH the bass + filter sweep on SPARKED's drop.
        lda #$9f
        sta $d418
        lda #$00
        sta $d404
        sta $d416
        sta $d417

        // Jump intro's lead pattern to phrase 2 (active 8ths) at
        // interlude START — gives the pad phase a moving lead line
        // under the typewriter instead of phrase 4's natural sparse
        // rests. mu_step lives in intro's resident music tables at
        // $1148; mu_frame at $1149.
        lda #32
        sta $1148
        lda #0
        sta $1149

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_filt_cut
        sta zp_xphase
        sta zp_yphase
        sta zp_plasma_tgl
        sta zp_bar_clr_ofs
        sta sp_phase
        sta sp_frame
        sta line_a_pos
        sta line_a_tick
        sta line_a_state
        sta line_a_typo_idx
        sta line_a_pause_cnt

        // Fill screen with solid block ($A0 reverse-space in screencode_mixed)
        // so the per-cell colour-RAM plasma is actually visible. Plain
        // $20 (space) is transparent — colour RAM cycling without any
        // foreground pixels would render nothing on screen.
        ldx #0
        lda #$a0
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

        // Line A is now revealed by update_line_a one char every 2 frames
        // during the pad phase — see story_line_a section. The screen is
        // already filled with $A0 above, so row 11 starts as a wash of
        // plasma-coloured blocks; chars overwrite them as they "type".
        // Line B is the SPARKED sprite-letter drop (init_sprites below).

        // fill ALL 25 color RAM rows
        lda #0
        sta zp_plasma_tgl
!all:   ldx zp_plasma_tgl
        jsr write_plasma_row
        inc zp_plasma_tgl
        lda zp_plasma_tgl
        cmp #25
        bne !all-
        lda #0
        sta zp_plasma_tgl

        jsr init_sprites

        // vsync IRQ
        lda #$ff
        sta VIC_RASTER
        rts


//==================================================================
// init_sprites — sprite-letter line B setup. 8 hires sprites point at
// pre-rendered chargen glyphs in $2000..$21C0; X positions span 152..208
// to centre the 8-char phrase under row 11; Y position is patched per
// frame by update_sprites depending on the global animation phase.
//==================================================================
init_sprites:
        // block pointers $80..$87 → $2000..$21C0
        ldx #0
!ptr:   txa
        clc
        adc #$80
        sta SPR_PTRS,x
        inx
        cpx #8
        bne !ptr-

        // X positions (low byte; all sprites have MSB clear since 208<256)
        ldx #0
        ldy #0
!xp:    lda spr_x_table,x
        sta SPR_X,y
        lda #SPR_SPAWN_Y          // park off-screen above
        sta SPR_X+1,y
        inx
        iny
        iny
        cpx #8
        bne !xp-
        lda #$00
        sta SPR_MSB

        // hires, no expand, in front of plasma
        lda #$00
        sta SPR_XEXP
        sta SPR_YEXP
        sta SPR_MC
        sta SPR_PRIO

        // sprite colours — alternating white / light-cyan keeps the
        // letters legible against any plasma colour underneath.
        ldx #0
!col:   lda spr_color_table,x
        sta SPR_COL,x
        inx
        cpx #8
        bne !col-

        // sprites off until the buildup beat fires update_sprites' fly-in
        lda #$00
        sta SPR_EN
        rts


//==================================================================
// write_plasma_row — true 2D plasma into row X's 40 colour-RAM cells.
//   X = row index 0..24.
//
// Algorithm: per cell, colour = palette[ (wave[X-phase] + wave[Y-phase]) & 0x0F ].
// Two independent phases (`zp_xphase`, `zp_yphase`) advance at
// different rates each frame, so the interference pattern morphs
// rather than just scrolling. Y-contribution is constant for the
// whole row — computed once at row start, reused for all 40 cells.
//==================================================================
write_plasma_row:
        // Per-row Y contribution: wave[(row_offset[X] + yphase) & 0xff].
        // row_offset has non-linear stagger so vertical bands curve.
        lda row_offset,x
        clc
        adc zp_yphase
        tay
        lda wave,y
        sta zp_y_contrib

        // Per-row X phase: starts at zp_xphase, increments per cell.
        lda zp_xphase
        sta zp_wave_phs

        // Self-modify destination ($D800 + X*40).
        lda row_cr_lo,x
        sta smc+1
        lda row_cr_hi,x
        sta smc+2

        // Per-cell loop: 40 colour-RAM writes.
        ldx #0
!lp:    ldy zp_wave_phs
        lda wave,y
        clc
        adc zp_y_contrib          // 2D plasma sum
        and #$0f
        tay
        lda plasma_palette,y      // hue-stable gradient
smc:    sta $d800,x
        inc zp_wave_phs
        inx
        cpx #40
        bcc !lp-
        rts


//==================================================================
// interrupt — main vsync handler, raster $FF
//==================================================================
interrupt:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

musichook:
        .byte $2c, $00, $00       // bit $0000 — pefchain rewrites to
                                   // jsr $119e (intro's my_music_play)
                                   // at link time via the 'M' tag in
                                   // intro's EFO header. Replaces the
                                   // old `jsr INTRO_MUSIC_PLAY` so the
                                   // auto-inserted blank-filler parts
                                   // between effects also call music
                                   // (= no SID dropout during load
                                   // gaps at transitions).
        // One-frame silence on SPARKED landing: if silence_cnt > 0,
        // mute SID for this frame then resume. Lightning before thunder.
        lda silence_cnt
        beq !no_silence+
        lda #$00
        sta $d418
        dec silence_cnt
        jmp !vol_done+
!no_silence:
        // Master vol + V3 gate: $9F during pad (bit 7 mutes V3 = no
        // arp, no resident-kit drums), $1F during buildup (V3 on).
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !v3_on+
        lda #$9f
        .byte $2c                  // skip next 2 bytes
!v3_on: lda #$1f
        sta $d418
!vol_done:

        // V2 lead PWM — slowly sweep V2 pulse-width via zp_xphase so
        // the lead line has a "breathing phaser" feel through the
        // whole part. zp_xphase ticks +2/frame from the plasma, so
        // /4 gives a smooth 0..7 walk; +4 keeps the width in the
        // 4..11 range (avoids the degenerate near-0/15 widths that
        // would make V2 nearly silent).
        lda zp_xphase
        lsr
        lsr
        and #$07
        clc
        adc #$04
        sta $d40a

        // Border flash on SPARKED landing — white top border for 3 frames
        lda flash_cnt
        beq !no_flash+
        lda #$01
        sta VIC_BORDER
        dec flash_cnt
!no_flash:

        // Phase check: plasma (beats < 16) or fire (beats >= 16).
        lda zp_beat_count
        cmp #FIRE_TRIGGER_BEAT
        bcc !fire_check_done+      // beat < 16 → continue plasma
        jmp fire_irq               // beat >= 16 → jump to fire
!fire_check_done:

        // V1 mute / build-up
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !buildup+
        lda #$00
        sta $d404
        jmp !beat+
!buildup:
        // Route V1 (bass) + V2 (lead) through the LP filter so the
        // cutoff ramp pulls BOTH up together — it's not just the pad
        // opening any more, the melody opens with it. V3 stays
        // unfiltered (arp/drum keep their bite). Resonance $2 in the
        // high nibble adds a slight emphasis at the cutoff for character.
        lda #$23                  // res $2 + V2 + V1 filtered
        sta $d417
        lda zp_filt_cut
        sta $d416
!beat:
        inc zp_beat_phase
        lda zp_beat_phase
        cmp #BEAT_PERIOD
        bcc !no_beat+
        lda #0
        sta zp_beat_phase
        inc zp_beat_count

        // rotate bar colours on beat
        inc zp_bar_clr_ofs

        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcc !no_beat+
        cmp #BUILDUP_BEAT
        bne !ramp+
        lda #FILT_CUT_LO
        sta zp_filt_cut
        jmp !no_beat+
!ramp:  lda zp_filt_cut
        clc
        adc #FILT_CUT_STEP
        bcs !sat+
        sta zp_filt_cut
        jmp !no_beat+
!sat:   lda #$ff
        sta zp_filt_cut
!no_beat:

        jsr update_line_a
        jsr update_sprites

        // plasma — advance both phases at different rates so the
        // interference pattern morphs rather than just scrolls.
        inc zp_xphase
        inc zp_xphase
        inc zp_yphase

        lda zp_plasma_tgl
        and #1
        bne !odd+
        lda #0
        sta row_base
        lda #13
        sta row_cnt
        jmp !go+
!odd:   lda #1
        sta row_base
        lda #12
        sta row_cnt
!go:
        ldx row_base
!row_lp:
        txa
        pha
        jsr write_plasma_row
        pla
        tax
        inx
        inx
        dec row_cnt
        bne !row_lp-

        inc zp_plasma_tgl

        // Bars only render during the buildup phase.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !bars_on+
        // Pad phase: skip bars, re-trigger this IRQ next frame.
        lda #$ff
        sta VIC_RASTER
        lda #<interrupt
        sta IRQ_VEC
        lda #>interrupt
        sta IRQ_VEC + 1
        jmp !done+
!bars_on:
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters
        sta VIC_RASTER
        lda #<bar_chain_0
        sta IRQ_VEC
        lda #>bar_chain_0
        sta IRQ_VEC + 1
        jmp !done+

!done:
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// update_line_a — typewriter with typo: types "FOR YEARS NO TIME
// FOR BREADBIN LOVE", pauses (the machine catches itself), backspaces
// 4 chars, then types "CODE". The hesitation is the confession.
//==================================================================
.const LINE_A_PERIOD  = 4        // frames per char
.const TYPO_TRIGGER   = 31       // position where typo starts (after "BREADBIN ")
.const TYPO_LEN       = 4        // "LOVE" = 4 chars
.const TYPO_PAUSE     = 60       // ~1.2 sec — uncomfortable hesitation
.const LA_TYPING      = 0
.const LA_TYPO        = 1
.const LA_PAUSE       = 2
.const LA_BACKSPACE   = 3
.const LA_RETYPE      = 4
.const LA_DONE        = 5

update_line_a:
        lda line_a_state
        cmp #LA_DONE
        bne !not_done+
        rts
!not_done:
        cmp #LA_PAUSE
        bne !not_pause+
        jmp la_pause
!not_pause:
        cmp #LA_BACKSPACE
        bne !not_bs+
        jmp la_backspace
!not_bs:

        // LA_TYPING / LA_TYPO / LA_RETYPE — all advance one char per tick
        inc line_a_tick
        lda line_a_tick
        cmp #LINE_A_PERIOD
        bcc !cursor+
        lda #0
        sta line_a_tick

        lda line_a_state
        cmp #LA_TYPO
        beq !typo_char+

        // Normal typing (LA_TYPING or LA_RETYPE)
        ldx line_a_pos
        lda story_line_a,x
        sta $05BA,x
        inc line_a_pos
        // Check if we hit the typo trigger
        lda line_a_state
        cmp #LA_TYPING
        bne !check_end+
        lda line_a_pos
        cmp #TYPO_TRIGGER
        bcc !cursor+
        lda #LA_TYPO
        sta line_a_state
        lda #0
        sta line_a_typo_idx
        jmp !cursor+

!check_end:
        // LA_RETYPE — check if fully done
        lda line_a_pos
        cmp #35
        bcc !cursor+
        lda #LA_DONE
        sta line_a_state
        rts

!typo_char:
        // Type wrong chars from typo_text
        ldx line_a_pos
        ldy line_a_typo_idx
        lda typo_text,y
        sta $05BA,x
        inc line_a_pos
        inc line_a_typo_idx
        lda line_a_typo_idx
        cmp #TYPO_LEN
        bcc !cursor+
        // Typed all wrong chars → pause
        lda #LA_PAUSE
        sta line_a_state
        lda #TYPO_PAUSE
        sta line_a_pause_cnt
        jmp !cursor+

!cursor:
        ldx line_a_pos
        cpx #39
        bcs !no_cur+
        lda #$a0
        sta $05BA,x
!no_cur:
        rts

la_pause:
        // Blinking cursor during the hesitation — the machine is thinking.
        ldx line_a_pos
        lda line_a_pause_cnt
        and #$08
        beq !cur_off+
        lda #$a0
        sta $05BA,x
        jmp !cur_done+
!cur_off:
        lda #$20
        sta $05BA,x
!cur_done:
        dec line_a_pause_cnt
        bne !wait+
        lda #LA_BACKSPACE
        sta line_a_state
        lda #TYPO_LEN
        sta line_a_typo_idx
!wait:  rts

la_backspace:
        inc line_a_tick
        lda line_a_tick
        cmp #5                    // deliberate backspace: 5 frames per delete
        bcc !bwait+
        lda #0
        sta line_a_tick
        dec line_a_pos
        ldx line_a_pos
        lda #$a0
        sta $05BA,x              // erase char
        dec line_a_typo_idx
        bne !bwait+
        // All wrong chars erased → retype correctly
        lda #LA_RETYPE
        sta line_a_state
!bwait: rts


//==================================================================
// update_sprites — sprite-letter line B animation state machine.
//
//   PHASE_OFF  → all sprites disabled (pad phase, beat < BUILDUP_BEAT).
//                Enters PHASE_FLY_IN the first frame of buildup.
//   PHASE_FLY_IN → letters drop from Y=0 to Y=SPR_TARGET_Y individually.
//                   Each sprite has a 2-frame stagger via spawn_delay,
//                   and uses fly_in_y[clamped (sp_frame - spawn_delay)]
//                   which encodes the gravity drop + 1 over-shoot bounce
//                   ramp before settling. Total ~32 frames for all 8 to
//                   settle = ~640 ms at 50 Hz.
//   PHASE_BOUNCE → at-target, per-sprite Y wobble derived from
//                   bounce_sine[(sp_frame + phase[i]) & $ff] — gentle
//                   ±2 px breathing.
//   PHASE_FLY_OUT → letters fly up out of frame, FLY_OUT_LEN frames
//                   total. Triggered when zp_beat_count hits
//                   TRANSITION_BEAT - 1.
//==================================================================
update_sprites:
        lda sp_phase
        beq sp_off
        cmp #PHASE_FLY_IN
        bne !skip_in+
        jmp sp_in
!skip_in:
        cmp #PHASE_BOUNCE
        bne !skip_bounce+
        jmp sp_bounce
!skip_bounce:
        cmp #PHASE_FLY_OUT
        bne !skip_out+
        jmp sp_out
!skip_out:
        // PHASE_DONE (or any other value) → no-op so SPARKED doesn't
        // re-fly after the FLY_OUT completes near the transition.
        rts

sp_off:
        // Wait for buildup to arm the drop.
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcc !rts+
        lda #PHASE_FLY_IN
        sta sp_phase
        lda #0
        sta sp_frame
        // X positions + arm all 8 sprites; they'll Y-update in sp_in.
        ldx #0
!xp:    txa
        asl
        tay
        lda spr_x_table,x
        sta SPR_X,y
        inx
        cpx #8
        bne !xp-
        lda #$ff
        sta SPR_EN
!rts:   rts

sp_in:
        // Per sprite: idx = sp_frame - spawn_delay[s]. Clamp to
        // [0, FLY_IN_LEN-1] and look up fly_in_y[idx].
        ldx #0
!loop:  lda sp_frame
        sec
        sbc spawn_delay,x
        bcs !ok+                  // sp_frame < spawn_delay → not spawned yet
        lda #SPR_SPAWN_Y
        jmp !setY+
!ok:    cmp #FLY_IN_LEN
        bcc !inrange+
        lda #SPR_TARGET_Y         // past the table — already settled
        jmp !setY+
!inrange:
        tay
        lda fly_in_y,y
!setY:  pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y               // SPR_X[2N+1] = SPR_Y[N]
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        lda sp_frame
        cmp #(FLY_IN_LEN + 16)    // last letter (spawn_delay max = 14) + table tail
        bcc !rts+
        lda #PHASE_BOUNCE
        sta sp_phase
        lda #5
        sta flash_cnt             // 5 frames of white border flash
        lda #1
        sta silence_cnt           // 1 frame of SID silence on impact
        lda #0
        sta sp_frame
!rts:   // also check: are we close to transition? then go straight to FLY_OUT.
        lda zp_beat_count
        cmp #(TRANSITION_BEAT - 1)
        bcc !nope+
        lda #PHASE_FLY_OUT
        sta sp_phase
        lda #0
        sta sp_frame
!nope:  rts

sp_bounce:
        // Per sprite: Y = SPR_TARGET_Y + bounce_sine[(sp_frame + spawn_delay[s]) & $ff]
        ldx #0
!loop:  lda sp_frame
        clc
        adc spawn_delay,x
        tay
        lda bounce_sine,y
        clc
        adc #SPR_TARGET_Y
        pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        // Hold here until transition is one beat away.
        lda zp_beat_count
        cmp #(TRANSITION_BEAT - 1)
        bcc !rts+
        lda #PHASE_FLY_OUT
        sta sp_phase
        lda #0
        sta sp_frame
!rts:   rts

sp_out:
        // Letters fly UP (Y decreases) — accelerating exit.
        // Y = SPR_TARGET_Y - fly_out_dy[(sp_frame + spawn_delay[s]) clamped]
        ldx #0
!loop:  lda sp_frame
        clc
        adc spawn_delay,x
        cmp #FLY_OUT_LEN
        bcc !inrange+
        lda #FLY_OUT_LEN - 1
!inrange: tay
        lda fly_out_dy,y          // accelerating dy table
        // Y = SPR_TARGET_Y - dy; if Y wraps (negative), park at SPR_SPAWN_Y
        sta zp_tmp
        lda #SPR_TARGET_Y
        sec
        sbc zp_tmp
        bcs !inframe+
        lda #SPR_SPAWN_Y
!inframe: pha
        txa
        asl
        tay
        iny
        pla
        sta SPR_X,y
        inx
        cpx #8
        bne !loop-

        inc sp_frame
        lda sp_frame
        cmp #FLY_OUT_LEN
        bcc !rts+
        // done — disable sprites, sit in PHASE_DONE so update_sprites
        // becomes a no-op until the part ends. Used to fall back to
        // PHASE_OFF, but at that point zp_beat_count is way past
        // BUILDUP_BEAT, so sp_off would immediately re-arm a SECOND
        // fly-in — letters dropped twice before the transition.
        lda #PHASE_DONE
        sta sp_phase
        lda #$00
        sta SPR_EN
!rts:   rts


//==================================================================
// Bar IRQ chain — 6 unrolled handlers
//==================================================================
bar_chain_0:
        lda bar_base_colors+0
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+1
        sta VIC_RASTER
        lda #<bar_chain_1
        sta IRQ_VEC
        lda #>bar_chain_1
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_1:
        lda bar_base_colors+1
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+2
        sta VIC_RASTER
        lda #<bar_chain_2
        sta IRQ_VEC
        lda #>bar_chain_2
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_2:
        lda bar_base_colors+2
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+3
        sta VIC_RASTER
        lda #<bar_chain_3
        sta IRQ_VEC
        lda #>bar_chain_3
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_3:
        lda bar_base_colors+3
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+4
        sta VIC_RASTER
        lda #<bar_chain_4
        sta IRQ_VEC
        lda #>bar_chain_4
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_4:
        lda bar_base_colors+4
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+5
        sta VIC_RASTER
        lda #<bar_chain_5
        sta IRQ_VEC
        lda #>bar_chain_5
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_5:
        lda bar_base_colors+5
        clc
        adc zp_bar_clr_ofs
        and #$0f
        sta VIC_BORDER
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters+6
        sta VIC_RASTER
        lda #<bar_chain_end
        sta IRQ_VEC
        lda #>bar_chain_end
        sta IRQ_VEC+1
        lda #$ff
        sta VIC_IRQ
        rti

bar_chain_end:
        lda #$00
        sta VIC_BORDER
        lda #$ff
        sta VIC_RASTER
        lda #<interrupt
        sta IRQ_VEC
        lda #>interrupt
        sta IRQ_VEC + 1
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// fadeout
//==================================================================

fadeout:
        sec
        rts

//==================================================================
// fire_irq — called every frame during the fire phase (beats >= 16).
// Merged from hush.asm: colour-RAM fire engine with banner text.
// ZP reuse during fire (plasma variables are dormant):
//   $f9 = zp_fire_dst_lo, $fa = zp_fire_dst_hi
//   $fb = zp_fire_src_lo, $fc = zp_fire_src_hi
//   $fd = zp_fire_tmp
//==================================================================

.var zp_fire_dst_lo = $f9
.var zp_fire_dst_hi = $fa
.var zp_fire_src_lo = $fb
.var zp_fire_src_hi = $fc
.var zp_fire_tmp    = $fd

fire_irq:
        // V3 gate stays open; musichook was called before we got here.
        lda #$1f
        sta $d418

        // First frame of fire? Run one-shot init.
        lda fire_did_init
        bne !running+
        jsr fire_init
        inc fire_did_init
        jmp !done+

!running:
        inc zp_fire_frame

        // Transition to greets when fire runs its course.
        lda zp_fire_frame
        cmp #FIRE_DURATION
        bcc !run+
        lda #$30
        sta zp_beat_count          // $F6 = $30 triggers pefchain
        jmp !done+

!run:
        // Banner swap at FIRE_SWAP_FRAME.
        lda zp_fire_frame
        cmp #FIRE_SWAP_FRAME
        bne !no_swap+
        lda fire_swap_flag
        bne !no_swap+
        inc fire_swap_flag
        lda #$01
        sta VIC_BORDER
        ldx #0
!copy:  lda msg_phase2,x
        sta SCREEN + FIRE_MSG_TOP * 40,x
        inx
        cpx #(FIRE_MSG_ROWS * 40)
        bne !copy-
        ldx #0
!c2:    lda #$0e
        sta COL_RAM + FIRE_MSG_TOP * 40,x
        inx
        cpx #(FIRE_MSG_ROWS * 40)
        bne !c2-
!no_swap:
        lda #$00
        sta VIC_BORDER

        // Expose banner to fire at frame 160 — text burns away.
        lda zp_fire_frame
        cmp #160
        bcc !no_expose+
        lda #1
        sta banner_exposed
!no_expose:

        // LP filter close sweep: $70 → $08 over FIRE_DURATION frames.
        lda zp_fire_frame
        eor #$ff
        lsr
        lsr
        clc
        adc #$08
        sta $d416

        // Volume fade from FIRE_FADE_START.
        lda zp_fire_frame
        cmp #FIRE_FADE_START
        bcc !propagate+
        sec
        sbc #FIRE_FADE_START
        lsr
        sta zp_fire_tmp
        lda #$0f
        sec
        sbc zp_fire_tmp
        bpl !vol+
        lda #0
!vol:   ora #$10
        sta $d418

!propagate:
        jsr fire_propagate
        jsr fire_seed

!done:
        lda #$ff
        sta VIC_IRQ
        lda #$ff
        sta VIC_RASTER
        lda #<interrupt
        sta IRQ_VEC
        lda #>interrupt
        sta IRQ_VEC + 1
        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// fire_init — one-shot setup when transitioning from plasma to fire.
//==================================================================
fire_init:
        // Fill screen with $A0 (solid block).
        ldx #0
        lda #$a0
!fa:    sta SCREEN + $000,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $300,x
        inx
        bne !fa-

        // Write phase 1 banner message.
        ldx #0
!fb:    lda msg_phase1,x
        sta SCREEN + FIRE_MSG_TOP * 40,x
        inx
        cpx #(FIRE_MSG_ROWS * 40)
        bne !fb-

        // Clear colour RAM to $00 (cold).
        ldx #0
        lda #$00
!cf:    sta COL_RAM + $000,x
        sta COL_RAM + $100,x
        sta COL_RAM + $200,x
        sta COL_RAM + $300,x
        inx
        bne !cf-

        // Banner rows: dark blue background.
        ldx #0
        lda #$06
!ct:    sta COL_RAM + FIRE_MSG_TOP * 40,x
        inx
        cpx #(FIRE_MSG_ROWS * 40)
        bne !ct-

        // Reset fire state.
        lda #0
        sta zp_fire_frame
        sta fire_swap_flag
        sta banner_exposed

        // Init SID filter for the close sweep.
        lda #$23
        sta $d417
        lda #$70
        sta $d416
        lda #$00
        sta $d415
        lda #$1f
        sta $d418

        // Disable sprites — turn off the SPARKED letters.
        lda #$00
        sta SPR_EN

        // VIC: standard hires text, screen $0400, chargen ROM at $1000.
        lda #$1b
        sta VIC_CTRL1
        lda #$16
        sta VIC_MEM
        lda #$08
        sta VIC_CTRL2
        lda #$00
        sta VIC_BG
        sta VIC_BORDER

        // Init SID noise generator for random seeding.
        lda #$ff
        sta $d40e
        sta $d40f
        lda #$80
        sta $d412

        rts


//==================================================================
// fire_propagate — heat propagation: each row copies from the row
// below, with 1-in-4 stochastic cooling through sbctab. Row
// alternation (even/odd frames) halves per-frame cost.
//==================================================================
fire_propagate:
        lda zp_fire_frame
        and #$01
        tax

!prow:
        lda banner_exposed
        bne !no_guard+
        cpx #FIRE_MSG_TOP
        beq !next_row+
        cpx #(FIRE_MSG_TOP + 1)
        beq !next_row+
        cpx #(FIRE_MSG_TOP + 2)
        beq !next_row+
!no_guard:

        // Destination = colour-RAM row X
        lda fire_row_col_lo,x
        sta zp_fire_dst_lo
        lda fire_row_col_hi,x
        sta zp_fire_dst_hi

        // Source = row X+1, or skip banner for row just below it
        // (only skip when banner is still protected)
        lda banner_exposed
        bne !normal_src+
        cpx #(FIRE_MSG_TOP - 1)
        bne !normal_src+
        ldx #(FIRE_MSG_TOP + FIRE_MSG_ROWS)
        lda fire_row_col_lo,x
        sta zp_fire_src_lo
        lda fire_row_col_hi,x
        sta zp_fire_src_hi
        ldx #(FIRE_MSG_TOP - 1)
        jmp !src_done+
!normal_src:
        inx
        lda fire_row_col_lo,x
        sta zp_fire_src_lo
        lda fire_row_col_hi,x
        sta zp_fire_src_hi
        dex
!src_done:
        txa
        pha

        ldy #39
!pcol:
        lda $d41b
        and #$03
        sta zp_fire_tmp
        lda (zp_fire_src_lo),y
        and #$0f
        ldx zp_fire_tmp
        bne !no_cool+
        tax
        lda fire_sbctab,x
!no_cool:
        sta (zp_fire_dst_lo),y
        dey
        bpl !pcol-

        pla
        tax
!next_row:
        inx
        inx
        cpx #25
        bcc !prow-

        rts


//==================================================================
// fire_seed — seed row 24 with a slowly drifting wave palette.
//==================================================================
fire_seed:
        lda zp_fire_frame
        lsr
        lsr
        sta zp_fire_tmp
        ldx #39
!seed:  txa
        clc
        adc zp_fire_tmp
        and #$0f
        tay
        lda fire_wave_palette,y
        sta COL_RAM + 24 * 40,x
        dex
        bpl !seed-
        rts


//==================================================================
// Tables
//==================================================================

// Wave: two overlaid sines, 0..15
.align 256
wave:
.for (var i = 0; i < 256; i++) {
        .var s1 = 7.5 + 7.5 * sin(i * 2 * PI / 256)
        .var s2 = 7.5 + 7.5 * sin(i * 4 * PI / 256)
        .byte floor((s1 + s2) * 0.5 + 0.5)
}

// 16-entry hue-stable plasma palette: symmetric blue→cyan→white→cyan→blue.
// Matches screenfill's ripple_palette for visual continuity. Each
// plasma index 0..15 maps to a C64 colour; the symmetry means the
// pattern flows back through itself rather than wrapping abruptly.
plasma_palette:
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00

// Row stagger — each row's phase offset in the wave
row_offset:
.for (var r = 0; r < 25; r++) {
        .byte floor(r * 197 / 25) & 255
}

// Row color RAM base addresses (precomputed)
row_cr_lo:
.for (var r = 0; r < 25; r++) {
        .byte <($d800 + r * 40)
}
row_cr_hi:
.for (var r = 0; r < 25; r++) {
        .byte >($d800 + r * 40)
}

// Bar raster positions
bar_rasters:
.byte 32, 72, 112, 152, 192, 232

// Bar base colours (0-15, offset by zp_bar_clr_ofs each beat)
bar_base_colors:
.byte 2, 4, 5, 7, 3, 6

// Work area (in code space, not ZP)
row_base: .byte 0
row_cnt:  .byte 0
flash_cnt: .byte 0
silence_cnt: .byte 0

// Story overlay text — uppercase chargen at $1000, codes $01..$1A
// for letters, $20 for space. 35 chars to fit centered in a 40-col
// row (col 2 .. col 36).
//
// "FOR YEARS NO TIME FOR BREADBIN CODE"
//   F=06 O=0F R=12   sp=20   Y=19 E=05 A=01 R=12 S=13   sp=20
//   N=0E O=0F   sp=20   T=14 I=09 M=0D E=05   sp=20
//   F=06 O=0F R=12   sp=20
//   B=02 R=12 E=05 A=01 D=04 B=02 I=09 N=0E   sp=20
//   C=03 O=0F D=04 E=05
story_line_a:
        .byte $06, $0F, $12, $20             // FOR_
        .byte $19, $05, $01, $12, $13, $20   // YEARS_
        .byte $0E, $0F, $20                  // NO_
        .byte $14, $09, $0D, $05, $20        // TIME_
        .byte $06, $0F, $12, $20             // FOR_
        .byte $02, $12, $05, $01, $04, $02, $09, $0E, $20  // BREADBIN_
        .byte $03, $0F, $04, $05             // CODE

//==================================================================
// Sprite-letter state + tables
//==================================================================

// Phase state — PHASE_OFF / FLY_IN / BOUNCE / FLY_OUT.
sp_phase: .byte 0
sp_frame: .byte 0

// Typewriter state for line A.
line_a_pos:      .byte 0    // chars revealed so far
line_a_tick:     .byte 0    // frame sub-counter
line_a_state:    .byte 0    // LA_TYPING / LA_TYPO / LA_PAUSE / LA_BACKSPACE / LA_RETYPE / LA_DONE
line_a_typo_idx: .byte 0    // index into typo_text / backspace counter
line_a_pause_cnt:.byte 0    // pause countdown

typo_text:
        .byte $0c, $0f, $16, $05   // LOVE (screencodes)

// Horizontal positions for the 8 sprite-letters of "SPARKED ". With
// 8-px spacing the phrase reads centered (trailing blank sprite #7
// is invisible). All values <256 so SPR_MSB stays 0.
spr_x_table:
        .byte 144, 152, 160, 168, 176, 184, 192, 200

// Sprite colours — alternating bright pair stays legible over any
// plasma colour the row-13 area happens to be flowing through.
spr_color_table:
        .byte $01, $0d, $01, $0d, $01, $0d, $01, $0d  // white / light-green

// Per-letter spawn-delay (frames after fly-in start that this letter
// begins dropping). Even spacing reads as a "ripple" of letters
// arriving. 0,2,4,...,14 = 8 letters × 2-frame stagger.
spawn_delay:
        .byte 0, 2, 4, 6, 8, 10, 12, 14

// Fly-in Y table — per-letter idx into this drives Y position during
// PHASE_FLY_IN. 0..15: accelerating drop from Y=0 down to SPR_TARGET_Y;
// 16..23: ~12-px overshoot bounce up then back; 24..31: settled.
.align 32
fly_in_y:
.for (var i = 0; i < 32; i++) {
        .var y = 0
        .if (i < 16) {
                .var t = i / 15.0
                .eval y = floor(SPR_TARGET_Y * t * t)
        } else .if (i < 24) {
                .var bp = (i - 16) / 8.0
                .eval y = floor(SPR_TARGET_Y - 12.0 * sin(bp * PI))
        } else {
                .eval y = SPR_TARGET_Y
        }
        .byte y
}

// Bounce sine — ±3 px wobble around SPR_TARGET_Y during PHASE_BOUNCE.
// Stored as signed 8-bit (negative = $FD..$FF). ADC #SPR_TARGET_Y picks
// up the correct Y mod 256.
.align 256
bounce_sine:
.for (var i = 0; i < 256; i++) {
        .byte round(3 * sin(i * 2 * PI / 256)) & $ff
}

// Fly-out dy — increasing per frame; Y = SPR_TARGET_Y - fly_out_dy[i]
// pushes letters UP off-screen with accelerating velocity.
fly_out_dy:
.for (var i = 0; i < 20; i++) {
        .var t = i / 19.0
        .byte floor(SPR_TARGET_Y * t * t)
}


//==================================================================
// Fire data tables — colour-RAM heat propagation
//==================================================================
fire_row_col_lo:
.for (var r = 0; r < 25; r++) {
        .byte <(COL_RAM + r * 40)
}
fire_row_col_hi:
.for (var r = 0; r < 25; r++) {
        .byte >(COL_RAM + r * 40)
}

// sbctab — colour-index cooling through the fire palette chain.
// Hottest → coldest: $01 → $07 → $08 → $0A → $02 → $09 → $0B → $00.
// Any colour not in the palette falls straight to $00.
fire_sbctab:
        .byte $00  // 00 black → black (coldest)
        .byte $07  // 01 white → yellow
        .byte $09  // 02 red → brown
        .byte $00  // 03 cyan → black
        .byte $00  // 04 purple → black
        .byte $00  // 05 green → black
        .byte $00  // 06 blue → black
        .byte $08  // 07 yellow → orange
        .byte $0A  // 08 orange → lt red
        .byte $0B  // 09 brown → dk grey
        .byte $02  // 0A lt red → red
        .byte $00  // 0B dk grey → black
        .byte $00  // 0C md grey → black
        .byte $00  // 0D lt green → black
        .byte $00  // 0E lt blue → black
        .byte $00  // 0F lt grey → black

// Wave palette: smooth 16-step gradient for seeding row 24.
fire_wave_palette:
        .byte $00, $0B, $09, $02, $0A, $08, $07, $01
        .byte $01, $07, $08, $0A, $02, $09, $0B, $00

// Phase 1 banner (frames 0-119): "THE MACHINE WAS NOT EMPTY"
// Three rows: solid top band, carved text, solid bottom band.
// $A0 = inverse space (solid block). Inverted PETSCII = $80 + screencode.
msg_phase1:
        .fill 40, $A0
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .byte $94, $88, $85, $A0          // T H E
        .byte $8D, $81, $83, $88, $89, $8E, $85, $A0  // M A C H I N E
        .byte $97, $81, $93, $A0          // W A S
        .byte $8E, $8F, $94, $A0          // N O T
        .byte $85, $8D, $90, $94, $99     // E M P T Y
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .fill 40, $A0

// Phase 2 banner (frames 120+): "THE SPARK CAME BACK"
msg_phase2:
        .fill 40, $A0
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .byte $94, $88, $85, $A0          // T H E
        .byte $93, $90, $81, $92, $8B, $A0// S P A R K
        .byte $83, $81, $8D, $85, $A0     // C A M E
        .byte $82, $81, $83, $8B          // B A C K
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .fill 40, $A0

fire_did_init:  .byte 0
fire_swap_flag: .byte 0
banner_exposed: .byte 0


//==================================================================
// Sprite shape data — 8 sprites × 64 bytes at $2000..$21FF.
// Block pointers $80..$87 in screen RAM at $07F8..$07FF select these.
// Each glyph is the C64 Set A uppercase chargen byte stamped into the
// middle of the top 8 rows of a 21-row sprite (8-px-wide letter, 8-px
// margin left + 8-px margin right within the 24-px-wide sprite).
//==================================================================

* = $2000 "SpriteShapes"
.var chargen = LoadBinary("../greets/chargen.bin")
.var phrase_chars = List().add($13, $10, $01, $12, $0B, $05, $04, $20)
                                          //   S    P    A    R    K    E    D    _

.function letter_sprite(code) {
        .var r = List()
        .var base = code * 8
        .for (var row = 0; row < 21; row++) {
                .if (row < 8) {
                        .eval r.add(0)
                        .eval r.add(chargen.get(base + row))
                        .eval r.add(0)
                } else {
                        .eval r.add(0)
                        .eval r.add(0)
                        .eval r.add(0)
                }
        }
        .eval r.add(0)
        .return r
}

.for (var i = 0; i < 8; i++) {
        .var s = letter_sprite(phrase_chars.get(i))
        .for (var b = 0; b < 64; b++) {
                .byte s.get(b)
        }
}
