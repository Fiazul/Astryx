class_name SystemDB
extends RefCounted
# Star systems you can wormhole between. Each system is its own LOCAL, small-
# coordinate space (1 unit = 0.1 AU, same as Sol) — you NEVER fly the real
# interstellar distance, so float precision is never stressed. The real
# light-year distance is display/transit metadata only (see Wormhole).
#
# A "body spec" is what PlanetSystem.load_system() consumes:
#   name, radius (visual), color, glow, model (opt GLB), star (bool),
#   live (bool — Sol's Sun/planets read live positions from Ephemeris),
#   pos  (Vector3 local scene units — used when live == false).

const SOL := "sol"
const K2_18 := "k2-18"
const PROXIMA := "proxima"
const TRAPPIST := "trappist"
const ALIEN := "alien"           # the hostile combat zone (Vortex + aliens)


# Every system, and a 2D galaxy-map position for each (arbitrary "star chart"
# layout — Sol at the origin). Used by the star map (StarMap).
static func all() -> Array:
	return [SOL, PROXIMA, TRAPPIST, K2_18, ALIEN]

static func galaxy_pos(id: String) -> Vector2:
	return {
		SOL: Vector2(0, 0), PROXIMA: Vector2(-38, 26), TRAPPIST: Vector2(58, 64),
		K2_18: Vector2(118, -44), ALIEN: Vector2(-92, -78),
	}.get(id, Vector2.ZERO)

# Hostile systems spawn the aliens + Vortex boss. Everywhere else is peaceful.
static func is_hostile(id: String) -> bool:
	return id == ALIEN


# Display name + real distance-from-Sol in light-years (metadata only).
static func display_name(id: String) -> String:
	return { SOL: "Sol", K2_18: "K2-18", PROXIMA: "Proxima b",
		TRAPPIST: "TRAPPIST-1", ALIEN: "Alien Zone" }.get(id, id)

static func light_years(id: String) -> float:
	return { SOL: 0.0, K2_18: 124.0, PROXIMA: 4.24, TRAPPIST: 39.0, ALIEN: 666.0 }.get(id, 0.0)

# Where the ship emerges (small local coord) when arriving in a system, and where
# that system's return/onward wormhole portal sits.
static func arrival_pos(id: String) -> Vector3:
	return {
		SOL: Vector3(-0.81, -1.97, -4.53), K2_18: Vector3(3.0, 0.6, -2.5),
		PROXIMA: Vector3(2.5, 0.5, -3.0), TRAPPIST: Vector3(3.2, 0.6, -3.5),
		ALIEN: Vector3(0.0, 1.5, -7.0),
	}.get(id, Vector3.ZERO)

static func portal_pos(id: String) -> Vector3:
	# Sol's portal sits out past Earth; the rest sit near each arrival point.
	return {
		SOL: Vector3(3.4, 1.7, -10.0), K2_18: Vector3(5.0, 0.8, -1.0),
		PROXIMA: Vector3(4.0, 1.0, -1.5), TRAPPIST: Vector3(4.5, 1.0, -1.5),
		ALIEN: Vector3(5.0, 1.0, -2.0),
	}.get(id, Vector3.ZERO)

# The wormhole (F) does one hop: Sol <-> K2-18. Every other system's portal
# returns you to Sol. (The star map lets you fast-travel anywhere directly.)
static func portal_dest(id: String) -> String:
	return { SOL: K2_18, K2_18: SOL }.get(id, SOL)


static func bodies(id: String) -> Array:
	match id:
		K2_18:    return _k2_18()
		PROXIMA:  return _proxima()
		TRAPPIST: return _trappist()
		ALIEN:    return _alien()
		_:        return _sol()


# Sol: the live bodies from Ephemeris (Sun + planets), tagged live so
# PlanetSystem reads their real Horizons positions each frame.
static func _sol() -> Array:
	var out := []
	for p in Ephemeris.PLANETS:
		var b := {
			"name": p.name, "radius": p.radius, "color": p.color,
			"glow": p.get("glow", 1.0), "star": p.get("star", false),
			"live": true, "pos": Vector3.ZERO,
		}
		if p.has("model"):
			b["model"] = p.model
		out.append(b)
	return out


# K2-18: a real M-dwarf (~124 ly) with its real planets. K2-18b is the famous
# sub-Neptune "hycean" candidate at 0.143 AU; K2-18c orbits inside it at 0.067
# AU. Positions are LOCAL (star at origin); orbital radii are real (× 10 u/AU).
# Purely static — no live source, so the swap never calls Horizons.
static func _k2_18() -> Array:
	return [
		{ "name": "K2-18",  "radius": 1.5,  "color": Color(1.0, 0.45, 0.28), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "K2-18b", "radius": 0.95, "color": Color(0.32, 0.62, 0.78), "glow": 0.5,
			"star": false, "live": false, "pos": Vector3(1.20, 0.10, 0.80) },   # 0.143 AU
		{ "name": "K2-18c", "radius": 0.5,  "color": Color(0.75, 0.6, 0.5),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-0.55, 0.05, 0.40) },  # 0.067 AU
	]


# Proxima Centauri (~4.24 ly) and its planet Proxima b.
static func _proxima() -> Array:
	return [
		{ "name": "Proxima Centauri", "radius": 1.3, "color": Color(1.0, 0.4, 0.24), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "Proxima b", "radius": 0.85, "color": Color(0.62, 0.46, 0.40), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(0.49, 0.06, 0.30) },   # ~0.0485 AU
	]


# TRAPPIST-1 (~39 ly): an ultra-cool red dwarf with several tightly-packed worlds.
static func _trappist() -> Array:
	return [
		{ "name": "TRAPPIST-1", "radius": 1.0, "color": Color(1.0, 0.5, 0.30), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "TRAPPIST-1b", "radius": 0.42, "color": Color(0.78, 0.5, 0.42), "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(0.11, 0.02, 0.05) },
		{ "name": "TRAPPIST-1d", "radius": 0.40, "color": Color(0.55, 0.62, 0.7),  "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-0.18, 0.03, 0.12) },
		{ "name": "TRAPPIST-1e", "radius": 0.46, "color": Color(0.35, 0.62, 0.78), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(0.22, 0.04, -0.18) },
		{ "name": "TRAPPIST-1g", "radius": 0.50, "color": Color(0.6, 0.6, 0.65),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-0.30, 0.05, -0.22) },
	]


# The hostile zone — a dim, blood-red star to fight under. Aliens + Vortex live here.
static func _alien() -> Array:
	return [
		{ "name": "Hostile Star", "radius": 1.4, "color": Color(0.9, 0.12, 0.12), "glow": 1.6,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
	]
