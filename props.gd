class_name Props
extends Node3D
# Hand-placed GLB landmarks (space stations, an astronaut, drifting probes) tracked
# with floating origin: each has a true_pos in game units and is rendered at
# (true_pos - ship_pos) every frame, just like the planets.
#
# Each prop is tagged with the star system it belongs to; only the props for the
# currently-loaded system are shown (set_system, called from main on arrival).
#
# These are decorative points-of-interest — no collision. They're auto-fitted to
# a target size and self-lit (no Light3D in the scene), then slowly spun.
#
# Two special kinds:
#   dock  — the Sol station you can land at (ship-swap hangar); Sol-only.
#   probe — a drifting deep-space probe. Fly close and it reports the local
#           "monster data" (hostiles in this system); see Main's probe readout.
#
# pos = absolute scene units (1u = 0.1 AU). size = longest-axis target.
# yaw = initial facing. spin = rad/s idle self-rotation. glow = self-illum.
# orbit = rad/s revolution around the system's star/origin (0 = parked).
# system = which star system this prop lives in (defaults to Sol).
const PROBE_SCAN_RANGE := 90.0   # fly within this of a probe to read its scan (×10 spread)
const STRUCT_SLOW_RANGE := 1600.0  # within this of any station/probe, the ship is force-slowed
const STRUCT_MIN_SPEED := 55.0     # strict crawl right at a structure

const PROP_LIST := [
	# --- Sol: the home station (dockable) + Finn, drifting nearby ---
	{
		"name": "", "path": "res://Wikiplanet Space Station (WSS).glb",
		"system": "sol",
		"pos": Vector3(-45.0, 15.0, 15.0), "size": 20.0, "yaw": 25.0, "spin": 0.03, "glow": 0.18,
		"orbit": 0.04, "dock": true, "dock_range": 90.0,
	},
	{
		"name": "Finn", "path": "res://Astronaut.glb",
		"system": "sol",
		"pos": Vector3(-40.0, 12.0, 10.0), "size": 0.3, "yaw": 200.0, "spin": 0.35, "glow": 0.45,
		"orbit": 0.04,
	},

	# --- One BIG dockable station per exoplanet system. You can land at each (F)
	#     and swap ships in its hangar, just like Earth's. They're large hulls, so
	#     they're parked far out (~14 u from the star at the origin: their hull
	#     half-extent is ~5 u, leaving them ~9 u clear of the star and the planets
	#     that cluster within ~1.5 u). Placed on the OPPOSITE side from this
	#     system's wormhole portal (portals sit at +x/-z, ~7-8 u out) and from the
	#     arrival point, so there's no clash with the wormhole and they sit away
	#     from where the alien swarm spawns/fights. Parked, not orbiting. ---
	{
		"name": "K2-18 Station", "path": "res://International Space Station.glb",
		"system": "k2-18",
		"pos": Vector3(-110.0, 15.0, 90.0), "size": 22.5, "yaw": 30.0, "spin": 0.03, "glow": 0.5,
		"dock": true, "dock_range": 80.0,
	},
	{
		"name": "Proxima Station", "path": "res://space station.glb",
		"system": "proxima",
		"pos": Vector3(-105.0, 12.0, 95.0), "size": 27.5, "yaw": 60.0, "spin": 0.025, "glow": 0.5,
		"dock": true, "dock_range": 90.0,
	},
	{
		"name": "TRAPPIST Outpost", "path": "res://space pod.glb",
		"system": "trappist",
		"pos": Vector3(-110.0, 15.0, 85.0), "size": 20.0, "yaw": 15.0, "spin": 0.04, "glow": 0.55,
		"dock": true, "dock_range": 75.0,
	},

	# --- Drifting probes (scannable): scattered through the hostile systems, away
	#     from Earth. Each reports local monster data when you fly close. ---
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "k2-18", "probe": true,
		"pos": Vector3(-32.0, 13.0, 26.0), "size": 2.25, "yaw": 0.0, "spin": 0.5, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "k2-18", "probe": true,
		"pos": Vector3(-20.0, -13.0, 42.0), "size": 2.25, "yaw": 120.0, "spin": 0.6, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "proxima", "probe": true,
		"pos": Vector3(-28.0, 9.0, 29.0), "size": 2.25, "yaw": 40.0, "spin": 0.55, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "proxima", "probe": true,
		"pos": Vector3(-22.0, 14.0, 40.0), "size": 2.25, "yaw": 200.0, "spin": 0.45, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "trappist", "probe": true,
		"pos": Vector3(-30.0, -8.0, 27.0), "size": 2.25, "yaw": 80.0, "spin": 0.6, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "trappist", "probe": true,
		"pos": Vector3(-24.0, 10.0, 40.0), "size": 2.25, "yaw": 300.0, "spin": 0.5, "glow": 0.5 },
	{ "name": "Probe", "path": "res://Space probe.glb", "system": "alien", "probe": true,
		"pos": Vector3(-34.0, 16.0, 30.0), "size": 2.25, "yaw": 160.0, "spin": 0.6, "glow": 0.5 },
]

var _items := []
var current_system := "sol"

