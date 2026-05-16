//==================================================================
// outline-64 — clean: open borders + 4 visible sprites + scroller
//
// No bars. Focus on the sprites being PRESENT (no Y-wraparound
// blink) and the scroll being smooth.
//
// Sprite blink fix: sprites 0,1 disabled at line $f9 and re-enabled
// at line $01. Their Y-wraparound duplicates (at raster Y+256) fall
// between those lines, where SPR_EN says they're off.
//==================================================================

.const SPR_X        = $d000
.const SPR_Y        = $d001
.const SPR_MSB      = $d010
.const VIC_CTRL1    = $d011
.const VIC_RASTER   = $d012
.const SPR_EN       = $d015
.const SPR_YEXP     = $d017
.const VIC_CTRL2    = $d016
.const SPR_MC       = $d01c
.const SPR_XEXP     = $d01d
.const VIC_BORDER   = $d020
.const VIC_BG       = $d021
.const SPR_COL      = $d027

.const SCREEN       = $0400
.const COLOUR_RAM   = $d800
.const SPR_PTRS     = $07f8
.const SPR_DATA     = $2000
.const SPR_BLOCK    = SPR_DATA / 64

.const SCROLL_ROW   = 4
.const SCROLL_SCR   = SCREEN + SCROLL_ROW * 40
.const SCROLL_COL   = COLOUR_RAM + SCROLL_ROW * 40

// Zero-page
.const zp_text_ptr  = $fb
.const zp_smooth    = $fd
.const zp_frame     = $fe

BasicUpstart2(start)

.pc = $0810 "Main"
start:
        sei
        lda #$35
        sta $01

        lda #$7f
        sta $dc0d
        sta $dd0d
        bit $dc0d
        bit $dd0d

        jsr clear_screen
        jsr init_sprites
        jsr init_scroll

        // clear the VIC garbage byte
        lda #0
        sta $3fff

        lda #$06
        sta VIC_BORDER          // blue border
        lda #$00
        sta VIC_BG              // black bg

        lda VIC_CTRL1
        and #$7f
        ora #$1b
        sta VIC_CTRL1

        // 38-col mode for smooth scroll edges (CSEL=0)
        lda #$00
        sta VIC_CTRL2

        // raster IRQ chain
        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER
        lda #$01
        sta $d01a
        lda #$ff
        sta $d019

        cli

forever:
        jmp forever


//==================================================================
clear_screen:
        ldx #0
        lda #$20
!loop:  sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne !loop-
        lda #$01
!loop:  sta COLOUR_RAM+$000,x
        sta COLOUR_RAM+$100,x
        sta COLOUR_RAM+$200,x
        sta COLOUR_RAM+$300,x
        inx
        bne !loop-
        rts


//==================================================================
init_sprites:
        ldx #63
!loop:  lda sprite_shape,x
        sta SPR_DATA,x
        dex
        bpl !loop-

        lda #SPR_BLOCK
        sta SPR_PTRS+0
        sta SPR_PTRS+1
        sta SPR_PTRS+2
        sta SPR_PTRS+3

        lda #%00001111
        sta SPR_EN
        sta SPR_XEXP
        sta SPR_YEXP            // round balls
        lda #0
        sta SPR_MC

        lda #$01                // white
        sta SPR_COL+0
        lda #$03                // cyan
        sta SPR_COL+1
        lda #$07                // yellow
        sta SPR_COL+2
        lda #$05                // green
        sta SPR_COL+3
        rts


//==================================================================
init_scroll:
        ldx #0
!fill:  lda scroll_text,x
        sta SCROLL_SCR,x
        inx
        cpx #40
        bne !fill-

        lda #<(scroll_text + 40)
        sta zp_text_ptr
        lda #>(scroll_text + 40)
        sta zp_text_ptr+1

        lda #7
        sta zp_smooth
        lda #0
        sta zp_frame

        ldx #0
!col:   lda #$03                // cyan
        sta SCROLL_COL,x
        inx
        cpx #40
        bne !col-
        rts


//==================================================================
// irq_close — line $f9. Toggle 24-row mode (border opens),
// DISABLE sprites 0+1 (their Y-wraparound duplicates fire between
// here and line $01 of next frame — keep them off).
//==================================================================
irq_close:
        pha
        lda #$ff
        sta $d019
        lda #$13                // 24-row, DEN
        sta VIC_CTRL1
        lda #%00001100          // sprites 2, 3 only
        sta SPR_EN
        lda #<irq_open
        sta $fffe
        lda #>irq_open
        sta $ffff
        lda #$01
        sta VIC_RASTER
        pla
        rti


