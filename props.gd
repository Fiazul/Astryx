class_name Props
extends Node3D
# Hand-placed GLB landmarks (space station, a detailed planet, a drifting
# astronaut) tracked with floating origin: each has a true_pos in game units and
# is rendered at (true_pos - ship_pos) every frame, just like the planets.
#
# These are decorative points-of-interest — no collision. They're auto-fitted to
# a target size and self-lit (no Light3D in the scene), then slowly spun.

# The space station is the ONE invented object (per spec) — a design placement,
# not real data: a small offset from Earth (the origin), in a slow low orbit.
# Finn the astronaut is a fictional character, drifting nearby as set-dressing.
# (No fake planets here — every celestial body is real, in ephemeris.gd.)
#
# pos = absolute scene units (1u = 0.1 AU). size = longest-axis target.
# yaw = initial facing. spin = rad/s idle self-rotation. glow = self-illum.
# orbit = rad/s revolution around Earth/origin (0 = parked).
const PROP_LIST := [
	{
		"name": "Wikiplanet Station", "path": "res://Wikiplanet Space Station (WSS).glb",
		"pos": Vector3(-4.5, 1.5, 1.5), "size": 1.8, "yaw": 25.0, "spin": 0.03, "glow": 0.18,
		"orbit": 0.04, "dock": true, "dock_range": 4.0,
	},
	{
		"name": "Finn", "path": "res://Astronaut.glb",
		"pos": Vector3(-4.0, 1.2, 1.0), "size": 0.5, "yaw": 200.0, "spin": 0.35, "glow": 0.45,
		"orbit": 0.04,
	},
]

var _items := []

# Dock target (the prop flagged "dock"), read by main for the dock prompt/menu.
var has_dock := false
var dock_pos := Vector3.ZERO
var dock_name := ""
var dock_range := 0.0


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

		var is_dock: bool = p.get("dock", false)
		_items.append({
			"holder": holder,
			"label": label,
			"pos": p.pos,
			"up": float(p.size) * 0.7,      # label height above the prop
			"spin": float(p.get("spin", 0.0)),
			"orbit": float(p.get("orbit", 0.0)),   # revolution around Earth/origin
			"cull": float(p.size) * 90.0,   # stop drawing big meshy props when far
			"is_dock": is_dock,
		})

		if is_dock:
			has_dock = true
			dock_pos = p.pos
			dock_name = p.name
			dock_range = float(p.get("dock_range", float(p.size) * 1.8))


func update(ship_pos: Vector3, delta: float) -> void:
	for it in _items:
		# Slow revolution around Earth (the origin), if this prop orbits.
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
		if it.label != null:
			it.label.visible = vis
			if vis:
				it.label.position = rel + Vector3(0.0, it.up, 0.0)
				# Keep the name roughly readable regardless of distance.
				it.label.pixel_size = clampf(dist * 0.0009, 0.01, 0.5)


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