# Dock target (the prop flagged "dock") for the current system, read by main.
var has_dock := false
var dock_pos := Vector3.ZERO
var dock_name := ""
var dock_range := 0.0

# Probe scan: set each frame — is the ship within range of a probe right now?
var probe_in_range := false
var probe_name := ""
# Strict speed cap from structure proximity (stations + probes), read by main each
# frame: INF when clear, easing down to STRUCT_MIN_SPEED right at a structure.
var struct_speed_limit := INF


func _ready() -> void:
	for p in PROP_LIST:
		var packed := load(p.path) as PackedScene
		if packed == null:
			push_warning("Props: couldn't load %s (imported yet?)" % p.path)
			continue
		var holder := Node3D.new()
		add_child(holder)
		var model := packed.instantiate() as Node3D
		holder.add_child(model)
		model.rotation = Vector3(0.0, deg_to_rad(p.yaw), 0.0)
		_fit(holder, model, p.size)
		_self_light(model, p.glow)

		# Floating name label (billboard), positioned each frame in update().
		var label: Label3D = null
		if p.has("name"):
			label = Label3D.new()
			label.text = p.name
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.outline_modulate = Color(0, 0, 0, 0.7)
			label.outline_size = 8
			label.font_size = 40
			label.no_depth_test = true
			add_child(label)

		_items.append({
			"holder": holder,
			"label": label,
			"name": p.get("name", ""),
			"system": p.get("system", "sol"),
			"pos": p.pos,
			"up": float(p.size) * 0.7,      # label height above the prop
			"spin": float(p.get("spin", 0.0)),
			"orbit": float(p.get("orbit", 0.0)),   # revolution around the star/origin
			"cull": float(p.size) * 90.0,   # stop drawing big meshy props when far
			"is_dock": bool(p.get("dock", false)),
			"is_probe": bool(p.get("probe", false)),
			"dock_range": float(p.get("dock_range", float(p.size) * 1.8)),
		})

	set_system(current_system)


# Switch to a system: show only its props and recompute the dock target. Called
# by main on arrival (replaces the old Sol-only visibility toggle).
func set_system(id: String) -> void:
	current_system = id
	has_dock = false
	dock_name = ""
	for it in _items:
		var here: bool = it.system == id
		it.holder.visible = here
		if it.label != null:
			it.label.visible = here
		if here and it.is_dock:
			has_dock = true
			dock_pos = it.pos
			dock_name = it.name
			dock_range = it.dock_range


func update(ship_pos: Vector3, delta: float) -> void:
	probe_in_range = false
	probe_name = ""
	var near_struct := INF
	for it in _items:
		if it.system != current_system:
			continue
		# Slow revolution around the star (the origin), if this prop orbits.
		if it.orbit != 0.0:
			it.pos = it.pos.rotated(Vector3.UP, it.orbit * delta)
			if it.is_dock:
				dock_pos = it.pos   # keep the dock prompt tracking the moving station
		var rel: Vector3 = it.pos - ship_pos  # floating origin
		it.holder.position = rel
		var dist := rel.length()
		var vis: bool = dist < it.cull
		it.holder.visible = vis
		if vis and it.spin != 0.0:
			it.holder.rotate_y(it.spin * delta)
		if it.is_probe and dist < PROBE_SCAN_RANGE:
			probe_in_range = true
			probe_name = it.name
		# Stations are "safe zones" — track the nearest so the ship is force-slowed near
		# any of them (a harbour speed limit), in every system. (Probes don't slow you;
		# Voyagers are slowed via the Sol planet safe-zone since they're Sol bodies.)
		if it.is_dock:
			near_struct = minf(near_struct, dist)
		if it.label != null:
			it.label.visible = vis
			if vis:
				it.label.position = rel + Vector3(0.0, it.up, 0.0)
				# Keep the name roughly readable regardless of distance.
				it.label.pixel_size = clampf(dist * 0.00012, 0.02, 1.2)
	# Force-slow zone: ease from full sublight down to a crawl as you near a structure.
	if near_struct < STRUCT_SLOW_RANGE:
		var t := clampf(near_struct / STRUCT_SLOW_RANGE, 0.0, 1.0)
		struct_speed_limit = lerpf(STRUCT_MIN_SPEED, 100000.0, t)
	else:
		struct_speed_limit = INF


# Scale model so its longest axis == target_len and recenter it on the holder.
func _fit(holder: Node3D, model: Node3D, target_len: float) -> void:
	var box := _combined_aabb(holder)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return
	var factor := target_len / longest
	model.scale = model.scale * factor
	var center := box.position + size * 0.5
	model.position -= center * factor


func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _gather(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _gather(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather(c))
	return out


# Self-illuminate every surface so props read against black space without lights.
func _self_light(model: Node3D, glow: float) -> void:
	for mi in _gather(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var m: BaseMaterial3D
			if orig is BaseMaterial3D:
				m = orig.duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.emission_enabled = true
			if m.albedo_texture != null:
				m.emission_texture = m.albedo_texture
				m.emission = Color(1, 1, 1)
			else:
				m.emission = m.albedo_color
			m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)
