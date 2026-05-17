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
        //   $20-$23 = sprite font shapes (overlay intro's bitmap area)
        //   $80-$83 = code + state + tables
        .byte 'P', $20, $23
        .byte 'P', $80, $83
        // Inherit intro's music tables ($10-$12) — we call my_music_play.
        .byte 'I', $10, $12
        // Zero-page: $f4 (beat_phase), $f6 (beat_count)
        .byte 'Z', $f4, $f6
        // I/O safe
        .byte 'S'
        .byte $00
