//==================================================================
// outline-64 — Sinus part: sine-displaced char-mode display with
// colour cycling.
//
// Narrative role: visual comedown after greets' kick climax. The
// inherited intro chords drift through with LP filter closing, while
// a screen of 256 characters sways under per-scanline $D016 sine
// wobble. Colour cycling on border + bg adds movement.
//
// After ~5 seconds the visual fades out and $f6 = $30 triggers the
// pefchain transition to end.
//
// Music arc:
//   Phase 1 (0-4s):  LP filter closes, at ~full wobble
//   Phase 2 (4-5s):  fade colours + volume toward black
//
// Memory:
//   $0800-$0XXX  code + tables
//   $1000-$125D  intro music tables (inherited)
//   $2000-$27FF  charset (2 KB, 256 chars × 8 bytes)
//   $0400-$07FF  screen RAM
//
// Transition: after N_FRAMES sets $f6 = $30 → pefchain advances.
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
.const CHARSET    = $2000

.const SID_VOL    = $d418
.const SID_FILT_CUT_LO = $d415
.const SID_FILT_CUT_HI = $d416
.const SID_FILT_CTRL   = $d417

.const FIRST_LINE = $32               // 50 — first visible scanline
.const N_LINES    = 200               // visible scanlines per frame
.const N_FRAMES   = 250               // ~5 seconds @ 50 Hz (keep < 256)

.const FADE_START = 200               // frame at which fade begins

.const INTRO_MUSIC_PLAY = $119e

.const zp_line   = $f8                // current scanline (0-199)
.const zp_frame  = $f9                // frame counter (0..N_FRAMES-1)
.const zp_timer  = $f6                // transition: set to $30 to trigger pefchain
.const zp_tmp    = $f7                // temporary


* = $0800 "Sinus"


//==================================================================
// setup
//==================================================================
setup:
        lda #0
        sta zp_timer
        sta zp_line
        sta zp_frame

        // Fill screen RAM with char indices: alternating columns
        // to make the $D016 wobble visible.
        ldx #0
!lp_s:  txa
        and #$01                       // 0,1,0,1,... per column
        sta SCREEN,x
        sta SCREEN + 40,x
        sta SCREEN + 80,x
        sta SCREEN + 120,x
        sta SCREEN + 160,x
        sta SCREEN + 200,x
        sta SCREEN + 240,x
        sta SCREEN + 280,x
        sta SCREEN + 320,x
        sta SCREEN + 360,x
        sta SCREEN + 400,x
        sta SCREEN + 440,x
        sta SCREEN + 480,x
        sta SCREEN + 520,x
        sta SCREEN + 560,x
        inx
        cpx #40
        bne !lp_s-

        // Fill colour RAM
        ldx #0
        lda #$01
!lp_c:  sta COL_RAM,x
        sta COL_RAM + 250,x
        sta COL_RAM + 500,x
        sta COL_RAM + 750,x
        inx
        cpx #250
        bne !lp_c-

        // Build charset: char 0 = vertical stripe (even cols white, odd black)
        // Char 1 = vertical stripe opposite (even cols black, odd white)
        // This creates a vertical stripe pattern that wobbles horizontally.
        ldy #0
        // Char 0: %11,%00,%11,%00 = white, black, white, black
