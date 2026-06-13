class_name Wormhole
extends Node3D
# Interstellar travel without breaking the engine: each system is its own small
# local space, and a wormhole teleports you between them. You NEVER fly the real
# light-years — the distance only sets how long the tunnel transit lasts and what
# the HUD reads. On arrival main.gd hard-resets the ship to a small local coord.
#
# A system can hold SEVERAL portals (Earth/Sol has one per exoplanet destination,
# spread far apart and parked); every other system has a single portal back to
# Sol. Each portal is a glowing ring with a floating "→ <destination>" label,
# floating-origin tracked. Fly near any portal, press F, and a tunnel sequence
# plays for ~ (ly × SEC_PER_LY) seconds, then main swaps to that portal's system.

const PORTAL_RANGE := 60.0    # ×10 for the spread-out system
const MAX_PORTALS := 4                  # pool size (Sol uses 3; others use 1)
# Transit length = light-years × this (clamped). Tunable: 0.15 → ~18s for K2-18b
# (dev-friendly); set ~2.9 for the ~6-minute "epic haul" the design calls for.
const SEC_PER_LY := 0.15
const TRANSIT_MIN := 4.0
const TRANSIT_MAX := 600.0

var ship: Node3D                       # for parenting/aligning the tunnel
var transiting := false
var dest_id := ""                      # destination of the portal you're at / heading to
var dest_ly := 0.0

# Portal pool. Each entry: { node, mat, label, pos, dest_id, dest_ly, active }.
var _portals := []
var _active := -1                      # index of the portal currently in F-range
var _tunnel: MeshInstance3D
var _tunnel_mat: StandardMaterial3D
var _t := 0.0
var _duration := 0.0


func _ready() -> void:
	for i in MAX_PORTALS:
		_portals.append(_build_portal())


func set_ship(s: Node3D) -> void:
	ship = s
	_build_tunnel()   # lives on the ship so it stays aligned with travel


# Lay out this system's portals (positions + destinations) and label each one.
func set_system(id: String) -> void:
	var defs: Array = SystemDB.portals(id)
	for i in MAX_PORTALS:
		var p = _portals[i]
		if i < defs.size():
			p.pos = defs[i].pos
			p.dest_id = defs[i].dest
			p.dest_ly = SystemDB.light_years(defs[i].dest)
			p.active = true
			p.node.visible = true
			p.label.text = "◇ %s ◇\n%.0f ly" % [SystemDB.display_name(p.dest_id), p.dest_ly]
			p.label.visible = true
		else:
			p.active = false
			p.node.visible = false
			p.label.visible = false
	_active = -1
	if defs.size() > 0:
		dest_id = defs[0].dest
		dest_ly = SystemDB.light_years(dest_id)


# True if the ship is within F-range of ANY portal; remembers the nearest one so
# start_transit / the HUD know which destination it is.
func in_range(ship_pos: Vector3) -> bool:
	if transiting:
		return false
	_active = -1
	var best := PORTAL_RANGE
	for i in _portals.size():
		var p = _portals[i]
		if not p.active:
			continue
		var d: float = (p.pos - ship_pos).length()
		if d < best:
			best = d
			_active = i
	if _active >= 0:
		dest_id = _portals[_active].dest_id
		dest_ly = _portals[_active].dest_ly
		return true
	return false


# Render-space position of the nearest portal (for the navigator marker).
func portal_rel(ship_pos: Vector3) -> Vector3:
	var best := INF
	var rel := Vector3.ZERO
	for p in _portals:
		if not p.active:
			continue
		var r: Vector3 = p.pos - ship_pos
		var d := r.length()
		if d < best:
			best = d
			rel = r
	return rel


func start_transit() -> void:
	transiting = true
	_t = 0.0
	var p = _portals[_active] if _active >= 0 else _portals[0]
	dest_id = p.dest_id
	dest_ly = p.dest_ly
	_duration = clampf(dest_ly * SEC_PER_LY, TRANSIT_MIN, TRANSIT_MAX)
	for pp in _portals:
		pp.node.visible = false
		pp.label.visible = false
	_tunnel.visible = true


func transit_remaining() -> float:
	return maxf(_duration - _t, 0.0)


