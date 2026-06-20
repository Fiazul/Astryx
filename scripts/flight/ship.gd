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
	{ "name": "Lyra",   "path": "res://assets/lyra.obj",   "tint": Color(1.0, 1.0, 1.0),    "length": 0.7, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 1.0,  "hp": 280, "bolt_scale": 1.8, "bolt_speed": 820.0,  "fire_cd": 0.22, "dmg": 3, "bolt_laser": true, "energy_max": 130.0, "energy_use": 0.85, "warp": 71.9, "pbr": true,
		"surf_roles": ["glass", "red", "red", "goldtrim", "goldtrim"],
		# Hangar dye: body = the red surfaces, WING/accent = the gold-trim surfaces (canopy glass
		# stays glass). Defaults keep her authored red-+-gold look.
		"color_pick": true, "body_role": "red", "wing_role": "goldtrim",
		"default_color": "burgundy", "default_wing": "champagne",
		"light_accent": Color(1.0, 0.86, 0.84), "light_energy": 0.85 },
	# Stella's GLB is ONE fused mesh that reads a tiny "atlas" palette: grey/black body +
	# two magenta accent swatches (no separate parts). swatch_split lists the model's five
	# swatch U-centres; swatch_accent marks the two magenta ones. split_by_swatch carves the
	# mesh into surface 0 = body, surface 1 = accent, then the color_pick/pbr path dyes them
	# independently (BODY COLOUR + WING COLOUR swatches + metallic/glassy finish in the hangar).
	{ "name": "Stella", "path": "res://assets/Spaceship.glb",     "tint": Color(0.70, 0.62, 0.95), "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.92, "hp": 80, "bolt_scale": 1.1, "bolt_speed": 1700.0, "fire_cd": 0.04, "dmg": 1, "energy_max": 100.0, "energy_use": 0.5, "warp": 71.9, "pbr": true,
		"swatch_split": [0.015, 0.045, 0.077, 0.108, 0.140], "swatch_accent": [0.015, 0.108],
		"surf_roles": ["sbody", "saccent"], "color_pick": true, "body_role": "sbody", "wing_surfs": [1],
		"default_color": "onyx", "default_wing": "burgundy",
		"light_accent": Color(0.80, 0.86, 1.00), "light_energy": 0.7 },
	{ "name": "Raptor", "path": "res://assets/Spaceship (2).glb", "tint": Color(0.70, 0.90, 0.95), "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.82, "hp": 170, "bolt_scale": 1.15, "bolt_speed": 1050.0, "fire_cd": 0.10, "dual": true, "dmg": 2, "energy_max": 170.0, "energy_use": 0.55, "warp": 125.0 },
	# Vela: a fast FTL ship (~29 s/ly cruise). Her drive spools up over time
	# (see WARP_CHARGE_*), so she eases into warp rather than snapping to it.
	# "brake": her ultimate — hold R to ease to a full stop (she's so fast that stopping
	# at a star is otherwise brutal; the air-brake makes her usable). Squishy hull.
	# Vela's GLB has 3 surfaces: 0 = nose/antenna trim, 1 = red accent (WING), 2 = grey body (main
	# hull). Surfaces 0 AND 2 both dye with the BODY colour (so the nose antenna recolours too,
	# instead of staying black); surface 1 dyes with the WING/accent colour.
	{ "name": "Vela",   "path": "res://assets/Spaceship (3).glb", "tint": Color(0.55, 0.80, 1.0),  "length": 0.55, "yaw": 180.0, "pitch": 0.0, "glow": 0.0, "energy_max": 100.0, "energy_use": 1.2, "warp": 99.1, "engine_pitch": 1.14, "brake": true, "hp": 90, "bolt_scale": 1.1, "bolt_speed": 1050.0, "fire_cd": 0.06, "dmg": 2, "pbr": true,
		"surf_roles": ["vbody", "vred", "vbody"], "color_pick": true, "body_role": "vbody", "wing_surfs": [1],
		"default_color": "graphite", "default_wing": "burgundy",
		"light_accent": Color(0.72, 0.85, 1.0), "light_energy": 0.8 },
	# Vela Iron Pulse — a UTILITY + SPEED hull: no weapons (can_fire false — you just pick her
	# and drive). She carries the GALACTIC DRIVE (0.08 s/ly ≈ 12.5 ly/s): the only hull that can
	# make the ~34-min haul to the Milky Way's core. In local space she obeys the same slow-zone
	# speed cap as every ship; only out in interstellar deep space does she open up to the fastest
	# drive in the game. She also runs a live CORE-DISTANCE SCANNER (core_total_ly / core_dist_ly),
	# so the HUD always reads how far the core is and how far remains.
	# Model: "jl 7 low" by ztrztr (CC-BY 4.0, see CREDITS.md) — one untextured surface, so the
	# WHOLE hull dyes as the body colour (surf_roles ["body"] + body_role "body", pbr path). The
	# model's long axis is X, so yaw 90 points the nose down -Z. Twin boosters at her tail (see
	# BOOSTER_LAYOUTS / BOOSTER_BACK_OVERRIDE / *_SCALE entries below).
	{ "name": "Vela Iron Pulse", "path": "res://assets/jl_7_low.glb", "tint": Color(0.48, 0.66, 0.92), "length": 0.6, "yaw": 90.0, "pitch": 0.0, "glow": 0.0, "energy_max": 100.0, "energy_use": 1.2, "warp": 150.0, "engine_pitch": 1.14, "brake": true, "hp": 90, "pbr": true, "galactic_drive": true, "can_fire": false,
		"surf_roles": ["body"], "color_pick": true, "body_role": "body",
		"default_color": "graphite",
		"light_accent": Color(0.72, 0.85, 1.0), "light_energy": 0.8 },
	# HaniStar — a slow, pretty support hull that CAN fight: fires a touch faster than
	# Lyra, hits a bit harder than Stella, 125 HP. Three light-blue boosters.
	# surf_roles indexes the GLB's 9 surfaces: gold = shiny rose-gold (7 = wings), glass =
	# top-front canopy (3), orb = soft neon-pink accents, hull = pink crystal body.
	# (4 = the two upright tail fins, kept pink hull.)
	{ "name": "HaniStar",   "path": "res://assets/utility_ship.glb",  "tint": Color(1.0, 0.412, 0.706), "length": 0.6,  "yaw": 90.0, "pitch": 0.0, "glow": 0.06, "energy_max": 120.0, "energy_use": 0.95, "warp": 71.9, "engine_pitch": 0.7, "light_energy": 0.45, "hp": 200, "fire_cd": 0.14, "dmg": 3, "bolt_scale": 0.95, "bolt_speed": 1500.0, "bolt_strong": true, "pbr": true,
		"surf_roles": ["hull", "hull", "gold", "glass", "hull", "hull", "hull", "gold", "hull"],
		# Same hangar feature as HaniNebula: pick body + wing colours independently. Surface map
		# (verified by rendering each surface a distinct colour): body = the "hull" surfaces,
		# front glass = surf 3 (canopy), WINGS = surf 4 — the big swept panels that spread wide
		# in plan and rise at the rear. surf 2 = silver-alloy accent.
		# Defaults keep her stock look: blush-pink body, silver ("gold" palette) wings.
		"color_pick": true, "body_role": "hull", "wing_surfs": [4], "default_color": "blush", "default_wing": "gold" },
	# Raptor 2 Neo ("mother ship"): the powerhouse — Stella's fire rate, Vela's top speed,
	# Lyra's damage, HaniStar's hull. Silver-blue metal body + glass illuminators.
	{ "name": "Raptor 2 Neo", "path": "res://assets/raptor2.obj", "tint": Color(1, 1, 1), "length": 0.65, "yaw": 0.0, "pitch": 0.0, "glow": 0.0, "engine_pitch": 0.7, "hp": 200, "bolt_scale": 1.3, "bolt_speed": 1700.0, "fire_cd": 0.06, "dmg": 3, "energy_max": 150.0, "energy_use": 0.7, "warp": 119.8, "pbr": true, "laser": true, "auto_capture": true,
		"laser_offset": Vector3(0.0, -0.03, -0.10),   # beam emitter point (slightly down)
		# The OBJ has exactly 2 surfaces: 0 = "Mat" (the whole hull), 1 = "iluminators" (the
		# glowing window strips). So the HULL is the solid metal body colour (picker recolours
		# it via body_role "silver"), and only the small illuminators are the glass windows.
		"surf_roles": ["silver", "glass"], "color_pick": true, "body_role": "silver", "default_color": "silver",
		"light_accent": Color(0.82, 0.90, 1.0), "light_energy": 0.8 },
	# HaniNebula — HaniStar's evolved "pro" form: metallic silver + slight pink, modern/
	# feminine, super powerful (combat tuned to Raptor 2 Neo). Booster cluster: big main
	# pair + smaller side subs + tiny top trio (see BOOSTER_LAYOUTS).
	{ "name": "HaniNebula", "path": "res://assets/haninebula.obj", "tint": Color(0.86, 0.83, 0.90), "length": 0.85, "yaw": 0.0, "pitch": 0.0, "glow": 0.05, "engine_pitch": 0.7, "hp": 200, "bolt_scale": 0.95, "bolt_speed": 1700.0, "fire_cd": 0.06, "dmg": 3, "bolt_strong": true, "energy_max": 150.0, "energy_use": 0.7, "warp": 125.0, "pbr": true,
		# Player-pickable colours (hangar swatches). Whole hull = the chosen body colour on
		# every surface EXCEPT index 20 = wings (Wigns_Plane.001) = the chosen wing colour.
		# The OBJ splits into 23 per-usemtl surfaces; wings land at surface 20. See SHIP_PALETTES.
		"color_pick": true, "wing_surf": 20, "default_color": "rosegold", "default_wing": "gold", "light_energy": 0.95 },
	# Vortex retired as a player ship — it's a boss enemy now (see combat.gd boss).
]
# Body-colour palettes the player picks in the hangar (ships flagged "color_pick").
# key = a metallic role in ShipMesh.recolor; accent = the hull-light tint that flatters it.
const SHIP_PALETTES := [
	{ "key": "rosegold", "name": "Rose Gold", "swatch": Color(0.86, 0.58, 0.52), "accent": Color(1.00, 0.88, 0.82) },
	{ "key": "blush",    "name": "Blush",     "swatch": Color(0.96, 0.74, 0.76), "accent": Color(1.00, 0.86, 0.88) },
	{ "key": "navy",     "name": "Navy",      "swatch": Color(0.16, 0.26, 0.62), "accent": Color(0.72, 0.84, 1.00) },
	{ "key": "teal",     "name": "Teal",      "swatch": Color(0.10, 0.66, 0.66), "accent": Color(0.72, 1.00, 0.98) },
	{ "key": "charcoal", "name": "Charcoal",  "swatch": Color(0.16, 0.16, 0.18), "accent": Color(0.85, 0.90, 1.00) },
	{ "key": "emerald",  "name": "Emerald",   "swatch": Color(0.06, 0.52, 0.26), "accent": Color(0.80, 1.00, 0.86) },
	{ "key": "burgundy", "name": "Burgundy",  "swatch": Color(0.52, 0.09, 0.19), "accent": Color(1.00, 0.84, 0.84) },
	{ "key": "silver",   "name": "Steel Blue","swatch": Color(0.42, 0.60, 0.95), "accent": Color(0.72, 0.85, 1.00) },
	{ "key": "gold",     "name": "Silver",    "swatch": Color(0.82, 0.84, 0.88), "accent": Color(0.90, 0.93, 1.00) },
	{ "key": "champagne","name": "Champagne Gold", "swatch": Color(0.83, 0.69, 0.42), "accent": Color(1.00, 0.94, 0.78) },
	{ "key": "ash",      "name": "Silver Ash",  "swatch": Color(0.74, 0.76, 0.80), "accent": Color(0.92, 0.95, 1.00) },
	{ "key": "graphite", "name": "Graphite",    "swatch": Color(0.30, 0.31, 0.34), "accent": Color(0.85, 0.90, 1.00) },
	{ "key": "onyx",     "name": "Onyx Black",  "swatch": Color(0.10, 0.10, 0.12), "accent": Color(0.80, 0.86, 1.00) },
]
var _color_choice := {}   # ship name -> { "body": key, "wing": key } (overrides default_color/default_wing)
var _bell_choice := {}    # ship name -> bool (booster engine bell on); default from BOOSTER_NO_RING
var _finish_choice := {}  # ship name -> "metallic" | "glassy" (glossy coat). Default metallic.
const BOOSTER_COLOR := Color(0.35, 0.8, 1.0)
# Booster nozzle placement (fractions of the fitted model's size). Nudge these
# to snap the plumes onto Lyra's actual engines.
const BOOSTER_BACK := 0.40          # how far back (0 = center, 0.5 = tail). Lower = closer to hull.
# Per-ship override of BOOSTER_BACK (fraction back toward the tail).
const BOOSTER_BACK_OVERRIDE := { "Vela Iron Pulse": 0.46 }   # push her plumes right to the tail
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
		Vector2(-0.08,  0.00),   # left
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
	"Vela Iron Pulse": [
		# Twin thrusters at her tail with a clear gap between them (her two rear nozzles),
		# nudged down to line up with the exhaust ports.
		Vector2(-0.13, -0.10),
		Vector2( 0.13, -0.10),
	],
	"HaniNebula": [
		# 2 big top-side mains (Reactor_Cylinder), highest up
		Vector2(-0.074, 0.107), Vector2( 0.074, 0.107),
		# 4 bottom thrusters (Reactor.001), furthest back
		Vector2( 0.025, 0.019), Vector2(-0.074, 0.019), Vector2(-0.025, 0.019), Vector2( 0.074, 0.019),
		# 5 tiny top-sublayer (top row, Reactor.002)
		Vector2(-0.021, 0.127), Vector2( 0.021, 0.127), Vector2( 0.000, 0.127), Vector2(-0.042, 0.126), Vector2( 0.042, 0.126),
		# 5 tiny top-sublayer (lower row, Reactor.003)
		Vector2(-0.042, 0.089), Vector2( 0.042, 0.089), Vector2(-0.021, 0.088), Vector2( 0.021, 0.088), Vector2( 0.000, 0.088),
	],
}
const BOOSTER_FALLBACK := [Vector2(-0.08, 0.0), Vector2(0.08, 0.0)]  # if a name isn't listed
# Per-ship plume shaping. Raptor: long/thin/small. Vela: long, thin, golden.
const BOOSTER_RADIUS_SCALE := { "Lyra": 0.9, "Raptor": 0.62, "Vela": 0.45, "Vela Iron Pulse": 0.34, "Stella": 0.40, "HaniStar": 0.6, "Raptor 2 Neo": 0.6, "HaniNebula": 0.82 }   # thinner = sharper flame
const BOOSTER_LENGTH_SCALE := { "Raptor": 1.0, "Vela": 1.4, "Vela Iron Pulse": 0.95, "Stella": 0.8, "Lyra": 0.8, "HaniStar": 0.9, "Raptor 2 Neo": 1.3, "HaniNebula": 1 }  # long, dramatic near-ship-length trails
const BOOSTER_COLOR_OVERRIDE := {
	"HaniStar": Color(0.62, 0.82, 1.0),    # very light blue exhaust
	"HaniNebula": Color(0.925, 0.612, 0.894, 0.851),  # soft pink exhaust (matches her silver+pink look)
	"Lyra": Color(0.55, 0.90, 1.0),    # pretty bright aqua-cyan
	"Raptor 2 Neo": Color(0.35, 0.65, 1.0),  # strong electric blue
	"Vela": Color(1.0, 0.82, 0.32),    # transparent gold
	"Vela Iron Pulse": Color(0.66, 0.10, 1.0),  # pure burning purple (hot white-violet core)
	"Stella": Color(1.0, 0.26, 0.20),  # sharp transparent red
	"Raptor": Color(0.85, 0.72, 0.45), # champagne gold (small + powerful; deploys in warp)
}
const BOOSTER_FADE_FLIP := false    # if the plume fades at the wrong end, flip this
# Hulls that skip the metal bell + nozzle ring (their model already has real nozzles, so we
# just drop a bare fire plume into each existing hole).
const BOOSTER_NO_RING := { "HaniNebula": true, "HaniStar": true, "Vela Iron Pulse": true }
# Hulls whose thrusters trail SMOKE behind the flame (a dark exhaust haze). Off for everyone
# except where listed. Vela Iron Pulse: burning-purple jet + a purple-grey smoke trail.
const BOOSTER_SMOKE := { "Vela Iron Pulse": true }
# Per-mount size multipliers (same order as BOOSTER_LAYOUTS). HaniStar: big main + smaller supports.
const BOOSTER_MOUNT_SCALE := { "HaniStar": [1.3, 0.65, 0.65],
	# Sized to each hole's real radius: 2 big mains, 4 bottom, then 10 tiny sub-layer holes.
	"HaniNebula": [0.45, 0.45,  0.40, 0.40, 0.40, 0.40,  0.17, 0.17, 0.17, 0.17, 0.17,  0.17, 0.17, 0.17, 0.17, 0.17] }
