//==================================================================
// EFO2 header for intro.pef. Built with `-binfile`, then concatenated
// with intro.prg to produce intro.efo.
//
// `setup`, `irq_close`, `fadeout` symbols come from intro.sym.
//==================================================================

.import source "intro.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"             // magic
        .word $0000              // prepare
        .word setup              // setup
        .word irq_close          // interrupt (first link in raster chain)
        .word $0000              // intro
        .word fadeout            // fadeout (silences SID, returns C=1)
        .word $0000              // cleanup
        .word $0000              // callmusic (music driven from IRQ chain)

        // Memory pages used by intro:
        //   $04-$09 BitmapScreenRAM ($0400-$09f1)
        //   $0B     Sprite shape
        //   $10-$12 Music
        //   $20-$3F Bitmap
        //   $40-$48 Tables (bounce_total is page-aligned at $4800)
        //   $4C-$53 Chargen-ROM copy (built at runtime in copy_chargen)
        //   $54-$5D BmpScroll (scroll_text at $5C00, sprite_shape at $5D62)
        .byte 'P', $04, $09
        .byte 'P', $0B, $0B
        .byte 'P', $10, $12
        .byte 'P', $20, $3F
        .byte 'P', $40, $48
        .byte 'P', $4C, $53
        .byte 'P', $54, $5D
        // Zero-page: $f5..$fe
        .byte 'Z', $f5, $fe
        // I/O safe (interrupts leave $01 at $35)
        .byte 'S'
        // Install my_music_play at $119E as the global play routine.
        // pefchain will then auto-rewrite the `bit !0` placeholders
        // in every later part's EFO callmusic slot to `jsr $119E` at
        // link time. The auto-inserted "blank" parts that pefchain
        // schedules between effects also call this routine, so SID
        // music keeps ticking during the load gaps that used to drop
        // out for ~0.5 s at every transition.
        .byte 'M', $9e, $11
        .byte $00                // end of tags
