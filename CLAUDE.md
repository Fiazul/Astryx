# Astryx — Build Spec

> Hobby / educational Godot project. This doc is the source of truth.
> **Don't re-discuss or re-justify these decisions — they're settled. Build from them.**

## What this is
**Astryx** — a third-person space explorer. You start at Earth, fly through space, and
planets appear as glowing dots that grow and resolve as you approach. Runs on a potato
PC. Scope is intentionally small. No combat, no menus, no inventory.

### Cast / canon (named 2026-06-12 by dev; fleet updated 2026-06-13)
- **Astryx** — the game.
- **Earth** — the launch point (player starts here; floating-origin world origin = Sol).
- **Rook** — the pilot (he).
- **The fleet (she)** — swappable 3rd-person hulls, picked at the station. Roster
  lives in `SHIP_MODELS` (`ship.gd`). Default is Lyra.
  - **Lyra** — the default hull; the starter you launch in.
  - **Stella** — the OG: the original, balanced, dependable ride.
    (The name once belonged to Lyra; it was freed up on 2026-06-12 and is now its
    own ship.)
  - **Raptor** — the dangerous one. Press **X** to flip her dual mode: Combat (a
    massive-fire-rate machine gun) ⇄ Warp (FTL, lightyear-class speed). Purple
    booster.
  - **Vela** — the fast, sleek FTL cruiser. Her warp drive spools up and blazes
    across a system (~0.5 ly/s at full charge). Golden booster.
- **Vortex** — the alien boss. A hostile hull scaled up huge with a red-hot menace
  tint; lives in the Alien Zone with the regular aliens and gets a boss HP banner on
  the HUD. (See `combat.gd` / `systems.gd`.)

## Hard constraints (already decided — do not revisit)
- **Engine:** Godot 4.x, **GDScript** for all game logic. (Dev knows C++/Python;
  GDScript chosen for fast iteration. Drop to C++/GDExtension ONLY if a hot path
  demands it — not preemptively.)
- **No solid planet surfaces.** Planets are glowing dots / emissive bodies, NOT
  detailed rendered surfaces. Aesthetic is dots-and-glow, not realism.
- **Potato-friendly is a requirement, not a nice-to-have:**
  - Stars/planets use **emissive materials + glow**, NOT `Light3D` nodes.
  - Shadows OFF globally.
  - Star field via `MultiMeshInstance3D`, never thousands of separate nodes.
  - Low-poly meshes only (sphere ~16 segments) where meshes are used at all.
- **Third-person chase camera.** (Revised 2026-06-12 by dev: was first-person/cockpit;
  now ship visible in 3rd person, with a free-look mode — hold RMB or T to orbit the
  camera while the ship flies on.) The ship hull IS visible, so it needs a model.
  (Originally specced as primitives-in-code; in practice the hulls are free low-poly
  GLBs collected from the internet — see `SHIP_MODELS` in `ship.gd`. Boosters/plumes
  are still built in code on top of the GLB.)
- **Minimal UI.** Just `Label`s for: light-year distance, nearby planet name,
  optional speed. Spawn them from code on a `CanvasLayer`. Do NOT build menus,
  anchored layouts, themes, or containers.

## The scale problem (critical — get this right early)
At light-year / astronomical scales, 32-bit floats break (jitter, warped geometry).
**Solution: floating origin.** Keep the ship pinned at (0,0,0); move the *universe*
around it every frame. Track each body's "true" position as plain data; render
position = `true_pos - ship_pos`. Display light-year distance as a label only.
Do NOT recompile Godot for double precision yet — floating origin alone covers it.

## Build order (do these in sequence)
1. **Godot basics sanity check** — a controllable camera/ship flying in empty 3D space (WASD + mouse look).
2. **Floating origin** — implement it now, while the scene is simple. Ship stays at origin; world moves.
3. **Dot→body LOD** — each planet = a billboard `Sprite3D` "dot" (always visible, scales with distance) + a hidden low-poly emissive sphere that only appears when close. (No solid surface — emissive glow only.)
4. **HUD label** — light-year distance readout via code-spawned `Label` on a `CanvasLayer`.
5. **Star field** — `MultiMeshInstance3D` background, emissive points, glow via `WorldEnvironment`.
6. **Real data (DONE)** — keyless `HTTPRequest` feeds: live JPL Horizons for Sun+planets, NASA Exoplanet Archive for exoplanet facts, baked HYG/SIMBAD constants for stars. No `api.nasa.gov` / API key. See "Real data sources" below.

