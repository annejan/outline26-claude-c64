# Dilemmas — outline-64

A running log of the design trade-offs we've hit while building the
demo, what we tried, and what we ended up choosing. Where `timing.md`
catalogues *what the demo does*, this file catalogues *why we couldn't
do it the other way*.

---

## Intro: bouncing logo vs fixed fade-text

**Want**: a fade-band text strip between the scroller and the logo
that **stays put** while the logo bounces below it.

**Why it's hard**: the FLD trick we use for the bounce works by
*freezing* one bitmap row and stretching it for K extra raster lines.
Everything *after* that row shifts down by K. So the only bitmap rows
with a fixed Y position are the rows **before** the FLD trigger.

In the original layout the FLD trigger is at `$3B` = row 1's natural
badline. That leaves exactly one fixed-Y bitmap row available: row 0,
which is already the scroller.

### What we tried

1. **Move the FLD trigger to `$5B`**, freezing row 5 instead of row 1.
   Then rows 1..4 are above the FLD trigger and the fade-text in
   row 4 stays fixed.
   - **Pro**: fade-text doesn't bounce.
   - **Con**: the FLD math behaves cleanly only when K leaves
     `yscroll = 3` after the K writes. With trigger `$3B` and
     `yscroll` starting at 3 then going to 5 for the first write,
     the K values cycle through `yscroll = (4 + K) % 8` at the end.
     For K = 28, that's `yscroll = 0` — VIC's next natural badline
     fires on `line % 8 == 0`, which is `$80` (= BAR_TOP). That
     happens to align cleanly with the natural row-by-row display
     resumption. **Moving the trigger to `$5B` reshapes the raster
     window**: the spurious-badline cascade keeps re-fetching row 5
     in a way that leaves a single sub-row of row 5's data visible
     between FLD end and the next natural badline, depending on K.
     Visible result: a **sawtoothed top edge of the logo** as K
     varies, because the logo's first pixel row starts one raster
     line earlier/later from one frame to the next.
   - **Verdict**: rejected. User feedback: *"make the FLD be smooth
     like before"* — the smooth bounce reads better than fixed text.

2. **Keep FLD at `$3B`, put fade-text into a bouncing row**.
   - The fade-text now travels with the logo as a single visual unit.
   - Text + logo bounce together; eye reads them as one composite.
   - **Verdict**: intermediate compromise. Replaced by (3).

3. **Symmetric FLD** (the answer all along) — top FLD does K writes
   *before* the logo, bottom FLD does (K_max − K) writes *after* it.
   Total FLD stretch per frame is constant (= K_max = 28). The logo
   bounces inside a 28-line arc, and **everything past the bottom
   FLD lands at the same raster position every frame** regardless of
   K. Fade-text moves to bitmap row 19 (= raster `$E3`, fixed Y) and
   no longer bounces.
   - **Pro**: bounce arc preserved at K_max=28, fade-text fixed,
     yscroll ends at constant `(4 + K_max) % 8 = 0` so the chain
     transitions cleanly into `irq_close`.
   - **Con**: bars zone shrinks from `$80..$EB` (108 lines) to
     `$80..$C1` (66 lines) — bars must end before bottom-FLD's
     earliest trigger at `$C3`. Acceptable trade: bars still span
     the logo in both bouncing extremes.
   - **Verdict**: shipped. See `irq_fld_bottom` in `intro.asm` and
     the IRQ-chain comment at the top of the file.
   - **Reference**: this is exactly Jesder's symmetric-FLD pattern
     from `ranzbak/defeest-demo-lft-loader/badline`. See the
     "external references" section at the bottom of this file.

### Levers we kept on the table but didn't use

- **Sprite multiplexing** for the fade-text: 8 sprites already
  pinned to the ball cascade (Y-wrap mitigation). Adding a 9th+
  via multiplexing costs ~80 cy/frame in the IRQ chain and is
  fragile under the existing chain's tight FLD/bars handover.
- **HIRES bitmap mode swap for one cell row**: would need a mid-
  frame `$D011 / $D016` toggle and per-row colour control. Worth
  it for a HUD, overkill for a 1.28 s fade-band.

