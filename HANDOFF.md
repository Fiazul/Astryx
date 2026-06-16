# Astryx — Session Handoff (v0.10.0)

> Pick-up doc for the next session. Project: `/home/fiazul/Desktop/Astryx`
> Godot 4.6.2 / GDScript · repo `git@github.com:Fiazul/Astryx.git` (main). Everything
> below is committed + pushed. The game is **all code-spawned** — `Main.tscn` is a
> one-node stub; `main.gd` builds the world, ship, camera, lights, and UI at runtime.

## State of the game (v0.10.0)
A real-solar-system third-person explorer with light combat, navigation, a
discovery loop, a coin economy, an **in-hangar ship customizer**, a **mission log**,
and a **zoomable star map**. ~10.5k lines of GDScript across 25 modules; 51 real
star systems; Android APK + touch controls; CI release builds.

## What changed since v0.8

### v0.9.0 — wormhole graph + quests + full resume
- **Wormhole graph travel**: Prim's MST + extra edges; BFS `next_hop()` routing over
  *known* edges (`is_edge_known`); the Interstellar hub only lists **unlocked** wormholes.
- **Full state resume**: position, system, hull, coins, discoveries, onboarding step,
  and active quest all persist to `user://profile.cfg` (saved from stable states only).

### v0.10.0 (this session)
- **Mission Log (J)** — `missions.gd` (`MissionDB`): every star/planet/moon is a mission
  with a crude/savage (mostly-true) story + coin bounty (`STORIES` keyed by body name).
  `quest_log.gd` (`QuestLog`, CanvasLayer) is the board: list grouped by system, detail
  pane, **★ Track** → `main.track_quest()` drives the nav arrow; survey to complete/claim.
- **Zoomable / pannable map** — `map_chart.gd` (`MapChart`, custom `_draw`): wheel-zoom,
  drag-pan out to ~150 ly, star/wormhole/planet icons on **toggleable filter layers**, a
  live animated **player cursor**, hover read-outs, wormhole lanes. `map.gd` hosts it +
  filter chips + a right-side system body list. Wormholes are live on the corner radar
  (`wormhole.portals_rel`, `minimap.gd` swirl blips); the nav arrow prioritises wormholes.
- **Warp-speed rebalance** — top hulls ≈ 23–24 s/ly, mid ≈ 28–30 s, others ≈ 40 s. Tuned
  via per-hull `warp` (terminal velocity = `THRUST × warp / DAMPING`, NOT the `MAX_SPEED`
  cap). `UNITS_PER_LY = 6,324,107.7`; `warp ≈ 2874.6 / target_seconds`.
- **HaniStar customizer** — now `color_pick` like HaniNebula: body + wing swatches, bell
  toggle, metallic/glassy finish. Wings = **GLB surface 4** (verified by rendering each
  surface). Added `wing_surfs` (list) + `wing_role` options for multi-surface wings
  (HaniNebula's single `wing_surf` couldn't express it). `current_has_wing_pick()` now
  recognises all three (`wing_surf`/`wing_surfs`/`wing_role`).
- **Champagne Gold** palette — new `champagne` swatch + `recolor` role (polished gold:
  metallic 0.85, roughness 0.16). Palette is now **10** colours.
- **Editable Cancel Nav** (and HUD declutter) — `cancel_nav` is a registered movable HUD
  widget (drag-place + wheel-scale, persists to `user://hud_layout.cfg`); default baked
  into `DEFAULT_LAYOUT`/`DEFAULT_SCALE`. Centre-screen clutter (objective/quest/tip lines,
  bottom help strip) moved off to the free right side (`rx = SCREEN.x - 300`).
- **Guardian "phantom boss" bugfix** — a guardian boss parked at a body kept summoning/
  firing with no distance gate → `in_combat()` stayed true → warp bled to sublight →
  player stranded with a stuck "100%" bar. Fixes: a **leash** in `_update_scan` abandons
  the fight (`combat.abandon_combat()`, zeroes `_combat_t`) once you're > `GUARD_RANGE×2.5`
  from the guarded body; `reset()` clears stale `guard_body`/`zone_kills`/`_combat_t`.
- **Named bosses** — `combat.BOSS_NAMES` (crude/savage), deterministic per body via hash;
  `boss_state()` returns `name`; HUD bar + probe scan show it (Alien-zone boss = "Vortex").

### Ships (`ship.gd`, `SHIP_MODELS`)
Seven hulls. Each entry tunes hp / fire / warp / booster / surface roles.
- **Lyra** tanky red laser-bolts (`raw` look) · **Stella** glass-cannon machine-gun ·
  **Raptor** dual-booster bruiser (X = warp/combat form fork) · **Vela** FTL, spools over
  ~9s, **R** air-brake · **HaniStar** pink support that fights (`bolt_strong`), now
  colour-pickable · **Raptor 2 Neo** mother-ship with nose **laser** (2 GLB surfaces:
  `silver` hull + `glass` strips) · **HaniNebula** evolved pro form, fully colour-pickable,
  boosters snapped to her model's real engine holes (`BOOSTER_NO_RING`), own music track.

