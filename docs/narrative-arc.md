# Narrative arc — Kloten met de broodtrommel

> *A C64 demo by deFEEST, releasing at X2026. The breadbin earned its lunch.*

The story is small and the vibe is silly. A human (Anus) hadn't
touched the breadbin in years — life got in the way. Then he sat
down with Kloot, an AI, and they wrote a demo together. It works.
The breadbin is alive. Lunch is served.

That's the whole thing. Seven parts carry it.

## Setlist

```
[01] screenfill   the disk loads          — DEFEEST bloom
[02] intro       the cracktro arrives    — deFEEST presents…
[03] interlude   the confession           — FOR YEARS NO TIME / SPARKED
[04] sinus       the breath                — quiet, breadbin-blue wobble
[05] greets      the party                  — lunchbased lifeforms, shoutouts
[06] coda        the trophy                  — KLOTEN MET DE BROODTROMMEL
[07] end         the bow                    — credits roll, lunch is over
```

For the audio side of every beat below, see
[`sound-arc.md`](./sound-arc.md). The two arcs lock in step: every
text reveal sits on top of an audio shift, every visual climax has a
music moment behind it.

## The arc

### 1. The disk loads (screenfill)

A radial DEFEEST bloom fills the screen, ripples cycle through it.
The audience is waiting. The breadbin is warming up. No music yet —
the SID is untouched. The promise is "something's about to happen."

### 2. The cracktro arrives (intro)

Bouncing logo, raster bars, balls. "deFEEST presents… a C64 demo
for X2026… Anus and Claude Opus and Augurk and Cinder and…"
The classic intro shape: chord pad + lead + arp running, and 20
seconds in the **drums kick in late** — that's the moment the demo
properly starts. The intro transitions out mid-thump.

### 3. The confession (interlude — story line 1)

Now the plasma. Bass goes quiet. A single line types itself out
char by char into the colour wash:

```
FOR YEARS NO TIME FOR BREADBIN CODE
```

That's the human admitting. The pad holds the silence. Then the
buildup beat hits — LP filter sweeps open on bass AND lead together
— and the answer drops in from above as eight sprite letters:

```
                SPARKED
```

It's a joke. It's the truth. It's the whole demo in two lines. AI
doesn't walk; it sparks. The line lands, the energy lifts, the
party isn't quite here yet — but the bass is coming back.

### 4. The breath (sinus)

Sinus is the breath after the joke. A field of repeating "DEFEEST"
text gently wobbling on a sine, colour cycling through breadbin
blues, LP filter closing on bass + lead until they're a muffled
warm hum. Drums stop. Volume fades. The eye of the storm. About 5
seconds where the audience can absorb what just happened and
anticipate what's next.

### 5. The greets (greets — community)

Drums come back full. V1 bass on the pattern. V2 lead doing its
filtered "wah" through the chord cycle. Across the middle of the
screen, eight X-expanded sprite letters DYCP-wave through a list
of demogroup names — the loudest moment, everyone gets a shoutout.
~77 seconds, scrolling through a wall of crew handles, landing on
"KLOOT."

No story text here. The story already happened in interlude.

### 6. The trophy (coda — story closing)

Cut to quiet. Three title lines, centred:

```
       KLOTEN MET DE BROODTROMMEL
       A DIGITAL LUNCH EXPERIENCE
            RELEASED AT X2026
```

Behind them, two 12-lobe Claude-style stars (one brown, one cyan)
orbit each other on sine paths, alternating which is in front of
the text every ~1.3 seconds. Parallax PETSCII starfield sparkles
around the title. A sparse 60-BPM sub-bass kick lands under the
held chord — the *thump* of *this is real, it shipped*. About 10
seconds.

The title is the trophy. Row 15 is the party tag.
*This happened. You watched it. Lunch is served.*

(Earlier drafts had row 15 say "ESPECIALLY KLOOT". Pulled because
the AI-character nod was already in the greets settle on `KLOOT`
and in the disk dirart — three on-screen mentions read as
ego-stroking. One is enough.)

### 7. The bow (end)

Credit roll. PWM-filtered chord/lead reprise — no drums, the room
has emptied, the party is over but everyone's still humming the
tune. Names scroll, names scroll, names scroll. Loops forever.
Lunch was served.

## The two arcs locking in

```
beat:    quiet  →  build  →  confess  →  breathe  →  drop  →  settle  →  bow
visual:  load   →  intro   →  text drop →  wobble  →  greetz →  twin star → credits
story:   --     →  hello   →  SPARKED   →  --       →  --     →  trophy + party tag → credits
music:   silent →  drums in→  filter rise→ filter close→full kit→ slow kick→ chord reprise
```

The story lands in two places: interlude (FOR YEARS NO TIME →
SPARKED) tells the confession; coda lands the trophy with the
title + the X2026 release tag, while the greets settle on `KLOOT`
gives the AI-character one subtle nod. Greets itself is the
party — no story, just community shoutouts. When the SPARKED letters drop, the bass returns and the
filter opens. When the sinus filter closes, the drums stop. When
the greets drums come back, the lead's wah kicks in. When the coda
title lands, the drums sparse out to one beat per second. Each
text reveal sits on an audio shift. Each visual climax has a
music moment under it. That's the cohesion — the arcs aren't
parallel tracks, they're the same wave seen from two sides.

## The lunchbox costume

The "lunchbox" theme is the language, not the plot. Tupperware,
broodtrommel (= bread tin = the C64's nickname "breadbin"), pindkaas
sandwich in drive 1541, "now go eat your lunch". It's the surface
joke — the *real* story underneath is **AI wrote the breadbin code,
the demo got made**. Lunch is just the costume the story wears so
it doesn't take itself too seriously.

If you're tweaking text content: keep the costume on. If you're
tweaking the audio or visuals: tweak in service of the beat /
visual / story locks in the table above. Don't break the lock.
