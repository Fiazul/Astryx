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
	# Lyra: clean multi-part OBJ (cockpitglass, fighter, engine, guns, enginecanopy).
	# Per-surface roles give glass canopy + silver body + gold accents; neutral dim
	# light rig so the metal reads without glowing. One engine -> one booster.
	{ "name": "Lyra",   "path": "res://assets/lyra.obj",   "tint": Color(1.0, 1.0, 1.0),    "length": 0.7, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 1.0,  "hp": 280, "bolt_scale": 1.8, "bolt_speed": 820.0,  "fire_cd": 0.22, "dmg": 3, "bolt_laser": true, "energy_max": 130.0, "energy_use": 0.85, "warp": 10.7, "pbr": true,
		"surf_roles": ["glass", "red", "red", "goldtrim", "goldtrim"],
		"light_accent": Color(1.0, 0.86, 0.84), "light_energy": 0.85 },
	{ "name": "Stella", "path": "res://assets/Spaceship.glb",     "tint": Color(0.70, 0.62, 0.95), "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.92, "hp": 80, "bolt_scale": 0.62, "bolt_speed": 1700.0, "fire_cd": 0.04, "dmg": 1, "energy_max": 80.0, "energy_use": 1.6, "warp": 10.0 },
	{ "name": "Raptor", "path": "res://assets/Spaceship (2).glb", "tint": Color(0.70, 0.90, 0.95), "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.82, "hp": 170, "bolt_scale": 0.95, "bolt_speed": 1050.0, "fire_cd": 0.10, "dual": true, "dmg": 2, "energy_max": 170.0, "energy_use": 0.55, "warp": 7.3 },
	# Vela: the FTL ship. warp 4312 -> max cruise ≈ 1.5 ly/s at full charge
	# (THRUST·warp/DAMPING, 1 ly = 632,411 units). Her drive spools up over time
	# (see WARP_CHARGE_*), so she eases into warp rather than snapping to it.
	# "brake": her ultimate — hold R to ease to a full stop (she's so fast that stopping
	# at a star is otherwise brutal; the air-brake makes her usable). Squishy hull.
	{ "name": "Vela",   "path": "res://assets/Spaceship (3).glb", "tint": Color(0.55, 0.80, 1.0),  "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "energy_max": 100.0, "energy_use": 1.2, "warp": 14.0, "engine_pitch": 1.14, "brake": true, "hp": 90, "bolt_scale": 0.9, "bolt_speed": 1050.0, "fire_cd": 0.06, "dmg": 2, "raw": true },
	# HaniStar — a slow, pretty support hull that CAN fight: fires a touch faster than
	# Lyra, hits a bit harder than Stella, 125 HP. Three light-blue boosters.
	# surf_roles indexes the GLB's 9 surfaces: gold = shiny rose-gold (7 = wings), glass =
	# top-front canopy (3), orb = soft neon-pink accents, hull = pink crystal body.
	# (4 = the two upright tail fins, kept pink hull.)
	{ "name": "HaniStar",   "path": "res://assets/utility_ship.glb",  "tint": Color(1.0, 0.412, 0.706), "length": 0.6,  "yaw": 90.0, "pitch": 0.0, "glow": 0.18, "energy_max": 120.0, "energy_use": 0.95, "warp": 8.3, "engine_pitch": 0.7, "hp": 200, "fire_cd": 0.18, "dmg": 2, "bolt_scale": 1.0, "bolt_speed": 900.0, "pbr": true,
		"surf_roles": ["hull", "hull", "gold", "glass", "hull", "hull", "hull", "gold", "hull"] },
	# Raptor 2 Neo ("mother ship"): the powerhouse — Stella's fire rate, Vela's top speed,
	# Lyra's damage, HaniStar's hull. Silver-blue metal body + glass illuminators.
	{ "name": "Raptor 2 Neo", "path": "res://assets/raptor2.obj", "tint": Color(1, 1, 1), "length": 0.65, "yaw": 0.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.7, "hp": 200, "bolt_scale": 1.0, "bolt_speed": 1700.0, "fire_cd": 0.06, "dmg": 3, "energy_max": 150.0, "energy_use": 0.7, "warp": 13.0, "pbr": true, "laser": true, "auto_capture": true,
		"laser_offset": Vector3(0.0, -0.03, -0.10),   # beam emitter point (slightly down)
		"surf_roles": ["glass", "silver"],
		"light_accent": Color(0.82, 0.90, 1.0), "light_energy": 0.8 },
	# Vortex retired as a player ship — it's a boss enemy now (see combat.gd boss).
]
const BOOSTER_COLOR := Color(0.35, 0.8, 1.0)
# Booster nozzle placement (fractions of the fitted model's size). Nudge these
# to snap the plumes onto Lyra's actual engines.
const BOOSTER_BACK := 0.40          # how far back (0 = center, 0.5 = tail). Lower = closer to hull.
# Per-ship override of BOOSTER_BACK (fraction back toward the tail).
const BOOSTER_BACK_OVERRIDE := {}
const BOOSTER_RISE := 0.0           # vertical nudge for the whole cluster (+ up, - down)
# Per-ship nozzle layout: each engine is (x, y) as fractions of the ship's WIDTH
# (x = left/right, y = up/down). Each ship has a different engine count/pattern;
# nudge these to snap the plumes onto each hull's actual bells.
#   Lyra   = 5 in an A (apex on top, legs spread wide at the bottom)
#   Vortex = 4
#   Stella = 2
#   Raptor = 1
const BOOSTER_LAYOUTS := {
	"Lyra": [ Vector2(0.0, 0.0) ],   # one plume on the engine (clean OBJ, centred)
	"Raptor 2 Neo": [   # onto the model's 4 engine bells: upper pair (up+left+forward) + lower pair
		Vector2(-0.32,  0.14), Vector2( 0.30,  0.14),
		Vector2(-0.17, -0.13), Vector2( 0.17, -0.13),
	],
	"Stella": [
		Vector2(-0.09,  0.00),   # left
		Vector2( 0.09,  0.00),   # right
	],
	"Raptor": [
		Vector2( 0.00, -0.02),   # single, centered
	],
	"HaniStar": [
		Vector2( 0.00, -0.10),   # main central thruster, slightly low
		Vector2(-0.30, -0.06),   # support booster, left side tucked against the hull
		Vector2( 0.30, -0.06),   # support booster, right side tucked against the hull
	],
	"Vela": [
		Vector2(-0.05, -0.01),   # twin engines, tight on the central block
		Vector2( 0.05, -0.01),
	],
}
const BOOSTER_FALLBACK := [Vector2(-0.08, 0.0), Vector2(0.08, 0.0)]  # if a name isn't listed
# Per-ship plume shaping. Raptor: long/thin/small. Vela: long, thin, golden.
const BOOSTER_RADIUS_SCALE := { "Lyra": 0.9, "Raptor": 0.62, "Vela": 0.45, "Stella": 0.40, "HaniStar": 0.6, "Raptor 2 Neo": 0.6 }   # one engine
const BOOSTER_LENGTH_SCALE := { "Raptor": 1.0, "Vela": 1.4,  "Stella": 0.8, "Lyra": 0.8, "HaniStar": 0.9, "Raptor 2 Neo": 1.3 }  # plume length × hull
const BOOSTER_COLOR_OVERRIDE := {
	"HaniStar": Color(0.62, 0.82, 1.0),    # very light blue exhaust
	"Lyra": Color(0.55, 0.90, 1.0),    # pretty bright aqua-cyan
	"Raptor 2 Neo": Color(0.35, 0.65, 1.0),  # strong electric blue
	"Vela": Color(1.0, 0.82, 0.32),    # transparent gold
	"Stella": Color(1.0, 0.26, 0.20),  # sharp transparent red
	"Raptor": Color(0.85, 0.72, 0.45), # champagne gold (small + powerful; deploys in warp)
}
const BOOSTER_FADE_FLIP := false    # if the plume fades at the wrong end, flip this
# Per-mount size multipliers (same order as BOOSTER_LAYOUTS). HaniStar: big main + smaller supports.
const BOOSTER_MOUNT_SCALE := { "HaniStar": [1.3, 0.65, 0.65] }
# Per-mount extra BACK offset (fraction of hull length) to push a nozzle clear of the
# hull when a rear plate blocks it. HaniStar's main sits behind a rear plate.
const BOOSTER_MOUNT_BACK := { "HaniStar": [0.08, 0.0, 0.0],
	"Raptor 2 Neo": [-0.08, -0.08, 0.0, 0.0] }   # push the upper pair forward
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
const BOOST_DRAIN := 16.0     # boost energy/sec burned while boosting (generous; combat owns the pool)
const MAX_SPEED := 10000.0
# Calm in-system cruise: sublight (non-warp) flight is capped here so you're not
# blitzing past the planets near Sol. Boost (Shift) multiplies it for fast travel.
# This is SEPARATE from warp — the per-ship ly tops are unaffected.
const SUBLIGHT_MAX := 550.0
# Auto-settle: close to a body, gently bleed speed toward a hover so releasing thrust
# holds you on station to capture (thrust still lets you nudge/orbit). Closer = stronger.
const SETTLE_RANGE := 900.0
const SETTLE_RATE := 1.5
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
var bolt_laser := false        # bolts render as red laser beams (Lyra) — combat reads this
var energy_max := 100.0        # per-ship energy cap (both bars); combat reads this
var energy_use := 1.0          # per-ship consume multiplier; combat + boost read this
var can_fire := true           # false for utility hulls (no weapons) — combat reads this
var has_laser := false         # right-click nose laser beam (Raptor 2 Neo) — combat reads this
var laser_offset := Vector3.ZERO   # local muzzle offset for the beam (x=right, y=up)
var auto_capture := false       # captures bodies in range automatically (no V) — Raptor 2 Neo
var combat_lock := false        # set by main while in combat — no interstellar/FTL speed
var combat_ref: Node                   # set by main — owns the shared energy pools
var _boost_starved := false            # true while boosting on an empty tank -> plume sputters
var is_boosting := false               # true while boost is actually engaged (combat pauses boost regen)
var boost_blocked := false             # true when Shift pressed in a slow-zone (boost unavailable)
var auto_cruise := false        # Num Lock: hold W+Shift hands-free (forward thrust + boost)
var autopilot := false          # hands-off cinematic flight to autopilot_target (M-map)
var autopilot_target := Vector3.ZERO   # world position to fly to
var autopilot_name := ""        # body the autopilot is bound to (main refreshes the target)
const AP_ARRIVE := 600.0        # stop autopilot within this distance of the target
const AP_TURN := 2.5            # autopilot turn rate toward the target
var muzzle := 2.5              # forward distance bolts spawn at — this hull's nose tip
var muzzle_drop := 0.0         # how far BELOW the nose bolts emerge (set per hull from its height)
var _dual := false             # Raptor: can toggle between combat + warp modes
# Warp is now a TOP-SPEED multiplier (cap = MAX_SPEED × warp). Tuned so the fastest
# hull crosses ~1 light-year in ~45 seconds (1 ly = 6.32M units; 14×10000 ≈ 140k u/s).
const RAPTOR_WARP := 12.0           # Raptor Warp mode
const RAPTOR_COMBAT_WARP := 7.3    # Raptor Combat mode top
const HYPERSONIC_SPEED := 15000.0   # above this a warp ship is "hypersonic" (no combat)
const WARP_FLOOR := 1.0        # zero-charge = calm sublight; holding W spools up to warp
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

# True only in Raptor's actual WARP form (not his combat mode) — drives the deployed,
# flared booster. is_warp_mode() can't tell the two apart (both warps are > 1.0).
func is_warp_form() -> bool:
	return _dual and warp >= RAPTOR_WARP

var _current_model := 0        # index into SHIP_MODELS
var _engine_pitch := 1.0       # per-ship engine voice character (set on build)
var _can_brake := false        # Vela: tap S for a near-instant full stop (her ultimate)
var _mesh_root: Node3D
var _engine_mat: StandardMaterial3D   # only used by the primitive fallback
var _boosters: Array = []
var _glow_tex: Texture2D
var _plume_grad: Texture2D
var _booster_color := BOOSTER_COLOR   # per-ship plume tint, set in _build_boosters
var _booster_ring := false            # add a glowing engine-ring at the nozzle (the HaniStar)
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
	_glow_tex = ShipMesh.make_glow_texture()
	_plume_grad = ShipMesh.make_plume_gradient(BOOSTER_FADE_FLIP)
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
	# (On laser ships RMB fires the nose beam instead, so free-look there is T-only.)
	_free_look = (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not has_laser) \
		or Input.is_physical_key_pressed(KEY_T)
	var md := _mouse_delta
	_mouse_delta = Vector2.ZERO
	var turn := 0.0   # this frame's mouse yaw (drives cosmetic banking below)

	if autopilot:
		_autopilot_steer(delta)
		_steer = Vector2.ZERO
		_look_yaw = 0.0
		_look_pitch = 0.0
	elif _free_look:
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
	# Shift = boost, draining the shared boost pool (owned by combat). It only ENGAGES
	# (and only burns energy) when the boost can actually push you faster — i.e. you're
	# NOT pinned by a star/station slow-zone. Pressing Shift in a slow-zone does nothing
	# and costs nothing.
	var boost := 1.0
	var be: float = combat_ref.boost_energy if combat_ref != null else 1.0
	var boost_effective := minf(speed_limit, struct_limit) >= SUBLIGHT_MAX
	var want_boost := Input.is_physical_key_pressed(KEY_SHIFT) or auto_cruise
	is_boosting = false
	# Pressed Shift where boost can't help (a slow-zone) -> tell the player, cost nothing.
	boost_blocked = want_boost and not boost_effective
	if want_boost and be > 0.0 and boost_effective:
		boost = BOOST_MULT
		is_boosting = true
		if combat_ref != null:
			combat_ref.boost_energy = maxf(combat_ref.boost_energy - BOOST_DRAIN * energy_use * delta, 0.0)
	# Plume only chokes if you're trying to boost effectively but the tank is empty.
	_boost_starved = want_boost and boost_effective and be <= 0.0
	var fwd := 0.0
	var strafe := 0.0
	var lift := 0.0
	# S is reverse thrust on every hull (Vela included) — with the heavier flight model
	# you need to be able to back off and reposition.
	if Input.is_physical_key_pressed(KEY_W) or auto_cruise:
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
	# Auto-pilot drives forward at warp toward the target (overrides manual thrust).
	if autopilot:
		fwd = -1.0
		strafe = 0.0
		lift = 0.0
		braking = false
	var eff_warp := 1.0
	if warp > 1.0 and not combat_lock:
		if Input.is_physical_key_pressed(KEY_W) or auto_cruise or autopilot:   # auto-cruise/autopilot spool warp too
			_warp_charge = minf(_warp_charge + delta / WARP_CHARGE_TIME, 1.0)
		else:
			_warp_charge = maxf(_warp_charge - delta / WARP_DECAY_TIME, 0.0)
		var c := _warp_charge * _warp_charge * (3.0 - 2.0 * _warp_charge)   # smoothstep
		eff_warp = lerpf(WARP_FLOOR, warp, c)
	elif combat_lock:
		# No interstellar speed during combat — bleed any spool back to sublight.
		_warp_charge = maxf(_warp_charge - delta / WARP_DECAY_TIME, 0.0)

	var local_accel := Vector3(strafe * STRAFE_THRUST, lift * STRAFE_THRUST, fwd * THRUST) * eff_warp
	if local_accel != Vector3.ZERO:
		velocity += (transform.basis * local_accel) * boost * delta

	# Gravitational tug toward nearby bodies (gentle; thrust overpowers it).
	velocity += gravity * delta

	# Arcade damping: velocity eases toward zero when you're not thrusting.
	velocity = velocity.lerp(Vector3.ZERO, clampf(DAMPING * delta, 0.0, 1.0))
	# Auto-settle near a body: a soft, always-on brake that strengthens as you close in,
	# so easing off the throttle lets you hover and capture instead of drifting past.
	if nearest_dist < SETTLE_RANGE and not braking:
		var settle := SETTLE_RATE * (1.0 - nearest_dist / SETTLE_RANGE)
		velocity = velocity.lerp(Vector3.ZERO, clampf(settle * delta, 0.0, 1.0))
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
	var throttle := 1.0 if (Input.is_physical_key_pressed(KEY_W) or auto_cruise) else 0.18
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
	# Always-on engines: keep a strong baseline plume even at idle (boosting still
	# pushes it to full). Without this the plume only "appeared" under thrust.
	throttle = maxf(throttle, 0.6)
	# Warp form (Raptor only): the booster DEPLOYS — a long, bright, flickering fire
	# trail. Combat mode keeps the regular short plume.
	var fire := is_warp_form()
	var t := Time.get_ticks_msec() * 0.001
	var flick := 1.0 + 0.18 * sin(t * 33.0) + 0.12 * sin(t * 71.0) if fire else 1.0
	var len_mul := 2.4 * flick if fire else 1.0
	var max_alpha := 0.95 if fire else 0.6
	# Out of boost juice: the engine coughs — a fast on/off stutter that cuts the plume.
	var sputter := 1.0
	if _boost_starved:
		sputter = 0.15 if fmod(t * 11.0, 1.0) < 0.45 else 1.0
		k = 1.0   # snap, so the stutter is visible instead of smoothed away
	for b in _boosters:
		# Plume length stretches with throttle; bell + ring (on the pivot) stay fixed.
		var sc: Vector3 = b.plume_holder.scale
		sc.y = lerpf(sc.y, (0.35 + throttle * 0.7) * len_mul * sputter, k)
		b.plume_holder.scale = sc
		# Plume transparency (additive) tracks throttle (fire = much brighter).
		var pcol: Color = b.plume_mat.albedo_color
		pcol.a = lerpf(pcol.a, clampf((0.05 + throttle * 0.45) * (1.7 if fire else 1.0) * sputter, 0.0, max_alpha), k)
		b.plume_mat.albedo_color = pcol
		# Soft core glow at the nozzle (bigger + flickering in fire mode).
		var cs := (0.35 + throttle * 0.7) * (1.6 * flick if fire else 1.0) * sputter
		b.core.scale = Vector3(cs, cs, cs)
		var ccol: Color = b.core_mat.albedo_color
		ccol.a = lerpf(ccol.a, clampf((0.12 + throttle * 0.5) * sputter, 0.0, 0.95), k)
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
	bolt_laser = bool(info.get("bolt_laser", false))
	energy_max = float(info.get("energy_max", 100.0))
	energy_use = float(info.get("energy_use", 1.0))
	can_fire = bool(info.get("can_fire", true))
	has_laser = bool(info.get("laser", false))
	laser_offset = info.get("laser_offset", Vector3.ZERO)
	auto_capture = bool(info.get("auto_capture", false))
	_dual = info.get("dual", false)
	_engine_pitch = float(info.get("engine_pitch", 1.0))
	_can_brake = info.get("brake", false)
	_warp_charge = 0.0
	# Loads a PackedScene (.glb/.gltf/.fbx/.dae) OR a bare Mesh (.obj) — wrap a Mesh
	# in a MeshInstance3D so both paths produce a model Node3D.
	var res := load(info.path)
	var model: Node3D
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		model = mi
	if model == null:
		push_warning("Ship: could not load %s — using primitive fallback." % info.path)
		_build_primitive_ship()
		return
	_mesh_root.add_child(model)
	model.rotation = Vector3(deg_to_rad(float(info.pitch)), deg_to_rad(float(info.yaw)), 0.0)
	var box := ShipMesh.fit_model(_mesh_root, model, float(info.length))
	# Bolts now spawn right AT the nose tip (~half the hull depth ahead of center) so
	# their trailing streak visibly emerges from the ship — even from a side view. The
	# slim bright tracer + soft trail keep it readable without sitting on the hull.
	muzzle = box.size.z * 0.55
	muzzle_drop = box.size.y * 0.25   # emerge a little below the nose, where the guns sit
	# Optionally lop off the model's rear (behind the ring) so the bell disc caps a
	# clean cut instead of the GLB's messy tail.
	if info.get("clip_back", false):
		var cut: float = box.size.z * float(BOOSTER_BACK_OVERRIDE.get(info.name, BOOSTER_BACK))
		ShipMesh.clip_behind(model, _mesh_root, cut)
	if info.get("metal", false) and info.has("gold_above"):
		# Silver body + champagne-gold top wing (split a single-surface mesh by height).
		ShipMesh.metal_split(model, _mesh_root, box.size.y * float(info.gold_above))
	else:
		ShipMesh.recolor(model, info.tint, float(info.glow), info.get("chrome", false), info.get("raw", false), info.get("pbr", false), info.get("surf_roles", []), info.get("metal", false))
	_build_boosters(box, info.name)
	if info.get("gold_backplate", false):
		_add_gold_backplate(box, info.name)
	if info.get("pbr", false):
		# Light rig tint/energy per ship (HaniStar: pink; metal ships: neutral + dim).
		var accent: Color = info.get("light_accent", Color(1.0, 0.70, 0.84))
		var lenergy: float = float(info.get("light_energy", 1.0))
		ShipMesh.add_hull_lights(_mesh_root, box, accent, lenergy)


# A champagne-gold heart plate seated at the booster cluster's base, filling the
# gaps between bells so the clipped rear reads as one solid backing instead of holes.
func _add_gold_backplate(box: AABB, ship_name: String) -> void:
	var s := box.size
	var plate := MeshInstance3D.new()
	plate.mesh = ShipMesh.make_heart_mesh(s.x * 0.5)   # sized to the bell cluster
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.737, 0.651, 0.478)   # champagne gold
	gm.metallic = 1.0
	gm.roughness = 0.12
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED     # visible from both sides
	plate.material_override = gm
	# Sit BEHIND the bells (toward the hull) so the bells mount on its face and every
	# plume fires out the far side — nothing passes through the plate.
	var mount_z := s.z * float(BOOSTER_BACK_OVERRIDE.get(ship_name, BOOSTER_BACK))
	plate.position = Vector3(0.0, s.y * BOOSTER_RISE, mount_z - s.z * 0.12)
	_mesh_root.add_child(plate)


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


# Begin hands-off cinematic flight to a body (main keeps autopilot_target current).
func start_autopilot(body_name: String) -> void:
	autopilot = true
	autopilot_name = body_name


# Steer the ship toward autopilot_target; cancel the moment the player takes control.
func _autopilot_steer(delta: float) -> void:
	# Cancel only when the player actually flies (thrust keys) — not the mouse, so it
	# doesn't abort the instant the map closes and the cursor re-captures.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_S) \
			or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_D) \
			or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_CTRL):
		autopilot = false
		return
	var to := autopilot_target - true_pos
	if to.length() < AP_ARRIVE:
		autopilot = false
		return
	var dir := to.normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var tb := Transform3D(Basis(), Vector3.ZERO).looking_at(dir, up).basis
	transform.basis = transform.basis.slerp(tb, clampf(AP_TURN * delta, 0.0, 1.0)).orthonormalized()


