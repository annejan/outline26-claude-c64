//==================================================================
// outline-64 — Hush: color-RAM fire (sauhir / mikkoparviainen style).
//
// Standard hires text mode. Every fire cell shows char $A0 (the
// inverse-space solid block) and the cell's COLOUR is the heat
// level — propagated by indexing through a fire palette chain via
// sbctab. Result: full-cell solid colour blocks with a smooth
// white→yellow→orange→red→brown→black gradient. No 4×4 multicolour
// dither, no half-cell boundaries, no custom charset.
//
// Palette chain (decrement order, hottest → coldest):
//   $01 white → $07 yellow → $08 orange → $0A lt red →
//   $02 red   → $09 brown  → $0B dk grey → $00 black
//
// Manifesto text rides in standard chargen ROM glyphs at rows 10-11
// (and the phase 2 swap still works) — multicolour mode is off, so
// text just renders with whatever colour is in colour RAM.
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021
.const VIC_SPR_EN = $d015
.const SCREEN     = $0400
.const COL_RAM    = $d800
.const SID_VOL    = $d418
.const SID_FILT_CUT_LO = $d415
.const SID_FILT_CUT_HI = $d416
.const SID_FILT_CTRL   = $d417
.const FIRST_LINE = $32
.const N_FRAMES   = 250
.const FADE_START = 200
.const SWAP_FRAME = 120
.const MSG_TOP    = 10            // 3-row banner spans rows 10-12
.const MSG_ROWS   = 3             // top band + text + bottom band
.const FIRE_TOP   = 0             // fire fills the whole screen
.const FIRE_BOT   = 24
.const INTRO_MUSIC_PLAY = $119e

.const zp_timer  = $f6
.const zp_frame  = $f7
.const zp_line   = $f8
.const zp_dst_lo = $f9
.const zp_dst_hi = $fa
.const zp_ptr    = $fb            // 2-byte ptr at $fb/$fc

* = $0800 "Hush"

setup:
        sei
        lda #$01
        sta zp_timer              // drum gate ON (non-$30, non-$00) →
                                  // K-S-K-S kit keeps hammering through
                                  // hush instead of the silent breakdown
        lda #0
        sta zp_frame
        sta swap_flag
        sta VIC_SPR_EN

        // ---- Screen RAM: $A0 (solid block) everywhere, manifesto
        // text overlaid on rows 10-11 ----
        ldx #0
        lda #$a0
!fa:    sta SCREEN + $000,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $300,x
        inx
        bne !fa-

        ldx #0
!fb:    lda msg_phase1,x
        sta SCREEN + MSG_TOP * 40,x
        inx
        cpx #(MSG_ROWS * 40)
        bne !fb-

        // ---- Colour RAM: all $00 (black = cold) initially ----
        ldx #0
        lda #$00
!cf:    sta COL_RAM + $000,x
        sta COL_RAM + $100,x
        sta COL_RAM + $200,x
        sta COL_RAM + $300,x
        inx
        bne !cf-

        // Manifesto rows: cool blue against the warm fire palette.
        // Phase 1 (accusation) = $06 dark blue. Inverted glyphs render
        // as blue rectangles with the text cut out — readable from
        // anywhere on the screen even through the flames.
        ldx #0
        lda #$06
!ct:    sta COL_RAM + MSG_TOP * 40,x
        inx
        cpx #(MSG_ROWS * 40)
        bne !ct-

        // ---- SID + filter init ----
        lda #$1f
        sta SID_VOL
        lda #$23
        sta SID_FILT_CTRL
        lda #$70
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        // ---- VIC config ----
        lda #$1b                  // DEN + 25 rows, yscroll 3 (standard text)
        sta VIC_CTRL1
        lda #$16                  // screen $0400 + chargen ROM set B
        sta VIC_MEM
        lda #$08                  // hires text mode, 40-col (no MC!)
        sta VIC_CTRL2
        lda #$00
        sta VIC_BG
        sta VIC_BORDER

        // Init SID noise generator for random seeding
        lda #$ff
        sta $d40e                 // V3 freq lo
        sta $d40f                 // V3 freq hi
        lda #$80
        sta $d412                 // V3 noise waveform, gate off

        lda VIC_CTRL1
        and #%01111111
        sta VIC_CTRL1
        lda #FIRST_LINE - 1
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN

        cli
        rts