# Per-mount extra BACK offset (fraction of hull length) to push a nozzle clear of the
# hull when a rear plate blocks it. HaniStar's main sits behind a rear plate.
const BOOSTER_MOUNT_BACK := { "HaniStar": [0.08, 0.0, 0.0],
	"Raptor 2 Neo": [-0.08, -0.08, 0.0, 0.0],   # push the upper pair forward
	# Real rear-opening depth of each hole group: mains/sublayers at -0.08, bottom 4 at +0.10.
	"HaniNebula": [-0.080, -0.080,  0.100, 0.100, 0.100, 0.100,  -0.081, -0.081, -0.081, -0.081, -0.081,  -0.081, -0.081, -0.081, -0.081, -0.081] }
# Camera zoom (mouse wheel)
const ZOOM_MIN := 0.2               # closest
const ZOOM_MAX := 6.0               # farthest
const ZOOM_STEP := 0.12             # per wheel notch
# =================================================================

# --- Flight tuning ---
# Heavier hull: lower THRUST + lower DAMPING means the ship carries its momentum and
# banks into wide, curving turns instead of snapping direction (no more jig-jag).
# Cruise speed stays ~THRUST/DAMPING (≈220), but acceleration and turn-out are gentler.
const THRUST := 1650.0        # forward/back accel (units/s^2) — ×10 for the spread-out system
const STRAFE_THRUST := 1050.0 # lateral / vertical accel
const BOOST_MULT := 3.0       # Shift multiplier
const BOOST_DRAIN := 5.0      # boost energy/sec burned while boosting — very efficient, so a full
							  # tank lasts a long time and tops back up fast (combat owns the pool)