# Additive booster plumes at the rear of the (fitted, centered) model — one per
# engine in this ship's BOOSTER_LAYOUTS entry (count/pattern differ per hull).
func _build_boosters(box: AABB, ship_name: String) -> void:
	var s := box.size
	var mount_z := s.z * float(BOOSTER_BACK_OVERRIDE.get(ship_name, BOOSTER_BACK))  # +Z is behind the ship (forward is -Z)
	var rise := s.y * BOOSTER_RISE
	var mounts: Array = BOOSTER_LAYOUTS.get(ship_name, BOOSTER_FALLBACK)
	_booster_color = BOOSTER_COLOR_OVERRIDE.get(ship_name, BOOSTER_COLOR)
	_booster_ring = true   # every ship gets the metallic engine bell + nozzle ring
	# Fewer engines read better a touch larger; scale radius down as count grows.
	var rscale: float = BOOSTER_RADIUS_SCALE.get(ship_name, 1.0)
	var lscale: float = BOOSTER_LENGTH_SCALE.get(ship_name, 1.0)
	# Sized PROPORTIONAL to the hull (no absolute floors — those blew up once the ships
	# shrank ~9×). radius ~ fraction of width, length ~ fraction of hull length.
	# Bells shrink as the count grows, but clamp so dense clusters (Lyra's 10) stay fat
	# enough to overlap into a solid disc instead of vanishing.
	var r := s.x * maxf(0.085 - 0.006 * mounts.size(), 0.05) * rscale
	var length := s.z * 0.55 * lscale
	# Optional per-mount size multipliers (same order as the mounts) so one ship can
	# mix a big main booster with smaller support boosters.
	var per: Array = BOOSTER_MOUNT_SCALE.get(ship_name, [])
	var back: Array = BOOSTER_MOUNT_BACK.get(ship_name, [])
	for i in mounts.size():
		var m: Vector2 = mounts[i]
		var ms: float = per[i] if i < per.size() else 1.0
		var bz: float = back[i] if i < back.size() else 0.0
		var pos := Vector3(m.x * s.x, rise + m.y * s.x, mount_z + bz * s.z)
		_boosters.append(_make_booster(pos, r * ms, length * ms))


