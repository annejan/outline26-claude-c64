//==================================================================
// EFO2 header for greets.pef.
//==================================================================

.import source "greets.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000                // prepare
        .word setup                // setup
        .word interrupt            // interrupt
        .word $0000                // main
        .word fadeout              // fadeout
        .word $0000                // cleanup
        .word $0000                // callmusic

        // Owned pages:
        //   $08-$0F = sprite font shapes (32 glyphs × 64 B = 2 KB,
        //             relocated from $2000 to free up the bitmap region)
        //   $20-$3F = koala bitmap data (8 KB at $2000-$3F3F)
        //   $80-$9F = code + state + tables + message + inline font +
        //             koala colour-RAM buffer + koala screen-RAM buffer
        //             (expanded from $80-$8F because font_data + the
        //             koala buffers push past $9000)
        //
        // Screen RAM ($0400-$07E7) is NOT claimed here even though
        // bitmap-mode greets writes to it — leaving $04-$07 unowned
        // lets pefchain's blank-filler effects (which paint a flat
        // screen during load gaps) use those pages. greets' setup
        // CPU-copies koala screen attrs from a buffer in $9x to $0400
        // at boot, so the data arrives via greets' own code rather
        // than via a pefchain page-load.
        .byte 'P', $08, $0F
        .byte 'P', $20, $3F
        .byte 'P', $80, $9F
        // Inherit intro's music tables ($10-$12)
        .byte 'I', $10, $12
        // Zero-page: $f4-$fa (kick state machine + shadow freq)
        .byte 'Z', $f4, $fa
        // I/O safe
        .byte 'S'
        .byte $00
