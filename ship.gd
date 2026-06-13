class_name Ship
extends Node3D
# Player ship: loads a swappable GLB (see SHIP_MODELS — Lyra by default, Stella
# as an alt) recolored, with a smooth additive booster plume and arcade 6DOF
# flight. If a .glb can't be loaded it falls back to a primitive fighter so the
# game never breaks. swap_ship() rebuilds the hull at runtime (used when docked).
#
# N.O.V.A.-style feel: simple to fly, momentum that eases to a stop, the hull
# banks into turns. Floating origin means we never move this node — it stays at
# (0,0,0) and only rotates; forward motion accumulates into `true_pos` and the
# world is rendered around it.
#
# fly(delta) is called by main.gd (explicit order); mouse look is read in _input.

# ============================ TWEAK ME ============================
# Ships you can fly — swap at the station. First entry is the default (Lyra).
# Per ship:
#   tint   multiplies the model's texture (a wash, not a clean repaint)
#   length auto-fit: longest axis scaled to this many units
#   yaw    facing in degrees — if it flies sideways/backward cycle 0/90/180/270
#   pitch  tip nose up/down if the model imports laid flat
#   glow   hull self-illumination (no scene lights, so the hull lights itself)
const SHIP_MODELS := [
	{ "name": "Lyra",   "path": "res://Rocket ship.glb",   "tint": Color(1.0, 1.0, 1.0),    "length": 4.0, "yaw": 180.0, "pitch": 0.0, "glow": 0.0 },
	{ "name": "Stella", "path": "res://Spaceship.glb",     "tint": Color(0.70, 0.62, 0.95), "length": 3.5, "yaw": 180.0, "pitch": 0.0, "glow": 0.0 },
	{ "name": "Raptor", "path": "res://Spaceship (2).glb", "tint": Color(0.70, 0.90, 0.95), "length": 3.8, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "fire_cd": 0.05, "dual": true },
	# Vela: the FTL ship. warp 1581 -> max cruise ≈ 0.5 ly/s at full charge
	# (THRUST·warp/DAMPING, 1 ly = 632,411 units). Her drive spools up over time
	# (see WARP_CHARGE_*), so she eases into warp rather than snapping to it.
	{ "name": "Vela",   "path": "res://Spaceship (3).glb", "tint": Color(0.55, 0.80, 1.0),  "length": 3.8, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "warp": 1581.0 },
	# Vortex retired as a player ship — it's a boss enemy now (see combat.gd boss).
]
const BOOSTER_COLOR := Color(0.35, 0.8, 1.0)
# Booster nozzle placement (fractions of the fitted model's size). Nudge these
# to snap the plumes onto Lyra's actual engines.
const BOOSTER_BACK := 0.40          # how far back (0 = center, 0.5 = tail). Lower = closer to hull.
const BOOSTER_RISE := 0.0           # vertical nudge for the whole cluster (+ up, - down)
# Per-ship nozzle layout: each engine is (x, y) as fractions of the ship's WIDTH
# (x = left/right, y = up/down). Each ship has a different engine count/pattern;
# nudge these to snap the plumes onto each hull's actual bells.
#   Lyra   = 5 in an A (apex on top, legs spread wide at the bottom)
#   Vortex = 4
#   Stella = 2
#   Raptor = 1
const BOOSTER_LAYOUTS := {
	"Lyra": [
		Vector2( 0.00,  0.16),   # apex (top center)
		Vector2(-0.11,  0.00),   # crossbar left
		Vector2( 0.11,  0.00),   # crossbar right
		Vector2(-0.18, -0.15),   # leg, bottom-left (widest)
		Vector2( 0.18, -0.15),   # leg, bottom-right (widest)
	],
	"Stella": [
		Vector2(-0.09,  0.00),   # left
		Vector2( 0.09,  0.00),   # right
	],
	"Raptor": [
		Vector2( 0.00, -0.02),   # single, centered
	],
	"Vela": [
		Vector2(-0.05, -0.01),   # twin engines, tight on the central block
		Vector2( 0.05, -0.01),
	],
}
const BOOSTER_FALLBACK := [Vector2(-0.08, 0.0), Vector2(0.08, 0.0)]  # if a name isn't listed
# Per-ship plume shaping. Raptor: long/thin/small. Vela: long, thin, golden.
const BOOSTER_RADIUS_SCALE := { "Raptor": 1.9, "Vela": 0.45, "Stella": 0.40 }   # Raptor: strong
const BOOSTER_LENGTH_SCALE := { "Raptor": 4.6, "Vela": 4.2,  "Stella": 3.6, "Lyra": 1.5 }  # longer trails
const BOOSTER_COLOR_OVERRIDE := {
	"Vela": Color(1.0, 0.82, 0.32),    # transparent gold
	"Stella": Color(1.0, 0.26, 0.20),  # sharp transparent red
	"Raptor": Color(0.62, 0.22, 1.0),  # dangerous transparent purple
}
const BOOSTER_FADE_FLIP := false    # if the plume fades at the wrong end, flip this
# Camera zoom (mouse wheel)
const ZOOM_MIN := 0.45              # closest
const ZOOM_MAX := 3.0               # farthest
const ZOOM_STEP := 0.12             # per wheel notch
# =================================================================