## Reference snippets (starting points, not final)

### Dot→body LOD with floating origin
```gdscript
extends Node3D

var planets := [
	{ "name": "Earth",    "pos": Vector3(0, 0, 0),         "radius": 1.0, "color": Color(0.2, 0.5, 1.0) },
	{ "name": "Mars",     "pos": Vector3(500, 0, 200),     "radius": 0.8, "color": Color(0.9, 0.4, 0.2) },
	{ "name": "GasGiant", "pos": Vector3(-1200, 300, 800), "radius": 3.0, "color": Color(0.8, 0.7, 0.4) },
]

@export var ship: Node3D
@export var detail_distance := 80.0
var bodies := []

func _ready():
	for p in planets:
		var dot := Sprite3D.new()
		dot.texture = preload("res://dot.png")  # small white circle
		dot.modulate = p.color
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(dot)

		var sphere := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radial_segments = 16
		mesh.rings = 8
		mesh.radius = p.radius
		mesh.height = p.radius * 2.0
		sphere.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p.color
		mat.emission_enabled = true        # emissive glow, no Light3D
		mat.emission = p.color
		sphere.material_override = mat
		sphere.visible = false
		add_child(sphere)

		bodies.append({ "data": p, "dot": dot, "sphere": sphere })

func _process(_delta):
	var ship_pos: Vector3 = ship.global_position if ship else Vector3.ZERO
	for b in bodies:
		var rel: Vector3 = b.data.pos - ship_pos   # floating origin
		var dist := rel.length()
		b.dot.position = rel
		b.sphere.position = rel
		if dist < detail_distance:
			b.sphere.visible = true
			b.dot.visible = false
		else:
			b.sphere.visible = false
			b.dot.visible = true
			b.dot.pixel_size = clamp(0.02 * (detail_distance / dist), 0.005, 0.05)
```

### Code-spawned HUD label
```gdscript
extends Node3D

var label: Label

func _ready():
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20, 20)
	canvas.add_child(label)

func _process(_delta):
	var dist_ly := 4.2  # replace with real calc
	label.text = "Distance: %.2f ly" % dist_ly
```

### Real data sources (done — keyless, no API key)
We do NOT use the `api.nasa.gov` APOD/`DEMO_KEY` API. The real, keyless feeds are:
- **JPL Horizons** — live Sun + planet positions, `ephemeris.gd`
  (`https://ssd.jpl.nasa.gov/api/horizons.api`). Baked constants (verified against
  Horizons) are the offline fallback so the scene is correct from frame 1.
- **NASA Exoplanet Archive (TAP)** — exoplanet facts refresh, `planet_data.gd`
  (`https://exoplanetarchive.ipac.caltech.edu/TAP/sync`), cached to
  `user://planet_data_cache.json`. Curated NASA fact sheets are the bundled fallback.
- **HYG / SIMBAD** — nearby-star catalog, baked as J2000 constants in `ephemeris.gd`.

All `HTTPRequest`-based, non-blocking, best-effort. `NASA_API_KEY` in `.env.example`
is unused — kept only as a placeholder for a possible future key-gated feed.

## Known time sinks (where effort actually goes)
- Floating-origin math at scale.
- Making fly-controls *feel* good.
- NOT the UI. UI is trivial here. Don't over-invest.

## Resolved decisions
- **Movement model:** arcade 6DOF with velocity damping + cosmetic banking into
  turns — simple, forgiving, with weight/character. Mouse aims; WASD thrust;
  Space/Ctrl up·down; Q/E roll; Shift boost. Implemented in `ship.gd`. (Base decided
  2026-06-12; the "N.O.V.A.-style" framing is dropped — the game has grown its own
  feel.) On top of the base model:
  - **Warp / FTL** — Vela (and Raptor in Warp mode) spool a warp drive up over time
    toward lightyear-class cruise, then back down; combat + crosshair disable while
    hypersonic.
  - **Free-look** — hold RMB or T to orbit the camera; release snaps back behind.
  - **Approach speed limit** — flight eases down as you near a body for stable
    scanning, but is free to escape away from it.
- **Esc / cursor & Settings (changed):** Esc no longer just frees the cursor as a
  one-shot — it toggles mouse capture (press again to recapture and fly). A Settings
  overlay (gear button) handles volume, sensitivity, glow, render scale, fullscreen.
  (Updated 2026-06-13.)
