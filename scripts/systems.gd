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
const INTERSTELLAR := "interstellar"   # the deep-space hub between systems (Stage 2)

# Interstellar hub layout: each real system shows up as a flyable "sun" laid out from
# its galaxy-map position. Kept to a few thousand units across — flyable + float-safe,
# no real-distance free-flight (that's the whole point of the hub). FTL is free here
# (these markers are NOT flagged `star`, so they don't gate warp).
const HUB_SCALE := 70.0
const HUB_DESTS := [SOL, PROXIMA, TRAPPIST, K2_18, ALIEN]

static func _hub_pos(id: String) -> Vector3:
	var g := galaxy_pos(id)
	var y: float = { SOL: 0.0, PROXIMA: 300.0, TRAPPIST: -400.0, K2_18: 600.0, ALIEN: -800.0 }.get(id, 0.0)
	return Vector3(g.x * HUB_SCALE, y, g.y * HUB_SCALE)

static func _hub_color(id: String) -> Color:
	return { SOL: Color(1.0, 0.85, 0.3), PROXIMA: Color(1.0, 0.55, 0.4),
		TRAPPIST: Color(1.0, 0.5, 0.3), K2_18: Color(1.0, 0.45, 0.28),
		ALIEN: Color(0.95, 0.15, 0.12) }.get(id, Color(1, 1, 1))

# The hub's bodies: one glowing sun per destination system (visual + label anchor).
static func _interstellar() -> Array:
	var out := []
	for id in HUB_DESTS:
		out.append({
			"name": "%s ✦" % display_name(id),   # ✦ marks a hub gate, distinct from in-system names
			"radius": 40.0, "mass": 0.0, "color": _hub_color(id), "glow": 2.2,   # mass 0 → free FTL hub, no grab
			"star": false, "live": false, "pos": _hub_pos(id), "model": "res://assets/star.glb",
		})
	return out


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
		TRAPPIST: "TRAPPIST-1", ALIEN: "Alien Zone", INTERSTELLAR: "Interstellar" }.get(id, id)

static func light_years(id: String) -> float:
	return { SOL: 0.0, K2_18: 124.0, PROXIMA: 4.24, TRAPPIST: 39.0, ALIEN: 666.0 }.get(id, 0.0)

# Where the ship emerges (small local coord) when arriving in a system, and where
# that system's return/onward wormhole portal sits.
static func arrival_pos(id: String) -> Vector3:
	return {
		SOL: Vector3(-8.1, -19.7, -45.3), K2_18: Vector3(30.0, 6.0, -25.0),
		PROXIMA: Vector3(25.0, 5.0, -30.0), TRAPPIST: Vector3(32.0, 6.0, -35.0),
		ALIEN: Vector3(0.0, 15.0, -70.0),
		INTERSTELLAR: Vector3(0.0, 200.0, 600.0),   # emerge just "south" of the Sol gate-sun
	}.get(id, Vector3.ZERO)

# Wormhole portals present in each system. Travel is HUB-AND-SPOKE: every system
# (Sol included) has a SINGLE edge gate to the Interstellar hub, pushed well out
# beyond the star's gravity field (and clear of any station). The hub holds one
# portal per destination system, each parked beside that system's gate-sun, so you
# emerge from Sol at the hub and pick your exoplanet there. The star map still
# fast-travels anywhere directly. Each entry: { pos: local units, dest: system }.
static func portals(id: String) -> Array:
	# The hub is central: every system has ONE edge gate to INTERSTELLAR (placed well
	# beyond the star's gravity field, ~2.5-3k u out), and the hub has one portal that
	# dives into each destination system, parked beside that system's gate-sun.
	if id == INTERSTELLAR:
		var out := []
		for dest in HUB_DESTS:
			out.append({ "pos": _hub_pos(dest) + Vector3(150.0, 0.0, 0.0), "dest": dest })
		return out
	match id:
		SOL:      return [{ "pos": Vector3(0.0, 400.0, -3000.0),  "dest": INTERSTELLAR }]
		_:        return [{ "pos": Vector3(0.0, 250.0, -2600.0),  "dest": INTERSTELLAR }]


