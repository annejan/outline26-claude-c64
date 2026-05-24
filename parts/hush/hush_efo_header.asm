//==================================================================
// EFO2 header for hush.pef.
//==================================================================

.import source "hush.sym"

.pc = $0000 "EfoHeader"
        .text "EFO2"
        .word $0000              // prepare
        .word setup              // setup
        .word interrupt          // interrupt
        .word $0000              // main
        .word fadeout            // fadeout
        .word $0000              // cleanup
        .word musichook          // callmusic — see interlude EFO header

        // Code + tables span $0800-$0Bxx (~4 pages). Hires text mode,
        // no custom charset — VIC reads chargen ROM set B at $1800.
        .byte 'P', $08, $0B
        // Inherit intro's music tables
        .byte 'I', $10, $12
        // Zero-page: $f6-timer/transition, $f7-tmp, $fb-line, $fc-frame.
        // We MUST avoid $f9/$fa — intro's my_music_play clobbers them every
        // call as its own zp_tmp/zp_msb, so any counter stored there gets
        // overwritten on each frame's JSR INTRO_MUSIC_PLAY.
        .byte 'Z', $f6, $fc
        // I/O safe
        .byte 'S'
        .byte $00
