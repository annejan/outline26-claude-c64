//==================================================================
// outline-64 — Coda: title card hold between greets' scroller and
// the end credit roll.
//
// Narrative role: the breather where the story lands. Greets has
// said its piece via the DYCP scroller; the credits are about to
// roll. Between them, the title sits centered on a quiet screen
// for ~10 seconds while the resident chord progression drifts on.
//
// Visuals (deliberately minimal — no custom font, no sprites):
//   row 11  KLOOT AND THE BREADBIN          (chargen ROM uppercase)
//   row 13  BY DEFEEST   FOR X 2026
//   border  slow sine colour cycle through col_tab
//   bg      stays black
//
// Music: jsr INTRO_MUSIC_PLAY each frame. Drums silent because
// setup zeros $F6 (the gating byte for percussion in my_music_play)
// — the title sits quiet, then the credit roll music takes over.
//
// Transition: after N_FRAMES ticks (~10 s) the IRQ writes $F6 = $30
// and pefchain advances to end.
//
// Memory:
//   $0800-$0AFF  code + col_tab (overlays sinus's old footprint —
//                sinus is no longer resident, so we can reuse)
//   $1000-$125D  intro music tables (inherited via 'I' tag)
//==================================================================

.const VIC_CTRL1  = $d011
.const VIC_RASTER = $d012
.const VIC_CTRL2  = $d016
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

.const SCREEN     = $0400
.const COL_RAM    = $d800

.const SID_VOL    = $d418

.const N_FRAMES   = 250               // ~10 s at the half-rate divider
                                      // (250 ticks @ 25 Hz)

.const INTRO_MUSIC_PLAY = $119e

.const zp_timer    = $f6              // transition: set to $30 to trigger pefchain
.const zp_subtick  = $fb              // half-rate divider toggle
.const zp_frame    = $fc              // animation tick (0..N_FRAMES-1)
                                      // Avoid $f9/$fa — intro's my_music_play
                                      // clobbers them every JSR.


* = $0800 "Coda"


//==================================================================
// setup
//==================================================================
setup:
        lda #0
        sta zp_timer
        sta zp_subtick
        sta zp_frame

        // Sprites off (greets had 8 enabled)
        sta $d015

        // VIC: text mode, ROM chargen $1000 (uppercase), screen $0400.
        lda #$1b                        // DEN=1, RSEL=1, YSCROLL=3
        sta VIC_CTRL1
        lda #$14                        // screen $0400, chargen $1000
        sta VIC_MEM
        lda #$08                        // CSEL=1, no MCM
        sta VIC_CTRL2

        // Clear $D011 bit 7 so raster compare lands on visible scanlines.
        lda VIC_CTRL1
        and #%01111111
        sta VIC_CTRL1

        // Border + bg black to start (border cycles per frame).
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        // Clear screen RAM to space ($20).
        lda #$20
        ldx #0
!clr:   sta SCREEN + $000,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $2e8,x
        inx
        bne !clr-

        // ---- paint the title text ----
        // Row 11 starts at $0400 + 11*40 = $05B8.
        // "KLOOT AND THE BREADBIN" = 22 chars, center at col 9.
        // Row 13 ($0608): "BY DEFEEST   FOR X 2026" = 23 chars, col 8.
        ldx #0
!t1:    lda title_main,x
        sta $05B8 + 9,x
        inx
        cpx #22
        bne !t1-

        ldx #0
!t2:    lda title_sub,x
        sta $0608 + 8,x
        inx
        cpx #23
        bne !t2-

        // ---- colour the title rows ----
        // Title row: white. Sub row: light grey. Everything else: $0E.
        // Colour RAM row 11 starts at $D800 + 11*40 = $D9B8.
        // Row 13: $DA08.
        ldx #0
        lda #$01                        // white
!c1:    sta $D9B8 + 9,x
        inx
        cpx #22
        bne !c1-

        ldx #0
        lda #$0f                        // light grey
!c2:    sta $DA08 + 8,x
        inx
        cpx #23
        bne !c2-

        // Settle SID: drums OFF (zp_timer = $00 gates the percussion
        // in intro's my_music_play). Vol restored to max.
        lda #$1f
        sta SID_VOL

        // Raster IRQ at top of visible area.
        lda #$32                        // line 50
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN

        rts


//==================================================================
// fadeout — no-op, transition is triggered from interrupt.
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// interrupt — per-frame raster IRQ.
//
// Per frame:
//   - jsr INTRO_MUSIC_PLAY (drums silent because $F6 = 0)
//   - half-rate tick: zp_frame only advances every 2nd IRQ
//   - if zp_frame >= N_FRAMES, set $F6 = $30 (transition)
//   - else border = col_tab[zp_frame] for slow sine colour cycle
//==================================================================
interrupt:
        jsr INTRO_MUSIC_PLAY

        // half-rate divider — same pattern as sinus would use
        lda zp_subtick
        eor #1
        sta zp_subtick
        bne !skip_inc+
        inc zp_frame
!skip_inc:

        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        lda #$00
        sta VIC_BORDER                  // settle to black before transition
        jmp !ack+

!run:
        ldy zp_frame
        lda col_tab,y
        sta VIC_BORDER

!ack:
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// title text — uppercase chargen at $1000, screencodes $01..$1A
// for A..Z, $20 for space.
//
// "KLOOT AND THE BREADBIN"
//   K=0B L=0C O=0F O=0F T=14 _=20
//   A=01 N=0E D=04 _=20
//   T=14 H=08 E=05 _=20
//   B=02 R=12 E=05 A=01 D=04 B=02 I=09 N=0E
//==================================================================
title_main:
        .byte $0B, $0C, $0F, $0F, $14, $20    // KLOOT_
        .byte $01, $0E, $04, $20              // AND_
        .byte $14, $08, $05, $20              // THE_
        .byte $02, $12, $05, $01, $04, $02, $09, $0E    // BREADBIN

// "BY DEFEEST   FOR X 2026"  (23 chars)
//   B=02 Y=19 _=20  D=04 E=05 F=06 E=05 E=05 S=13 T=14 _=20 _=20 _=20
//   F=06 O=0F R=12 _=20  X=18 _=20  2=32 0=30 2=32 6=36
title_sub:
        .byte $02, $19, $20                                 // BY_
        .byte $04, $05, $06, $05, $05, $13, $14, $20        // DEFEEST_
        .byte $20, $20                                       // __
        .byte $06, $0F, $12, $20                            // FOR_
        .byte $18, $20                                       // X_
        .byte $32, $30, $32, $36                            // 2026


//==================================================================
// Border colour table — 256-entry slow sine through a calm palette
// (mostly blues / cyans, no harsh contrasts — this is the breather).
//==================================================================
.align 256
col_tab:
.for (var i = 0; i < 256; i++) {
        // 4-step low-saturation palette indexed by sine phase.
        // Bands: $00 black / $06 blue / $0E light-blue / $0F light-grey.
        .var s = floor(2 + 1.99 * sin(i * 2 * PI / 256))   // 0..3
        .if (s == 0) { .byte $00 }
        .if (s == 1) { .byte $06 }
        .if (s == 2) { .byte $0e }
        .if (s == 3) { .byte $0f }
}
