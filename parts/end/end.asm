//==================================================================
// outline-64 — Part 3: credit roll
//
// Loaded after main's outro via `jsr $c90 / jmp $3800`. Overwrites
// main's now-dead bitmap area ($2000-$3F3F): custom 8x8 font goes to
// $3000 (charset RAM in VIC bank 0), code follows at $3800.
//
// Layout:
//   $3000-$37FF  custom font (256 glyphs × 8 bytes, mostly zero;
//                only the chars used by credit_text are populated)
//   $3800-….     end code, IRQs, scroll state, credit text + tables
//
// Visual: 38-column text mode. Credit text scrolls up 1 px / frame
// (yscroll bits 0-2) with a 24-row block-move every 8 frames pulling
// the next line in at row 24. The 8-px side strips (CSEL=0 extended
// border) and top/bottom borders show a rainbow rasterbar via per-
// line $d020 polling in the chained IRQ. Loops on the credit text.
//==================================================================

.const SCREEN     = $0400
.const FONT       = $3000
.const COLRAM     = $d800
.const VIC_CTRL1  = $d011        // DEN, RSEL, BMM, ECM, yscroll bits 0-2
.const VIC_RASTER = $d012
.const SPR_EN     = $d015
.const VIC_CTRL2  = $d016        // RES, MCM, CSEL, xscroll bits 0-2
.const VIC_MEM    = $d018
.const VIC_IRQ    = $d019
.const VIC_IRQEN  = $d01a
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

.const zp_yscroll  = $f7         // current $d011 yscroll value, decrements each frame from 7→0 then wraps
.const zp_text_row = $f8         // index into credit_text (advances on hardware-scroll wrap)
.const zp_frame    = $f9         // free-running frame counter (for bar palette drift)
.const zp_tmp      = $fa

.const N_CREDIT_ROWS = 36        // KEEP IN SYNC with the .text blocks below
.const BAR_TOP       = $32       // first display line; bars run BAR_TOP..BAR_BOT
.const BAR_BOT       = $f8


//==================================================================
// font_data — custom 8×8 charset at $3000. Each char takes 8 bytes
// at offset (char_code × 8). screencode_mixed: lowercase a-z at
// $01-$1A, uppercase A-Z at $41-$5A, digits 0-9 at $30-$39, space
// $20, '.' $2E, ',' $2C, ':' $3A, '!' $21, '-' $2D. We only fill
// the codes credit_text actually uses; everything else stays $00.
//==================================================================
.pc = FONT "Font"

// $00 — unused
        .fill 8, 0

// $01 'a'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %00000110
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $02 'b'
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11111100
        .byte %00000000
// $03 'c'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %01111110
        .byte %00000000
// $04 'd'
        .byte %00000110
        .byte %00000110
        .byte %01111110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $05 'e'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %11000110
        .byte %11111110
        .byte %11000000
        .byte %01111110
        .byte %00000000
// $06 'f'
        .byte %00011110
        .byte %00110000
        .byte %01111100
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
// $07 'g'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %01111100
        .byte %00000000
// $08 'h'
        .byte %11000000
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $09 'i'
        .byte %00011000
        .byte %00000000
        .byte %00111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00111100
        .byte %00000000
// $0a 'j'
        .byte %00001100
        .byte %00000000
        .byte %00011100
        .byte %00001100
        .byte %00001100
        .byte %01101100
        .byte %00111000
        .byte %00000000
// $0b 'k'
        .byte %11000000
        .byte %11000000
        .byte %11001110
        .byte %11011100
        .byte %11110000
        .byte %11011100
        .byte %11001110
        .byte %00000000
// $0c 'l'
        .byte %00111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00111100
        .byte %00000000
// $0d 'm'
        .byte %00000000
        .byte %00000000
        .byte %11101100
        .byte %11111110
        .byte %11010110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $0e 'n'
        .byte %00000000
        .byte %00000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %00000000
