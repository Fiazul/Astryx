# Astryx — Star Field Report

The background sky is a **real-catalogue star field**: every star is a genuine
catalogued star with its **real sky position**, **real brightness** (apparent
magnitude), and a **real color** derived from its measured photometry. Nothing in
the default sky is invented.

## How it works

- **One baked points-mesh, one draw call.** Geometry is built offline by
  `tools/build_starfield.gd` and saved as `assets/starfield_*.res`. The game just
  loads the finished mesh — zero startup cost.
- **Real color from real data.** Each star's **B-V color index** (temperature) maps
  to RGB via the standard Mitchell-Charity blackbody approximation: negative B-V →
  hot blue, ~0 → white, positive → cool orange-red.
  - HYG stars carry B-V directly.
  - Tycho-2 stars: `B-V = 0.850 · (BT − VT)` from their two measured magnitudes.
- **Real brightness drives size + glow.** Apparent magnitude sets each star's point
  size and additive intensity (steep curve: faint stars stay dim, so the sky reads
  as black space with crisp bright stars — not "TV static").
- **Renderer:** additive soft-glow point shader (`scripts/starfield.gd`), per-star
  size in UV.x, per-star color in vertex COLOR. Live brightness knob `STAR_GAIN`.

## Quality tiers (`const QUALITY` in `scripts/starfield.gd`)

| Tier | Stars | Source | Real? |
|------|-------|--------|-------|
| **`tycho`** *(default)* | **355,360** | Tycho-2, brightest (magnitude ≤ 10.0) | **100% real** |
| `high` | 500,000 | 117,930 real HYG + 382,070 procedural Milky-Way band | Real + fill |
| `low` | 117,930 | HYG catalogue only | **100% real** |

All three meshes ship in the build; switching tiers needs no re-bake.

## Real catalogue facts

- **Source catalogues:** HYG v41 (~120k) and **Tycho-2** (CDS I/259).
- **Full Tycho-2 catalogue parsed:** **2,539,913** real stars.
  - Stars with both BT & VT bands (full real color): **2,539,802**
  - Stars measured in only one band (defaulted to white): **111** (0.004%)
- **Default sky (`tycho`, mag ≤ 10):** **355,360** real stars — the brightest 14% of
  Tycho-2. The faint 86% were dropped purely for GPU safety (rendering all 2.54M
  crashed the test machine; ~1M is the safe ceiling here).

## Tuning

- Denser real sky: raise `TYCHO_MAG_CUT` in `tools/build_starfield.gd`
  (10.5 → ~582k, 11.0 → ~937k) and re-bake. Keep ≤ ~900k to stay GPU-safe.
- Lighter / potato: set `QUALITY = "low"` (117,930 real HYG).
- Brightness: tweak `STAR_GAIN` in `scripts/starfield.gd` (no re-bake).

## The galaxy backdrop (the Milky Way's core)

Beyond the point-stars, a **textured galaxy model** sits in the sky as the Milky Way
itself — so you can *see* the band and the bright **galactic core** from inside the disc.
It's drawn by `scripts/galaxy_model.gd` (added in `main.gd` right after the starfield).

- **Real model, real direction.** `assets/galaxy.glb` ("Galaxy" by 991519166, **CC-BY 4.0**,
  credited in `CREDITS.md`) is placed toward the **real Sgr A\* direction**
  `(-0.0546, -0.4849, -0.8728)` — the actual line to the galactic centre.
- **Physically-correct view.** The disc is laid flat in the **real galactic plane** (its
  normal aligned to the galactic north pole `(-0.868, 0.456, -0.198)`). The ship (always at
  the origin) sits *inside* the disc radius, so you see the galaxy roughly **edge-on**, with
  the core glowing toward Sgr A\* — exactly how the Milky Way looks from our spot in it.
- **Backdrop only — you don't travel there.** The real core is ~26,000 ly away; at that
  distance float32 has no precision left, and a parallax-free shell wouldn't move anyway.
  The galaxy is a fixed world backdrop you orient toward, not a destination.
- **Glows like light, not a solid object.** Materials are made **additive** at runtime so the
  model's black base contributes nothing (stars show through) and only the luminous arms add
  light. The flat disc card (a coarse 82-vertex mesh) uses a small **radial-fade shader** so
  its glow falls to zero before the mesh edge — no hard "polygon" silhouette. Backdrops never
  cast shadows (a null-material shadow pass crashes the integrated GPU).
- **Tunables** (`scripts/galaxy_model.gd`): `DIST` / `TARGET_RADIUS` (size & how embedded —
  `TARGET_RADIUS` must stay above `DIST` or the ship falls outside the disc), `BRIGHTNESS`,
  and `fade_start` / `fade_end` in `DISC_SHADER` (where the rim fade begins/ends).

## Re-baking

```
python3 tools/parse_tycho.py          # Tycho-2 .gz parts -> tools/data/tycho_slim.bin
godot --headless --script tools/build_starfield.gd   # -> assets/starfield_*.res
```
Raw catalogue data lives in `tools/data/` and is excluded from game exports via
`.gdignore`.