---

## IRQ-chain budget: who gets the slack?

The IRQ chain is `irq_close@$F9 → irq_open@$01 → irq_fld@$3B →
irq_bars@$80 → irq_fld_bottom@$C3+K → irq_close@$F9`. Each stage's
window:

| Stage | Window | Lines | Cycles |
|-------|--------|-------|--------|
| irq_close → irq_open | `$F9 → $01` | 64 | ~4032 |
| irq_open → irq_fld | `$01 → $3B` | 58 | ~3654 |
| irq_fld → irq_bars | `$3B → $80` | 69 | ~4347 |
| irq_bars → irq_fld_bottom | `$80 → $C3+K` | 67..95 | ~4222..5985 |
| irq_fld_bottom → irq_close | `$C3+K → $F9` | 22..54 | ~1386..3402 |

Total per frame: 312 lines × 63 cy = 19,656 cy.

### Where work lives

- **scroller update** (~2400 cy) — in `irq_close`, where there's a
  ~4032-cy hole between bottom border and top of next frame.
- **music play** (~600..2000 cy, peak on step-boundary frames) —
  in `irq_fld` after the FLD loop. The `$3B → $80` window has
  ~4347 cy, of which the FLD loop K=28 eats ~1764 cy (raster-
  locked), leaving plenty for music + handover.
- **sprite movement + counters** — in `irq_open`. `$01..$3B`
  is 58 lines = ~3654 cy and rarely tight.
- **fade-text colour cycle** (~280 cy idle, ~900 cy peak when
  rendering one of 20 chars during a phrase swap) — in
  `irq_close` after the scroller.

### What we tried

- **Moving music into `irq_open`** to give `irq_fld` a tight,
  predictable handover to `irq_bars` (only needs ~5 lines for
  vector + rti instead of 13+ lines for music_play).
  - **Pro**: bars start exactly at `$80` every frame, no step-
    boundary-frame jitter.
  - **Con**: even with a clean handover, the `$5B` trigger we
    were testing in parallel still produced the sawtooth artifact
    (the artifact was *trigger-position* not *music-position*).
    Once we reverted FLD to `$3B`, the `$3B → $80 = 4347 cy`
    window was wide enough that music_play in `irq_fld` no
    longer causes any observable bars-timing issue.
  - **Verdict**: rolled back, music stays in `irq_fld`.

### Levers

- **Move heavy chunks across frames**: chunked phrase rasterise
  spreads ~12 kcy of work over 20 frames (~600 cy each).
- **Precompute tables**: `char_dst_lo/hi` and `phrase_base`
  avoid runtime multiplication (saved an asl-chain-carry bug
  for char index ≥ 16).
- **Cycle annotations in source**: every block in `render_one_char`
  and `update_fade_text` has cycle counts so we can predict
  whether new work will fit.

---

## Hiding things VIC wants to show

VIC's open-top-border and open-bottom-border tricks let us draw past
the natural display window. They also expose VC garbage in the
border zones — VIC keeps fetching cells from wherever VC last
pointed.

**Symptom**: the LOGO's top yellow pixels can leak into the open-top
border zone as a ghost stripe. Visible mostly when bars are on but
the logo hasn't been revealed yet (`zp_intro` between `T_BARS=120`
and `T_LOGO=200`).

### What we tried

- **Defer `copy_logo`** to per-frame column copies during the reveal
  phase, so the logo bitmap stays at $00 until the reveal actually
  needs each column.
  - **Pro**: pre-reveal bitmap is fully zero — no VC-garbage leak.
  - **Con**: adds ~490 cy/frame during the 40-frame reveal window.
  - **Verdict**: user said *"not hiding pre reveal"* — leak accepted
    as a minor pre-reveal artifact rather than spend cycles to fix.

### Levers

- **Zero the bitmap data, not just screen RAM**: only works if you
  can reliably restore it before display needs it.
- **Disable display entirely (`DEN=0`)**: would also kill bars +
  scroller. Non-starter.