# Returns true on the frame the transit finishes (main then swaps the system).
func update(ship_pos: Vector3, delta: float) -> bool:
	if transiting:
		_t += delta
		_tunnel_mat.uv1_offset += Vector3(0.0, -2.5 * delta, 0.0)  # rush the rings past
		var pulse := 0.7 + 0.3 * sin(_t * 8.0)
		_tunnel_mat.emission_energy_multiplier = 2.0 * pulse
		if _t >= _duration:
			transiting = false
			_tunnel.visible = false
			return true
		return false

	# idle: float every active portal in place (floating origin), spin + pulse it.
	var glow := 2.0 + 0.8 * sin(Time.get_ticks_msec() * 0.004)
	for p in _portals:
		if not p.active:
			continue
		var rel: Vector3 = p.pos - ship_pos
		p.node.visible = true
		p.node.position = rel
		p.node.rotate_z(0.6 * delta)
		p.mat.emission_energy_multiplier = glow
		p.label.visible = true
		p.label.position = rel + Vector3(0.0, 11.0, 0.0)
		p.label.pixel_size = clampf(rel.length() * 0.00012, 0.02, 1.2)
	return false


# --- visuals ---------------------------------------------------------------
# Build one portal (ring + event-horizon core + danger glow + floating label) and
# return its state dict. The pool of these is positioned per system in set_system.
func _build_portal() -> Dictionary:
	# A dangerous-looking hole: a dark event-horizon core, a fiery accretion ring
	# that spins, and an outer red danger-glow. All emissive — no lights.
	var torus := TorusMesh.new()
	torus.inner_radius = 4.75
	torus.outer_radius = 7.75
	torus.rings = 36
	torus.ring_segments = 16
	var portal := MeshInstance3D.new()
	portal.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.32, 0.05)        # fiery orange accretion
	mat.albedo_color = Color(1.0, 0.28, 0.04)
	mat.emission_energy_multiplier = 2.6
	portal.material_override = mat
	portal.visible = false
	add_child(portal)

	# Event horizon — a near-black sphere that swallows the center.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.9; sm.height = 9.8; sm.radial_segments = 20; sm.rings = 10
	core.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.01, 0.0, 0.015)          # the hole — eats the light
	core.material_override = cmat
	portal.add_child(core)

	# Outer danger glow — billboarded red haze so it reads as a threat from afar.
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(27.5, 27.5)
	glow.mesh = q
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gmat.albedo_texture = _make_hole_glow()
	gmat.albedo_color = Color(1.0, 0.18, 0.06, 0.85)
	glow.material_override = gmat
	portal.add_child(glow)

	# Floating destination label (billboard), positioned each frame in update().
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_modulate = Color(0, 0, 0, 0.7)
	label.outline_size = 8
	label.font_size = 40
	label.modulate = Color(1.0, 0.7, 0.45)
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	add_child(label)

	return {
		"node": portal, "mat": mat, "label": label,
		"pos": Vector3.ZERO, "dest_id": "", "dest_ly": 0.0, "active": false,
	}


# Radial haze: bright near the rim, fading out — the hole's danger glow.
func _make_hole_glow() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_tunnel() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 160.0
	cyl.radial_segments = 28
	cyl.rings = 1
	_tunnel = MeshInstance3D.new()
	_tunnel.mesh = cyl
	_tunnel.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)  # length along Z (travel axis)
	_tunnel.position = Vector3(0.0, 0.0, -55.0)             # ahead of the chase camera
	_tunnel_mat = StandardMaterial3D.new()
	_tunnel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tunnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED      # we view it from inside
	_tunnel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tunnel_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tunnel_mat.emission_enabled = true
	_tunnel_mat.emission = Color(0.6, 0.5, 1.0)
	_tunnel_mat.emission_energy_multiplier = 2.0
	_tunnel_mat.albedo_texture = _make_tunnel_texture()
	_tunnel_mat.emission_texture = _tunnel_mat.albedo_texture
	_tunnel_mat.uv1_scale = Vector3(6.0, 12.0, 1.0)          # repeat rings down the tube
	_tunnel.material_override = _tunnel_mat
	_tunnel.visible = false
	ship.add_child(_tunnel)


# Bright rings on a dark band that scroll past — a cheap "wormhole" wall.
func _make_tunnel_texture() -> Texture2D:
	var h := 64
	var img := Image.create(4, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(h)
		var band := pow(0.5 + 0.5 * sin(v * TAU * 3.0), 4.0)   # periodic bright rings
		var c := Color(0.6 + 0.4 * band, 0.5 + 0.3 * band, 1.0, 0.15 + 0.85 * band)
		for x in 4:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