# --- Flight tuning ---
const THRUST := 220.0         # forward/back accel (units/s^2)
const STRAFE_THRUST := 130.0  # lateral / vertical accel
const BOOST_MULT := 3.0       # Shift multiplier
const MAX_SPEED := 1000.0
# Damping vs thrust sets the real cruise speed (~THRUST/DAMPING ≈ 200 u/s here,
# ~600 boosted) — MAX_SPEED is just a ceiling. Tune feel with THRUST/DAMPING.
const DAMPING := 1.1          # higher = eases to a stop faster when idle
const MOUSE_SENS := 0.0022    # default; runtime value lives in `mouse_sens` (Settings menu)
const ROLL_RATE := 1.8        # manual Q/E roll (rad/s)
const BANK_ANGLE := 0.5       # max cosmetic bank into turns (rad)
const BANK_SMOOTH := 5.0
const CAM_OFFSET := Vector3(0.0, 2.2, 8.5)  # behind (+Z) and above the ship
const CAM_LAG := 6.0
const FOV_BASE := 70.0
const FOV_KICK := 14.0        # extra FOV at full speed (sense of speed) — gentle

# --- State ---
var velocity := Vector3.ZERO
var true_pos := Vector3.ZERO   # absolute position in game units (floating origin)
var speed_limit := INF         # set by main from PlanetSystem; eases us down near a body
var nearest_dir := Vector3.ZERO  # toward nearest body; we only ease down when approaching it
var gravity := Vector3.ZERO    # set by main from PlanetSystem; gentle pull toward bodies
var frozen := false            # docked at a station — motion held, mouse freed
var transiting := false        # in a wormhole tunnel — motion held, view locked forward
var camera: Camera3D           # assigned by main; driven from fly()
var mouse_sens := MOUSE_SENS   # live mouse sensitivity (Settings menu adjusts this)
var warp := 1.0                # per-ship MAX speed multiplier; >1 = breaks physics (Vela)
var _warp_charge := 0.0        # 0..1 spool-up; ramps while thrusting forward
var fire_cooldown := 0.22      # seconds between shots (combat reads this)
var _dual := false             # Raptor: can toggle between combat + warp modes
const RAPTOR_WARP := 1581.0    # Raptor's warp-mode multiplier (≈0.5 ly/s, like Vela)
const HYPERSONIC_SPEED := 1500.0   # above this a warp ship is "hypersonic" (no combat)
const WARP_FLOOR := 5.0        # warp multiplier at zero charge (controllable start)
const WARP_CHARGE_TIME := 9.0  # seconds of thrust to reach full warp
const WARP_DECAY_TIME := 3.5   # seconds to spool back down when you ease off

# True when a warp ship is blazing fast — combat + crosshair are disabled.
func is_hypersonic() -> bool:
	return warp > 1.0 and velocity.length() > HYPERSONIC_SPEED