const MAX_SPEED := 10000.0
# Calm in-system cruise: sublight (non-warp) flight is capped here so you're not
# blitzing past the planets near Sol. Boost (Shift) multiplies it for fast travel.
# This is SEPARATE from warp — the per-ship ly tops are unaffected.
const SUBLIGHT_MAX := 550.0
const GRAVITY_IDLE_SPEED := 50.0   # below this, an un-thrusting ship is released from gravity (no idle drift)
# Weapons speed-lock: you can only fire at regular (sublight) speed. Holding fire force-caps
# the ship to this, so opening fire while warping/boosting drops you to combat speed.
const WEAPON_FIRE_SPEED := SUBLIGHT_MAX
# Auto-settle: close to a body, gently bleed speed toward a hover so releasing thrust
# holds you on station to capture (thrust still lets you nudge/orbit). Closer = stronger.
const SETTLE_RANGE := 900.0
const SETTLE_RATE := 1.5
# Damping vs thrust sets the real cruise speed (~THRUST/DAMPING here) — MAX_SPEED is
# just a ceiling. Lower DAMPING = more glide/momentum (the "heavy" feel).
const DAMPING := 0.75         # higher = eases to a stop faster when idle (WARP cruise tuning)
# Sublight drift: a much lighter damping used at non-warp speeds so the ship GLIDES — it
# carries momentum through turns and coasts when you ease off, instead of braking itself.
# Sublight top speed is capped (SUBLIGHT_MAX) regardless, so this only adds drift, not
# speed. At warp we blend back to DAMPING so FTL travel times stay tuned.
const DRIFT_DAMPING := 0.32
const BRAKE_RATE := 3.0       # Vela's air-brake (R): eases velocity to ~0 over ~1.5s
const STEER_SMOOTH := 9.0     # mouse-steer inertia: lower = heavier, more turn coast
const STRAFE_SMOOTH := 5.0    # A/D & up/down (strafe/lift) input inertia: lower = heavier
const MOUSE_SENS := 0.0022    # default; runtime value lives in `mouse_sens` (Settings menu)
# --- Continuous "follow-up" steering: mouse motion winds a PERSISTENT turn rate that keeps the
# ship rotating after you stop moving your hand (no rotating-forever fatigue). Move the same way
# = faster; move opposite = smoothly winds down THROUGH centre and reverses (no sticky middle —
# we deliberately do NOT snap to zero). Idle jitter under the dead zone is ignored.
const MOUSE_DEADZONE := 0.6   # px/frame below this = idle jitter, ignored (so a still hand holds the turn)
const RATE_ACCEL := 3.4       # how fast mouse motion winds the turn-rate up (× mouse_sens). Higher =
							  # the auto-rotate engages in a quick move instead of a long hold
const MAX_YAW_RATE := 3.2     # top yaw turn speed (rad/s) — higher = big turns need much less mouse
							  # sweep (fine aim is unaffected: small moves never reach the cap)
const MAX_PITCH_RATE := 2.6   # top pitch turn speed (rad/s)
const PITCH_LEVEL := 3.0      # pitch self-levels to 0 when idle (so the nose settles, never backflips)
const REVERSE_BOOST := 2.6    # (A/D keyboard) opposing the current spin winds it down this much faster
const REVERSE_BRAKE := 6.0    # mouse opposing the spin brakes it toward 0 this fast (rad/s²) — makes
							  # reversing IMMEDIATE even with a gentle move (kills full spin in ~0.27s)
const YAW_LEVEL := 2.0        # when the mouse goes idle the yaw rate COASTS to 0 this fast — the turn
							  # carries a moment (heavy-ship follow-through) then settles, so it never
							  # spins forever. Higher = stops sooner/snappier; lower = longer coast.
const YAW_KEY_RATE := 0.6     # A/D also steer the yaw from the keyboard: they INTERRUPT the mouse
							  # auto-rotate and drive the turn this fast (rad/s²) so you can break a
							  # spin and change direction with a key (they still strafe too).
const ROLL_RATE := 1.8        # manual Q/E roll (rad/s)
const FLIP_TIME := 3.4        # cinematic drift-flip duration — long & SLOW, a heavy lazy roll (W+C)
const FLIP_CRUISE := 340.0    # steady glide speed DURING the flip so it travels across space
const FLIP_SWERVE := 4.2      # peak yaw-rate of the wavey curve the glide carves (rad/s)
const FLIP_EASE := 2.2        # how gently the glide blends in/out (lower = more seamless)
const FLIP_LEAP_BOOST := 0.9  # extra speed at the START of the flip → a quick LEAP that punches
							  # out of slow-zones (the flip also BYPASSES the body speed cap)

# Warp arrival: a warp ship eases out of warp as it falls toward the nearest mark, so
# it arrives instead of blasting past (and the star has time to bloom into a sphere).
const WARP_ARRIVE_TIME := 2.0      # seconds-to-arrival at which warp starts easing out
const WARP_ARRIVE_SPEED := 400.0   # gentle speed warp bleeds down to (slow enough to scan)
const BANK_ANGLE := 0.8       # max cosmetic bank into turns (rad ≈ 46°) — a clear, visible roll
const BANK_GAIN := 0.7        # bank per unit yaw-RATE (rad/s); full bank ≈ at MAX_YAW_RATE
const BANK_SMOOTH := 5.0
# Cosmetic nose-lean into vertical mouse: a big ship doesn't snap up/down, it tips its nose
# and the whole hull leans into the climb/dive. Pure mesh tilt (heading/aim untouched), eased
# in slowly so it reads as mass, not a flick.
const LEAN_PITCH := 0.5       # max nose-lean into a climb/dive (rad ≈ 29°)
const LEAN_PITCH_GAIN := 0.6  # lean per unit pitch-RATE (rad/s)
const LEAN_SMOOTH := 4.0      # lower = heavier/slower lean (the big-ship weight)
# Cinematic cruise sway: after holding a straight line for SWAY_DELAY seconds the hull
# starts a slow, gentle roll left↔right (cosmetic, on the mesh only — the actual heading
# never changes, so you stay on the same line). Steering resets it instantly.
const SWAY_DELAY := 3.0       # seconds of straight cruise before the sway eases in
const SWAY_RAMP := 2.0        # seconds to ramp the sway from 0 → full once it begins
const SWAY_ANGLE := 0.11      # peak roll of the sway (rad ≈ 6.3°) — subtle, not a wobble
# How much the gun muzzle follows the COSMETIC bank. 0 = the bullet start point is LOCKED to
# the nose centreline and never swings left/right when you strafe/bank with A/D. (Real
# rotation — mouse aim, Q/E roll — still moves it, since that lives in transform.basis.)
const MUZZLE_BANK_FOLLOW := 0.0
const CAM_OFFSET := Vector3(0.0, 0.33, 1.0)  # behind (+Z) and above the ship; the higher Y
											 # drops the hull lower in frame → a bigger gap
											 # between the ship's nose and the centre crosshair
