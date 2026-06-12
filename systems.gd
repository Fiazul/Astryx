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


# Display name + real distance-from-Sol in light-years (metadata only).
static func display_name(id: String) -> String:
	return { SOL: "Sol", K2_18: "K2-18" }.get(id, id)

static func light_years(id: String) -> float:
	return { SOL: 0.0, K2_18: 124.0 }.get(id, 0.0)

# Where the ship emerges (small local coord) when arriving in a system, and where
# that system's return/onward wormhole portal sits.
static func arrival_pos(id: String) -> Vector3:
	return { SOL: Vector3(-0.81, -1.97, -4.53), K2_18: Vector3(3.0, 0.6, -2.5) }.get(id, Vector3.ZERO)

static func portal_pos(id: String) -> Vector3:
	# Sol's portal sits out past Earth; K2-18's sits near the arrival point.
	return { SOL: Vector3(2.0, 1.0, -6.0), K2_18: Vector3(5.0, 0.8, -1.0) }.get(id, Vector3.ZERO)

# The system each portal jumps to (one hop each way, for now).
static func portal_dest(id: String) -> String:
	return { SOL: K2_18, K2_18: SOL }.get(id, SOL)


static func bodies(id: String) -> Array:
	match id:
		K2_18: return _k2_18()
		_:     return _sol()


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
