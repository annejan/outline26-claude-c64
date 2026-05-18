//==================================================================
// EFO2 header for coda.pef.
//==================================================================

.import source "coda.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word $0000              // callmusic

        // Code + col_tab fit in 3 pages: code at $0800-$09xx, col_tab
        // at $0A00 (256 bytes). Reuses the area sinus claimed earlier
        // — by the time coda loads, sinus is long gone.
        .byte 'P', $08, $0A
        // Inherit intro's resident music tables.
        .byte 'I', $10, $12
        // Zero-page: $f6 (timer / transition), $fb (subtick), $fc (frame).
        // MUST avoid $f9/$fa — intro's my_music_play clobbers them every
        // call as its own zp_tmp/zp_msb.
        .byte 'Z', $f6, $fc
        // I/O safe.
        .byte 'S'
        .byte $00