# Orbit the whole camera rig this many degrees so you view the ship from slightly BELOW (a low,
# heroic angle that shows a bit of the belly). + = bottom view (look up), - = top view (look down).
# Rig position + aim rotate together, so the ship stays framed where it is — only the angle shifts.
const CAM_VIEW_PITCH_DEG := 0.0
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
@onready var audio := GameAudio   # autoload; the engine voice is driven from fly()
var mouse_sens := MOUSE_SENS   # live mouse sensitivity (Settings menu adjusts this)
var warp := 1.0                # per-ship MAX speed multiplier; >1 = breaks physics (Vela)
var has_galactic_drive := false  # this hull can run the galactic drive (Vela Iron Pulse)
# Live core-distance scanner (only meaningful on the Iron Pulse). main feeds these from the
# GalaxyModel each frame so the HUD can read total + remaining distance to the core in real time.
var core_total_ly := 0.0       # full distance of the voyage (≈ 26,000 ly)
var core_dist_ly := 0.0        # distance still to go right now (shrinks as you fly the drive)
var _warp_charge := 0.0        # 0..1 spool-up; ramps while thrusting forward
var fire_cooldown := 0.22      # seconds between shots (combat reads this)
var max_hp := 100              # this hull's defence / hull integrity (combat reads this)
var bolt_speed := 950.0        # this hull's bullet velocity (combat reads this)
var bolt_scale := 1.0          # this hull's bullet size multiplier (combat reads this)
var bolt_damage := 1           # damage per bolt (combat reads this) — Lyra's hit hard
var bolt_laser := false        # bolts render as red laser beams (Lyra) — combat reads this
var bolt_strong := false       # extra-bright/strong bolt material (HaniStar) — combat reads this
var energy_max := 100.0        # per-ship energy cap (both bars); combat reads this
var energy_use := 1.0          # per-ship consume multiplier; combat + boost read this
var can_fire := true           # false for utility hulls (no weapons) — combat reads this
var has_laser := false         # right-click nose laser beam (Raptor 2 Neo) — combat reads this
var laser_offset := Vector3.ZERO   # local muzzle offset for the beam (x=right, y=up)
var auto_capture := false       # captures bodies in range automatically (no V) — Raptor 2 Neo
var combat_lock := false        # set by main while in combat — no interstellar/FTL speed
var firing := false             # set by main while holding fire — force-caps to combat speed
var touch_fire := false         # mobile: the on-screen FIRE button (NOT the emulated mouse, which
								# every touch would otherwise trigger) — main reads this on touch builds
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
var _raptor_warp_form := false # Raptor: true while in the Warp(X) form (else Combat form)
# Warp multiplies cruise speed. The REAL top speed is the terminal velocity THRUST·warp/DAMPING
# (the cap = MAX_SPEED·warp is just a ceiling and isn't reached) — so, with 1 ly = 6.32M units,
# time per ly ≈ UNITS_PER_LY·DAMPING / (THRUST·warp) = 2874.6 / warp seconds (W-cruise, no boost;
# Shift/auto-cruise boost ×3 is ~3× faster). Per-hull tuning (sec/ly): Raptor combat 23 · Raptor
# warp-form 30 · Raptor 2 Neo 24 · HaniNebula 23 · Vela 29 · Lyra/Stella/HaniStar 40.
const RAPTOR_WARP := 95.8           # Raptor Warp (X) form — ~30s / ly
const RAPTOR_COMBAT_WARP := 125.0   # Raptor Combat form — ~23s / ly (faster than warp form, per design)
const HYPERSONIC_SPEED := 15000.0   # above this a warp ship is "hypersonic" (no combat)
const WARP_FLOOR := 1.0        # zero-charge = calm sublight; holding W spools up to warp
# FTL gate: warp can only spool up once you're beyond the system star's gravity field.
# Inside this radius you fly normal sublight cruise no matter the hull.
const SOL_FIELD_RADIUS := 2200.0
const WARP_CHARGE_TIME := 9.0  # seconds of thrust to reach full warp
const WARP_DECAY_TIME := 3.5   # seconds to spool back down when you ease off

# --- Galactic drive (Vela Iron Pulse only) ---
# The pilgrimage to the Milky Way's core (~26,000 ly). It is NOT a translation speed tier — flying
# the real distance at that speed shatters float precision and piles up across saves. Instead the
# galaxy backdrop LOOMS in toward the core at a fixed pace (galactic_loom_rate → main → galaxy),
# decoupled from how fast the ship actually moves. She still flies normal space at her own warp;
# this just advances the bounded voyage. Only while in deep space (warp_ready) and spooled up.
const GALACTIC_SEC_PER_LY := 0.08      # LOCKED voyage pace — the tuned 0.08 s/ly (do not drift)
const GALACTIC_LOOM_LY_PER_S := 1.0 / GALACTIC_SEC_PER_LY   # = 12.5 ly/s → ~26,000 ly in ~34.7 min
const GALACTIC_TEST_MULT := 10.0  # ⚠ TEST ONLY — set back to 1.0 before shipping. 10× the loom
								  # → core run in ~3.5 min instead of ~35, so the voyage is testable.

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

# In open/FTL deep space: every speed cap (body gravity zone, station/probe/wormhole
# slow-zone) is lifted. This is the "interstellar" signal the music state machine reads.
func in_open_space() -> bool:
	return is_inf(speed_limit) and is_inf(struct_limit)

# Raptor only: toggle between Combat mode (machine-gun, normal flight) and Warp
# mode (Vela-style FTL). Returns the new mode name for HUD feedback.
func toggle_warp_mode() -> String:
	if not _dual:
		return ""
	# Track the form with an explicit flag, not the warp magnitude — Combat is now FASTER
	# than the Warp form, so a magnitude test would no longer tell the two modes apart.
	_raptor_warp_form = not _raptor_warp_form
	if _raptor_warp_form:
		warp = RAPTOR_WARP          # Warp / FTL form
		_warp_charge = 0.0
		return "WARP"
	else:
		warp = RAPTOR_COMBAT_WARP   # back to Combat form
		return "COMBAT"

func is_warp_mode() -> bool:
	return _dual and warp > 1.0

# True while the galactic drive is carrying us — the drive hull, spooled up, in clear deep space.
# main uses it to loom the core; the HUD uses it for the drive readout; streaks use it for the blur.
func galactic_cruising() -> bool:
	return has_galactic_drive and warp_ready() and _warp_charge > 0.02

# Signed ly/s the galactic core looms this frame: the LOCKED voyage pace (0.08 s/ly × test mult),
# its sign set by whether she's heading toward the core (+ = approach) or away (− = recede). It is
# NOT scaled by spool/throttle — once she's cruising the drive, the pace is the locked 0.08 s/ly,
# full stop. DECOUPLED from her real translation speed, so the ~26,000 ly haul is a bounded illusion
# that never moves true_pos. main feeds this to galaxy.advance_ly each frame.
func galactic_loom_rate() -> float:
	if not galactic_cruising() or velocity.length() < 1.0:
		return 0.0
	var heading := signf(velocity.normalized().dot(GalaxyModel.DIR.normalized()))
	return GALACTIC_LOOM_LY_PER_S * GALACTIC_TEST_MULT * heading

# True only in Raptor's actual WARP form (not his combat mode) — drives the deployed,
# flared booster.
func is_warp_form() -> bool:
	return _dual and _raptor_warp_form

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
var _booster_smoke := false           # trail dark smoke behind the flame (Vela Iron Pulse)
var _plume_len_s := 0.6               # smoothed plume length (live flicker layered on top)
var _plume_a_s := 0.0                 # smoothed plume alpha
var _core_a_s := 0.0                  # smoothed core-glow alpha
# Booster TIER (4 levels): slow-zone L1 (base) / L2 (Shift — fatter+longer, clear gap),
# interstellar L3 (brighter/stronger) / L4 (+Shift — max). Each lever eases smoothly so
# crossing tiers swells the plume instead of popping. See _update_boosters().
var _tier_w_s := 1.0                  # smoothed plume WIDTH (radius) multiplier
var _tier_len_s := 1.0                # smoothed plume LENGTH multiplier
var _tier_bright_s := 1.0             # smoothed plume BRIGHTNESS multiplier
var _tier_hot_s := 0.0                # smoothed hot/white shift (interstellar L3/L4)
var _streaks: GPUParticles3D          # motion streaks at high speed
var _streak_mat: StandardMaterial3D
var _cam_zoom := 1.0          # target zoom (mouse wheel)
var _cam_zoom_smooth := 1.0   # eased toward _cam_zoom
var _cam_basis := Basis()
var _bank := 0.0
var _lean := 0.0              # eased cosmetic nose-lean into a climb/dive (mesh-only)
var _flip_t := 0.0            # remaining cinematic flip time (0 = not flipping)
var _flip_dir := 1.0          # +1 roll/drift right · -1 left
var _flip_yaw := 0.0          # accumulated swerve of the drift heading during the flip
var _cruise_t := 0.0           # seconds held on a straight cruise (drives the cinematic sway)
var _mouse_delta := Vector2.ZERO
var _steer := Vector2.ZERO     # eased mouse-steer (rotational inertia for curving turns)
var _yaw_rate := 0.0           # yaw turn-rate (rad/s) — eases to 0 when the mouse is idle (heading-hold)
var _pitch_rate := 0.0         # pitch turn-rate (rad/s) — self-levels to 0 when the mouse is idle
var _strafe := 0.0             # eased A/D lateral input (heavy, drifting thrust)
var _lift := 0.0              # eased Space/Ctrl vertical input
var _mouse_captured := false
var _free_look := false       # true while RMB or T is held
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

# Touch look: the on-screen drag region feeds steering here (same pipeline as mouse-look,
# but with no mouse capture, which phones don't have). Called by TouchControls.
func add_touch_look(v: Vector2) -> void:
	_mouse_delta += v


