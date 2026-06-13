# Astryx · v0.2.0

A potato-friendly **third-person space explorer** in Godot 4 / GDScript. Launch
from Earth, fly the **real** solar system, wormhole to a real exoplanet, and
dogfight aliens. Everything is spawned from code; no detailed assets, just
emissive bodies, glow, and a few low-poly GLBs.

## Features
- **Real positions** — Sun + planets from live **JPL Horizons**, nearby stars from
  the J2000 catalog. Earth is the origin (floating-origin engine for AU↔ly scale).
- **Wormhole travel** — fly to a portal, press **J**, transit the tunnel, emerge
  at the real **K2-18** system (M-dwarf + **K2-18b** at its real 0.143 AU orbit).
- **Combat** — left-click machine-gun bolts (aim by flying); alien ships hunt and
  fire back. Hull / Kills on the HUD.
- **Ships** — 4 selectable hulls at the station (dock with **F**, pick **1–4**).
- **Looping music** while travelling.

## Controls
`WASD` thrust · `Space/Ctrl` up·down · `Q/E` roll · `Shift` boost · `mouse` aim ·
**`L-click` fire** · **`J`** wormhole · **`H`** / button → teleport to Earth ·
`F` dock · `Esc` free cursor

## Run
Install **Godot 4.6+** (GDScript, no C#), open this folder as a project, press **F5**.
No keys or build steps. *(Optional `bgm.mp3` is gitignored — drop your own in the
project root for music.)*

## Layout
`main.gd` orchestrator · `ephemeris.gd` real data + Horizons fetch ·
`systems.gd` star systems · `planet_system.gd` body LOD · `wormhole.gd` transit ·
`combat.gd` dogfight · `ship.gd` flight/visuals · `props.gd` station · `hud.gd` UI ·
`starfield.gd` backdrop · `tools/real_positions.py` coordinate verifier.

## Data
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (solar system) · HYG/SIMBAD (stars).

---
Hobby / educational project.