//==================================================================
// irq_open — line $01. Restore 25-row, RE-ENABLE all sprites,
// do scroll & sprite motion.
//==================================================================
irq_open:
        pha
        txa
        pha
        tya
        pha

        lda #$ff
        sta $d019
        lda #$1b                // 25-row, DEN
        sta VIC_CTRL1
        lda #%00001111          // all 4 sprites on
        sta SPR_EN

        jsr do_scroll
        lda zp_smooth
        sta VIC_CTRL2           // X-scroll (CSEL=0)
        jsr move_sprites

        lda #<irq_close
        sta $fffe
        lda #>irq_close
        sta $ffff
        lda #$f9
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// move_sprites — each ball bounces in its own zone via sine.
//   sprite 0: TOP border, narrow Y range (Y stays in 14..30
//             so it's safely visible at top of rendered area)
//   sprite 1: TOP border, narrow Y range, different phase
//   sprite 2: BOTTOM border, narrow Y range (≤ $f4)
//   sprite 3: BOTTOM border, narrow Y range, different phase
//
// Y-wraparound: for sprites at Y < 56, the comparator also fires
// at raster Y+256 (in lower part of rendered frame). We hide that
// duplicate by disabling sprites 0+1 in irq_close. Sprites 2 and 3
// at Y > 200 have their duplicate at Y+256 > 311 — past the PAL
// frame end — so they don't need disabling.
//==================================================================
move_sprites:
        // sprite 0
        lda zp_frame
        clc
        adc #0
        tay
        lda sine_x,y
        sta SPR_X+0
        lda zp_frame
        tay
        lda sine_top,y
        sta SPR_Y+0

        // sprite 1
        lda zp_frame
        clc
        adc #64
        tay
        lda sine_x,y
        sta SPR_X+2
        lda zp_frame
        clc
        adc #128
        tay
        lda sine_top,y
        sta SPR_Y+2

        // sprite 2
        lda zp_frame
        clc
        adc #128
        tay
        lda sine_x,y
        sta SPR_X+4
        lda zp_frame
        clc
        adc #64
        tay
        lda sine_bot,y
        sta SPR_Y+4

        // sprite 3
        lda zp_frame
        clc
        adc #192
        tay
        lda sine_x,y
        sta SPR_X+6
        lda zp_frame
        clc
        adc #192
        tay
        lda sine_bot,y
        sta SPR_Y+6

        lda #0
        sta SPR_MSB
        rts


//==================================================================
do_scroll:
        inc zp_frame
        dec zp_smooth
        bpl !done+

        lda #7
        sta zp_smooth

        ldx #0
!shift: lda SCROLL_SCR + 1, x
        sta SCROLL_SCR, x
        inx
        cpx #39
        bne !shift-

        ldy #0
!next:  lda (zp_text_ptr),y
        cmp #$ff
        bne !place+
        lda #<scroll_text
        sta zp_text_ptr
        lda #>scroll_text
        sta zp_text_ptr+1
        jmp !next-
!place: sta SCROLL_SCR + 39
        inc zp_text_ptr
        bne !done+
        inc zp_text_ptr+1
!done:  rts


//==================================================================
// Data
//==================================================================

// Sprite X sine — swings 50..200, no MSB needed (X < 256)
.align 256
sine_x:
        .fill 256, 50 + round(75 * (1 + sin(toRadians(i * 360 / 256))))

// Sprite Y for top-border sprites — range 14..30
// (14 = top of rendered area, 30 = safe inside top border zone)
.align 256
sine_top:
        .fill 256, 14 + round(8 * (1 - cos(toRadians(i * 360 / 256))))

// Sprite Y for bottom-border sprites — range 226..240
// (226 = past bar area, 240 = ≤ $f4 so safely before the Y > $f7
// sprite display quirk)
.align 256
sine_bot:
        .fill 256, 226 + round(7 * (1 - cos(toRadians(i * 360 / 256))))


// pre-pad with 40 spaces so text scrolls IN from the right
.encoding "screencode_upper"
scroll_text:
        .text "                                        "
        .text "HELLO FROM OUTLINE 64! "
        .text "THIS IS A MINIMAL OPEN-BORDER DEMO WITH FOUR SPRITES AND A SMOOTH-SCROLLING MESSAGE. "
        .text "THE TOP/BOTTOM BORDERS ARE OPENED USING THE CANONICAL HCL POLLING TRICK FROM CODEBASE64. "
        .text "TWO WHITE/CYAN BALLS LIVE IN THE OPENED TOP BORDER, AND TWO YELLOW/GREEN BALLS DOWN BELOW IN THE OPENED BOTTOM BORDER. "
        .text "                                        "
        .byte $ff


sprite_shape:
        .byte %00000001, %11111000, %00000000
        .byte %00000111, %11111110, %00000000
        .byte %00001111, %11111111, %00000000
        .byte %00011111, %11111111, %10000000
        .byte %00111111, %11111111, %11000000
        .byte %00111111, %11111111, %11000000
        .byte %01111111, %11111111, %11100000
        .byte %01111111, %11111111, %11100000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %11111111, %11111111, %11110000
        .byte %01111111, %11111111, %11100000
        .byte %01111111, %11111111, %11100000
        .byte %00111111, %11111111, %11000000
        .byte %00111111, %11111111, %11000000
        .byte %00011111, %11111111, %10000000
        .byte %00001111, %11111111, %00000000
        .byte %00000111, %11111110, %00000000
        .byte %00000001, %11111000, %00000000
        .byte 0