// $0f 'o'
        .byte %00000000
        .byte %00000000
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $10 'p'
        .byte %00000000
        .byte %00000000
        .byte %11111100
        .byte %11000110
        .byte %11111100
        .byte %11000000
        .byte %11000000
        .byte %00000000
// $11 'q'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %00000110
        .byte %00000000
// $12 'r'
        .byte %00000000
        .byte %00000000
        .byte %11011100
        .byte %11100110
        .byte %11000000
        .byte %11000000
        .byte %11000000
        .byte %00000000
// $13 's'
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %11000000
        .byte %01111100
        .byte %00000110
        .byte %11111100
        .byte %00000000
// $14 't'
        .byte %00110000
        .byte %00110000
        .byte %11111100
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00011100
        .byte %00000000
// $15 'u'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000000
// $16 'v'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11000110
        .byte %01101100
        .byte %00111000
        .byte %00000000
// $17 'w'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %11010110
        .byte %11111110
        .byte %01101100
        .byte %00000000
// $18 'x'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %01101100
        .byte %00111000
        .byte %01101100
        .byte %11000110
        .byte %00000000
// $19 'y'
        .byte %00000000
        .byte %00000000
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %01111100
        .byte %00000000
// $1a 'z'
        .byte %00000000
        .byte %00000000
        .byte %11111110
        .byte %00001100
        .byte %00011000
        .byte %00110000
        .byte %11111110
        .byte %00000000

// $1b..$1f — gap to space ($20)
        .fill 8 * (5), 0

// $20 ' '
        .fill 8, 0
// $21 '!'
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
        .byte %00110000
        .byte %00000000

// $22..$2b — unused gap
        .fill 8 * 10, 0

// $2c ','
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00110000
        .byte %00110000
        .byte %01100000
// $2d '-'
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %01111110
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
// $2e '.'
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000

// $2f — unused
        .fill 8, 0

// $30 '0'
        .byte %01111100
        .byte %11000110
        .byte %11001110
        .byte %11010110
        .byte %11100110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $31 '1'
        .byte %00111000
        .byte %01111000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %01111110
        .byte %00000000
// $32 '2'
        .byte %01111100
        .byte %11000110
        .byte %00000110
        .byte %00011100
        .byte %00110000
        .byte %01100000
        .byte %11111110
        .byte %00000000
// $33 '3'
        .byte %01111100
        .byte %11000110
        .byte %00000110
        .byte %00111100
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $34 '4'
        .byte %00001100
        .byte %00011100
        .byte %00111100
        .byte %01101100
        .byte %11111110
        .byte %00001100
        .byte %00001100
        .byte %00000000
// $35 '5'
        .byte %11111110
        .byte %11000000
        .byte %11111100
        .byte %00000110
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $36 '6'
        .byte %01111100
        .byte %11000110
        .byte %11000000
        .byte %11111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $37 '7'
        .byte %11111110
        .byte %00000110
        .byte %00001100
        .byte %00011000
        .byte %00110000
        .byte %00110000
        .byte %00110000
        .byte %00000000
// $38 '8'
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111100
        .byte %00000000
// $39 '9'
        .byte %01111100
        .byte %11000110
        .byte %11000110
        .byte %01111110
        .byte %00000110
        .byte %11000110
        .byte %01111100
        .byte %00000000

// $3a ':'
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000
        .byte %00000000
        .byte %01100000
        .byte %01100000
        .byte %00000000

// $3b..$ff — rest unused, zero fill up to $3800
        .fill (FONT + $800) - *, 0


//==================================================================
// End code at $3800. Entry: start.
//==================================================================
.pc = $3800 "End"