func _make_booster(mount: Vector3, radius: float, length: float) -> Dictionary:
	# A pivot rotated so the cylinder's +Y axis points backward (+Z). Scaling the
	# pivot's Y stretches the plume while keeping the wide nozzle anchored here.
	var pivot := Node3D.new()
	pivot.position = mount
	pivot.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	_mesh_root.add_child(pivot)

	# Rough-metallic engine bell the plume emerges from (ring ships only). Extends
	# BACKWARD past the hull (+Y in pivot space = +Z = tail) so the nozzle reads as a
	# real engine housing — especially the central main booster, whose nozzle would
	# otherwise sit buried inside the hull with its ring hidden.
	if _booster_ring:
		var bell := MeshInstance3D.new()
		var bmesh := CylinderMesh.new()
		bmesh.top_radius = radius * 1.5       # wide opening at the back
		bmesh.bottom_radius = radius * 1.1    # narrows toward the hull
		bmesh.height = radius * 1.8
		bmesh.radial_segments = 16
		bell.mesh = bmesh
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.03, 0.03, 0.04)   # deep black housing
		bmat.metallic = 0.7
		bmat.roughness = 0.5                           # subtle sheen, stays dark
		# Very faint floor so the black bell still reads as a solid shape, not a void.
		bmat.emission_enabled = true
		bmat.emission = Color(0.03, 0.03, 0.04)
		bmat.emission_energy_multiplier = 0.5
		bell.material_override = bmat
		bell.position = Vector3(0.0, bmesh.height * 0.42, 0.0)
		pivot.add_child(bell)

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
	# Only this holder is scaled to stretch the plume — the bell + ring stay fixed to
	# the hull (scaling the pivot itself used to drag them backward).
	var plume_holder := Node3D.new()
	pivot.add_child(plume_holder)
	var plume := MeshInstance3D.new()
	plume.mesh = cyl
	plume.material_override = plume_mat
	plume.position = Vector3(0.0, length * 0.5, 0.0)  # wide end sits at the pivot
	plume_holder.add_child(plume)

	# Optional glowing engine-ring framing the nozzle — a bit of design at the tail so
	# the hull isn't just a bare metal blob. Hole faces back (the pivot's 90° tilt).
	if _booster_ring:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 1.5    # frames the bell's wide back opening
		torus.outer_radius = radius * 1.95
		torus.rings = 24
		torus.ring_segments = 10
		ring.mesh = torus
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(0.0, 0.0, 0.0, 0.95)   # deep opaque black rim
		ring.material_override = rmat
		# Sit at the bell's mouth (the visible nozzle exit), not the buried pivot origin.
		ring.position = Vector3(0.0, radius * 1.8 * 0.92, 0.0)
		pivot.add_child(ring)

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
		"plume_holder": plume_holder,
		"plume_mat": plume_mat,
		"core": core,
		"core_mat": core_mat,
	}


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