# Raptor only: toggle between Combat mode (machine-gun, normal flight) and Warp
# mode (Vela-style FTL). Returns the new mode name for HUD feedback.
func toggle_warp_mode() -> String:
	if not _dual:
		return ""
	if warp > 1.0:
		warp = 1.0          # back to Combat mode
	else:
		warp = RAPTOR_WARP  # Warp / FTL mode
		_warp_charge = 0.0
	return "WARP" if warp > 1.0 else "COMBAT"

func is_warp_mode() -> bool:
	return _dual and warp > 1.0

var _current_model := 0        # index into SHIP_MODELS
var _mesh_root: Node3D
var _engine_mat: StandardMaterial3D   # only used by the primitive fallback
var _boosters: Array = []
var _glow_tex: Texture2D
var _plume_grad: Texture2D
var _booster_color := BOOSTER_COLOR   # per-ship plume tint, set in _build_boosters
var _streaks: GPUParticles3D          # motion streaks at high speed
var _streak_mat: StandardMaterial3D
var _cam_zoom := 1.0          # target zoom (mouse wheel)
var _cam_zoom_smooth := 1.0   # eased toward _cam_zoom
var _cam_basis := Basis()
var _bank := 0.0
var _mouse_delta := Vector2.ZERO
var _mouse_captured := false