start:
        sei
        lda #$35
        sta $01

        // VIC bank 0 ($3c → $0000-$3FFF).
        lda #$3c
        sta $dd02

        // Screen $0400, charset $3000 → $d018 = (1<<4) | (6<<1) = $1c.
        lda #%00011100
        sta VIC_MEM

        // Text mode, DEN, RSEL, yscroll=7 (will animate).
        lda #$1f
        sta VIC_CTRL1
        sta zp_yscroll
        // 38-column mode (CSEL=0): the 8-px left/right strips become
        // extended border, which the bar IRQ then rainbows.
        lda #$00
        sta VIC_CTRL2

        lda #$00
        sta VIC_BG              // bg black (under text)
        sta VIC_BORDER          // border starts black (per-line bars overwrite)
        sta SPR_EN              // sprites off
        sta $d418               // silence SID (master vol = 0)

        // Clear screen to space ($20) and colour RAM to white.
        ldx #0
        lda #$20
!cs:    sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x       // last partial page → $06e8..$07e7
        inx
        bne !cs-
        ldx #0
        lda #$01
!cc:    sta COLRAM+$000,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne !cc-

        // Init scroll state and prime row 24 with the first credit line.
        lda #0
        sta zp_text_row
        sta zp_frame
        jsr push_next_credit_row

        // Raster IRQ chain: irq_top@$00 (yscroll + maybe row-shift),
        // then irq_bars@$32..$f8 for the side rainbow.
        lda #<irq_top
        sta $fffe
        lda #>irq_top
        sta $ffff
        lda #$00
        sta VIC_RASTER
        lda #$01
        sta VIC_IRQEN
        lda #$ff
        sta VIC_IRQ
        cli

forever:
        jmp forever


//==================================================================
// irq_top — fires at raster $00. Tick yscroll down; on wrap, do a
// hardware-scroll row-up and pull a fresh credit line into row 24.
// Then chain to irq_bars at line $32.
//==================================================================
irq_top:
        pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        inc zp_frame

        // yscroll = (yscroll - 1). At 0, wrap to 7 and trigger hardware scroll.
        lda zp_yscroll
        sec
        sbc #1
        bpl !no_wrap+
        // Wrap path: scroll text rows up by 1, pull next credit line.
        jsr scroll_rows_up
        jsr push_next_credit_row
        lda #7
!no_wrap:
        sta zp_yscroll

        // Compose $d011: DEN=1, RSEL=1, BMM=0, ECM=0 → $18 plus yscroll.
        ora #$18
        sta VIC_CTRL1

        // Chain to bar IRQ.
        lda #<irq_bars
        sta $fffe
        lda #>irq_bars
        sta $ffff
        lda #BAR_TOP
        sta VIC_RASTER

        pla
        tay
        pla
        tax
        pla
        rti


//==================================================================
// irq_bars — fires at line BAR_TOP. Tight per-line $d020 write loop
// from BAR_TOP to BAR_BOT, indexing a 256-byte palette by raster +
// zp_frame so the bars drift downward over time. Chains back to
// irq_top at line $00.
//==================================================================
irq_bars:
        pha
        tya
        pha
        lda #$ff
        sta VIC_IRQ

        // Self-modify lda's lo byte to shift palette per frame.
        lda zp_frame
        lsr                      // /2 for slower drift
        sta bar_lda+1

        // 18-cy loop: ldy raster (4), lda pal,y (4), sta $d020 (4),
        // cpy #bot (2), bcc (3) = 17. Fits within badline budget.
!loop:  ldy VIC_RASTER           // 4
bar_lda:
        lda bar_palette,y        // 4
        sta VIC_BORDER           // 4
        cpy #BAR_BOT             // 2
        bcc !loop-               // 3

        lda #$00
        sta VIC_BORDER           // restore black border for safety

        // Chain back to top.
        lda #<irq_top
        sta $fffe
        lda #>irq_top
        sta $ffff
        lda #$00
        sta VIC_RASTER

        pla
        tay
        pla
        rti


