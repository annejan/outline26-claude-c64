# outline26-claude-c64

A C64 demo for the Outline 2026 demoparty, written together with Claude.
KickAssembler 6510, tested on VICE x64sc (PAL).

## What's in the demo

Three sequenced parts loaded by [Spindle](https://hd0.linusakesson.net/spindle.php):

### Part 1 — `parts/screenfill/screenfill.asm` (loading screen)

- Walks a "DEFEEST" string across the whole 40×25 screen, alternating
  upper/lower case per cell via a rotating bit-mask.
- Holds for ~3 sec running a **water-ripple colour cycle**: a precomputed
  1024-byte radial-distance map indexes a 16-entry palette shifted by a
  phase counter each frame, so concentric rings appear to expand outward
  from the centre.
- Last second of hold snaps bg+border $06 → $00 (no `$0B` intermediate;
  on new-VIC `$0B` is brighter than blue, see [COLFADE v2](https://codebase.c64.org/lib/exe/fetch.php?media=vic:colfade_v2.pdf)) and walks the ripple
  palette through a hue-stable fadetab to black.
- Hands off to main with `jsr $c90 / jmp $0810`.

### Part 2 — `parts/main/main.asm` (the demo)

- **Open top/bottom borders** via the canonical HCL polling trick
  (`$d011` 24/25-row toggle in IRQs at line `$f9` and `$01`).
- **Multicolour bitmap "deFEEST" logo** mid-screen (160×200 Koala, encoded
  from a PNG by `tools/png_to_koala.py`). Wipes in column-by-column from
  the left via `reveal_column`, then floats on a flexible-line-distance
  bounce.
- **FLD logo bounce** — anchor-style "late write" pattern at line `$3B`.
  Per-frame `K = bounce_total[frame]` writes increment `$D011`'s yscroll
  after VIC's cycle-14 check, so each line's badline check sees the
  previous write and fires a spurious badline. Smooth 0..28 px bounce,
  3× sine frequency.
- **Bitmap scroller** at the very top, bitmap row 0 (lines `$33..$3A`).
  Cycles through three scroll modes via `$fe` sentinels in `scroll_text`:
  - mode 0 — all rows shift left (right-to-left, normal reading)
  - mode 1 — all rows shift right (left-to-right "deFEEST classic"); the
    advance walks `zp_text_ptr` **backwards** through block 2 so the
    source still reads forward
  - mode 2 — zig-zag (even pixel rows shift left, odd rows shift right)
  1 px/frame via 40-cell ROL/ROR chains. Per-cell rainbow colour-RAM
  cycle every frame so the letters flow through hues. Sprites 0-2 have
  their foreground-priority bit set, so the rainbow strokes overdraw
  the balls swinging through the scroller row.
- **Rainbow rasterbars** wrapping the logo. The bar IRQ at line `$80`
  polls `$d012` and writes both `$d021` (background, behind the bitmap's
  transparent pixels) and `$d020` (border / side stripes) per scanline
  from a page-aligned 512-byte palette. 21-cy tight loop fits within the
  bad-line CPU budget.
- **Eight X+Y-expanded "koorballen" sprites** bouncing on sine paths —
  three in the open top border, three in the display (Y range 90..200,
  clear of the FLD zone), two in the open bottom border. Sprites 0-2
  are disabled in `irq_close` to hide their Y+256 wrap-around duplicates.
- **Custom 3-voice SID music** — bass pulse, lead pulse, sustained arp
  over a 32-step Am-Em-F-G chord progression with a 128-step lead melody.
- **Sequenced intro** (driven by `zp_intro`, ticks at 25 Hz, saturates
  at `$ff`):

  | tick | const         | event                                   |
  | ---- | ------------- | --------------------------------------- |
  |   0  |               | logo bg + scroller hidden, SID muted    |
  |  40  | `T_BALLS`     | sprite 0 appears (then 1 every 8 ticks) |
  | 120  | `T_BARS`      | rasterbars on; V1 bass gate fires       |
  | 200  | `T_LOGO`      | logo wipe-reveal begins (40 columns)    |
  | 240  | `T_SCROLLER`  | scroller fade-in; V3 arp gate fires     |

  Sprites cascade in one-at-a-time (top 3 → mid 3 → bot 2). SID master
  volume ramps from `$00` to `$0f` over the intro window. V2 lead gates
  at `T_BALLS`.

- **Sequenced outro** (`zp_outro`, armed when `scroll_text` hits `$ff`,
  same 25 Hz tick):

  | tick | const            | event                                |
  | ---- | ---------------- | ------------------------------------ |
  |   0  |                  | scroller advance frozen; row drains  |
  |  40  | `T_OUTRO_LOGO`   | logo un-wipes (column 39 → 0)        |
  | 120  | `T_OUTRO_BARS`   | rasterbars off                       |
  | 176  | `T_OUTRO_BALLS`  | sprite 7 despawns (then 6, 5, ... 0) |
  | 240  | `T_OUTRO_DONE`   | hand-off to part 3 via `jsr $c90`    |

  SID master volume fades back to `$00` over the first ~5 sec of the
  outro window (`vol_intro - vol_outro`, clamped).

### Part 3 — `parts/end/end.asm` (placeholder)

109-byte text-mode placeholder. Drops `"to be continued..."` centered on
black, halts. Loads at `$c000` (the dead screenfill region) so main's
code at `$0810` survives the load and the trailing `jmp $c000` fires
into the new entry point.

50 Hz PAL, locked.

## Build / run

You need:

- **KickAssembler** (jar in `kickass/KickAss.jar`, [download from theweb.dk](http://theweb.dk/KickAssembler/))
- **VICE** with `x64sc` (`zypper in vice` on openSUSE)
- **xa65** for Spindle (`zypper in xa` on openSUSE)
- **Spindle v2.3** — first run `./build.sh` will fail with hints; build the `spin` tool via:
  ```
  curl -L https://hd0.linusakesson.net/files/spindle-2.3.tgz | tar xz
  cd spindle-2.3/spindle && make
  ```
- Java for the assembler

Build the multi-part disk and run:

```
./build.sh        # produces outline-64.d64
./run-disk.sh     # autostarts the disk in stock x64sc
./run-mcp.sh      # autostarts in a VICE build with the embedded MCP
                  #  server (for driving / inspecting from Claude)
```

## Spindle script

`script` lists the paragraphs Spindle bakes into the .d64. Paragraph 0
auto-loads at boot; each subsequent `jsr $c90` advances to the next one
and loads it into the listed addresses.

> **Trap to remember:** every per-chunk byte-count in `script` is
> hard-coded. When you grow a main.asm segment, **update the matching
> `script` byte-count** to KickAssembler's reported segment size or
> Spindle silently truncates the tail. The boot then runs into garbage
> and dies at BASIC READY with no error from either tool — check the
> Memory Map line in `./build.sh` output.

Spindle's resident loader sits at `$0c00-$0dff` (+ scratch `$0e00-$0eff`
and zero-page `$f4-$f7` during loads). The main demo keeps clear of that
range — bitmap screen RAM moved to `$0400`.

## Main-demo memory layout (VIC bank 0)

| Range          | Contents                                       |
| -------------- | ---------------------------------------------- |
| `$0400-$07e7`  | Bitmap-mode screen RAM (colour info)           |
| `$07f8-$07ff`  | Sprite pointers                                |
| `$0810-$0a46`  | Main code + IRQs (entry point: `$0810`)        |
| `$0b00-$0b3f`  | Sprite shape data (block `$2c`)                |
| `$0c00-$0dff`  | **reserved for Spindle's resident loader**     |
| `$1000-$1275`  | Hand-written 3-voice SID player + patterns     |
| `$2000-$3f3f`  | Logo bitmap (multicolour, 8000 bytes)          |
| `$4000-$47ff`  | Page-aligned tables (palette, sines, bounce)   |
| `$4c00-$53ff`  | Chargen-ROM copy (mixed-case font for scroll)  |
| `$5400-$5bbc`  | Bitmap scroll renderer + scroll text + sprite shape |

> **Trap to remember:** VIC sees the chargen ROM at `$1000-$1fff` in
> bank 0, *not* RAM. Sprite shape data placed there is invisible to
> VIC — VIC reads chargen glyphs as sprite data. Keep sprite blocks
> outside that window.

## Tools

- `tools/png_to_koala.py` — convert a PNG to a 4-colour C64 multicolour
  bitmap (`defeest.kla`). Uses a fixed slot palette
  (black/blue/yellow/white) so every cell has the same 4 colours —
  works for logos with a small palette.
- `vicemon.py` — stdlib VICE binary-monitor client (originated in the
  Umbra C64 project). Launch VICE with
  `-binarymonitor -binarymonitoraddress ip4://127.0.0.1:6502`
  then `python3 vicemon.py read 0xADDR LEN`, `regs`, `resume`. Kept
  around for one-off CPU/memory pokes; for interactive driving use the
  VICE-MCP build that `run-mcp.sh` launches.

## Credits

- Music: hand-written 3-voice SID jam (bass + lead + arp)
- Logo: defeest.nl
- Assembly: Anne Jan Brouwer with Claude (Anthropic) Opus 4.7