!ch0:   lda #$c0                       // %11000000
        sta CHARSET,y
        lda #$30                       // %00110000  (shifted by 2)
        sta CHARSET + 1,y
        lda #$0c                       // %00001100
        sta CHARSET + 2,y
        lda #$03                       // %00000011
        sta CHARSET + 3,y
        // Char 1: %00,%11,%00,%11 = black, white, black, white
        lda #$00
        sta CHARSET + 4,y
        lda #$c0
        sta CHARSET + 5,y
        lda #$30
        sta CHARSET + 6,y
        lda #$0c
        sta CHARSET + 7,y

        iny                             // next group of 8 bytes
        cpy #$0800 / 8
        bne !ch0-

        // Init SID — LP filter mode + volume
        lda #$1f
        sta SID_VOL
        lda #$10                        // LP filter mode bit
        sta SID_FILT_CTRL
        lda #$70                        // mid filter cutoff
        sta SID_FILT_CUT_HI
        lda #$00
        sta SID_FILT_CUT_LO

        // Multicolour character mode
        lda #$1b                        // DEN=1, RSEL=1, YSCROLL=3
        sta VIC_CTRL1
        lda #$18                        // screen $0400, charset $2000
        sta VIC_MEM
        lda #$c8                        // MCM=1, CSEL=1, xscroll=0
        sta VIC_CTRL2
        lda #$00
        sta VIC_BORDER
        sta VIC_BG

        lda #$1b
        sta VIC_CTRL1

        // Raster IRQ at top of visible area
        lda #FIRST_LINE - 1
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN

        rts


//==================================================================
// fadeout
//==================================================================
fadeout:
        sec
        rts


//==================================================================
// interrupt / irq_top — fires at FIRST_LINE-1. Calls music once per
// frame, updates filter sweep + fade state, resets scanline counter,
// and points IRQ vector to irq_sine.
//==================================================================
interrupt:
irq_top:
        jsr INTRO_MUSIC_PLAY

        lda #0
        sta zp_line
        inc zp_frame

        // Transition timer: after N_FRAMES, set $f6 = $30
        lda zp_frame
        cmp #N_FRAMES
        bcc !run+
        lda #$30
        sta zp_timer
        jmp !post+

!run:
        // LP filter closes over duration: $70 → $08
        eor #$ff
        lsr
        lsr
        clc
        adc #$08
        sta SID_FILT_CUT_HI

        // Fade volume in last 50 frames: volume = $0f - (progress>>1)
        lda zp_frame
        cmp #FADE_START
        bcc !post+

        sec
        sbc #FADE_START
        lsr
        sta zp_tmp
        lda #$0f
        sec
        sbc zp_tmp
        bpl !vol+
        lda #0
!vol:   ora #$10
        sta SID_VOL

!post:
        lda #<irq_sine
        sta $fffe
        lda #>irq_sine
        sta $ffff

        lda #FIRST_LINE
        sta VIC_RASTER
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// irq_sine — fires at each visible scanline. Writes $D016 fine
// scroll and border/bg colour from tables.
//==================================================================
irq_sine:
        ldy zp_line

        ldx zp_frame
        cpx #FADE_START
        bcs !fade+

        // Normal zone — wobble + colour sweep
        lda sine_tab,y
        sta VIC_CTRL2
        lda col_tab,y
        sta VIC_BORDER
        lda bg_tab,y
        sta VIC_BG
        jmp !next+

!fade:
        // Fade zone — black everything
        lda #0
        sta VIC_CTRL2
        sta VIC_BORDER
        sta VIC_BG

!next:
        iny
        sty zp_line
        cpy #N_LINES
        beq !last+

        tya
        clc
        adc #FIRST_LINE
        sta VIC_RASTER
        jmp !ack+

!last:
        lda #<irq_top
        sta $fffe
        lda #>irq_top
        sta $ffff
        lda #FIRST_LINE - 1
        sta VIC_RASTER

!ack:
        lda #$ff
        sta VIC_IRQ
        rti


//==================================================================
// Sine table — 256 entries, range 0-7 for $D016 fine scroll.
//==================================================================
.align 256
sine_tab:
.for (var i = 0; i < 256; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 2 * PI / 256))
}


//==================================================================
// Border colour table.
//==================================================================
.align 256
col_tab:
.for (var i = 0; i < N_LINES; i++) {
        .byte floor(3.5 + 3.5 * sin(i * 4 * PI / 200))
}


//==================================================================
// Background colour table.
//==================================================================
.align 256
bg_tab:
.for (var i = 0; i < N_LINES; i++) {
        .byte floor(4.5 + 3.5 * sin(i * 3 * PI / 200 + 0.5))
}