//==================================================================
// scroll_rows_up — shift rows 1..24 of SCREEN up into 0..23. Row 24
// is overwritten immediately after by push_next_credit_row. Done in
// ROW-MAJOR order (full row 0 first, then row 1, …) so each row's
// 40-byte write completes before VIC reads it for display.
//
// Timing (called from irq_top at line $00):
//   - Per-row inner: ldy #39 + 40×(lda/sta/dey/bpl) ≈ 561 cy ≈ 9 lines
//   - Row K destination written by line ~9(K+1)
//   - VIC reads row K at line 50 + 8K
//   - margin = 50 + 8K − (9K + 9) = 41 − K  (positive for K ≤ 23 ✓)
//
// Total ~13.5k cy (~213 lines) so the chained bar IRQ doesn't start
// until ~line $D5 on shift frames — a brief 30-line strip at the
// bottom is the only rainbow on those frames. Acceptable trade-off
// to keep the text itself tear-free.
//==================================================================
scroll_rows_up:
        .for (var r = 0; r < 24; r++) {
            ldy #39
        !l: lda SCREEN + (r+1)*40, y
            sta SCREEN +    r *40, y
            dey
            bpl !l-
        }
        rts


//==================================================================
// push_next_credit_row — copy 40 chars from credit_text[zp_text_row]
// into screen row 24, then advance zp_text_row (wrapping at
// N_CREDIT_ROWS for an infinite loop).
//==================================================================
push_next_credit_row:
        ldx zp_text_row
        lda row_ptr_lo,x
        sta !src+ + 1
        lda row_ptr_hi,x
        sta !src+ + 2
        ldy #39
!src:   lda $1234,y               // self-modified above to credit_text + row*40
        sta SCREEN + 24*40, y
        dey
        bpl !src-

        inc zp_text_row
        lda zp_text_row
        cmp #N_CREDIT_ROWS
        bcc !ok+
        lda #0                    // wrap → loop credit roll forever
!ok:    sta zp_text_row
        rts


//==================================================================
// bar_palette — 256-byte rainbow indexed by raster line (low byte).
// Built from a smooth 32-entry blue→cyan→white→cyan→blue ramp,
// repeated 8 times so any raster value lands inside the table.
//==================================================================
.align 256
bar_palette:
.for (var rep = 0; rep < 8; rep++) {
        .byte $00, $06, $06, $0e, $0e, $03, $03, $01
        .byte $01, $03, $03, $0e, $0e, $06, $06, $00
        .byte $00, $02, $02, $0a, $0a, $07, $07, $01
        .byte $01, $07, $07, $0a, $0a, $02, $02, $00
}


//==================================================================
// credit_text — N_CREDIT_ROWS rows × 40 chars each (space-padded
// via the row() macro). Update N_CREDIT_ROWS at the top when adding
// or removing lines. Renders in lowercase via screencode_mixed so
// the font's $01-$1A slots cover everything.
//==================================================================
.encoding "screencode_mixed"

.macro row(s) {
        .text s
        .fill 40 - s.size(), $20
}

credit_text:
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("              defeest presents          ")
        row("                                        ")
        row("              outline 2026 demo         ")
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("           code                         ")
        row("              anne jan brouwer          ")
        row("              claude opus 4.7           ")
        row("                                        ")
        row("           music                        ")
        row("              hand-written 3-voice sid  ")
        row("                                        ")
        row("           graphics                     ")
        row("              defeest.nl                ")
        row("                                        ")
        row("           tools                        ")
        row("              kickassembler             ")
        row("              spindle 2.3               ")
        row("              vice x64sc                ")
        row("                                        ")
        row("           greetings                    ")
        row("              outline 2026 crew         ")
        row("              codebase64                ")
        row("              linus akesson             ")
        row("              mads nielsen              ")
        row("                                        ")
        row("                                        ")
        row("              thanks for watching       ")
        row("                                        ")
        row("                                        ")
        row("                                        ")
        row("                                        ")

// Per-row pointer tables — KA evaluates these at assembly time so we
// avoid a runtime row×40 multiply.
row_ptr_lo:
.for (var r = 0; r < N_CREDIT_ROWS; r++) {
        .byte <(credit_text + r * 40)
}
row_ptr_hi:
.for (var r = 0; r < N_CREDIT_ROWS; r++) {
        .byte >(credit_text + r * 40)
}
