# Astryx — Session Handoff (v0.3.0)

> Pick-up doc for the next session. Project: `/home/fiazul/Desktop/godot_game`
> Godot 4.6 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main). All work
> below is committed + pushed.

## State of the game (v0.3.0)
A real-solar-system third-person explorer with light combat, navigation, and a
discovery loop. Everything is code-spawned (Main.tscn is a one-node stub).

**Ships** (`ship.gd`, `SHIP_MODELS`): Lyra, Stella, Raptor, **Vela**.
- **Vela** = FTL ship (`warp 1581` → cruise ≈0.5 ly/s). Drive **spools up** over
  ~9s while holding W (`WARP_FLOOR/WARP_CHARGE_TIME`). Hypersonic (>1500 u/s)
  disables combat + crosshair. Gold booster.
- **Raptor** = **dual-mode** (press **X**): Combat (machine-gun, `fire_cd 0.05`)
  ⇄ Warp (Vela-style FTL). Long **purple-fire** booster trail in Warp mode
  (`_update_boosters` `fire` branch). `toggle_warp_mode()` flips `warp` 1↔1581.
- Per-ship boosters: `BOOSTER_LAYOUTS` (count/positions), `BOOSTER_RADIUS_SCALE`,
  `BOOSTER_LENGTH_SCALE`, `BOOSTER_COLOR_OVERRIDE`. Stella red, Lyra longer.

**Flight feel:** directional approach speed-limit (`ship.fly` cap uses
`nearest_dir`) — eases down when moving TOWARD a body (stable scan), free to
escape AWAY (no "stuck at Earth"). Warp ships ignore the limit.

**Galaxy / navigation:**
- Named stars (`Ephemeris.STARS`) are **real floating-origin destinations** at
  true distances (`star_true_pos`, `UNITS_PER_LY`). Fly toward one → ly counts
  down → blooms into an emissive sphere (`planet_system.gd` star loop, consts
  `STAR_SKY/STAR_NEAR/STAR_RADIUS`). Only Vela/Raptor-warp are fast enough.
- **Waypoint navigator** (Tab) + **3D orientation gizmo** + **off-screen arrow**
  (`navigator.gd`). **Corner radar** (`minimap.gd`).
- **Star map** (M, `map.gd`) → click a system to jump. **Wormhole** = **F**
  (`wormhole.gd`, black-hole visual). **Alien Zone** system holds Vortex boss +
  aliens; Sol/exoplanet systems are peaceful (`SystemDB.is_hostile`).

**Discovery:** hold **V** near a body to scan → persistent **Codex** (C,
`codex.gd`/`codex_panel.gd`, `user://codex.json`). Details panel (**G**,
`planet_info.gd`) shows real NASA facts (`planet_data.gd`, cached + 20-day
refresh from the Exoplanet Archive), **gated behind discovery**.

**Combat** (`combat.gd`): straight bolts, hitmarker + enemy flash + explosive
bursts, Vortex boss (his old ship hull, scaled huge, red). `ship.fire_cooldown`
drives rate.

**UI:** Settings overlay (`settings.gd`, volume/sensitivity/glow/render-scale/
fullscreen) opened by the **⚙ button**. Styled top-right control bar (Map/Codex/
Settings). **Esc** = release/recapture cursor & "back" (no longer opens
settings). Bigger HUD + 3D names. `project.godot` stretch = `canvas_items`.

## Controls
WASD thrust · Shift boost · Q/E roll · Space/Ctrl up·down · L-click fire ·
**Tab** waypoint · **V** scan · **C** codex · **G** details · **M** map ·
**F** dock/wormhole · **X** Raptor mode · **H** home · **Esc** cursor/back ·
mouse-wheel zoom · **1–4** swap ship (docked).

## ⭐ NEXT VERSION — Plan C: double-precision (the big one)
The galaxy is navigable now, but at ly-scale `true_pos` (millions of units)
float32 precision wobbles distant bodies (the "warp wall"). **Plan C** = rebuild
Godot with `precision=double` (64-bit coords) so the *entire* galaxy is flyable
with no jitter — the foundation for **real planet sizes** and **actual landable
surfaces**. This was explicitly deferred to next version.

Also queued (from the brainstorm): **proximity inflation** (planets tower over
you up close), **combat stakes** (Hull 0 currently does nothing → death/respawn),
moons/sub-planets, more real systems (TRAPPIST done; add neutron stars).

## Headless workflow (assistant can't see a GPU)
Render via xvfb + software GL to verify geometry/composition (NOT final colour):
```
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 res://tools/<scene>.tscn
```
A tiny tool scene loads/builds, awaits frames, saves to `user://x.png`; copy from
`~/.local/share/godot/app_userdata/Astryx/` and read it. **Always delete
`tools/*` afterwards (keep only `real_positions.py`).** Run `godot --headless
--import` after adding a `class_name` so the registry updates.
