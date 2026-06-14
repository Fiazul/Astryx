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
	# engine_pitch gives each hull a distinct engine voice: Lyra neutral, Stella a
	# warm mid, Raptor a deep growl, Vela a high sleek whine. (Dedicated per-ship
	# loops can be dropped in later via gen_engine_audio.py; this shapes the shared one.)
	# Combat identity per hull (combat.gd reads hp / bolt_speed / bolt_scale / fire_cd):
	#   Lyra   — the tank: huge HP, big slow heavy bullets, lazy fire rate.
	#   Stella — the machine-gun: blistering fire rate + very fast small bolts, low HP.
	#   Raptor — bruiser: high defence, fast fire, FTL warp form (X).
	#   Vela   — glass cannon: squishy, fast fire like Raptor, the fastest FTL hull.
	{ "name": "Lyra",   "path": "res://Rocket ship.glb",   "tint": Color(1.0, 1.0, 1.0),    "length": 0.45, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 1.0,  "hp": 250, "bolt_scale": 1.8, "bolt_speed": 820.0,  "fire_cd": 0.34, "dmg": 3, "warp": 230.0, "raw": true },
	{ "name": "Stella", "path": "res://Spaceship.glb",     "tint": Color(0.70, 0.62, 0.95), "length": 0.40, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.92, "hp": 100, "bolt_scale": 0.62, "bolt_speed": 1700.0, "fire_cd": 0.04, "dmg": 1, "warp": 345.0 },
	{ "name": "Raptor", "path": "res://Spaceship (2).glb", "tint": Color(0.70, 0.90, 0.95), "length": 0.42, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.82, "hp": 135, "bolt_scale": 0.95, "bolt_speed": 1050.0, "fire_cd": 0.05, "dual": true, "dmg": 2, "warp": 345.0 },
	# Vela: the FTL ship. warp 4312 -> max cruise ≈ 1.5 ly/s at full charge
	# (THRUST·warp/DAMPING, 1 ly = 632,411 units). Her drive spools up over time
	# (see WARP_CHARGE_*), so she eases into warp rather than snapping to it.
	# "brake": her ultimate — hold R to ease to a full stop (she's so fast that stopping
	# at a star is otherwise brutal; the air-brake makes her usable). Squishy hull.
	{ "name": "Vela",   "path": "res://Spaceship (3).glb", "tint": Color(0.55, 0.80, 1.0),  "length": 0.42, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "warp": 5749.0, "engine_pitch": 1.14, "brake": true, "hp": 120, "bolt_scale": 0.9, "bolt_speed": 1050.0, "fire_cd": 0.05, "dmg": 2, "raw": true },
	# Mule — a UTILITY hull: no weapons, very slow (0.001 ly), but a 1000-HP tank.
	# Used later to tow/reposition stations. Three white-transparent boosters.
	{ "name": "Mule",   "path": "res://utility_ship.glb",  "tint": Color(0.60, 0.66, 0.76), "length": 0.7,  "yaw": 0.0, "pitch": 0.0, "glow": 0.0, "warp": 3.0, "engine_pitch": 0.7, "hp": 1000, "can_fire": false, "raw": true },
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
	"Mule": [
		Vector2(-0.20,  0.00),   # left engine pod
		Vector2( 0.20,  0.00),   # right engine pod
		Vector2( 0.00,  0.04),   # central thruster
	],
	"Vela": [
		Vector2(-0.05, -0.01),   # twin engines, tight on the central block
		Vector2( 0.05, -0.01),
	],
}
const BOOSTER_FALLBACK := [Vector2(-0.08, 0.0), Vector2(0.08, 0.0)]  # if a name isn't listed
# Per-ship plume shaping. Raptor: long/thin/small. Vela: long, thin, golden.
const BOOSTER_RADIUS_SCALE := { "Lyra": 0.6, "Raptor": 0.70, "Vela": 0.45, "Stella": 0.40, "Mule": 0.6 }   # thin spikes
const BOOSTER_LENGTH_SCALE := { "Raptor": 2.2, "Vela": 1.4,  "Stella": 0.8, "Lyra": 0.5, "Mule": 0.9 }  # plume length × hull
const BOOSTER_COLOR_OVERRIDE := {
	"Mule": Color(1.0, 1.0, 1.0),      # white (transparent additive plume)
	"Lyra": Color(1.0, 0.94, 0.72),    # holy golden-white
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
# Heavier hull: lower THRUST + lower DAMPING means the ship carries its momentum and
# banks into wide, curving turns instead of snapping direction (no more jig-jag).
# Cruise speed stays ~THRUST/DAMPING (≈220), but acceleration and turn-out are gentler.
const THRUST := 1650.0        # forward/back accel (units/s^2) — ×10 for the spread-out system
const STRAFE_THRUST := 1050.0 # lateral / vertical accel
const BOOST_MULT := 3.0       # Shift multiplier
const MAX_SPEED := 10000.0
# Calm in-system cruise: sublight (non-warp) flight is capped here so you're not
# blitzing past the planets near Sol. Boost (Shift) multiplies it for fast travel.
# This is SEPARATE from warp — the per-ship ly tops are unaffected.
const SUBLIGHT_MAX := 550.0
# Damping vs thrust sets the real cruise speed (~THRUST/DAMPING here) — MAX_SPEED is
# just a ceiling. Lower DAMPING = more glide/momentum (the "heavy" feel).
const DAMPING := 0.75         # higher = eases to a stop faster when idle
const BRAKE_RATE := 3.0       # Vela's air-brake (R): eases velocity to ~0 over ~1.5s
const STEER_SMOOTH := 9.0     # mouse-steer inertia: lower = heavier, more turn coast
const MOUSE_SENS := 0.0022    # default; runtime value lives in `mouse_sens` (Settings menu)
const ROLL_RATE := 1.8        # manual Q/E roll (rad/s)

# Warp arrival: a warp ship eases out of warp as it falls toward the nearest mark, so
# it arrives instead of blasting past (and the star has time to bloom into a sphere).
const WARP_ARRIVE_TIME := 2.0      # seconds-to-arrival at which warp starts easing out
const WARP_ARRIVE_SPEED := 400.0   # gentle speed warp bleeds down to (slow enough to scan)
const BANK_ANGLE := 0.5       # max cosmetic bank into turns (rad)
const BANK_SMOOTH := 5.0
const CAM_OFFSET := Vector3(0.0, 0.26, 1.0)  # behind (+Z) and above the now-tiny ship
const CAM_LAG := 6.0
# Free-look (hold RMB or T): mouse orbits the camera instead of steering; the ship
# holds its heading and flies on. Released, the view eases back behind the ship.
const LOOK_YAW_LIMIT := 2.7     # how far around the ship the view can swing (rad)
const LOOK_PITCH_LIMIT := 1.2   # how far up/down (rad)
const LOOK_RETURN := 8.0        # how fast the view snaps to target / eases back home
const FOV_BASE := 70.0
const FOV_KICK := 14.0        # extra FOV at full speed (sense of speed) — gentle

# --- State ---
var velocity := Vector3.ZERO
var true_pos := Vector3.ZERO   # absolute position in game units (floating origin)
var speed_limit := INF         # set by main from PlanetSystem; eases us down near a body
var nearest_dir := Vector3.ZERO  # toward nearest body; we only ease down when approaching it
var nearest_dist := INF        # distance to nearest body; set by main (warp arrival ease-out)
var star_field_dist := 0.0     # distance to this system's star; set by main (FTL gate; 0 = locked until known)
var struct_limit := INF        # strict sublight cap near stations/probes; set by main from props
var gravity := Vector3.ZERO    # set by main from PlanetSystem; gentle pull toward bodies
var dock_approach := 0.0       # 0 outside the station's landing zone, 1 at the pad; set by main
var frozen := false            # docked at a station — motion held, mouse freed
var transiting := false        # in a wormhole tunnel — motion held, view locked forward
var camera: Camera3D           # assigned by main; driven from fly()
var audio: GameAudio           # assigned by main; the engine voice is driven from fly()
var mouse_sens := MOUSE_SENS   # live mouse sensitivity (Settings menu adjusts this)
var warp := 1.0                # per-ship MAX speed multiplier; >1 = breaks physics (Vela)
var _warp_charge := 0.0        # 0..1 spool-up; ramps while thrusting forward
var fire_cooldown := 0.22      # seconds between shots (combat reads this)
var max_hp := 100              # this hull's defence / hull integrity (combat reads this)
var bolt_speed := 950.0        # this hull's bullet velocity (combat reads this)
var bolt_scale := 1.0          # this hull's bullet size multiplier (combat reads this)
var bolt_damage := 1           # damage per bolt (combat reads this) — Lyra's hit hard
var can_fire := true           # false for utility hulls (no weapons) — combat reads this
var muzzle := 2.5              # forward distance bolts spawn at — this hull's nose tip
var _dual := false             # Raptor: can toggle between combat + warp modes
const RAPTOR_WARP := 3450.0        # Raptor Warp mode (≈1.2 ly/s)
const RAPTOR_COMBAT_WARP := 345.0  # Raptor Combat mode top (≈0.12 ly/s, like Stella)
const HYPERSONIC_SPEED := 15000.0   # above this a warp ship is "hypersonic" (no combat)
const WARP_FLOOR := 5.0        # warp multiplier at zero charge (controllable start)
# FTL gate: warp can only spool up once you're beyond the system star's gravity field.
# Inside this radius you fly normal sublight cruise no matter the hull.
const SOL_FIELD_RADIUS := 2200.0
const WARP_CHARGE_TIME := 9.0  # seconds of thrust to reach full warp
const WARP_DECAY_TIME := 3.5   # seconds to spool back down when you ease off

# Station landing zone: speed is force-reduced as you near the pad so you can
# actually land — applies to ALL ships, warp included. Fed by main via dock_approach.
const DOCK_EDGE_SPEED := 1000.0    # speed cap at the outer edge of the zone (gentle entry)
const DOCK_PLATFORM_SPEED := 60.0  # speed cap right at the pad (smooth final approach)
const DOCK_SPIN := 0.5             # showroom turntable spin (rad/s) while docked

# True when a warp ship is blazing fast — combat + crosshair are disabled.
func is_hypersonic() -> bool:
	return warp > 1.0 and velocity.length() > HYPERSONIC_SPEED

# This hull can build full FTL right now: it has a warp drive AND it's clear of every
# force-slow safe-zone (deep space). Near a star/planet the zone caps your speed.
func warp_ready() -> bool:
	return warp > 1.0 and is_inf(speed_limit)

# Raptor only: toggle between Combat mode (machine-gun, normal flight) and Warp
# mode (Vela-style FTL). Returns the new mode name for HUD feedback.
func toggle_warp_mode() -> String:
	if not _dual:
		return ""
	if warp >= RAPTOR_WARP:
		warp = RAPTOR_COMBAT_WARP   # back to Combat mode (≈0.12 ly cap)
		return "COMBAT"
	else:
		warp = RAPTOR_WARP          # Warp / FTL mode (≈1.2 ly)
		_warp_charge = 0.0
		return "WARP"

func is_warp_mode() -> bool:
	return _dual and warp > 1.0

var _current_model := 0        # index into SHIP_MODELS
var _engine_pitch := 1.0       # per-ship engine voice character (set on build)
var _can_brake := false        # Vela: tap S for a near-instant full stop (her ultimate)
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
var _steer := Vector2.ZERO     # eased mouse-steer (rotational inertia for curving turns)
var _mouse_captured := false
var _free_look := false       # true while holding RMB / T — mouse orbits the view
var _look_yaw := 0.0          # target orbit angles (set in fly)
var _look_pitch := 0.0
var _look_yaw_s := 0.0        # smoothed orbit angles actually applied to the camera
var _look_pitch_s := 0.0


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
		_steer = Vector2.ZERO
		_look_yaw = 0.0
		_look_pitch = 0.0
		_update_boosters(1.0, delta)
		_update_streaks(1.0)
		_update_camera(delta)
		if audio:
			audio.engine_off()   # silent in the wormhole
		return

	# Docked: hold position, idle the boosters, keep the camera steady, and slowly
	# turntable the hull so the ship is clearly on show while you pick one.
	if frozen:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_steer = Vector2.ZERO
		_look_yaw = 0.0
		_look_pitch = 0.0
		_mesh_root.rotate_y(DOCK_SPIN * delta)
		_update_boosters(0.0, delta)
		_update_streaks(0.0)
		_update_camera(delta)
		if audio:
			audio.engine_off()   # engine cut while docked
		return

	# --- Look vs. steer ---
	# Hold RMB or T for free-look: the mouse orbits the camera around the ship while
	# the ship holds its heading and keeps flying. Release to steer normally again.
	_free_look = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or Input.is_physical_key_pressed(KEY_T)
	var md := _mouse_delta
	_mouse_delta = Vector2.ZERO
	var turn := 0.0   # this frame's mouse yaw (drives cosmetic banking below)

	if _free_look:
		_steer = Vector2.ZERO
		_look_yaw = clampf(_look_yaw - md.x * mouse_sens, -LOOK_YAW_LIMIT, LOOK_YAW_LIMIT)
		_look_pitch = clampf(_look_pitch - md.y * mouse_sens, -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	else:
		# Normal steering: mouse aims, Q/E roll. View eases back behind the ship.
		# The steer input is low-passed so the hull ramps into a turn and coasts out
		# of it — a heavier, curving feel rather than an instant snap.
		_steer = _steer.lerp(md, clampf(STEER_SMOOTH * delta, 0.0, 1.0))
		turn = _steer.x * mouse_sens
		rotate_object_local(Vector3.UP, -_steer.x * mouse_sens)
		rotate_object_local(Vector3.RIGHT, -_steer.y * mouse_sens)
		var roll := 0.0
		if Input.is_physical_key_pressed(KEY_Q):
			roll += 1.0
		if Input.is_physical_key_pressed(KEY_E):
			roll -= 1.0
		rotate_object_local(Vector3.BACK, roll * ROLL_RATE * delta)
		orthonormalize()  # scrub float drift out of the basis over time
		_look_yaw = 0.0
		_look_pitch = 0.0

	# --- Thrust (local axes -> world via current basis) ---
	var boost := BOOST_MULT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var fwd := 0.0
	var strafe := 0.0
	var lift := 0.0
	# S is reverse thrust on every hull (Vela included) — with the heavier flight model
	# you need to be able to back off and reposition.
	if Input.is_physical_key_pressed(KEY_W):
		fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		fwd += 1.0
	# R is Vela's signature air-brake: hold it to ease velocity to ~0 over ~1.5s and
	# drop the warp charge, so she can actually park despite her absurd top speed.
	var braking := _can_brake and Input.is_physical_key_pressed(KEY_R)
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		lift += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		lift -= 1.0

	# FTL: every hull can spool warp by holding W. There's no gate — instead the
	# force-slow safe-zones around stars/planets cap your speed when you're near them,
	# so you naturally drop out of warp near a body and fly free in the deep.
	var eff_warp := 1.0
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
	# Vela's air-brake (R): a smooth, hard stop — ~1.5s to a standstill — plus a warp
	# dump, so she can pull up at a star instead of blowing through it.
	if braking:
		velocity = velocity.lerp(Vector3.ZERO, clampf(BRAKE_RATE * delta, 0.0, 1.0))
		_warp_charge = 0.0
	var cap := MAX_SPEED * eff_warp * boost
	if eff_warp <= 1.0:
		cap = minf(cap, SUBLIGHT_MAX * boost)   # calm sublight cruise when not warping
	# Force-slow safe-zones around stars/planets/moons (NO pull) — applied in ANY mode
	# and ANY direction, so you ease right down to orbit, analyse, and capture a body,
	# and a star drops you out of warp as you arrive. Scaled by the body's mass.
	cap = minf(cap, speed_limit)
	# Harbour cap near stations — any mode, so you never blast through a structure.
	cap = minf(cap, struct_limit)
	# Bleed warp charge when something is force-slowing us, so the drive visibly drops
	# out of warp as you settle near a body/station instead of pinning at full spool.
	if (speed_limit < INF or struct_limit < INF) and cap < MAX_SPEED:
		_warp_charge = minf(_warp_charge, cap / maxf(MAX_SPEED, 1.0))
	velocity = velocity.limit_length(cap)

	# Platform approach: inside the station's landing zone the speed is force-reduced
	# so you can actually land — no matter how fast you arrived (warp included). The
	# cap shrinks smoothly with proximity, easing you down rather than snapping. You
	# keep steering, you just can't blast through. (dock_approach is fed by main.)
	if dock_approach > 0.0:
		var land_cap := lerpf(DOCK_EDGE_SPEED, DOCK_PLATFORM_SPEED, dock_approach)
		velocity = velocity.limit_length(land_cap)

	# --- Floating origin: never move the node; accumulate the true position ---
	true_pos += velocity * delta

	# --- Cosmetic banking (on the mesh only, so the camera stays steady) ---
	var target_bank := clampf(-turn * 7.0 - strafe * 0.35, -BANK_ANGLE, BANK_ANGLE)
	_bank = lerpf(_bank, target_bank, clampf(BANK_SMOOTH * delta, 0.0, 1.0))
	_mesh_root.rotation.z = _bank

	# --- Engine / booster intensity ---
	var throttle := 1.0 if Input.is_physical_key_pressed(KEY_W) else 0.18
	if Input.is_physical_key_pressed(KEY_S):
		throttle = maxf(throttle, 0.55)
	if boost > 1.0:
		throttle *= 1.4
	_update_boosters(throttle, delta)

	# --- Engine voice: loop while we're on the gas, with start/stop whooshes ---
	if audio:
		var thrusting := local_accel != Vector3.ZERO
		var ship_name: String = SHIP_MODELS[_current_model].name
		audio.update_engine(ship_name, thrusting, clampf(throttle, 0.0, 1.0), boost > 1.0, _engine_pitch, delta, is_warp_mode())
	if _engine_mat:  # fallback ship only
		var e := 2.0 + throttle * 4.0
		_engine_mat.emission_energy_multiplier = lerpf(
			_engine_mat.emission_energy_multiplier, e, clampf(8.0 * delta, 0.0, 1.0))

	_update_streaks(velocity.length() / MAX_SPEED)
	_update_camera(delta)


func _update_boosters(throttle: float, delta: float) -> void:
	var k := clampf(10.0 * delta, 0.0, 1.0)
	# Warp/travel mode (Raptor): a long, bright, flickering purple FIRE trail.
	var fire := is_warp_mode()
	var t := Time.get_ticks_msec() * 0.001
	var flick := 1.0 + 0.18 * sin(t * 33.0) + 0.12 * sin(t * 71.0) if fire else 1.0
	var len_mul := 2.4 * flick if fire else 1.0
	var max_alpha := 0.95 if fire else 0.6
	for b in _boosters:
		# Plume length stretches with throttle; nozzle stays anchored.
		var sc: Vector3 = b.pivot.scale
		sc.y = lerpf(sc.y, (0.35 + throttle * 0.7) * len_mul, k)
		b.pivot.scale = sc
		# Plume transparency (additive) tracks throttle (fire = much brighter).
		var pcol: Color = b.plume_mat.albedo_color
		pcol.a = lerpf(pcol.a, clampf((0.05 + throttle * 0.45) * (1.7 if fire else 1.0), 0.0, max_alpha), k)
		b.plume_mat.albedo_color = pcol
		# Soft core glow at the nozzle (bigger + flickering in fire mode).
		var cs := (0.35 + throttle * 0.7) * (1.6 * flick if fire else 1.0)
		b.core.scale = Vector3(cs, cs, cs)
		var ccol: Color = b.core_mat.albedo_color
		ccol.a = lerpf(ccol.a, clampf(0.12 + throttle * 0.5, 0.0, 0.95), k)
		b.core_mat.albedo_color = ccol


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	# Camera basis lags the ship's a touch -> gentle sway / sense of speed.
	_cam_basis = _cam_basis.slerp(transform.basis, clampf(CAM_LAG * delta, 0.0, 1.0))
	_cam_zoom_smooth = lerpf(_cam_zoom_smooth, _cam_zoom, clampf(10.0 * delta, 0.0, 1.0))
	# Free-look orbit: ease the applied angles toward target (0 = straight behind).
	# Rotating the whole chase rig keeps the ship framed, so at 0 it's the usual cam.
	var lk := clampf(LOOK_RETURN * delta, 0.0, 1.0)
	_look_yaw_s = lerpf(_look_yaw_s, _look_yaw, lk)
	_look_pitch_s = lerpf(_look_pitch_s, _look_pitch, lk)
	var basis := _cam_basis * (Basis(Vector3.UP, _look_yaw_s) * Basis(Vector3.RIGHT, _look_pitch_s))
	var cam_pos := basis * (CAM_OFFSET * _cam_zoom_smooth)  # ship at origin -> global
	camera.global_transform = Transform3D(basis, cam_pos)
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
	max_hp = int(info.get("hp", 100))
	bolt_speed = float(info.get("bolt_speed", 950.0))
	bolt_scale = float(info.get("bolt_scale", 1.0))
	bolt_damage = int(info.get("dmg", 1))
	can_fire = bool(info.get("can_fire", true))
	_dual = info.get("dual", false)
	_engine_pitch = float(info.get("engine_pitch", 1.0))
	_can_brake = info.get("brake", false)
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
	# Bolts spawn out in FRONT of the nose, not at it: from the chase camera a bolt
	# right at the tip reads as sitting above/behind the hull. Push it ~1.5 hull-depths
	# past center so its first visible frame is already downrange and clear of the ship
	# (scales with hull size — the muzzle moment itself isn't shown).
	muzzle = box.size.z * 1.6
	_recolor(model, info.tint, float(info.glow), info.get("chrome", false), info.get("raw", false))
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
	# Clear any showroom-spin / banking carryover so the hull is aligned with the
	# nose again the instant you undock (otherwise it'd fly pointing sideways).
	_mesh_root.rotation = Vector3.ZERO
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
func _recolor(model: Node3D, tint: Color, glow: float, chrome := false, raw := false) -> void:
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
			if raw:
				# Keep the model's AUTHORED colours/textures exactly (its beautiful
				# design), and render them UNSHADED so they show full-colour in our
				# light-less scene — no flat tint, no washout.
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.vertex_color_use_as_albedo = true   # honour per-vertex colours if any
				m.emission_enabled = false
			elif chrome:
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
	# Sized PROPORTIONAL to the hull (no absolute floors — those blew up once the ships
	# shrank ~9×). radius ~ fraction of width, length ~ fraction of hull length.
	var r := s.x * (0.085 - 0.006 * mounts.size()) * rscale
	var length := s.z * 0.55 * lscale
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
