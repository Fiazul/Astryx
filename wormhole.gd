class_name Wormhole
extends Node3D
# Interstellar travel without breaking the engine: each system is its own small
# local space, and a wormhole teleports you between them. You NEVER fly the real
# light-years — the distance only sets how long the tunnel transit lasts and what
# the HUD reads. On arrival main.gd hard-resets the ship to a small local coord.
#
# A glowing ring portal sits in each system (floating-origin tracked). Fly near
# it, press J, and a tunnel sequence plays for ~ (ly × SEC_PER_LY) seconds, then
# main swaps the system.

const PORTAL_RANGE := 6.0
# Transit length = light-years × this (clamped). Tunable: 0.15 → ~18s for K2-18b
# (dev-friendly); set ~2.9 for the ~6-minute "epic haul" the design calls for.
const SEC_PER_LY := 0.15
const TRANSIT_MIN := 4.0
const TRANSIT_MAX := 600.0

var ship: Node3D                       # for parenting/aligning the tunnel
var transiting := false
var dest_id := ""
var dest_ly := 0.0

var _portal: MeshInstance3D
var _portal_pos := Vector3.ZERO        # local true position of this system's portal
var _portal_mat: StandardMaterial3D
var _tunnel: MeshInstance3D
var _tunnel_mat: StandardMaterial3D
var _t := 0.0
var _duration := 0.0


func _ready() -> void:
	_build_portal()


func set_ship(s: Node3D) -> void:
	ship = s
	_build_tunnel()   # lives on the ship so it stays aligned with travel


# Point the portal at the current system's location + onward destination.
func set_system(id: String) -> void:
	_portal_pos = SystemDB.portal_pos(id)
	dest_id = SystemDB.portal_dest(id)
	dest_ly = SystemDB.light_years(dest_id)


func in_range(ship_pos: Vector3) -> bool:
	return not transiting and (_portal_pos - ship_pos).length() < PORTAL_RANGE


func start_transit() -> void:
	transiting = true
	_t = 0.0
	_duration = clampf(dest_ly * SEC_PER_LY, TRANSIT_MIN, TRANSIT_MAX)
	_portal.visible = false
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

	# idle: float the portal in place (floating origin) and spin it
	_portal.visible = true
	_portal.position = _portal_pos - ship_pos
	_portal.rotate_z(0.6 * delta)
	_portal_mat.emission_energy_multiplier = 2.0 + 0.8 * sin(Time.get_ticks_msec() * 0.004)
	return false


# --- visuals ---------------------------------------------------------------
func _build_portal() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 2.0
	torus.outer_radius = 2.7
	torus.rings = 24
	torus.ring_segments = 12
	_portal = MeshInstance3D.new()
	_portal.mesh = torus
	_portal_mat = StandardMaterial3D.new()
	_portal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_mat.emission_enabled = true
	_portal_mat.emission = Color(0.5, 0.4, 1.0)
	_portal_mat.albedo_color = Color(0.5, 0.4, 1.0)
	_portal_mat.emission_energy_multiplier = 2.0
	_portal.material_override = _portal_mat
	add_child(_portal)


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