static func bodies(id: String) -> Array:
	match id:
		INTERSTELLAR: return _interstellar()
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
			"mass": p.get("mass", 1.0),    # real mass (Earth=1) drives the force-slow zone
			"ring": p.get("ring", false),  # Saturn's ring
			"craft": p.get("craft", false),   # Voyagers drift outward forever
			"drift": p.get("drift", 0.0),
			"live": true, "pos": Vector3.ZERO,
		}
		if p.has("model"):
			b["model"] = p.model
		out.append(b)
	# Major moons orbit their live parent planet each frame (see PlanetSystem.refresh).
	for m in Ephemeris.MOONS:
		out.append({
			"name": m.name, "radius": m.radius, "color": m.color, "glow": m.get("glow", 0.25),
			"mass": m.get("mass", 0.01), "star": false, "live": false, "pos": Vector3.ZERO,
			"parent": m.parent, "orbit_r": m.orbit_r, "orbit_speed": m.orbit_speed,
		})
	return out


# K2-18: a real M-dwarf (~124 ly) with its real planets. K2-18b is the famous
# sub-Neptune "hycean" candidate at 0.143 AU; K2-18c orbits inside it at 0.067
# AU. Positions are LOCAL (star at origin); orbital radii are real (× 10 u/AU).
# Purely static — no live source, so the swap never calls Horizons.
static func _k2_18() -> Array:
	return [
		{ "name": "K2-18",  "radius": 6.0, "mass": 120000.0, "color": Color(1.0, 0.45, 0.28), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://assets/star.glb" },
		{ "name": "K2-18b", "radius": 3.8,  "color": Color(0.32, 0.62, 0.78), "glow": 0.5,
			"star": false, "live": false, "pos": Vector3(12.0, 1.0, 8.0) },   # 0.143 AU
		{ "name": "K2-18c", "radius": 2.0,  "color": Color(0.75, 0.6, 0.5),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-5.5, 0.5, 4.0) },   # 0.067 AU
	]


# Proxima Centauri (~4.24 ly) and its planet Proxima b.
static func _proxima() -> Array:
	return [
		{ "name": "Proxima Centauri", "radius": 5.0, "mass": 40000.0, "color": Color(1.0, 0.4, 0.24), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://assets/star.glb" },
		{ "name": "Proxima b", "radius": 3.2, "color": Color(0.62, 0.46, 0.40), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(4.9, 0.6, 3.0) },   # ~0.0485 AU
	]


# TRAPPIST-1 (~39 ly): an ultra-cool red dwarf with several tightly-packed worlds.
static func _trappist() -> Array:
	return [
		{ "name": "TRAPPIST-1", "radius": 3.8, "mass": 30000.0, "color": Color(1.0, 0.5, 0.30), "glow": 2.0,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://assets/star.glb" },
		{ "name": "TRAPPIST-1b", "radius": 1.6, "color": Color(0.78, 0.5, 0.42), "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(1.1, 0.2, 0.5) },
		{ "name": "TRAPPIST-1d", "radius": 1.5, "color": Color(0.55, 0.62, 0.7),  "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-1.8, 0.3, 1.2) },
		{ "name": "TRAPPIST-1e", "radius": 1.7, "color": Color(0.35, 0.62, 0.78), "glow": 0.4,
			"star": false, "live": false, "pos": Vector3(2.2, 0.4, -1.8) },
		{ "name": "TRAPPIST-1g", "radius": 1.9, "color": Color(0.6, 0.6, 0.65),   "glow": 0.35,
			"star": false, "live": false, "pos": Vector3(-3.0, 0.5, -2.2) },
	]


# The hostile zone — a dim, blood-red star to fight under. Aliens + Vortex live here.
static func _alien() -> Array:
	return [
		{ "name": "Hostile Star", "radius": 5.25, "mass": 50000.0, "color": Color(0.9, 0.12, 0.12), "glow": 1.6,
			"star": true, "live": false, "pos": Vector3(0, 0, 0), "model": "res://assets/star.glb" },
		# The deep-catalog nebula — a big, soft, colourful glow out past the hostiles
		# (placeholder for a proper volumetric cloud later). No speed limit out here.
		{ "name": "Veil Nebula", "radius": 160.0, "color": Color(0.65, 0.40, 0.95), "glow": 1.3,
			"mass": 0.0, "star": false, "live": false, "pos": Vector3(420.0, 90.0, -560.0) },
	]