func _ready() -> void:
	_glow_tex = _make_glow_texture()
	_plume_grad = _make_plume_gradient(BOOSTER_FADE_FLIP)
	_build_visual()
	_set_capture(true)
	_cam_basis = transform.basis  # seed so the first frame isn't a lurch


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_mouse_delta += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = clampf(_cam_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = clampf(_cam_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		elif not _mouse_captured and not frozen:
			_set_capture(true)
	# (Esc is owned by the Settings menu — opens/closes it and frees the cursor.)


# Called every frame by main.gd, before the world is rebuilt around the ship.
func fly(delta: float) -> void:
	# Wormhole transit: motion held, view locked forward, streaks at full tilt.
	if transiting:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_update_boosters(1.0, delta)
		_update_streaks(1.0)
		_update_camera(delta)
		return

	# Docked: hold position, idle the boosters, keep the camera steady.
	if frozen:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_update_boosters(0.0, delta)
		_update_streaks(0.0)
		_update_camera(delta)
		return

	# --- Rotation: mouse aims, Q/E roll ---
	var yaw := _mouse_delta.x * mouse_sens
	var pitch := _mouse_delta.y * mouse_sens
	_mouse_delta = Vector2.ZERO

	rotate_object_local(Vector3.UP, -yaw)
	rotate_object_local(Vector3.RIGHT, -pitch)

	var roll := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		roll += 1.0
	if Input.is_physical_key_pressed(KEY_E):
		roll -= 1.0
	rotate_object_local(Vector3.BACK, roll * ROLL_RATE * delta)
	orthonormalize()  # scrub float drift out of the basis over time

	# --- Thrust (local axes -> world via current basis) ---
	var boost := BOOST_MULT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var fwd := 0.0
	var strafe := 0.0
	var lift := 0.0
	if Input.is_physical_key_pressed(KEY_W):
		fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		fwd += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		lift += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		lift -= 1.0

	# Warp ships (Vela) spool their drive up over time toward full warp, then
	# back down when you ease off the throttle — so warp is earned, not instant.
	var eff_warp := warp
	if warp > 1.0:
		if Input.is_physical_key_pressed(KEY_W):
			_warp_charge = minf(_warp_charge + delta / WARP_CHARGE_TIME, 1.0)
		else:
			_warp_charge = maxf(_warp_charge - delta / WARP_DECAY_TIME, 0.0)
		var c := _warp_charge * _warp_charge * (3.0 - 2.0 * _warp_charge)   # smoothstep
		eff_warp = lerpf(WARP_FLOOR, warp, c)

	var local_accel := Vector3(strafe * STRAFE_THRUST, lift * STRAFE_THRUST, fwd * THRUST) * eff_warp
	if local_accel != Vector3.ZERO:
		velocity += (transform.basis * local_accel) * boost * delta

	# Gravitational tug toward nearby bodies (gentle; thrust overpowers it).
	velocity += gravity * delta

	# Arcade damping: velocity eases toward zero when you're not thrusting.
	velocity = velocity.lerp(Vector3.ZERO, clampf(DAMPING * delta, 0.0, 1.0))
	# Warp ships (Vela) break physics: huge cap, and they ignore the gravity-well
	# slowdown so they can blast across a system. Normal ships obey speed_limit.
	var cap := MAX_SPEED * eff_warp * boost
	# Ease down only when moving TOWARD the nearest body (so you can stabilise and
	# scan). Pointing away is free, so you never get "stuck" at Earth/a planet.
	if warp <= 1.0 and velocity.dot(nearest_dir) >= 0.0:
		cap = minf(cap, speed_limit)
	velocity = velocity.limit_length(cap)

	# --- Floating origin: never move the node; accumulate the true position ---
	true_pos += velocity * delta

	# --- Cosmetic banking (on the mesh only, so the camera stays steady) ---
	var target_bank := clampf(-yaw * 7.0 - strafe * 0.35, -BANK_ANGLE, BANK_ANGLE)
	_bank = lerpf(_bank, target_bank, clampf(BANK_SMOOTH * delta, 0.0, 1.0))
	_mesh_root.rotation.z = _bank

	# --- Engine / booster intensity ---
	var throttle := 1.0 if Input.is_physical_key_pressed(KEY_W) else 0.18
	if Input.is_physical_key_pressed(KEY_S):
		throttle = maxf(throttle, 0.55)
	if boost > 1.0:
		throttle *= 1.4
	_update_boosters(throttle, delta)
	if _engine_mat:  # fallback ship only
		var e := 2.0 + throttle * 4.0
		_engine_mat.emission_energy_multiplier = lerpf(
			_engine_mat.emission_energy_multiplier, e, clampf(8.0 * delta, 0.0, 1.0))

	_update_streaks(velocity.length() / MAX_SPEED)
	_update_camera(delta)


func _update_boosters(throttle: float, delta: float) -> void:
	var k := clampf(10.0 * delta, 0.0, 1.0)
	for b in _boosters:
		# Plume length stretches with throttle; nozzle stays anchored.
		var sc: Vector3 = b.pivot.scale
		sc.y = lerpf(sc.y, 0.35 + throttle * 0.7, k)   # less stretch under thrust
		b.pivot.scale = sc
		# Plume transparency (additive) tracks throttle.
		var pcol: Color = b.plume_mat.albedo_color
		pcol.a = lerpf(pcol.a, clampf(0.05 + throttle * 0.35, 0.0, 0.6), k)
		b.plume_mat.albedo_color = pcol
		# Soft core glow at the nozzle.
		var cs := 0.35 + throttle * 0.7
		b.core.scale = Vector3(cs, cs, cs)
		var ccol: Color = b.core_mat.albedo_color
		ccol.a = lerpf(ccol.a, clampf(0.12 + throttle * 0.5, 0.0, 0.85), k)
		b.core_mat.albedo_color = ccol


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	# Camera basis lags the ship's a touch -> gentle sway / sense of speed.
	_cam_basis = _cam_basis.slerp(transform.basis, clampf(CAM_LAG * delta, 0.0, 1.0))
	_cam_zoom_smooth = lerpf(_cam_zoom_smooth, _cam_zoom, clampf(10.0 * delta, 0.0, 1.0))
	var cam_pos := _cam_basis * (CAM_OFFSET * _cam_zoom_smooth)  # ship at origin -> global
	camera.global_transform = Transform3D(_cam_basis, cam_pos)
	# Clamp the fraction so warp speeds don't blow the FOV out into a fisheye.
	var speed_frac := clampf(velocity.length() / MAX_SPEED, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, FOV_BASE + speed_frac * FOV_KICK, clampf(4.0 * delta, 0.0, 1.0))


func _set_capture(c: bool) -> void:
	_mouse_captured = c
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if c else Input.MOUSE_MODE_VISIBLE)


# ----------------------------------------------------------------------------
# Visual setup
# ----------------------------------------------------------------------------
func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	_build_ship_model(_current_model)
	_build_streaks()


# A field of thin additive streaks that stream past the ship — only at speed, so
# you feel "fast" without any HUD number. Lives on the ship (origin), in local
# coords, flowing +Z (toward/behind the chase camera).
func _build_streaks() -> void:
	_streaks = GPUParticles3D.new()
	add_child(_streaks)
	_streaks.amount = 90
	_streaks.lifetime = 0.45
	_streaks.local_coords = true
	_streaks.emitting = false
	_streaks.visibility_aabb = AABB(Vector3(-60, -60, -90), Vector3(120, 120, 180))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 11, 45)
	pm.direction = Vector3(0, 0, 1)        # stream toward/past the camera
	pm.spread = 0.0
	pm.initial_velocity_min = 180.0
	pm.initial_velocity_max = 240.0
	pm.gravity = Vector3.ZERO
	_streaks.process_material = pm

	var streak := BoxMesh.new()
	streak.size = Vector3(0.03, 0.03, 2.4)  # long + thin = a motion streak
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_streak_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
	streak.material = _streak_mat
	_streaks.draw_pass_1 = streak