fadeout:
        sec
        rts

interrupt:
musichook:
        .byte $2c, $00, $00       // → JSR INTRO_MUSIC_PLAY (pefchain patch)
        lda #$1f
        sta SID_VOL
        inc zp_frame

        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        jmp !ack+

!run:
        // ---- Phase 2 swap at frame 120 ----
        lda zp_frame
        cmp #SWAP_FRAME
        bne !no_swap+
        lda swap_flag
        bne !no_swap+
        inc swap_flag
        lda #$01
        sta VIC_BORDER            // 1-frame white border flash
        ldx #0
!copy:  lda msg_phase2,x
        sta SCREEN + MSG_TOP * 40,x
        inx
        cpx #(MSG_ROWS * 40)
        bne !copy-
        // Phase 2 colour: $0E light blue (hope / opposite)
        ldx #0
        lda #$0e
!c2:    sta COL_RAM + MSG_TOP * 40,x
        inx
        cpx #(MSG_ROWS * 40)
        bne !c2-

!no_swap:
        lda #$00
        sta VIC_BORDER

        // ---- LP filter cutoff close: $70 → $08 over 250 frames ----
        lda zp_frame
        eor #$ff
        lsr
        lsr
        clc
        adc #$08
        sta SID_FILT_CUT_HI

        // ---- Volume fade from frame 200 ----
        lda zp_frame
        cmp #FADE_START
        bcs !do_fade+
        jmp !propagate+
!do_fade:
        sec
        sbc #FADE_START
        lsr
        sta zp_dst_lo
        lda #$0f
        sec
        sbc zp_dst_lo
        bpl !vol+
        lda #0
!vol:   ora #$10
        sta SID_VOL

!propagate:
        // ---- Heat propagation: row alternation per frame ----
        // Frame parity selects which rows update: even frames process
        // rows 0,2,4..22; odd frames 1,3,5..23. Halves per-frame
        // propagation cost to ~11000 cy so music_play ticks at a
        // clean 50 Hz (no more drift during hush). Each row updates
        // every 2 frames = 25 fps effective fire animation.
        // The seed below STILL runs every frame so the wave drift
        // and source flicker stay at 50 Hz.
        // Msg rows (MSG_TOP, MSG_TOP+1) are SKIPPED so the locked
        // text colour stays uncorrupted by the propagating fire.
        lda zp_frame
        and #$01
        tax                        // X = starting row (0 even / 1 odd)
!prow:
        // Skip the 3 banner rows (MSG_TOP..MSG_TOP+MSG_ROWS-1 = 10-12).
        // Row 9 (MSG_TOP-1) sources from row 13 (MSG_TOP+MSG_ROWS),
        // skipping over the banner so fire keeps climbing past it.
        cpx #MSG_TOP
        beq !next_row+
        cpx #(MSG_TOP + 1)
        beq !next_row+
        cpx #(MSG_TOP + 2)
        beq !next_row+

        // Destination is always row X
        lda row_col_lo,x
        sta zp_ptr
        lda row_col_hi,x
        sta zp_ptr + 1

        // Source row: normally X+1, but for X = MSG_TOP-1 it's
        // MSG_TOP+MSG_ROWS (skip the msg box).
        cpx #(MSG_TOP - 1)
        bne !normal_src+
        ldx #(MSG_TOP + MSG_ROWS)
        lda row_col_lo,x
        sta zp_dst_lo
        lda row_col_hi,x
        sta zp_dst_hi
        ldx #(MSG_TOP - 1)
        jmp !src_done+
!normal_src:
        inx
        lda row_col_lo,x
        sta zp_dst_lo
        lda row_col_hi,x
        sta zp_dst_hi
        dex
!src_done:
        txa
        pha

        ldy #39
!pcol:
        lda $d41b                  // SID random
        and #$03                   // 4 outcomes (0..3)
        sta zp_line                // save dice
        lda (zp_dst_lo),y          // load heat
        and #$0f
        ldx zp_line
        bne !no_cool+              // 3/4 chance: keep current heat
        tax                        // 1/4 chance: cool via sbctab
        lda sbctab,x