# Called every frame by main.gd, before the world is rebuilt around the ship.
func fly(delta: float) -> void:
	# Wormhole transit: motion held, view locked forward, streaks at full tilt.
	if transiting:
		velocity = Vector3.ZERO
		_mouse_delta = Vector2.ZERO
		_steer = Vector2.ZERO
		_strafe = 0.0
		_lift = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_bank = 0.0
		_lean = 0.0
		# Face the nose INTO the tunnel (the tunnel renders ahead at local -Z). Flip 180°
		# so the ship dives forward instead of riding through tail-first. The hull holds
		# STABLE facing the portal — only a faint breathing roll/pitch so it isn't dead
		# (yaw stays exactly PI so the nose points dead-on). (Reset to 0 on normal path.)
		var wob := Time.get_ticks_msec() * 0.001
		_mesh_root.rotation = Vector3(
			sin(wob * 0.7) * 0.012, PI, sin(wob * 0.5) * 0.018)
		_update_boosters(0.4, delta)            # engines low — calm, not hypersonic
		_update_streaks(SUBLIGHT_MAX * 0.7)     # restrained streaks — dark, not warp-busy
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
		_strafe = 0.0
		_lift = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_bank = 0.0
		_lean = 0.0
		_mesh_root.rotate_y(DOCK_SPIN * delta)
		_update_boosters(0.0, delta)
		_update_streaks(0.0)   # docked — no motion streaks
		_update_camera(delta)
		if audio:
			audio.engine_off()   # engine cut while docked
		return

	# --- Look vs. steer ---
	# HOLD RMB or T for free-look: the mouse orbits the camera (full 360°) around the ship
	# while it keeps flying. Release to steer normally again.
	# (On laser ships RMB fires the nose beam instead, so free-look there is T-only.)
	_free_look = (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not has_laser) \
		or Input.is_physical_key_pressed(KEY_T)
	var md := _mouse_delta
	_mouse_delta = Vector2.ZERO
	var turn := 0.0   # this frame's mouse yaw (drives cosmetic banking below)
	var lean := 0.0   # this frame's mouse pitch (drives the cosmetic nose-lean below)

	if autopilot:
		_autopilot_steer(delta)
		_steer = Vector2.ZERO
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_look_yaw = 0.0
		_look_pitch = 0.0
	elif _free_look:
		_steer = Vector2.ZERO
		_yaw_rate = 0.0
		_pitch_rate = 0.0
		_look_yaw -= md.x * mouse_sens
		_look_pitch = clampf(_look_pitch - md.y * mouse_sens, -LOOK_PITCH_LIMIT, LOOK_PITCH_LIMIT)
	else:
		# Heading steering with inertia: mouse motion winds a turn rate (so it has weight and curves),
		# but when you STOP moving, the rate eases back to 0 — the ship SETTLES on its heading instead
		# of spinning forever. So you can fix a direction; a stray nudge just nudges, it can't lock a
		# runaway spin. Reversing brakes hard so flipping direction is immediate. Idle jitter ignored.
		if absf(md.x) > MOUSE_DEADZONE:
			if _yaw_rate * md.x < 0.0:
				_yaw_rate = move_toward(_yaw_rate, 0.0, REVERSE_BRAKE * delta)
			_yaw_rate = clampf(_yaw_rate + md.x * mouse_sens * RATE_ACCEL, -MAX_YAW_RATE, MAX_YAW_RATE)
		else:
			# Mouse idle → settle: ease the turn rate to 0 so the ship holds its heading.
			_yaw_rate = lerpf(_yaw_rate, 0.0, clampf(YAW_LEVEL * delta, 0.0, 1.0))
		# A/D INTERRUPT the auto-rotate and steer the yaw directly — break a spin and change
		# direction from the keyboard. Opposing the current spin winds it down/reverses faster.
		var kyaw := 0.0
		if Input.is_physical_key_pressed(KEY_A):
			kyaw -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			kyaw += 1.0
		if kyaw != 0.0:
			var kax := YAW_KEY_RATE * (REVERSE_BOOST if _yaw_rate * kyaw < 0.0 else 1.0)
			_yaw_rate = clampf(_yaw_rate + kyaw * kax * delta, -MAX_YAW_RATE, MAX_YAW_RATE)
		if absf(md.y) > MOUSE_DEADZONE:
			_pitch_rate = clampf(_pitch_rate + md.y * mouse_sens * RATE_ACCEL, -MAX_PITCH_RATE, MAX_PITCH_RATE)
		else:
			_pitch_rate = lerpf(_pitch_rate, 0.0, clampf(PITCH_LEVEL * delta, 0.0, 1.0))
		turn = _yaw_rate     # banking reads the turn RATE (rad/s) so the bank holds with the turn
		lean = _pitch_rate
		rotate_object_local(Vector3.UP, -_yaw_rate * delta)
		rotate_object_local(Vector3.RIGHT, -_pitch_rate * delta)
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
	# Every hull (the Iron Pulse included) translates at its OWN warp here — fast, but a sane,
	# bounded coordinate rate. Her dramatic galactic SPEED is not a translation tier; it's the
	# core-voyage looming (see galactic_loom_rate + main), which is decoupled from true_pos so the
	# ~26,000 ly haul can never balloon the floating-origin coordinate the way it used to.
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

	# Heavy lateral/vertical control: ease the A/D and Space/Ctrl inputs so they ramp into
	# thrust and coast out of it (a weighty, drifting feel) instead of snapping on/off.
	# Forward/back (W/S) stays responsive — only the sideways/vertical axes are weighted.
	var sk := clampf(STRAFE_SMOOTH * delta, 0.0, 1.0)
	_strafe = lerpf(_strafe, strafe, sk)
	_lift = lerpf(_lift, lift, sk)
	var local_accel := Vector3(_strafe * STRAFE_THRUST, _lift * STRAFE_THRUST, fwd * THRUST) * eff_warp
	if local_accel.length_squared() > 0.0001:
		velocity += (transform.basis * local_accel) * boost * delta

	# Gravitational tug toward nearby bodies. It draws you in and helps you settle to land,
	# but must NEVER trap you. Two safeguards:
	#  • IDLE RELEASE — a parked, slow ship (no thrust) is let go entirely, so gravity can't
	#    balance damping into a permanent ~30 u/s drift toward the star while you sit still.
	#  • OUTWARD FADE — thrusting away from the pull fades it out (gone when straight out).
	var g := gravity
	var g_thrusting := local_accel.length_squared() > 0.0001
	if not g_thrusting and velocity.length() < GRAVITY_IDLE_SPEED:
		g = Vector3.ZERO                        # idle + slow → released; you settle to a stop
	elif g.length() > 0.01 and g_thrusting:
		var thrust_dir := (transform.basis * local_accel).normalized()
		var outward := -g.normalized()
		var align := thrust_dir.dot(outward)   # 1 = thrusting straight out, -1 = straight in
		if align > 0.0:
			g *= (1.0 - align)                  # fade the pull as you head outward
	velocity += g * delta

	# Damping: velocity eases toward zero when you're not thrusting. Sublight uses the
	# light DRIFT_DAMPING so the ship glides and carries momentum through turns; as warp
	# spools up we blend back to the heavier DAMPING that the FTL travel speeds are tuned
	# around, so deep-space cruise times are unchanged.
	var damp := DRIFT_DAMPING
	if eff_warp > 1.0:
		damp = lerpf(DRIFT_DAMPING, DAMPING, smoothstep(1.0, 2.0, eff_warp))
	velocity = velocity.lerp(Vector3.ZERO, clampf(damp * delta, 0.0, 1.0))
	# Auto-settle near a body: a soft brake that strengthens as you close in, so EASING OFF the
	# throttle lets you hover and capture instead of drifting past. Only while coasting, though —
	# holding thrust pushes you right in (and through), so a body never freezes you in place.
	if nearest_dist < SETTLE_RANGE and not braking and not g_thrusting:
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
	# Weapons lock: while you hold fire you're pulled down to regular combat speed — you
	# can't shoot above it, so opening fire itself slows the ship out of warp/boost.
	if firing:
		cap = minf(cap, WEAPON_FIRE_SPEED)
	# Bleed warp charge when something is force-slowing us, so the drive visibly drops
	# out of warp as you settle near a body/station (or open fire) instead of pinning at full spool.
	if (speed_limit < INF or struct_limit < INF or firing) and cap < MAX_SPEED:
		_warp_charge = minf(_warp_charge, cap / maxf(MAX_SPEED, 1.0))
	# The drift-flip LEAP bypasses slow-zone/gravity caps so it can break you out of a well.
	if _flip_t > 0.0:
		cap = maxf(cap, FLIP_CRUISE * (1.0 + FLIP_LEAP_BOOST))
	velocity = velocity.limit_length(cap)

	# Platform approach: inside the station's landing zone the speed is force-reduced
	# so you can actually land — no matter how fast you arrived (warp included). The
	# cap shrinks smoothly with proximity, easing you down rather than snapping. You
	# keep steering, you just can't blast through. (dock_approach is fed by main.)
	if dock_approach > 0.0:
		var land_cap := lerpf(DOCK_EDGE_SPEED, DOCK_PLATFORM_SPEED, dock_approach)
		velocity = velocity.limit_length(land_cap)

	# --- Floating origin: never move the node; accumulate the true position ---
	# Safe now: every hull translates at its own warp (bounded coordinate rate), and the core
	# voyage looms separately instead of flying real distance — so this never balloons.
	true_pos += velocity * delta

	# --- Cosmetic banking (on the mesh only, so the camera stays steady) ---
	var target_bank := clampf(-turn * BANK_GAIN - _strafe * 0.35, -BANK_ANGLE, BANK_ANGLE)
	# Cinematic cruise sway: hold a straight line (forward thrust, no steer/strafe input)
	# and after a beat the hull breathes a slow roll left↔right. Any steer/strafe input
	# unwinds it fast so it never fights real control.
	var steering := absf(turn) > 0.0008 or absf(_strafe) > 0.04 or _free_look or autopilot or braking
	var cruising := (Input.is_physical_key_pressed(KEY_W) or auto_cruise) and not steering
	_cruise_t = (_cruise_t + delta) if cruising else maxf(_cruise_t - delta * 3.0, 0.0)
	var sway_ramp := clampf((_cruise_t - SWAY_DELAY) / SWAY_RAMP, 0.0, 1.0)
	if sway_ramp > 0.0:
		# Two non-harmonic sines → an organic drift rather than a metronome wobble. At
		# interstellar speed the wave stretches LONGER and a touch wider (a grand, slow
		# banking roll) vs. the quicker breathe of normal sublight cruise.
		var warpf := smoothstep(1.0, 2.0, eff_warp)        # 0 sublight → 1 full warp
		var rate := lerpf(1.0, 0.5, warpf)                 # slower = longer wave at warp
		var amp := SWAY_ANGLE * lerpf(1.0, 1.45, warpf)    # slightly wider roll at warp
		var st := Time.get_ticks_msec() * 0.001
		var sway := (sin(st * 0.9 * rate) + 0.4 * sin(st * 0.37 * rate + 1.1)) / 1.4
		target_bank = clampf(target_bank + sway * amp * sway_ramp, -BANK_ANGLE, BANK_ANGLE)
	_bank = lerpf(_bank, target_bank, clampf(BANK_SMOOTH * delta, 0.0, 1.0))
	# Nose-lean into a climb/dive: vertical mouse leans the whole hull (mesh only; the real
	# pitch already happened on the transform above). Eased slowly so the big ship tips its
	# nose with weight instead of snapping. +lean (mouse down → nose-down dive) reads natural.
	var target_lean := clampf(lean * LEAN_PITCH_GAIN, -LEAN_PITCH, LEAN_PITCH)
	_lean = lerpf(_lean, target_lean, clampf(LEAN_SMOOTH * delta, 0.0, 1.0))
	_mesh_root.rotation = Vector3(_lean, 0.0, _bank)   # clear any transit flip/wobble
	# Cinematic drift-flip: a full 360° barrel roll layered on the bank (cosmetic — heading
	# is untouched). The sideways drift kick was added to velocity in do_flip().
	if _flip_t > 0.0:
		_flip_t = maxf(_flip_t - delta, 0.0)
		var fp := 1.0 - _flip_t / FLIP_TIME            # 0 → 1 across the move
		# NOSE STAYS STRAIGHT: a pure barrel roll around the forward axis — only the wings
		# sweep (x-y), the nose never pitches/yaws off the aim line. Heavy eased slow-fast-slow.
		var fe := fp * fp * (3.0 - 2.0 * fp)
		_mesh_root.rotation.z = _bank + _flip_dir * TAU * fe
		# DRIVE the ship through a wide wavey arc so it visibly TRAVELS while rolling. A compound
		# sine gives a rich S-on-S-on-S weave (more curve); facing/aim (transform) is untouched.
		# The glide is LERPED in (and out), so entering/leaving the flip is seamless — no snap.
		var weave := sin(fp * TAU) + 0.45 * sin(fp * 2.0 * TAU) + 0.22 * sin(fp * 3.0 * TAU)
		_flip_yaw += _flip_dir * FLIP_SWERVE * weave * delta
		# Quick LEAP: a speed burst that decays into the cruise glide over the first third.
		var leap := 1.0 + FLIP_LEAP_BOOST * (1.0 - smoothstep(0.0, 0.32, fp))
		var glide := (-transform.basis.z).rotated(Vector3.UP, _flip_yaw) * (FLIP_CRUISE * leap)
		velocity = velocity.lerp(glide, clampf(FLIP_EASE * delta, 0.0, 1.0))

	# --- Engine / booster intensity ---
	var flipping := _flip_t > 0.0
	var throttle := 1.0 if (Input.is_physical_key_pressed(KEY_W) or auto_cruise) else 0.18
	if Input.is_physical_key_pressed(KEY_S):
		throttle = maxf(throttle, 0.55)
	if boost > 1.0:
		throttle *= 1.4
	if flipping:
		throttle = 1.7                      # boosters BLAZE — the leap-push is a hard burn
	_update_boosters(throttle, delta)

	# --- Engine voice: loop while we're on the gas, with start/stop whooshes ---
	if audio:
		var thrusting := local_accel != Vector3.ZERO or flipping
		var ship_name: String = SHIP_MODELS[_current_model].name
		# During the leap, force the boost voice so you HEAR the push.
		audio.update_engine(ship_name, thrusting, clampf(throttle, 0.0, 1.0), boost > 1.0 or flipping, _engine_pitch, delta, is_warp_mode())
	if _engine_mat:  # fallback ship only
		var e := 2.0 + throttle * 4.0
		_engine_mat.emission_energy_multiplier = lerpf(
			_engine_mat.emission_energy_multiplier, e, clampf(8.0 * delta, 0.0, 1.0))

	# Fat motion streaks during the leap-push (warp-like), normal speed-based otherwise.
	_update_streaks(maxf(velocity.length(), MAX_SPEED * 0.7) if flipping else velocity.length())
	_update_camera(delta)