# Density + brightness + flow speed all ramp with how close we are to top speed.
func _update_streaks(speed_frac: float) -> void:
	if _streaks == null:
		return
	var t := clampf((speed_frac - 0.3) / 0.5, 0.0, 1.0)   # off until ~1/3 speed
	_streaks.emitting = t > 0.01
	_streaks.amount_ratio = clampf(0.15 + t, 0.0, 1.0)
	_streaks.speed_scale = 1.0 + t * 1.6
	var a: Color = _streak_mat.albedo_color
	a.a = t * 0.8
	_streak_mat.albedo_color = a


# (Re)build the hull + boosters for SHIP_MODELS[idx]. Safe to call at runtime to
# swap ships: it clears the old model first.
func _build_ship_model(idx: int) -> void:
	# Detach old children immediately (queue_free is deferred, which would let the
	# old meshes pollute the AABB fit below) then free them.
	for c in _mesh_root.get_children():
		_mesh_root.remove_child(c)
		c.queue_free()
	_boosters.clear()
	_engine_mat = null

	var info = SHIP_MODELS[idx]
	warp = float(info.get("warp", 1.0))
	fire_cooldown = float(info.get("fire_cd", 0.22))
	_dual = info.get("dual", false)
	_warp_charge = 0.0
	var packed := load(info.path) as PackedScene
	if packed == null:
		push_warning("Ship: could not load %s — using primitive fallback." % info.path)
		_build_primitive_ship()
		return

	var model := packed.instantiate() as Node3D
	_mesh_root.add_child(model)
	model.rotation = Vector3(deg_to_rad(float(info.pitch)), deg_to_rad(float(info.yaw)), 0.0)
	var box := _fit_model(model, float(info.length))
	_recolor(model, info.tint, float(info.glow), info.get("chrome", false))
	_build_boosters(box, info.name)


# --- Ship-swap API (called by main when docked) ---
func swap_ship(idx: int) -> void:
	if idx < 0 or idx >= SHIP_MODELS.size() or idx == _current_model:
		return
	_current_model = idx
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO  # drop any banking carryover
	_build_ship_model(idx)

func ship_count() -> int:
	return SHIP_MODELS.size()

func current_index() -> int:
	return _current_model

func ship_name_at(i: int) -> String:
	return SHIP_MODELS[i].name

func set_frozen(f: bool) -> void:
	frozen = f
	_set_capture(not f)


# Point the nose (-Z) at a world point and snap the chase camera to match, so
# the very first frame opens already framed (no swing). Used at spawn.
func face_toward(world_point: Vector3) -> void:
	if world_point.is_equal_approx(global_position):
		return
	look_at(world_point, Vector3.UP)
	_cam_basis = transform.basis


