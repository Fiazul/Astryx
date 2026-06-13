# Astryx — 64-bit (double-precision) full-scale experiment

This branch (`experiment/64bit-scale`) carries the ~10× system spread (Stage 1) plus
the plan to go **true-real-scale** once Godot runs in double precision. `main` stays
on the stable single-precision v0.6.0.

## Why 64-bit
World coordinates are 32-bit floats by default. Float32 keeps ~7 significant digits,
so a few **million** units from the origin the position snaps to the nearest ~1–8
units → visible jitter (the "warp wall"). Our named stars already sit at
`UNITS_PER_LY × ly` ≈ tens of millions of units, so flying to them free-hand wobbles.

A Godot built with `precision=double` uses 64-bit floats for coordinates (~15–16
digits). The jitter effectively vanishes, which lets us:
- give planets their **true size ratios** (Sun 109× Earth, not compressed),
- place bodies at **true AU distances** (not a compressed cheat),
- **free-fly interstellar** at real ly distances with no warp wall,
- keep the ship tiny against genuinely huge worlds.

It is a **compile-time engine flag**, not a project toggle — see
`tools/build_godot_double.sh`. The project itself runs unchanged under the
double-precision editor; floating-origin already keeps the player near 0,0,0.

## Build & run
```bash
tools/build_godot_double.sh 4.6.3-stable          # ~20-40 min, needs sudo for apt
# then:
~/godot-src/bin/godot.linuxbsd.editor.*double*  --path .
```

## Once it runs cleanly — ratchet the scale toward real (the dials)
Do these gradually, testing jitter at the far edges each step:

1. **`ephemeris.gd`**
   - `AU_TO_UNITS` — raise toward a true scale (e.g. 1000+). `UNITS_PER_LY` must stay
     `63241.077 × AU_TO_UNITS` (update the literal together).
   - Planet `radius` — move toward true ratios (Sun ≫ Jupiter > Earth > Mars > Mercury)
     instead of today's compressed values.
2. **`ship.gd`** — `THRUST`/`MAX_SPEED`/`HYPERSONIC_SPEED`, `SOL_FIELD_RADIUS`,
   `WARP_ARRIVE_*`, dock speeds, ship `length`, `CAM_OFFSET` all scale with the world.
3. **`planet_system.gd`** — gravity (`GRAVITY_STRENGTH`/`_MAX_ACCEL`/`_RANGE_MULT`,
   `STAR_GRAVITY_*`) and the star LOD bands (`STAR_NEAR/SKY/RADIUS`).
4. **`props.gd` / `systems.gd` / `wormhole.gd`** — all hand-placed positions & sizes.
5. **`minimap.gd`** — `DIST_SCALE`.

Everything above is already expressed in plain constants, so each is a single dial.
Export templates also need a `precision=double` build (`target=template_release`)
before shipping a 64-bit binary.

## Stage 2 (still planned, branch-independent)
Edge **portal → interstellar zone**: even with 64-bit, a curated interstellar hub
(stars at flyable distances) is the cleaner UX than free-flying tens of millions of
units. Double precision just makes the in-zone flight rock-solid.