func _update_boosters(throttle: float, delta: float) -> void:
	var k := clampf(10.0 * delta, 0.0, 1.0)
	# Always-on engines: keep a strong baseline plume even at idle (boosting still
	# pushes it to full). Without this the plume only "appeared" under thrust.
	throttle = maxf(throttle, 0.6)
	# Warp form (Raptor only): the booster DEPLOYS — much longer and brighter. Combat
	# mode keeps the regular short plume.
	var fire := is_warp_form()
	var t := Time.get_ticks_msec() * 0.001
	# Living flame — EVERY engine breathes, even at cruise. Layered sines (different,
	# non-harmonic rates) read as an organic flicker instead of a clean pulse; warp form
	# flickers harder. `flick` shapes length, `shimmer` shapes brightness (faster).
	var amp := 0.16 if fire else 0.06
	var flick := 1.0 + amp * sin(t * 32.0) + (amp * 0.6) * sin(t * 67.0 + 1.7)
	var shimmer := 1.0 + (0.12 if fire else 0.05) * sin(t * 48.0 + 0.5)
	var deploy := 2.4 if fire else 1.0
	var max_alpha := 0.95 if fire else 0.6
	# Out of boost juice: the engine coughs — a fast on/off stutter that cuts the plume.
	var sputter := 1.0
	if _boost_starved:
		sputter = 0.15 if fmod(t * 11.0, 1.0) < 0.45 else 1.0
		k = 1.0   # snap, so the stutter is visible instead of smoothed away
	# --- Booster TIER from flight state (4 levels, see _tier_* vars) ---
	#   L1 slow-zone, no Shift      : base
	#   L2 slow-zone + Shift        : fatter + longer (clear gap from L1)
	#   L3 interstellar, no Shift   : brighter / stronger (hot-shifted glow)
	#   L4 interstellar + Shift     : max — biggest + brightest
	# The booster LEADS the speed: it powers up with the warp SPOOL (which starts the instant you
	# hold W in open space), not with the final velocity — so the plume strengthens FIRST and the
	# interstellar speed builds in behind it. `spool_s` ramps to full by ~55% charge (faster than
	# the speed, which keeps climbing to 100%), giving the clear "booster, THEN ship boost" order.
	var spool := _warp_charge if (warp > 1.0 and warp_ready()) else 0.0
	var spool_s := smoothstep(0.0, 0.55, spool)
	var interstellar := spool_s > 0.01
	var tier_w := 1.0
	var tier_len := 1.0
	var tier_bright := 1.0
	var tier_hot := 0.0
	if interstellar:                           # L3 (base) → L4 (with Shift), scaled by the spool
		var l4 := 1.0 if is_boosting else 0.0
		tier_w      = lerpf(1.0, lerpf(1.4, 1.6, l4), spool_s)
		tier_len    = lerpf(1.0, lerpf(1.2, 1.25, l4), spool_s)
		tier_bright = lerpf(1.0, lerpf(1.5, 1.9, l4), spool_s)
		tier_hot    = lerpf(0.0, lerpf(0.4, 0.6, l4), spool_s)
	elif is_boosting or boost_blocked:         # L2 (Shift in a slow-zone)
		tier_w = 1.5; tier_len = 1.2; tier_bright = 1.18; tier_hot = 0.0
	var ks := clampf(6.0 * delta, 0.0, 1.0)    # tiers ease a touch slower than the flicker
	_tier_w_s = lerpf(_tier_w_s, tier_w, ks)
	_tier_len_s = lerpf(_tier_len_s, tier_len, ks)
	_tier_bright_s = lerpf(_tier_bright_s, tier_bright, ks)
	_tier_hot_s = lerpf(_tier_hot_s, tier_hot, ks)
	# Interstellar (L3/L4) may glow brighter than the cruise cap.
	max_alpha = maxf(max_alpha, 0.6 + 0.35 * _tier_hot_s)
	# Smooth only the throttle-driven BASE values; the flicker/shimmer are applied
	# instantly on top so the per-frame lerp can't iron the animation flat.
	_plume_len_s = lerpf(_plume_len_s, (0.35 + throttle * 0.7) * deploy * sputter, k)
	_plume_a_s = lerpf(_plume_a_s, clampf((0.05 + throttle * 0.45) * (1.7 if fire else 1.0) * sputter, 0.0, max_alpha), k)
	_core_a_s = lerpf(_core_a_s, clampf((0.12 + throttle * 0.5) * sputter, 0.0, 0.95), k)
	var hot_col: Color = _booster_color.darkened(_tier_hot_s * 0.5)   # interstellar runs DARKER/deeper, not washed-out white
	# Bell + ring grow WITH the plume (gentler than the plume so the nozzle stays in proportion).
	var bell_w := 1.0 + (_tier_w_s - 1.0) * 0.7
	for b in _boosters:
		# Plume length stretches with throttle (× tier) and flickers live; bell + ring stay fixed.
		# Width (x/z) is driven entirely by the tier so higher tiers read as FATTER.
		var sc: Vector3 = b.plume_holder.scale
		sc.x = _tier_w_s
		sc.z = _tier_w_s
		sc.y = _plume_len_s * flick * _tier_len_s
		b.plume_holder.scale = sc
		# Plume brightness (additive) tracks throttle × tier and pulses with the shimmer;
		# interstellar tiers also shift the colour hotter/whiter for a stronger look.
		var pcol: Color = b.plume_mat.albedo_color
		pcol.r = hot_col.r; pcol.g = hot_col.g; pcol.b = hot_col.b
		pcol.a = clampf(_plume_a_s * shimmer * _tier_bright_s, 0.0, max_alpha)
		b.plume_mat.albedo_color = pcol
		# Soft core glow at the nozzle — flickers with the flame so the root looks alive.
		var cs := (0.35 + throttle * 0.7) * (1.6 if fire else 1.0) * sputter * flick * _tier_w_s
		b.core.scale = Vector3(cs, cs, cs)
		var ccol: Color = b.core_mat.albedo_color
		var hot_core: Color = hot_col.lerp(Color.WHITE, 0.35)
		ccol.r = hot_core.r; ccol.g = hot_core.g; ccol.b = hot_core.b
		ccol.a = clampf(_core_a_s * shimmer * _tier_bright_s, 0.0, 0.98)
		b.core_mat.albedo_color = ccol
		# Grow the metal bell + ring (fatter, matching the wider plume) — radius only.
		if b.bell != null:
			b.bell.scale = Vector3(bell_w, 1.0, bell_w)
		if b.ring != null:
			b.ring.scale = Vector3(bell_w, 1.0, bell_w)


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
	# CAM_VIEW_PITCH orbits the rig (position + aim together) so the ship is seen from slightly below.
	var basis := _cam_basis * Basis(Vector3.RIGHT, deg_to_rad(CAM_VIEW_PITCH_DEG)) \
		* (Basis(Vector3.UP, _look_yaw_s) * Basis(Vector3.RIGHT, _look_pitch_s))
	var cam_pos := basis * (CAM_OFFSET * _cam_zoom_smooth)  # ship at origin -> global
	# Wormhole transit: only a SLIGHT, slow buffet (gentle position drift + a touch of
	# roll/pitch) and a restrained FOV lean → the dive feels tense and dark, not stormy.
	if transiting:
		var t := Time.get_ticks_msec() * 0.001
		var pj := 0.05
		cam_pos += basis * Vector3(sin(t * 7.0) * pj, cos(t * 9.0) * pj, sin(t * 11.0) * pj * 0.5)
		var jr := 0.004
		basis = basis * Basis.from_euler(Vector3(
			sin(t * 5.0) * jr, cos(t * 6.0) * jr, sin(t * 8.0) * jr * 2.0))
		camera.global_transform = Transform3D(basis, cam_pos)
		camera.fov = lerpf(camera.fov, FOV_BASE + FOV_KICK * 0.8, clampf(3.0 * delta, 0.0, 1.0))
		return
	camera.global_transform = Transform3D(basis, cam_pos)
	# Clamp the fraction so warp speeds don't blow the FOV out into a fisheye.
	var speed_frac := clampf(velocity.length() / MAX_SPEED, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, FOV_BASE + speed_frac * FOV_KICK, clampf(4.0 * delta, 0.0, 1.0))