# Scale the model so its longest axis == target, recenter it on the origin, and
# return the resulting AABB (centered) in _mesh_root space.
func _fit_model(model: Node3D, target_len: float) -> AABB:
	# Measured in _mesh_root space (the model's parent) so it accounts for the
	# model's yaw/pitch rotation — recentering uses model.position, same space.
	var box := _combined_aabb(_mesh_root)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var factor := target_len / longest
	model.scale = model.scale * factor
	var center := box.position + size * 0.5
	model.position -= center * factor
	return AABB(-size * factor * 0.5, size * factor)


# Union of every child MeshInstance3D's AABB, expressed in `root`'s local space.
func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _gather_mesh_instances(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _gather_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather_mesh_instances(c))
	return out


# Give the hull a polished, vibrant metallic skin. With no scene lights the
# shine comes from the reflective sky (see main._setup_environment) plus a
# fresnel rim; a gentle emission keeps it from ever going fully dark in deep
# space. The model's own texture stays as surface detail.
func _recolor(model: Node3D, tint: Color, glow: float, chrome := false) -> void:
	for mi in _gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var m: BaseMaterial3D
			if orig is BaseMaterial3D:
				m = orig.duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			if chrome:
				# Pure sci-fi white brushed metal with a cyan edge glow — drop the
				# model's own (purple) texture and make a clean polished hull.
				m.albedo_texture = null
				m.albedo_color = Color(0.86, 0.90, 0.96)
				m.metallic = 0.85
				m.metallic_specular = 0.85
				m.roughness = 0.3
				m.rim_enabled = true
				m.rim = 0.7
				m.rim_tint = 0.0                    # bright white fresnel edge
				m.emission_enabled = true
				m.emission_texture = null
				m.emission = Color(0.15, 0.7, 1.0)  # cyan self-glow accent
				m.emission_energy_multiplier = 0.25
			else:
				# Painted hull: low metalness so the model's own colour texture
				# shows under the key+fill lights; dim flat emission floor only.
				m.albedo_color = tint
				m.metallic = 0.1
				m.metallic_specular = 0.5
				m.roughness = 0.5
				m.rim_enabled = true
				m.rim = 0.25
				m.rim_tint = 0.5
				m.emission_enabled = true
				m.emission_texture = null
				m.emission = tint
				m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)


# Additive booster plumes at the rear of the (fitted, centered) model — one per
# engine in this ship's BOOSTER_LAYOUTS entry (count/pattern differ per hull).
func _build_boosters(box: AABB, ship_name: String) -> void:
	var s := box.size
	var mount_z := s.z * BOOSTER_BACK  # +Z is behind the ship (forward is -Z)
	var rise := s.y * BOOSTER_RISE
	var mounts: Array = BOOSTER_LAYOUTS.get(ship_name, BOOSTER_FALLBACK)
	_booster_color = BOOSTER_COLOR_OVERRIDE.get(ship_name, BOOSTER_COLOR)
	# Fewer engines read better a touch larger; scale radius down as count grows.
	var rscale: float = BOOSTER_RADIUS_SCALE.get(ship_name, 1.0)
	var lscale: float = BOOSTER_LENGTH_SCALE.get(ship_name, 1.0)
	var r := clampf(s.x * (0.085 - 0.006 * mounts.size()), 0.035, 0.16) * rscale
	var length := maxf(s.z * 0.20, 0.4) * lscale
	for m in mounts:
		var pos := Vector3(m.x * s.x, rise + m.y * s.x, mount_z)
		_boosters.append(_make_booster(pos, r, length))


func _make_booster(mount: Vector3, radius: float, length: float) -> Dictionary:
	# A pivot rotated so the cylinder's +Y axis points backward (+Z). Scaling the
	# pivot's Y stretches the plume while keeping the wide nozzle anchored here.
	var pivot := Node3D.new()
	pivot.position = mount
	pivot.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	_mesh_root.add_child(pivot)

	var plume_mat := StandardMaterial3D.new()
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Gradient texture drives the alpha so the plume fades smoothly nozzle->tail.
	plume_mat.albedo_texture = _plume_grad
	plume_mat.albedo_color = Color(_booster_color.r, _booster_color.g, _booster_color.b, 0.18)

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0          # tapers to a point at the tail
	cyl.bottom_radius = radius    # wide at the nozzle
	cyl.height = length
	cyl.radial_segments = 12
	cyl.rings = 0
	var plume := MeshInstance3D.new()
	plume.mesh = cyl
	plume.material_override = plume_mat
	plume.position = Vector3(0.0, length * 0.5, 0.0)  # wide end sits at the pivot
	pivot.add_child(plume)

	# Soft additive core glow at the nozzle (billboarded).
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	core_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	core_mat.billboard_keep_scale = true
	core_mat.albedo_texture = _glow_tex
	var cc := _booster_color.lerp(Color.WHITE, 0.35)   # hot core in the plume's tint
	core_mat.albedo_color = Color(cc.r, cc.g, cc.b, 0.6)
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.6, radius * 2.6)
	var core := MeshInstance3D.new()
	core.mesh = quad
	core.material_override = core_mat
	core.position = mount
	_mesh_root.add_child(core)

	return {
		"pivot": pivot,
		"plume_mat": plume_mat,
		"core": core,
		"core_mat": core_mat,
	}


# Vertical alpha ramp for the plume: opaque at the nozzle, fading to clear at the
# tail. Which mesh end is which depends on UV winding, so BOOSTER_FADE_FLIP flips it.
func _make_plume_gradient(flip: bool) -> Texture2D:
	var h := 64
	var img := Image.create(2, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)  # 0 at image top .. 1 at bottom
		if flip:
			t = 1.0 - t
		var a := pow(1.0 - t, 1.4)        # bright at t=0, easing to 0
		for x in 2:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


# Soft radial glow circle, generated once (no binary asset to ship).
func _make_glow_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


# ----------------------------------------------------------------------------
# Fallback: a small fighter from primitives (used only if the .glb won't load)
# ----------------------------------------------------------------------------
func _build_primitive_ship() -> void:
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.22, 0.26, 0.34)
	hull_mat.metallic = 0.6
	hull_mat.roughness = 0.4
	hull_mat.emission_enabled = true
	hull_mat.emission = Color(0.14, 0.17, 0.24)
	hull_mat.emission_energy_multiplier = 0.5

	var fuselage := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.7, 0.4, 2.2)
	fuselage.mesh = fmesh
	fuselage.material_override = hull_mat
	_mesh_root.add_child(fuselage)

	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.45
	cone.height = 1.2
	cone.radial_segments = 8
	cone.rings = 0
	nose.mesh = cone
	nose.material_override = hull_mat
	nose.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	nose.position = Vector3(0.0, 0.0, -1.6)
	_mesh_root.add_child(nose)

	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wmesh := BoxMesh.new()
		wmesh.size = Vector3(1.5, 0.08, 0.9)
		wing.mesh = wmesh
		wing.material_override = hull_mat
		wing.position = Vector3(s * 0.95, -0.04, 0.35)
		wing.rotation = Vector3(0.0, 0.0, s * deg_to_rad(14.0))
		_mesh_root.add_child(wing)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.4, 0.8, 1.0)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.35, 0.75, 1.0)
	glass_mat.emission_energy_multiplier = 1.6
	var cockpit := MeshInstance3D.new()
	var cmesh := BoxMesh.new()
	cmesh.size = Vector3(0.42, 0.26, 0.7)
	cockpit.mesh = cmesh
	cockpit.material_override = glass_mat
	cockpit.position = Vector3(0.0, 0.2, -0.35)
	_mesh_root.add_child(cockpit)

	_engine_mat = StandardMaterial3D.new()
	_engine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_engine_mat.albedo_color = Color(0.2, 0.9, 1.0)
	_engine_mat.emission_enabled = true
	_engine_mat.emission = Color(0.2, 0.9, 1.0)
	_engine_mat.emission_energy_multiplier = 3.0
	var engine := MeshInstance3D.new()
	var emesh := BoxMesh.new()
	emesh.size = Vector3(0.5, 0.3, 0.3)
	engine.mesh = emesh
	engine.material_override = _engine_mat
	engine.position = Vector3(0.0, 0.0, 1.2)
	_mesh_root.add_child(engine)
