# Astryx · v0.11.3

A potato-friendly **third-person space explorer** in Godot 4 / GDScript. Launch
from Earth, fly the **real** solar system, wormhole across a tested interstellar
network to real exoplanets, dogfight aliens and their bosses, and customize your
ship in the hangar. The world is spawned from code — emissive bodies, glow and a
few low-poly meshes.

## ▶ Gameplay
[![Astryx — gameplay](https://img.youtube.com/vi/txmrN1_HsiM/maxresdefault.jpg)](https://www.youtube.com/watch?v=txmrN1_HsiM)

*Gameplay clips (edited together, with sound) — warp out to real stars, fight the guardian waves defending a world, and capture it.*

## Features
- **Real positions** — Sun + planets from live **JPL Horizons**, **~50 of the nearest
  real star systems** from the J2000 catalog. Earth is the origin (floating-origin
  engine for AU↔ly scale).
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
- **Wormhole network** — a **5-hub** graph (Prim's MST + extra edges, BFS routing) with a
  *tested* guarantee: **Earth → anywhere ≤ 2 hops, any → any ≤ 3 hops** — you're never more
  than 3 jumps from a star. Fly to a portal, press **F**, transit the tunnel, arrive.
  See [`WORMHOLE_NETWORK.md`](WORMHOLE_NETWORK.md).
- **Combat** — instant **hitscan "ray bullets"** (left-click; aim by flying), right-click nose
  laser on Raptor 2; alien ships hunt and fire dodgeable bolts. Guarded bodies are defended by
  a **named boss** + finite **guardian waves** — clear the swarm, break the boss, capture the
  body for **coins** (with a capture-celebration payout).
- **Ray Tab-targeting** — **Tab** locks onto whatever your nose points at (nearest the aim
  *ray* by angle, not the nearest object), cycling the 4 closest; unscanned targets read
  "Unknown Star/Planet" until you **scan (V)**. See [`TAB_TARGETING.md`](TAB_TARGETING.md).
- **Navigation & discovery** — a real zoomable/pannable star **map** (M): star/wormhole/
  planet icons on toggleable layers, a live player cursor, hover read-outs, wormhole lanes,
  out to ~150 ly. Wormholes show live on the **corner radar** and the always-on nav arrow
  points you to the nearest wormhole first. **Scan (V)** → persistent **Codex** (L) with real
  NASA facts (G). A **beginner tutorial/quest** eases new pilots in.
- **Mission log** (J) — every star, planet & moon is its own mission with a crude,
  (mostly) true story and a coin bounty. Browse the board, click a mission to read it,
  and **Navigate** straight to it. Survey the body to complete it and claim the bounty.
- **Star gravity & teleport** — stars gently pull you in (and let go once you thrust away, so
  you're never trapped). A rare, theatrical **teleport ritual** handles emergency-home and
  station→station jumps; a **platform-network console** fast-travels between unlocked stations.
- **Audio** — per-ship engine voice + script-generated SFX + background music.

## Controls
`WASD` thrust · `Space/Ctrl` up·down · `Q/E` roll · `Shift` boost · `mouse` aim ·
**`L-click` fire** · **`R-click` laser** (Raptor 2) · `R` Vela air-brake ·
`Num Lock` auto-cruise · `W+C` drift-flip · **`Tab`** waypoint · **`V`** scan · **`L`** codex ·
**`J`** mission log · **`G`** details · **`M`** map · **`F`** dock / wormhole · **`H`** teleport to Earth ·
wheel zoom · **`1–7`** swap ship (docked) · `Esc` free cursor / back

## Run
Install **Godot 4** (GDScript, no C#), open this folder as a project, press **F5**.
No keys or build steps. *(Open it in the editor once after pulling so it imports
any new `.obj` / audio assets.)*

## Layout
~12k lines of GDScript across ~35 code-spawned modules:
`main.gd` orchestrator · `ephemeris.gd` real data + Horizons fetch ·
`systems.gd` star systems · `planet_system.gd` body LOD + gravity · `wormhole.gd` graph +
transit · `combat.gd` dogfight/bosses · `ship.gd` flight/visuals · `ship_mesh.gd`
mesh/material helpers · `props.gd` stations/platforms · `platform_teleport.gd` fast-travel
console · `hud.gd` + `minimap.gd` + `crosshair.gd` UI · `map.gd`/`map_chart.gd` star map ·
`missions.gd`/`quest_log.gd` quests · `codex.gd`/`codex_panel.gd` discovery · `tutor.gd`
tutorial · `reward_card.gd` payouts · `navigator.gd` routing · `audio.gd` sound ·
`starfield.gd` backdrop · `touch.gd` mobile controls · `tools/` verifiers + asset/SFX
generators.

## Data
[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (solar system) · HYG/SIMBAD (stars).

## Assets
World, effects and SFX are code/script-generated. 3D ship & prop models are free assets
([Poly Pizza](https://poly.pizza/), [Free3D](https://free3d.com/)); music is AI-generated.
See [`CREDITS.md`](CREDITS.md).

---
Hobby / educational project. See `HANDOFF.md` for the full per-system breakdown.