func _set_capture(c: bool) -> void:
	_mouse_captured = c
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if c else Input.MOUSE_MODE_VISIBLE)


# World position of the gun muzzle, tracking the hull's COSMETIC bank so bolts always
# leave the visible nose (slightly below centre) instead of drifting sideways when you
# bank into a turn or strafe with A/D. The forward offset sits on the roll axis (so it's
# unaffected); the small downward drop is rolled with the hull to stay glued to the gun.
func muzzle_world() -> Vector3:
	var local_off := Basis.from_euler(Vector3(0.0, 0.0, _bank * MUZZLE_BANK_FOLLOW)) * Vector3(0.0, -muzzle_drop, -muzzle)
	return true_pos + transform.basis * local_off


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


# Density + brightness + flow speed all ramp with the ship's RAW speed. Two ramps so
# you feel motion across the whole envelope: a gentle cue over the calm sublight range
# (so normal cruise no longer feels static), then the dramatic warp stretch up top.
func _update_streaks(speed: float) -> void:
	if _streaks == null:
		return
	# Sublight cue: 0 at rest -> ~full by SUBLIGHT_MAX (the calm-cruise cap). Kept subtle
	# so it reads as "moving" without the busy warp look — but visible enough to notice.
	var sub := clampf(speed / SUBLIGHT_MAX, 0.0, 1.0)
	# High-speed/warp stretch: off until ~1/3 of MAX_SPEED, full near the top.
	var hi := clampf((speed / MAX_SPEED - 0.3) / 0.5, 0.0, 1.0)
	var t := maxf(sub * 0.72, hi)
	_streaks.emitting = t > 0.01
	_streaks.amount_ratio = clampf(0.15 + t, 0.0, 1.0)
	_streaks.speed_scale = 1.0 + t * 1.6
	var a: Color = _streak_mat.albedo_color
	a.a = t * 0.8
	# Galactic drive only: at her absolute top speed the normal ramp is already maxed out, so
	# push the streaks PAST it — a much faster, denser hyperspace blur. Eased by the spool charge
	# so it swells in with the drive; ONLY this hull while actually cruising, so regular flight
	# (and every other ship) keeps the exact streak feel above.
	if galactic_cruising():
		var g := _warp_charge   # 0..1 drive spool
		_streaks.emitting = true
		_streaks.amount_ratio = 1.0
		_streaks.speed_scale = lerpf(2.6, 9.0, g)   # far faster flow than the warp max (2.6)
		a.a = lerpf(0.8, 0.95, g)
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
	bolt_strong = bool(info.get("bolt_strong", false))
	energy_max = float(info.get("energy_max", 100.0))
	energy_use = float(info.get("energy_use", 1.0))
	can_fire = bool(info.get("can_fire", true))
	has_laser = bool(info.get("laser", false))
	laser_offset = info.get("laser_offset", Vector3.ZERO)
	auto_capture = bool(info.get("auto_capture", false))
	_dual = info.get("dual", false)
	_raptor_warp_form = false      # Raptor always loads in its (faster) Combat form
	_engine_pitch = float(info.get("engine_pitch", 1.0))
	_can_brake = info.get("brake", false)
	has_galactic_drive = bool(info.get("galactic_drive", false))
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
	# Bolts spawn close to the nose — just shy of the hull's front tip — so the bright tracer
	# clearly emerges from the ship rather than floating ahead of it.
	muzzle = box.size.z * 0.42
	muzzle_drop = box.size.y * 0.18   # emerge a little below centre (lowered to match the
									  # hull's new lower framing), where the guns sit
	# Optionally lop off the model's rear (behind the ring) so the bell disc caps a
	# clean cut instead of the GLB's messy tail.
	if info.get("clip_back", false):
		var cut: float = box.size.z * float(BOOSTER_BACK_OVERRIDE.get(info.name, BOOSTER_BACK))
		ShipMesh.clip_behind(model, _mesh_root, cut)
	# Single-surface "atlas palette" hulls (Stella) get split into body + accent surfaces
	# FIRST, so the color_pick path below can dye the two parts independently.
	if not (info.get("swatch_split", []) as Array).is_empty():
		ShipMesh.split_by_swatch(model, info.swatch_split, info.get("swatch_accent", []))
	# Resolve per-surface roles + hull-light accent. Ships flagged "color_pick" build their
	# roles from the player's chosen palette (body + wings independently).
	var roles: Array = info.get("surf_roles", [])
	var accent: Color = info.get("light_accent", Color(1.0, 0.70, 0.84))
	if info.get("color_pick", false):
		var c: Dictionary = _colors_for(info.name, info)
		var wing: int = int(info.get("wing_surf", -1))
		var template: Array = info.get("surf_roles", [])
		var body_role := String(info.get("body_role", ""))
		var wing_role := String(info.get("wing_role", ""))
		var wing_surfs: Array = info.get("wing_surfs", [])   # several wing surfaces by index
		roles = []
		if template.is_empty():
			# Whole-hull style (HaniNebula): body everywhere, wing colour at wing_surf.
			for s in 24:
				roles.append(String(c.wing) if s == wing else String(c.body))
		else:
			# Template style (Raptor 2 / HaniStar): replace body_role surfaces with the body
			# colour, the wing surfaces with the wing colour, and keep the rest (e.g. glass).
			# Wings can be one wing_surf index, a wing_surfs list, or any wing_role surfaces.
			for i in template.size():
				var r := String(template[i])
				if (wing >= 0 and i == wing) or wing_surfs.has(i) or (wing_role != "" and r == wing_role):
					roles.append(String(c.wing))
				elif body_role != "" and r == body_role:
					roles.append(String(c.body))
				else:
					roles.append(r)
		for p in SHIP_PALETTES:
			if String(p.key) == String(c.body):   # accent light follows the body colour
				accent = p.accent
				break
	if info.get("metal", false) and info.has("gold_above"):
		# Silver body + champagne-gold top wing (split a single-surface mesh by height).
		ShipMesh.metal_split(model, _mesh_root, box.size.y * float(info.gold_above))
	else:
		ShipMesh.recolor(model, info.tint, float(info.glow), info.get("chrome", false), info.get("raw", false), info.get("pbr", false), roles, info.get("metal", false))
	# Surface finish (color_pick ships): "glassy" = real see-through tinted glass;
	# "metallic" = pure smooth polished metal.
	if info.get("color_pick", false):
		if _finish_for(info.name) == "glassy":
			ShipMesh.set_glassy(model)
		else:
			ShipMesh.set_polished(model)
	# Some hulls (HaniNebula, early stage) fly without authored booster plumes yet.
	if not info.get("no_boosters", false):
		_build_boosters(box, info.name)
	if info.get("gold_backplate", false):
		_add_gold_backplate(box, info.name)
	if info.get("pbr", false):
		# Light rig tint/energy per ship (accent resolved above — picks the palette tint
		# for color_pick ships, else the entry's light_accent).
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

