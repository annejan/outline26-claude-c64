//==================================================================
// outline-64 — Part 3: end ("to be continued..." placeholder)
//
// Loaded into $c000 by main's jsr $c90 + jmp $c000 after the outro
// completes. Overwrites the dead screenfill region; main's code at
// $0810 is untouched so the jmp $c000 instruction survives.
//
// Minimal: clear screen, drop a centered text line, halt. Replace
// later with credits / next scene / whatever.
//==================================================================

.const SCREEN     = $0400
.const COLRAM     = $d800
.const VIC_BORDER = $d020
.const VIC_BG     = $d021

.encoding "screencode_mixed"

* = $c000 "End"
start:
        sei
        lda #$35
        sta $01

        // VIC bank 0, screen $0400, chargen ROM at $1800 (mixed case
        // so we can spell "to be continued..." in lowercase).
        lda #$3c
        sta $dd02
        lda #%00010110
        sta $d018

        // Text mode (BMM=0), DEN, RSEL, yscroll=3.
        lda #$1b
        sta $d011
        // CSEL, no x-scroll, mono text (MCM=0).
        lda #$08
        sta $d016

        lda #$00
        sta VIC_BORDER          // border black
        sta VIC_BG              // bg black
        sta $d015               // sprites off
        sta $d418               // master volume = 0 (silence)

        // Clear screen to space ($20 in screencode_mixed).
        ldx #0
        lda #$20
!c1:    sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x       // last partial page covers $06e8..$07e7
        inx
        bne !c1-

        // Colour RAM → light blue.
        ldx #0
        lda #$0e
!c2:    sta COLRAM+$000,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne !c2-

        // Drop message centered on row 12.
        // X starts at length-1; sta uses (base + (40-len)/2) + X to land
        // the trailing char in the right column.
        ldx #(msg_end - msg - 1)
!w:     lda msg,x
        sta SCREEN + 12*40 + (40 - (msg_end - msg))/2, x
        dex
        bpl !w-

forever:
        jmp forever

msg:
        .text "to be continued..."
msg_end:
