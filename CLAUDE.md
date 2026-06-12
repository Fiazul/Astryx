# Astryx — Build Spec

> Hobby / educational Godot project. This doc is the source of truth.
> **Don't re-discuss or re-justify these decisions — they're settled. Build from them.**

## What this is
**Astryx** — a third-person space explorer. You start at Earth, fly through space, and
planets appear as glowing dots that grow and resolve as you approach. Runs on a potato
PC. Scope is intentionally small. No combat, no menus, no inventory.

### Cast / canon (named 2026-06-12 by dev)
- **Astryx** — the game.
- **Earth** — the launch point (player starts here; floating-origin world origin = Sol).
- **Rook** — the pilot (he).
- **Lyra** — the ship (she). The visible 3rd-person hull is Lyra. (Renamed from
  "Stella" 2026-06-12.)

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
  now N.O.V.A.-style — simple-but-characterful flight, ship visible in 3rd person.)
  The ship hull IS visible, so it needs a model — but a *simple low-poly* one with
  some character, built from primitives in code. Not a detailed asset.
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
6. **NASA data (optional, later)** — `HTTPRequest` node pulls real positions (e.g. NASA Exoplanet Archive / HYG star DB) to place bodies. This is just HTTP + JSON; it's the easy part.

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

### NASA API (optional, later)
```gdscript
func _ready():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_done)
	http.request("https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY")

func _on_done(result, code, headers, body):
	var data = JSON.parse_string(body.get_string_from_utf8())
	print(data["title"])
```
Free key: api.nasa.gov. Real positional data: NASA Exoplanet Archive, HYG star database.

## Known time sinks (where effort actually goes)
- Floating-origin math at scale.
- Making fly-controls *feel* good.
- NOT the UI. UI is trivial here. Don't over-invest.

## Resolved decisions
- **Movement model (was open):** arcade 6DOF with velocity damping + cosmetic
  banking into turns (N.O.V.A.-style — simple, forgiving, with weight/character).
  Mouse aims; WASD thrust; Space/Ctrl up·down; Q/E roll; Shift boost. Implemented
  in `ship.gd`. (Decided 2026-06-12.)