# --- Player-pickable colours / bell / finish (hangar swatches & toggles) ---
# Get (lazily initialising) the body+wing colour choice for a hull.
func _colors_for(ship_nm: String, info: Dictionary) -> Dictionary:
	if not _color_choice.has(ship_nm):
		_color_choice[ship_nm] = {
			"body": String(info.get("default_color", "silver")),
			"wing": String(info.get("default_wing", "gold")),
		}
	return _color_choice[ship_nm]

# Whether this hull currently shows the metal engine bell (player-toggleable in the hangar).
func _bell_for(ship_nm: String) -> bool:
	if not _bell_choice.has(ship_nm):
		_bell_choice[ship_nm] = not BOOSTER_NO_RING.get(ship_nm, false)
	return _bell_choice[ship_nm]

func _finish_for(ship_nm: String) -> String:
	return String(_finish_choice.get(ship_nm, "metallic"))

func current_has_color_pick() -> bool:
	return bool(SHIP_MODELS[_current_model].get("color_pick", false))

func current_has_wing_pick() -> bool:
	var info: Dictionary = SHIP_MODELS[_current_model]
	# Wings can be a single wing_surf index, a wing_surfs list, or a wing_role — any means
	# the hull has a separately-pickable wing colour (so the hangar shows the wing swatch).
	return int(info.get("wing_surf", -1)) >= 0 \
		or not (info.get("wing_surfs", []) as Array).is_empty() \
		or String(info.get("wing_role", "")) != ""

func current_body_color() -> String:
	var info = SHIP_MODELS[_current_model]
	return String(_colors_for(info.name, info).body)

func current_wing_color() -> String:
	var info = SHIP_MODELS[_current_model]
	return String(_colors_for(info.name, info).wing)

# Set the active hull's "body" or "wing" colour to a palette key, then rebuild it.
func set_ship_color(part: String, key: String) -> void:
	var info = SHIP_MODELS[_current_model]
	if not info.get("color_pick", false):
		return
	var c: Dictionary = _colors_for(info.name, info)
	if part == "wing":
		c.wing = key
	else:
		c.body = key
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO
	_build_ship_model(_current_model)

func current_bell() -> bool:
	return _bell_for(SHIP_MODELS[_current_model].name)

# Add/remove the engine bell on the active hull and rebuild it.
func set_ship_bell(on: bool) -> void:
	_bell_choice[SHIP_MODELS[_current_model].name] = on
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO
	_build_ship_model(_current_model)

func current_finish() -> String:
	return _finish_for(SHIP_MODELS[_current_model].name)

# Set the active hull's surface finish ("metallic" | "glassy") and rebuild it.
func set_ship_finish(key: String) -> void:
	_finish_choice[SHIP_MODELS[_current_model].name] = key
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO
	_build_ship_model(_current_model)

# Serialise every per-ship customization choice (colour/bell/finish) for the profile,
# so each hull keeps the look the player gave it across sessions.
func customization_state() -> Dictionary:
	return { "color": _color_choice, "bell": _bell_choice, "finish": _finish_choice }

# Restore saved customization (from the profile) and rebuild the live hull so the
# player sees their saved colours immediately on load.
func load_customization(d: Dictionary) -> void:
	if d == null:
		return
	if d.has("color"): _color_choice = d.color.duplicate(true)
	if d.has("bell"):  _bell_choice = d.bell.duplicate(true)
	if d.has("finish"): _finish_choice = d.finish.duplicate(true)
	_bank = 0.0
	_mesh_root.rotation = Vector3.ZERO
	_build_ship_model(_current_model)

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


# Cinematic drift-flip (W + C): a full barrel roll plus a sideways drift slew. The roll is
# cosmetic (mesh only, so heading/aim are unaffected); the drift is a one-off velocity kick
# that decays through the normal damping. dir < 0 = left, ≥ 0 = right. Works in free-look too.
func do_flip(dir := 1.0) -> void:
	if _flip_t > 0.0 or frozen or transiting:
		return
	_flip_dir = -1.0 if dir < 0.0 else 1.0
	_flip_t = FLIP_TIME
	_flip_yaw = 0.0
	# Motion is DRIVEN each frame during the flip (see fly()'s flip block) so the ship glides
	# through a wide arc instead of spinning on the spot — no one-shot impulse to be damped away.


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
	# Most ships get the metal engine bell + nozzle ring; hulls with their own nozzles
	# (HaniNebula) default to none. _bell_for() honours the player's hangar toggle — it
	# falls back to BOOSTER_NO_RING the first time, then tracks add/remove choices.
	_booster_ring = _bell_for(ship_name)
	_booster_smoke = bool(BOOSTER_SMOKE.get(ship_name, false))
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
	# Hoisted so the tier system can grow the bell/ring with the plume (see _update_boosters).
	var bell: MeshInstance3D = null
	var ring: MeshInstance3D = null

	# Rough-metallic engine bell the plume emerges from (ring ships only). Extends
	# BACKWARD past the hull (+Y in pivot space = +Z = tail) so the nozzle reads as a
	# real engine housing — especially the central main booster, whose nozzle would
	# otherwise sit buried inside the hull with its ring hidden.
	if _booster_ring:
		bell = MeshInstance3D.new()
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
		ring = MeshInstance3D.new()
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

	# Optional smoke trail: dark purple-grey puffs billowing out behind the flame. Left in WORLD
	# space (local_coords off) so they linger as a trail rather than rigidly following the nozzle.
	# MIX blend (not additive) so the smoke actually reads as dark haze against the void.
	if _booster_smoke:
		var smoke := GPUParticles3D.new()
		pivot.add_child(smoke)
		smoke.amount = 22
		smoke.lifetime = 1.5
		smoke.local_coords = false
		smoke.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))
		var sp := ParticleProcessMaterial.new()
		sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		sp.emission_sphere_radius = radius * 0.7
		sp.direction = Vector3(0.0, 1.0, 0.0)   # pivot +Y = +Z = straight out the tail
		sp.spread = 16.0
		sp.initial_velocity_min = length * 0.7
		sp.initial_velocity_max = length * 1.2
		sp.damping_min = length * 0.6           # billow + slow as it drifts back
		sp.damping_max = length * 0.9
		sp.gravity = Vector3.ZERO
		sp.scale_min = radius * 1.4
		sp.scale_max = radius * 2.6
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.42, 0.16, 0.58, 0.40))   # purple-grey, semi-opaque at birth
		ramp.set_color(1, Color(0.18, 0.07, 0.28, 0.0))    # fades to nothing
		var gtex := GradientTexture1D.new()
		gtex.gradient = ramp
		sp.color_ramp = gtex
		smoke.process_material = sp
		var smesh := QuadMesh.new()
		smesh.size = Vector2(radius * 3.0, radius * 3.0)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		smat.billboard_keep_scale = true
		smat.albedo_texture = _glow_tex          # soft round puff (reused soft-glow sprite)
		smat.vertex_color_use_as_albedo = true   # let the colour-ramp tint + fade each puff
		smesh.material = smat
		smoke.draw_pass_1 = smesh

	return {
		"pivot": pivot,
		"plume_holder": plume_holder,
		"plume_mat": plume_mat,
		"core": core,
		"core_mat": core_mat,
		"bell": bell,   # may be null (ring-less hulls)
		"ring": ring,   # may be null
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
