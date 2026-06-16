# Astryx · v0.10.0

A potato-friendly **third-person space explorer** in Godot 4 / GDScript. Launch
from Earth, fly the **real** solar system, wormhole to a real exoplanet, dogfight
aliens, and customize your ship in the hangar. Everything is spawned from code; no
detailed assets, just emissive bodies, glow, and a few low-poly meshes.

## Features
- **Real positions** — Sun + planets from live **JPL Horizons**, nearby stars from
  the J2000 catalog. Earth is the origin (floating-origin engine for AU↔ly scale).
- **Seven ships** — Lyra, Stella, Raptor, **Vela** (FTL), **HaniStar**,
  **Raptor 2 Neo** (laser mother-ship), **HaniNebula**. Dock with **F**, swap with
  **1–7**. Each hull has its own stats, boosters, and engine voice.
- **In-hangar customizer** — on HaniStar, HaniNebula & Raptor 2 Neo, pick **body /
  wing colours** (10-colour palette incl. **Champagne Gold** metallic), toggle the
  **engine bell**, and switch **metallic / glassy** finish. Choices are saved
  per-ship to your profile and persist across sessions.
- **Editable HUD** — drag-place and scale HUD widgets in a layout editor; placement
  persists to your profile (defaults are the shipped layout).
- **Flight feel** — sublight "space drift" that carries momentum through turns,
  weighted strafe, eased mouse-steer, and living animated booster flames.
- **Wormhole travel** — fly to a portal, press **F**, transit the tunnel, emerge at
  a real exoplanet system.
- **Combat** — left-click bolts (aim by flying), right-click nose laser on Raptor 2;
  alien ships hunt and fire back. Guarded bodies are defended by a **named boss** +
  its summoned fleet — beat the boss to capture the body for **coins**.
- **Navigation & discovery** — a real zoomable/pannable star **map** (M): star/wormhole/
  planet icons on toggleable layers, a live player cursor, hover read-outs, wormhole lanes,
  out to ~150 ly. Wormholes show live on the **corner radar** and the always-on nav arrow
  points you to the nearest wormhole first. Paid **waypoint navigator** (Tab), **scan** (V) →
  persistent **Codex** (C) with real NASA facts (G).
- **Mission log** (J) — every star, planet & moon is its own mission with a crude,
  (mostly) true story and a coin bounty. Browse the board, click a mission to read it,
  and **Navigate** straight to it. Survey the body to complete it and claim the bounty.
- **Audio** — per-ship engine voice + looping music; HaniNebula has her own track.

## Controls
`WASD` thrust · `Space/Ctrl` up·down · `Q/E` roll · `Shift` boost · `mouse` aim ·
**`L-click` fire** · **`R-click` laser** (Raptor 2) · `R` Vela air-brake ·
`Num Lock` auto-cruise · **`Tab`** waypoint · **`V`** scan · **`C`** codex ·
**`J`** mission log · **`G`** details · **`M`** map · **`F`** dock / wormhole · **`H`** teleport to Earth ·
wheel zoom · **`1–7`** swap ship (docked) · `Esc` free cursor / back

## Run
Install **Godot 4** (GDScript, no C#), open this folder as a project, press **F5**.
No keys or build steps. *(Open it in the editor once after pulling so it imports
any new `.obj` / audio assets.)*

## Layout
`main.gd` orchestrator · `ephemeris.gd` real data + Horizons fetch ·
`systems.gd` star systems · `planet_system.gd` body LOD · `wormhole.gd` transit ·
`combat.gd` dogfight · `ship.gd` flight/visuals · `ship_mesh.gd` mesh/material
helpers · `props.gd` station · `hud.gd` UI · `audio.gd` sound · `map.gd` star map ·
`codex.gd` discovery · `starfield.gd` backdrop · `tools/real_positions.py` verifier.

## Data
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (solar system) · HYG/SIMBAD (stars).

---
Hobby / educational project. See `HANDOFF.md` for the full per-system breakdown.
