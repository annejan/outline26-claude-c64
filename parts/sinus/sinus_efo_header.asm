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

        // Code + tables span $0800-$0CFF (5 pages: code at $0800-$09xx,
        // sine_tab at $0A00, col_tab at $0B00, bg_tab at $0C00). DROPPED
        // the $20-$27 charset claim — sinus now uses chargen ROM at
        // $1000, no custom charset needed.
        .byte 'P', $08, $0C
        // Inherit intro's music tables
        .byte 'I', $10, $12
        // Zero-page: $f6 (timer/transition), $f8-line, $f9-frame
        .byte 'Z', $f5, $f9
        // I/O safe
        .byte 'S'
        .byte $00
