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
		SOL: Vector3(-8.1, -19.7, -45.3), K2_18: Vector3(30.0, 6.0, -25.0),
		PROXIMA: Vector3(25.0, 5.0, -30.0), TRAPPIST: Vector3(32.0, 6.0, -35.0),
		ALIEN: Vector3(0.0, 15.0, -70.0),
	}.get(id, Vector3.ZERO)

# Wormhole portals present in each system. Earth (Sol) has a SEPARATE portal for
# each exoplanet destination — spread far apart, parked, clear of every other
# object (Earth sits at the origin; the Sun is ~10 u out). Every other system
# keeps a single portal back to Sol, pushed well out from its star (and well clear
# of that system's station, which lives on the opposite side). The star map still
# fast-travels anywhere directly. Each entry: { pos: local units, dest: system }.
static func portals(id: String) -> Array:
	match id:
		SOL:
			return [
				{ "pos": Vector3(34.0, 17.0, -100.0),  "dest": K2_18 },
				{ "pos": Vector3(-110.0, 20.0, -60.0), "dest": PROXIMA },
				{ "pos": Vector3(80.0, -25.0, 80.0),   "dest": TRAPPIST },
			]
		K2_18:    return [{ "pos": Vector3(75.0, 10.0, -15.0),  "dest": SOL }]
		PROXIMA:  return [{ "pos": Vector3(65.0, 12.0, -22.0),  "dest": SOL }]
		TRAPPIST: return [{ "pos": Vector3(70.0, 12.0, -22.0),  "dest": SOL }]
		ALIEN:    return [{ "pos": Vector3(75.0, 12.0, -30.0),  "dest": SOL }]
		_:        return [{ "pos": Vector3(50.0, 10.0, -20.0),  "dest": SOL }]


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
		{ "name": "K2-18",  "radius": 3.75, "color": Color(1.0, 0.45, 0.28), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "K2-18b", "radius": 2.4,  "color": Color(0.32, 0.62, 0.78), "glow": 0.5,
			"star": false, "live": false, "pos": Vector3(12.0, 1.0, 8.0) },   # 0.143 AU
		{ "name": "K2-18c", "radius": 1.25, "color": Color(0.75, 0.6, 0.5),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-5.5, 0.5, 4.0) },   # 0.067 AU
	]


# Proxima Centauri (~4.24 ly) and its planet Proxima b.
static func _proxima() -> Array:
	return [
		{ "name": "Proxima Centauri", "radius": 3.25, "color": Color(1.0, 0.4, 0.24), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "Proxima b", "radius": 2.1, "color": Color(0.62, 0.46, 0.40), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(4.9, 0.6, 3.0) },   # ~0.0485 AU
	]


# TRAPPIST-1 (~39 ly): an ultra-cool red dwarf with several tightly-packed worlds.
static func _trappist() -> Array:
	return [
		{ "name": "TRAPPIST-1", "radius": 2.5, "color": Color(1.0, 0.5, 0.30), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
		{ "name": "TRAPPIST-1b", "radius": 1.05, "color": Color(0.78, 0.5, 0.42), "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(1.1, 0.2, 0.5) },
		{ "name": "TRAPPIST-1d", "radius": 1.0, "color": Color(0.55, 0.62, 0.7),  "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-1.8, 0.3, 1.2) },
		{ "name": "TRAPPIST-1e", "radius": 1.15, "color": Color(0.35, 0.62, 0.78), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(2.2, 0.4, -1.8) },
		{ "name": "TRAPPIST-1g", "radius": 1.25, "color": Color(0.6, 0.6, 0.65),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-3.0, 0.5, -2.2) },
	]


# The hostile zone — a dim, blood-red star to fight under. Aliens + Vortex live here.
static func _alien() -> Array:
	return [
		{ "name": "Hostile Star", "radius": 3.5, "color": Color(0.9, 0.12, 0.12), "glow": 1.6,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://star.glb" },
	]
