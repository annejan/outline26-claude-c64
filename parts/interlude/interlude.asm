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
.const IRQ_VEC    = $fffe

.const INTRO_MUSIC_PLAY = $119e

.const BEAT_PERIOD   = 24
.const BUILDUP_BEAT  = 24
.const FILT_CUT_LO   = $40
.const FILT_CUT_STEP = $18

.const zp_beat_phase = $f4
.const zp_filt_cut   = $f5
.const zp_beat_count = $f6
.const zp_plasma_phs = $f7
.const zp_plasma_tgl = $f8
.const zp_bar_clr_ofs= $f9
.const zp_wave_phs   = $fa
.const zp_tmp        = $fc

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

        lda #$1f
        sta $d418
        lda #$00
        sta $d404
        sta $d416
        sta $d417

        lda #0
        sta zp_beat_phase
        sta zp_beat_count
        sta zp_filt_cut
        sta zp_plasma_phs
        sta zp_plasma_tgl
        sta zp_bar_clr_ofs

        // clear screen to space
        ldx #0
        lda #$20
!clr:   sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne !clr-

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

        // vsync IRQ
        lda #$ff
        sta VIC_RASTER
        rts


//==================================================================
// write_plasma_row — write 40 cells (packed as 20 bytes) to color RAM
//   X = row index 0..24
//==================================================================
write_plasma_row:
        lda zp_plasma_phs
        clc
        adc row_offset,x
        sta zp_wave_phs

        lda row_cr_lo,x
        sta smc+1
        lda row_cr_hi,x
        sta smc+2

        ldx #0
!lp:    ldy zp_wave_phs
        lda wave,y
        asl
        asl
        asl
        asl
        sta zp_tmp
        iny
        lda wave,y
        and #$0f
        ora zp_tmp
smc:    sta $d800,x
        inx
        inc zp_wave_phs
        inc zp_wave_phs
        cpx #20
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

        jsr INTRO_MUSIC_PLAY
        lda #$1f
        sta $d418

        // V1 mute / build-up
        lda zp_beat_count
        cmp #BUILDUP_BEAT
        bcs !buildup+
        lda #$00
        sta $d404
        jmp !beat+
!buildup:
        lda #$01
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

        // plasma — advance phase, update half the rows
        inc zp_plasma_phs

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
        jsr write_plasma_row
        inx
        inx
        dec row_cnt
        bne !row_lp-

        inc zp_plasma_tgl

        // chain to first bar IRQ
        lda #$1b
        sta VIC_CTRL1
        lda bar_rasters
        sta VIC_RASTER
        lda #<bar_chain_0
        sta IRQ_VEC
        lda #>bar_chain_0
        sta IRQ_VEC + 1

        pla
        tay
        pla
        tax
        pla
        rti


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