### In-hangar customizer (`hud.gd set_hangar` → `main.gd` → `ship.gd`)
- **BODY / WING COLOUR** swatches from `Ship.SHIP_PALETTES` (10: rosegold, blush, navy,
  teal, charcoal, emerald, burgundy, silver=SteelBlue, gold=Silver, **champagne**=gold).
- **ENGINE BELL** add/remove · **FINISH** metallic/glassy (`ShipMesh.set_glassy`).
- Opt in with `"color_pick": true`. Surface mapping styles in `_build_ship_model`:
  **whole-hull** (HaniNebula: body everywhere except `wing_surf`) vs **template**
  (Raptor 2 / HaniStar: replace `body_role` surfaces, paint `wing_surf`/`wing_surfs`/
  `wing_role` with wing colour, keep glass).
- Persisted per-ship: `ship.customization_state()`/`load_customization()` ↔
  `user://profile.cfg` `[player] customization`.
- ⚠️ **Metallic gotcha:** in this probe-less scene `metallic = 1.0` has no diffuse and
  only mirrors the empty starfield → reads as *clear glass*. Palette roles use
  `metallic ≈ 0.55` + `emission = albedo` so colours stay solid (see `ship_mesh.gd recolor`).

### Flight feel, VFX, audio
- **Sublight drift** (`DRIFT_DAMPING` 0.32) glides through turns; blends to `DAMPING`
  (0.75) as warp spools so FTL times stay tuned. Heavy A/D + up/down low-passed.
- Living booster flame (layered sines on a smoothed base) + motion streaks.
- Per-ship engine voice ducks under music after ~8s; **HaniNebula** has her own track.

## Controls
WASD thrust · **Shift** boost · **Q/E** roll · **Space/Ctrl** up·down ·
**L-click** fire · **R-click** laser (Raptor 2) · **Tab** waypoint · **V** scan/capture ·
**C** codex · **J** mission log · **G** details · **M** map · **F** dock/wormhole ·
**R** Vela brake · **Num Lock** auto-cruise · **H** teleport Earth · **Esc** cursor/back ·
wheel zoom · **1–7** swap ship (docked).

## ⭐ NEXT — planned TODO (carried over)
1. **Bullet "bloat" fix** (combat.gd) — the fat cyan bar in fast dogfights. Root cause
   diagnosed: a 51-unit additive trail + hard bloom (emission 10) near the ~1u chase cam.
   Levers: cap `reach` to ~20 + drop emission to ~4. **Reverted twice** — must NOT change
   shooting speed/gating; only the trail/bloom. Get a screenshot to confirm.
2. **Platform F-interaction** — at a platform, **F** lets you choose ship AND quick-teleport
   to another unlocked platform. (Platforms = wormhole-attached now + player-placed later.)
3. **Show platforms on the map** (each platform's position).
4. **Confirm warp boost fork** — is the 23 s/ly the W-cruise terminal or boosted? If boosted,
   divide `warp` by ~3.
5. **Unify interaction on F** — drop **V** capture (hold-F to capture; F context chain:
   dock/platform/wormhole/capture); repurpose **V** → auto-navigate to the tracked quest.
   (Do NOT change shooting.)
6. **Right-side quest box** — boxed/table tracker on the right; click or key → navigate.
   Replaces the old top-centre tracker.
7. **Guide/prompts as side notifications** — boxed, clickable for detail (currently plain
   right-side labels).
- Background long-shot: **double-precision build** (`precision=double`) to kill float32
  jitter at ly-scale → real planet sizes + landable surfaces; combat stakes (Hull 0 is a
  no-op today → death/respawn).

## Headless / verification workflow (assistant can't see a live GPU)
- **Parse check** — never `--import` the real tree (the importer re-tabs `ship.gd`
  comments). Validate on a **copy**: `cp -r . /tmp/acheck && rm -rf /tmp/acheck/.godot &&
  godot --headless --path /tmp/acheck --import` then grep stderr for errors.
- **Render a model surface-by-surface** (to identify wings etc.) — the real Godot binary
  (`/home/fiazul/Desktop/space_craft/Godot_v4.6.2-stable_linux.x86_64`) under
  `xvfb-run` renders with hardware GL: load the GLB into a `Node3D` scene, tint each
  surface a distinct colour, position a `Camera3D`, `await` a few `process_frame`s, then
  `get_viewport().get_texture().get_image().save_png(...)`. Run as a real scene
  (`godot --path COPY res://render.tscn`), NOT `--script` (a SceneTree `--script` won't
  pump render frames and hangs).
- Visual changes need the user's eyes — get a screenshot before declaring done.

## Profile / saves
`user://profile.cfg` (progress + per-ship customization), `user://codex.json`
(captures), `user://hud_layout.cfg` (HUD layout). Flatpak userdata:
`~/.var/app/org.godotengine.Godot/data/godot/app_userdata/Cold Light/`.
