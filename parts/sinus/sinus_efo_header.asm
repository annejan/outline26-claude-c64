//==================================================================
// EFO2 header for sinus.pef.
//==================================================================

.import source "sinus.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Code at $08, charset at $20-$27
        .byte 'P', $08, $08
        .byte 'P', $20, $27
        // Inherit intro's music tables
        .byte 'I', $10, $12
        // Zero-page: $f6 (timer/transition), $f8-line, $f9-frame
        .byte 'Z', $f6, $f9
        // I/O safe
        .byte 'S'
        .byte $00
