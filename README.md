# Astryx

A small, third‑person space explorer built in **Godot 4** with **GDScript**. You
launch from Earth, fly out through the solar system, and watch distant bodies
grow from glowing dots into real worlds as you approach. Built to run on a
potato — emissive bodies and glow instead of heavy lighting, a single instanced
star field, low‑poly meshes only.

> Cast: **Rook** flies the ship **Lyra**, launching from **Earth** with the
> **Sun** at the heart of the system.

## ✨ What makes it tick

- **Real positions, not eyeballed.** The Sun and all eight planets are placed
  from their *actual* coordinates, fetched live from **NASA/JPL Horizons** for
  today's date (keyless), with constants verified against Horizons to 4 decimals
  as an offline fallback. Earth is the geocentric origin; nearby stars
  (Proxima, Sirius, Tau Ceti…) are placed from the real J2000 catalog.
- **Floating origin.** At astronomical scale 32‑bit floats fall apart, so the
  ship stays pinned at `(0,0,0)` and the universe moves around it. Each body's
  true position is tracked as data and rendered relative to the ship.
- **Dot → body LOD.** Far away, a body is a soft billboard dot; up close it
  crossfades into a real model (Earth, the Sun) or an emissive sphere.
- **Arcade 6DOF flight.** Mouse aims, `WASD` thrusts, the hull banks into turns,
  momentum eases to a stop — simple but with character. Dock at the station to
  swap ships.
- **Minimal, code‑spawned HUD.** Distance from Earth, speed, and the nearest
  body — just labels on a `CanvasLayer`.

## 🎮 Controls

| Input | Action |
|---|---|
| `Mouse` | Aim |
| `W` / `S` | Thrust forward / back |
| `A` / `D` | Strafe |
| `Space` / `Ctrl` | Up / down |
| `Q` / `E` | Roll |
| `Shift` | Boost |
| `Mouse wheel` | Zoom the chase camera |
| `F` | Dock / undock at the station |
| `Esc` | Free the cursor |

## ▶️ Running it

1. Install **Godot 4.6+** (standard build, GDScript — no C# needed).
2. Open this folder as a project in Godot.
3. Press **F5** (or the Play button).

No API keys, accounts, or build steps required.

## 🧱 How it's put together

Everything is spawned from code; `Main.tscn` is a one‑node stub. The root
`main.gd` wires the pieces and drives update order each frame:

| File | Role |
|---|---|
| `main.gd` | Root orchestrator, lighting, docking |
| `ephemeris.gd` | Real body data + live JPL Horizons fetch + offline fallback |
| `planet_system.gd` | Dot↔body LOD, gravity, approach speed‑zones, star backdrop |
| `ship.gd` | Ship model, materials, arcade flight, boosters, speed streaks |
| `props.gd` | Hand‑placed GLB landmarks (the station, an astronaut) |
| `hud.gd` | Code‑spawned HUD labels |
| `starfield.gd` | Instanced background star field |
| `tools/real_positions.py` | Standalone script that prints/verifies the real coordinates |

The design spec and the decisions behind it live in [`CLAUDE.md`](CLAUDE.md).

## 📜 Data sources

- **Solar‑system positions** — [JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) (keyless).
- **Nearby stars** — J2000 RA/Dec/parallax from the HYG / SIMBAD catalogs.

---

A hobby / educational project. Built with [Claude Code](https://claude.com/claude-code).