!no_cool:
        sta (zp_ptr),y
        dey
        bpl !pcol-

        pla
        tax
!next_row:
        inx
        inx                        // skip the other-parity row
        cpx #FIRE_BOT
        bcc !prow-                 // bcc not bne — loop while < 24

        // ---- Seed row 24 with a SLOWLY DRIFTING SMOOTH WAVE ----
        // wave_palette has a smooth gradient (each step = 1 palette
        // entry). Indexed by (col + zp_frame>>2) → drift 1 col per 4
        // frames. NO SID jitter at the source — the wave provides all
        // variation, cohesive flame shapes emerge.
        lda zp_frame
        lsr
        lsr
        sta zp_line                // wave phase
        ldx #39
!seed:
        txa
        clc
        adc zp_line
        and #$0f
        tay
        lda wave_palette,y
        sta COL_RAM + FIRE_BOT * 40,x
        dex
        bpl !seed-


!ack:
        lda #$ff
        sta VIC_IRQ
        rti

//==================================================================
// Tables
//==================================================================

// Pseudo-random noise — 256 bytes used for per-row source shift.
noise_tab:
.for (var i = 0; i < 256; i++) {
        .byte ((i * 73 + 113) ^ (i << 3) ^ (i >> 1)) & $ff
}

// Colour-RAM row base addresses for rows 0..25 (25 + sentinel).
row_col_lo:
.for (var r = 0; r < 26; r++) {
        .byte <(COL_RAM + r * 40)
}
row_col_hi:
.for (var r = 0; r < 26; r++) {
        .byte >(COL_RAM + r * 40)
}

// Wave palette: 16-entry SMOOTH gradient (one palette step per entry,
// up then down then up). Adjacent cells differ by exactly one heat
// level → cohesive flame shapes when the wave drifts sideways.
wave_palette:
        .byte $00, $0B, $09, $02, $0A, $08, $07, $01
        .byte $01, $07, $08, $0A, $02, $09, $0B, $00

// sbctab — decrement a colour through the fire palette chain.
// Hottest → coldest: $01 → $07 → $08 → $0A → $02 → $09 → $0B → $00.
// Anything off-palette goes straight to $00 (heat dies).
sbctab:
.for (var v = 0; v < 256; v++) {
        .var c = $00
        .if (v == $01) { .eval c = $07 }
        .if (v == $07) { .eval c = $08 }
        .if (v == $08) { .eval c = $0a }
        .if (v == $0a) { .eval c = $02 }
        .if (v == $02) { .eval c = $09 }
        .if (v == $09) { .eval c = $0b }
        .if (v == $0b) { .eval c = $00 }
        .byte c
}

// msg_phase{1,2} — 3-row banner: solid blue top band + carved text
// middle row + solid blue bottom band. $A0 is inverse space (full
// 8×8 colour block); inverted letters ($80 + screencode) are solid
// blocks with the glyph cut out so light fire can shine through.
//
// Phase 1 (frames 0-119):
//   row 10: ████████████████████████████████████████   (top band)
//   row 11:        THE MACHINE WAS NOT EMPTY           (carved text)
//   row 12: ████████████████████████████████████████   (bottom band)
msg_phase1:
        .fill 40, $A0
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .byte $D4, $C8, $C5, $A0
        .byte $CD, $C1, $C3, $C8, $C9, $CE, $C5, $A0
        .byte $D7, $C1, $D3, $A0
        .byte $CE, $CF, $D4, $A0
        .byte $C5, $CD, $D0, $D4, $D9
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .fill 40, $A0

// Phase 2 (frames 120-249):
//   row 10: ████████████████████████████████████████   (top band)
//   row 11:           THE SPARK CAME BACK              (carved text)
//   row 12: ████████████████████████████████████████   (bottom band)
msg_phase2:
        .fill 40, $A0
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .byte $D4, $C8, $C5, $A0
        .byte $D3, $D0, $C1, $D2, $CB, $A0
        .byte $C3, $C1, $CD, $C5, $A0
        .byte $C2, $C1, $C3, $CB
        .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
        .fill 40, $A0

swap_flag:      .byte 0
