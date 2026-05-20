# Sound arc — how music flows across the seven parts

## TL;DR

Intro owns the music. Its **tables and play routine stay resident in
RAM** for the rest of the demo (intro EFO claims `'P', $10, $12`; every
subsequent part declares `'I', $10, $12` so pefchain doesn't overwrite
them). Interlude, sinus, greets, and coda all call into intro's
`my_music_play` at `$119E` from their per-frame IRQ, so the chord
progression + lead + arp drift through six of the seven parts with no
discontinuity. End is the exception — it runs its own `end_music_init`
+ player for the credit-roll reprise.

The interesting parts are the **per-part SID register management
overlays** on top of that continuous music.

## The arc

| Part        | What you hear                                                       |
|-------------|---------------------------------------------------------------------|
| screenfill  | (silence — SID untouched, music engine isn't running yet)           |
| intro       | Bass + lead + arp build in. Drums kick in late (when `zp_outro != 0` — intro's outro animation starts, ~20 s in). K-S-K-S backbeat: V3 paints kick (triangle pitch slam) and snare (low-noise + triangle body) alternating on the quarter; V1 bass-bleeds N_C1 (~33 Hz) sub under both. |
| interlude   | Pad-only first ~1.6 s (V1 muted, line A "FOR YEARS…" typewriter reveals). Last 2.4 s buildup: V1 returns, LP cutoff ramps up with **V1 + V2 both routed through the filter** (res $2) so the bass AND lead open up together, sprite-letter "AI WROTE" drops, drums continue from intro. |
| sinus       | **Breakdown.** LP filter closes — and now actually closes audibly because V1 + V2 are routed through it ($D417 = $23, res $2). Cutoff ramps $70 → $08 over the duration; vol fades over the last 50 frames. Drums silent (sinus zeros `$F6 = zp_outro` — the gating byte). The eye of the storm before the drop. |
| greets      | **Climax / drop.** Drums return (greets' setup re-arms `$F6`), full mix + lead + arp. V2 (lead) routed through LP filter ($D417 = $42, res $4) with a slow cutoff "wah" — `zp_wobble_pos` OR'd with $40 ramps $40..$FF over 5 s breathing the melody. DYCP scroller tells the personal arc on top of the loudest moment. |
| coda        | **Aftermath.** Intro's drums silenced again (coda's setup zeros `$F6`), but coda *owns* V3 for the whole part — overrides the arp every IRQ with its own hard-restart kick on a ~60 BPM cadence. Chord pad + lead drift on V1/V2 under a sparser, slower thump than greets. Title card sits quietly while the music breathes out. |
| end         | `end_music_init` re-inits SID for slow chord/lead reprise. PWM + filter sweep. No drums. The credit-roll outro. |

## Why my_music_play is special

It runs on **every** part from intro onward via the inherited address
`$119E`. That means decisions baked into `my_music_play` propagate to
every part that calls it. The most important one:

```kickass
// in my_music_play
lda zp_intro                ; counter that saturates at $FF in intro
lsr / lsr / lsr             ; vol = intro >> 3 (caps at $1F)
cmp #$10
bcc !vin_ok+
lda #$0F                    ; clamp to $0F (max SID vol)
!vin_ok:
sta $D418                   ; SID master volume
```

**Critical pitfall** (we've shipped this bug already, don't redo it):
There used to be a `vol_out = zp_outro >> 3` subtraction before the
`sta $D418`, intended to fade the master volume out during intro's
outro animation. The problem: `zp_outro` saturates at `$F0` and stays
there for the rest of the demo. So once intro's outro completes:

- `vol_in - vol_out = $0F - $0F = 0` → SID muted
- Interlude and greets both call `my_music_play` every frame → both
  silently muted, every frame
- Interlude's `setup` writes `$D418 = $1F` once, then the first
  `my_music_play` call wipes it back to 0

If you ever need an audio fade-out, do it **outside** `my_music_play`
and gate it on a counter that ONLY ticks in the relevant part. Don't
modify shared resident code with global side effects.

## The $D418 filter-mode contract

`$D418` packs two unrelated things:

| Bits | Meaning                                            |
|------|----------------------------------------------------|
| 0-3  | Master volume (0-15)                               |
| 4    | LP filter mode                                     |
| 5    | BP filter mode                                     |
| 6    | HP filter mode                                     |
| 7    | Cut V3 to output (V3 muted if set)                 |

`my_music_play` writes a vol-only value (bits 4-7 = 0). So any part
that needs LP/BP/HP mode active must **re-write `$D418` after the
`jsr INTRO_MUSIC_PLAY` call, every frame**:

```kickass
jsr INTRO_MUSIC_PLAY
lda #$1F                ; LP mode (bit 4) + vol 15
sta $D418
```

See `parts/interlude/interlude.asm` — its build-up filter sweep relies
on LP mode being asserted every frame.

## Drums in `my_music_play`

Percussion lives inside intro's `my_music_play` and propagates to
every later part that calls it (interlude / greets — sinus and coda
also call it, but their setups zero `$F6` so the resident drum gate
stays closed there. Coda then layers its OWN V3 kick on top, owning
the voice for the entire part).

### K-S-K-S kit (since 2026-05-20)

The original "single rumble" kick has been replaced by a two-drum
kit walked from a 16-byte table (`drum_table` at the end of intro's
music segment). Both drums share the same DRUM_LEN=4 window, the
same V1 sub-bass layer, and the same gate-on-throughout / peak-ADSR
pattern — the character difference is the V3 voicing.

```
drum_table:
    ; KICK rows (offset 0) — pure triangle pitch slam, no noise.
    .byte $11, $10   ; triangle, ~250 Hz
    .byte $11, $04   ; ~62 Hz
    .byte $11, $02   ; ~30 Hz sub
    .byte $11, $02   ; hold sub
    ; SNARE rows (offset 8) — low-noise transient + triangle body.
    .byte $81, $20   ; low noise, ~500 Hz
    .byte $11, $10   ; triangle, ~250 Hz
    .byte $11, $05   ; ~80 Hz
    .byte $11, $03   ; ~50 Hz
```

Architecture:

```kickass
; --- DRUM trigger (at step boundary, every 4th step = ~125 BPM) ---
lda zp_outro
beq !drum_done+       ; drums gated: only fire if zp_outro != 0
lda mu_step
and #$03
bne !drum_done+

; Pick kick (offset 0) or snare (offset 8): bit 2 of mu_step splits
; even/odd quarters, ASL'd to byte-offset into the 16-byte table.
lda mu_step
and #$04
asl
sta drum_offset

lda #DRUM_LEN
sta drum_state

; V1 BASS-BLEED — N_C1 sub-bass thump on EVERY hit. Replaces the
; bass-pattern note at this step; V1's punchy $04/$61 ADSR shapes it.
; Where the actual low-end weight comes from — a 3-voice chip can't
; afford to leave the kick on a single voice.
ldx #N_C1
lda sid_freq_lo,x / sta $D400
lda sid_freq_hi,x / sta $D401
lda #$40 / sta $D404   ; gate off → release prior bass note
lda #$41 / sta $D404   ; gate on → fresh attack of sub-bass thump

!drum_done:

; --- DRUM tick (every frame, end of my_music_play) ---
lda drum_state
beq !drum_skip+
dec drum_state
lda #DRUM_LEN-1
sec / sbc drum_state
asl                    ; phase × 2 bytes/row
clc / adc drum_offset  ; + kick/snare offset
tay
lda drum_table,y   / sta $D412   ; ctrl (gate stays on throughout)
lda drum_table+1,y / sta $D40F   ; V3 freq hi
lda #$00 / sta $D40E
!drum_skip:
```

The state bytes `drum_state` + `drum_offset` live in intro's music
segment (around `$128A`), so every part inheriting `'I', $10, $12`
sees the same state.

### Why the kit is built this way

- **V3 alone can't paint a kick** — it's competing with V2 lead and
  the arp it shares its voice with. The V1 bass-bleed adds the sub
  that makes the kick read as a hit, not a thin click. Pattern from
  the codebase64 Macro Player (Geir Tjelta / Jeroen Tel) and the
  Prince-of-Persia SFX routine.
- **Peak-ADSR throughout** — kick rides at full volume because the
  arp's $00/$F0 envelope is left untouched. Punch comes from waveform
  contrast and pitch sweep, not envelope dynamics. The post-kick arp
  $41 (pulse+gate) write swaps waveform with gate held on → no
  envelope retrigger, no attack ramp, no audible seam.
- **Triangle, not sawtooth** — sawtooth's all-harmonics buzz reads as
  "head punch" (high frequencies); triangle's odd-harmonics-only +
  1/n² rolloff keeps the energy in the belly band where the kick
  belongs.
- **Bass note sacrificed every 4th step** — V1 plays the sub-thump
  instead of the scheduled bass note on kick steps. 3 of every 4
  bass notes survive; kicks land on the quarter. Cost worth paying.

### The `zp_outro != 0` gate

Drums fire only when `zp_outro` is non-zero. This means:

- Intro's first ~20 s: `zp_outro = 0` → no drums (clean buildup)
- Intro's outro animation (sprites despawn, etc.): `zp_outro` ticks
  from `1` toward `$F0` → DRUMS ENTER LATE
- Interlude/greets: `$F6` repurposed as their own counters but
  always > 0 once setup runs → drums continue
- Sinus: setup zeros `$F6` (which is `zp_timer` there), kept at 0
  until the very last frame → **resident drums silent** = the comedown
- Coda: setup zeros `$F6` (also `zp_timer`) → **resident drums silent**,
  but coda runs its own V3 kick state machine that overrides the arp
  every frame
- End: doesn't call `my_music_play` (uses its own routine) → no drums

### Why this gating works for "cohesive music"

Story interleave depends on this:
- Sad pad in interlude (after a brief drum exit at transition):
  drums quickly return at beat 1 because `$F6` ticks to 1 fast
- Greets climax: drums in their natural place
- Sinus visual breather: drums genuinely STOP for ~5 s, giving the
  ear a moment before end's reprise

## Per-voice muting trick

`my_music_play` re-writes V1/V2/V3 freq + control at chord-step
boundaries (every `STEP_FRAMES = 6` frames). Between boundaries the
voices play whatever you last wrote.

To mute one voice without modifying the music engine:

```kickass
jsr INTRO_MUSIC_PLAY    ; engine may have just gated a new bass note
lda #$00
sta $D404               ; force V1 control = 0 (no wave + gate off)
```

The voice stays silent because the engine only writes new control on
step boundaries; we squash it again every frame in between. Crucially
**do NOT zero `$D405`/`$D406` (AD/SR)** if you intend to un-mute
later — the envelope shape needs to survive so the bass sounds right
when it returns. Set ADSR once in intro's `my_music_init`; leave it
alone elsewhere.

## Inter-part transitions

There's no audio fade between parts — the music carries continuously.
The "feeling of transition" is carried by:

- **Drums ENTERING late in intro** (when `zp_outro` arms — the
  outro cascade visually mirrors the audio escalation)
- **Visual cascade in intro's outro** (sprites despawn one by one,
  bars off, logo un-wipes)
- **V1 mute drop + the typewriter reveal of "FOR YEARS NO TIME FOR
  BREADBIN CODE" on interlude's plasma** — the sudden bass drop +
  the sad admission, char-by-char during the pad phase. AI doesn't
  walk, so the second line is now "AI WROTE" — 8 hires sprite letters
  that drop in from above on the buildup beat.
- **V1 return + LP cutoff sweep (V1 + V2 both filtered now) + sprite-
  letter "AI WROTE" drop in interlude's last 2.4 s** — rising tension,
  the build. Bass AND lead open up together as the filter rolls open.
- **Drums STOP + LP filter close + vol fade in sinus** — the
  breakdown / breather, the calm before the drop. Visual is a
  hypnotic sine wobble of repeating DEFEEST text. The LP close is
  now audibly closing the bass + lead because V1 + V2 are routed
  through the filter ($D417 = $23) — previously the cutoff sweep was
  silent because no voices were routed.
- **DYCP scroller + LP-filtered lead "wah" telling the full story in
  greets** — the climax with drums returning + bass + filtered lead
  ($D417 = $42, V2 through filter w/ res $4) + arp. The cutoff
  follows `zp_wobble_pos | $40` so the melody breathes 5 s/cycle in
  step with the visual DYCP motion, on top of the loudest moment of
  the demo.
- **Coda's sparse hard-restart kick under the title card** — drums
  from intro's gated player drop out again, but coda owns V3 and
  fires its own slow ~60 BPM thump under the held chord. The room
  settles. Title sits centered on a quiet screen for ~10 s.
- **end's own `music_init` re-init** with PWM + filter sweep for the
  credit roll reprise — quiet, no drums, settles to the title card

If you're tweaking the score, work WITHIN this rhythm rather than
adding hard cuts. Volume drops anywhere on the resident path leak
into every later part.
