# Astryx — Session Handoff

> Pick-up doc for the next (compact) session. Focus: **ship work** + **audio wiring**.
> Project: `/home/fiazul/Desktop/godot_game` · Godot 4.6 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main, tag `v0.2.0`).

## ⚠️ FIRST THING: uncommitted local changes
`v0.2.0` is pushed, but the **latest ship work is NOT committed yet**. Local edits ready to ship as **`v0.2.1`**:
- **New Lyra = `Rocket ship.glb`** (a low-poly space shuttle; kept the name "Lyra", dropped the old purple model + chrome override). Colors come from its texture (white/orange/black), `metallic 0`, white tint — rendered faithfully.
- **5 boosters** (the shuttle's engine cluster) — see `BOOSTER_MOUNTS` in `ship.gd`.
- **"Glowing bulb" fix** — see below.
→ Decision pending: commit as `v0.2.1` + **delete now-unused `Lyra.glb` / `Lyra_0.png`** (no longer referenced in any `.gd`). Verify with: `grep -c Lyra.glb *.gd`.

## Recent ship work (what & where)
- `ship.gd` `SHIP_MODELS` — 4 ships: **Lyra** (shuttle), **Stella**, **Vortex**, **Raptor** (last two = `Spaceship (1/2).glb`, also reused as aliens). All `yaw 180`, `glow 0.0`.
- `ship.gd` `BOOSTER_MOUNTS` (5 × `Vector2(x,y)`, fractions of ship width) + `_build_boosters()` + `BOOSTER_BACK 0.40` — nudge these to snap plumes onto each engine bell. `BOOSTER_COLOR` is cyan (line ~29) — change to orange if you want shuttle-like exhaust.
- `ship.gd` `_recolor(model, tint, glow, chrome)` — `chrome:true` = white-metal+cyan override (currently unused; Lyra no longer uses it). Non-chrome keeps the model's own texture.

## The "bulb glow" fix (in `main._setup_environment`)
Was: everything haloed into glowing bulbs. Root cause = **`glow_bloom`** haloing lit surfaces. Now:
- `glow_bloom = 0.0` + `glow_hdr_threshold = 1.0` → **only emissive bodies (stars/Sun/portal) glow**, never lit metal.
- `glow_intensity 0.55`, levels lowered.
- `tonemap_exposure = 0.7` → global **−30% brightness** (keeps colour + specular shine).
- All ship `glow` (self-emission) set to **0.0** — they're always lit by the key+fill `DirectionalLight3D`s, so no self-glow needed.
**Tuning dials:** `tonemap_exposure` (overall brightness), `glow_intensity` (how much stars bloom).

## 🔊 Audio — the dev is making these files; wire them on arrival
Drop files in project root with these names; wire each to its trigger. **Priority-1 four ≈ 90% of the "alive" feel.**

**P1 — combat (short `.wav`, dry):**
| File | Trigger | Where to hook |
|---|---|---|
| `sfx_fire.wav` | player bolt (≤0.08s, fires ~16/s) | `combat.gd` `_spawn_bolt` (player branch) / `update()` fire |
| `sfx_explosion.wav` | alien dies (~0.6s) | `combat.gd` `_damage_alien` → `_boom` |
| `sfx_hit.wav` | alien bolt hits you (~0.3s) | `combat.gd` `_step_bolts` player-hit branch |
| `sfx_alien_fire.wav` | alien fires (lower pitch) | `combat.gd` `_step_aliens` fire block |

**P2 — travel:**
| File | Trigger |
|---|---|
| `sfx_engine.ogg` (**loop**) | while thrusting/boost — `ship.fly()` throttle |
| `sfx_warp.wav` | press J / enter portal — `main._input` J / `wormhole.start_transit` |
| `sfx_tunnel.ogg` (**loop**) | during transit — `wormhole.update()` transiting |
| `sfx_teleport.wav` | teleport home — `main.teleport_home` |

**P3 — polish:** `sfx_click.wav` (teleport button), `sfx_alarm.wav` (Hull < 20%).

**Wiring pattern:** make a small `audio.gd` (a pool of `AudioStreamPlayer`s) or add players in `combat.gd`/`ship.gd`; one-shots = `.play()` on a fresh/pooled player (gun needs several voices for rapid fire), loops = one player toggled. Bus: keep SFX above music (music is at −14 dB in `main._setup_music`, gated to play only while moving).

## How to "see" without a GPU (the dev runs the game; assistant can't)
Headless can't render. Use xvfb + software GL:
```
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 res://tools/<scene>.tscn
```
A tiny scene-script loads `res://Main.tscn`, awaits ~20 frames, `get_viewport().get_texture().get_image().save_png("user://x.png")`, `get_tree().quit()`. Copy the png out of `~/.local/share/godot/app_userdata/Astryx/` and Read it. **Caveat: llvmpipe misrepresents colour/exposure** — trust it for geometry/composition, NOT final colour. Always delete `tools/*` afterwards (keep only `real_positions.py`).
**New `class_name` scripts:** run `godot --headless --import` once so the global class registry picks them up, or you'll get false "Identifier not declared" parse errors.

## State of the game (v0.2.x)
Real solar system (live JPL Horizons) · **wormhole** Sol↔K2-18/K2-18b (press J at portal; transit `SEC_PER_LY=0.15`≈18s, set `2.9` for ~6 min) · **combat** (L-click machine-gun, aliens hunt+fire, Hull/Kills HUD) · **teleport** (H key / button) · **music** (gated to travel). Floating-origin engine; each system is local small-coord space → no precision issues (double-precision refactor is MOOT, don't do it).

## Next-phase options (dev was choosing)
1. **A — combat feel:** wire SFX (above) + **death/respawn** (Hull 0 currently does nothing) + **off-screen target arrow** to nearest alien + hit-flash/shake.
2. **B — more galaxy:** map + click-to-jump (not just one portal) + more real exoplanet systems (TRAPPIST-1, Proxima b).
3. **C — polish:** animated ship-select table; confirm Earth renders blue on real GPU.
Dev leaned toward **A** (it's demo day; combat is the freshest). Also pending: commit `v0.2.1`, delete old `Lyra.glb`, optional rocket-orange boosters.

## Quick start for next session
1. Read this file + `git status` (uncommitted shuttle work).
2. If audio files present → wire P1 first.
3. Verify via xvfb render; commit `v0.2.1` when the dev's happy.