- **Put cleanup into `init_slide_hide`** so reveal restores from a
  resident copy. Costs RAM (logo is 2880 bytes).

---

## Sprite Y-zones must not overlap

8 sprites, each with a single Y register. When Y > 232 or so, the
sprite's pixels wrap across the screen boundary and a "ghost" appears
near the top.

**Symptom** (before zone separation): bottom balls' Y-wrap doubles
fire between bottom border close (`$F9`) and top of next frame (`$01`).

### What we did

Three sprite zones with **non-overlapping Y ranges**:

- sprites 0/1/2: top border (Y = 14..30), disabled during VBL
  (between `$F9` and `$01`) so their wrap doubles never fire on screen.
- sprites 3/4/5: display area (Y = 60..200), no wrap.
- sprites 6/7: bottom border (Y = 226..240), no wrap.

The gap between top (max Y=30) and middle (min Y=60) = **30 pixels**.
That's the visible "the 3 middle balls don't touch the 3 top balls"
gap — it's the wrap-mitigation buffer.

### Levers we could still pull

- **Sprite multiplexing** to make a sprite jump between zones. Costs
  cycles in the IRQ chain (re-setup Y/X mid-frame). Not worth it for
  the ball cascade visual.
- **Use the same sprite for top and middle by snapping Y** — would
  reintroduce the wrap problem.

---

## Crisp text in MC bitmap mode

MC bitmap mode has 4 pixels per cell horizontally (160-pixel-wide
screen). Folding 8-pixel-wide hires chargen glyphs to 4 MC pixels
via OR-pair conversion loses the holes in letters like `b/d/o/p` —
they become chunky blobs.

### What we tried

- **OR-pair MC fold-down**: 8 hires bits → 4 MC bit-pairs, where each
  pair is "11" if either source bit is set.
  - **Pro**: each character fits in 1 cell.
  - **Con**: letter holes disappear; reads as "blurry" text.
  - **Verdict**: rejected after user feedback.

- **Bit-expansion across 2 cells per char**: each hires bit becomes
  exactly one MC bit-pair (11 if set, 00 if clear). 8 hires bits →
  8 MC bit-pairs spread across 2 MC bytes = 2 cells (8 MC pixels).
  - **Pro**: every detail of the chargen glyph survives; letter
    holes intact.
  - **Con**: phrases now span 2× the cells (20 chars = 40 cells =
    full screen width). Less freedom for layout.
  - **Verdict**: chosen. Crisp glyphs were the user's clear preference.

### Levers we kept on the table

- **Custom MC-native font**: glyphs designed natively for 4 MC pixels
  wide. Cleaner result but ~184 bytes of hand-drawn glyph data plus
  encoding work. Postponed.
- **Mode-switch to HIRES on the text row**: would give 8 hires pixels
  per cell with full chargen quality. Mid-frame `$D016` toggle is
  fragile under the existing IRQ chain.

---

## Pefchain page-claim discipline

The EFO header's `'P', lo, hi` tags tell pefchain which page range
the part wants to keep resident. **Pages outside the claim can be
overwritten by background loads of the next part** — including
tables the current part is actively reading.

### Symptom

`bounce_total` lives at `$4800` (the start of the Tables segment's
second 256-byte block, after the X/Y phase tables). The original
EFO claim was `'P', $40, $47` — *exclusive of `$48`*. Pefchain
background-loaded the next part's data on top of `bounce_total`,
which silently changed the FLD K values frame-to-frame.

Visible result: **the logo "jumped" while bouncing** because K
read random bytes from the next part's text data instead of a smooth
sine.

### Fix

Extended the claim to `'P', $40, $48` and also `'P', $54, $5D`
to cover the BmpScroll segment's actual extent (scroll_text +
sprite_shape). Same lesson for any future table that lives at a
page boundary: **the claim must end *at or above* the highest page
you write/read at runtime**, including page-aligned tables.

### Levers

- **Audit symbols against EFO claims** every time a new resident
  table is added — `intro.sym` has the addresses; cross-check
  against `intro_efo_header.asm`.
- **Page-align tables intentionally** so the claim boundary is
  easy to verify visually.

