# Astryx — Session Handoff (v0.8.0)

> Pick-up doc for the next session. Project: `/home/fiazul/Desktop/Astryx`
> Godot 4 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main). Everything
> below is committed + pushed. The game is **all code-spawned** — `Main.tscn` is a
> one-node stub; `main.gd` builds the world, ship, camera, lights, and UI at runtime.

## State of the game (v0.8.0)
A real-solar-system third-person explorer with light combat, navigation, a
discovery loop, a coin economy, and an **in-hangar ship customizer**.

### Ships (`ship.gd`, `SHIP_MODELS`)
Seven hulls. Each entry tunes hp / fire / warp / booster / surface roles.
- **Lyra** — tanky, slow red laser-bolts (`bolt_laser`), authored look (`raw`).
- **Stella** — glass-cannon machine-gunner (80 hp, `fire_cd 0.04`).
- **Raptor** — bruiser, dual booster.
- **Vela** — the FTL ship; drive **spools up** over ~9s holding W
  (`WARP_FLOOR`/`WARP_CHARGE_TIME`). **R** = air-brake (`brake`) to actually park.
- **HaniStar** — pretty pink support hull that fights; **strong pink bolts**
  (`bolt_strong` → `HANI_PINK` in `combat.gd`), light-blue boosters.
- **Raptor 2 Neo** ("mother ship") — powerhouse + nose **laser beam** (R-click).
  OBJ has exactly **2 surfaces**: `Mat` (whole hull) + `iluminators` (window
  strips) → `surf_roles: ["silver","glass"]` (hull = solid metal body, strips =
  glass). Body **colour-pickable**.
- **HaniNebula** — HaniStar's evolved pro form. Combat tuned to Raptor 2 Neo.
  Metallic silver + gold wings, **fully colour-pickable** (body + wings).
  Boosters are snapped to her model's **real engine holes** (16 mounts found via
  union-find clustering — `BOOSTER_LAYOUTS["HaniNebula"]`, no metal bell:
  `BOOSTER_NO_RING`). Has her **own background music** (see Audio).

### In-hangar customizer (NEW in v0.8) — the big feature
Dock at a station, pick a ship, and a **customization panel** appears
(`hud.gd set_hangar`). Signals: `ship_color_selected(part,key)`,
`ship_bell_toggled(on)`, `ship_finish_selected(key)` → wired in `main.gd` →
`ship.gd` rebuilds the hull.
- **BODY / WING COLOUR** swatches — `Ship.SHIP_PALETTES` (9: rosegold, blush,
  navy, teal, charcoal, emerald, burgundy, silver=SteelBlue, gold=Silver).
- **ENGINE BELL** add/remove · **FINISH** metallic/glassy (`ShipMesh.set_glassy`).
- Ships opt in with `"color_pick": true`. Two styles in `_build_ship_model`:
  **whole-hull** (HaniNebula: body everywhere except `wing_surf`) vs **template**
  (Raptor 2: replace `body_role` surfaces, keep glass).
- **Persisted per-ship** across sessions: `ship.customization_state()` /
  `load_customization()` ↔ `user://profile.cfg` `[player] customization`
  (`_color_choice`/`_bell_choice`/`_finish_choice`). Saved on every change.
- ⚠️ **Metallic gotcha:** in this probe-less scene `metallic = 1.0` has no diffuse
  and only mirrors the empty starfield → reads as *clear glass*. All palette roles
  use `metallic ≈ 0.55` + `emission = albedo` so colours stay solid. Don't crank
  metallic back to 1.0 (see the long comment block in `ship_mesh.gd recolor`).

### Flight feel (`ship.fly`)
- **Sublight drift** — sublight uses a light `DRIFT_DAMPING` (0.32) so the ship
  **glides / carries momentum through turns**; blends back to `DAMPING` (0.75) as
  warp spools (`eff_warp` 1→2) so **FTL travel times stay tuned**. Top sublight
  speed is still capped (`SUBLIGHT_MAX`), so this adds glide, not speed.
- **Heavy A/D + up/down** — `strafe`/`lift` inputs are low-passed (`_strafe`/
  `_lift`, `STRAFE_SMOOTH`) so they ramp in/coast out; mouse-steer already eased
  (`_steer`/`STEER_SMOOTH`). Forward/back stays responsive.
- **Muzzle** locked to the nose centreline (`muzzle_world`, `MUZZLE_BANK_FOLLOW=0`)
  so bolts don't drift sideways when you bank/strafe.

### Motion + booster VFX
- **Motion streaks** (`_update_streaks`, GPUParticles) now ramp from a *gentle*
  sublight cue (so normal cruise no longer feels static — `sub*0.72`) up into the
  dramatic warp stretch. Tune the `0.72` for sublight visibility.
- **Living booster flame** (`_update_boosters`) — every engine now flickers/shimmers
  even at cruise (layered sines applied *instantly* on top of a smoothed base, so
  the per-frame lerp can't flatten it). Warp form flickers harder. Amplitudes are
  small (`amp` / `shimmer`) — that's the "gentle breathe, not flapping" tuning.

### Audio (`audio.gd` engine/SFX · `main.gd` music)
- Engine voice = per-ship loop + start/stop whooshes; ducks under the music after
  ~8s of steady drive (`drive_time`).
- Background music gated by the drive clock. **HaniNebula has a dedicated track**
  (`assets/bgm_hani.ogg`) swapped in *only while silent/paused* so it fades in/out
  cleanly (`_desired_music_track`, `_music_hani`). Source was a user-edited mashup.

### Economy / nav / discovery (unchanged from v0.7)
Coins (capture rewards, `user://profile.cfg`), paid navigator, star map (M),
wormhole (F), Codex (C), scan (V), real NASA facts (G).

## Controls
WASD thrust · **Shift** boost · **Q/E** roll · **Space/Ctrl** up·down ·
**L-click** fire · **R-click** laser (Raptor 2) · **Tab** waypoint · **V** scan ·
**C** codex · **G** details · **M** map · **F** dock/wormhole · **R** Vela brake ·
**Num Lock** auto-cruise · **Esc** cursor/back · wheel zoom · **1–7** swap (docked).

## ⭐ NEXT VERSION — candidates
- **Plan C: double-precision build** (still the big one). At ly-scale `true_pos`
  (millions of units) float32 wobbles distant bodies. Rebuild Godot with
  `precision=double` for a jitter-free galaxy → real planet sizes + landable
  surfaces. Then: proximity inflation, combat stakes (Hull 0 does nothing now →
  death/respawn), moons, more real systems.
- **Customizer polish**: glowing illuminators on Raptor 2 (emissive role instead
  of glass); colour-pick the HaniNebula booster/exhaust tint; preview swatches.

## Headless workflow (assistant can't see a GPU)
Render via xvfb + software GL to verify geometry/composition (NOT final colour):
```
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --rendering-driver opengl3 --resolution 1280x720 res://tools/<scene>.tscn
```
A tiny tool scene loads/builds, awaits frames, saves to `user://x.png`; copy from
`~/.local/share/godot/app_userdata/Astryx/` and read it. **Delete `tools/*`
afterwards.** Run `godot --headless --import` after adding a `class_name`, and
after changing a `.obj`/audio asset (regenerates `.godot/imported/*`). Note:
`godot` may not be on PATH — there's no CLI parse-check available in that case.