---

## Things we know hurt that we haven't fixed

- **Open-top-border scroller ghost**: at certain raster timings,
  the scroller text appears in a small fragment at the top-right
  of the screen, in the open border zone. Pre-existing in original
  code. Hiding it would need the deferred-copy or DEN-toggle
  techniques above.
- **Logo top "tearing"**: with FLD `$3B` and the original geometry,
  the logo's top yellow arc has a stepped bitmap design that reads
  as slight stair-stepping when the bounce is mid-arc. Bitmap
  feature, not a raster glitch.
- **Phrase 3 may not have time to show**: with intro ending around
  `zp_intro = $FF` and fade-text only starting at `T_SCROLLER=240`,
  the 2.56 s × 3 phrases cycle barely fits before intro outro
  triggers. Phrase 0 + 1 always show; phrase 2 ("the breadbin felt
  it") may be cut short or skipped.

---

## External references — code we learned from

These aren't ours; they're the public C64 demos / reference code we
read or borrowed techniques from. Listed here so future-us doesn't
have to re-find them.

### `ranzbak/defeest-demo-lft-loader`

`https://github.com/ranzbak/defeest-demo-lft-loader`

A 2018 deFEEST demo by `ranzbak`, multi-part chained by lft's loader.
Useful subdirectories:

- **`defeest-intro/`** — sprite-letters bouncing-wave intro. 7 multi-
  colour sprites each carry one hand-drawn letter of "deFEEST". Five-
  IRQ chain, phase-offset Y bounce per sprite, text-mode bottom-row
  scroller. The notable trick is **shape-sharing**: sprites 1, 3, 4
  all point at sprite block `$3040` (= letter 'e') — three 'e's in
  "deFEEST", one block. Worth borrowing for any letter-as-sprite
  effect we add later.

- **`badline/`** — Jesder/0xc64-tutorial-derived FLD intro with a
  koala bitmap and a 4×4 scroller at the bottom. **This is where the
  symmetric-FLD pattern in our intro comes from.** Their
  `logo_bounce_heights[]` cycles K = 0..15; per frame they do K top-
  FLD writes (`render_bitmap_start`) and (16 − K) bottom-FLD writes
  (`render_bitmap_end`), with the bottom-FLD raster trigger self-
  modified to `177 + K`. Constant 16-line total stretch → header
  text above and 4×4 scroller below stay pinned. Also has an
  `apply_interrupt` tail-call helper worth stealing if our IRQ
  chain grows further.

### `ranzbak/speedcode`

`https://github.com/ranzbak/speedcode`

Reference for speedcode techniques (long unrolled raster work) —
not yet borrowed. On the watchlist if we ever need to fit something
big into a tight raster window (HIRES mode toggle, full-screen
plasma, etc.).

### Jesder / 0xc64 — 4×4 dynamic text scroller

`http://www.0xc64.com/2017/02/12/tutorial-4x4-dynamic-text-scroller/`

The 4×4 scroller in ranzbak's `badline` follows this tutorial.
Probably overkill for our intro (we have a full-width bitmap
scroller already) but worth knowing about for greets or other
parts that want fancier glyphs in a small footprint.

### Janne Hellsten — BINTRIS series part 5: bad lines and FLD

`https://nurpax.github.io/posts/2018-06-19-bintris-on-c64-part-5.html`

Excellent write-up of the bad-line condition `(RASTER & 7) == YSCROLL`
and how FLD uses it to scroll the screen down. The big stability
lesson we took from this: **FLD timing must not depend on adjacent
IRQs' workload**. Music play with variable cycle cost (step-boundary
frames) inside or right after the FLD chain produces jitter even
when the FLD loop itself is cycle-tight. Fix: move variable-cost
work (music, scroller updates) into a different IRQ with a separate,
generous window. Also documents the realistic ~20–22 usable cycles
on a bad line (not the often-quoted 23).

### `codebase.c64.org`

The general C64 codebase reference. We default to it for any new
VIC or 6510 routine per repo convention (see `feedback-codebase64-
first.md` in memory).
