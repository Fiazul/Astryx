# Autoload singleton (registered as `Ephemeris` in project.godot). class_name dropped per ADR-0001.
extends Node
# REAL positions for Cold Light. Earth is the anchor at the scene origin (0,0,0) —
# every coordinate here is GEOCENTRIC, the frame NASA RA/Dec are measured in.
#
# Two kinds of body, two truths:
#   • Sun + planets MOVE day-to-day -> fetched LIVE from JPL Horizons (keyless)
#     for the real current date, so you fly today's real sky. If the net is down
#     we fall back to baked constants that were verified against Horizons to 4
#     decimals (see tools/real_positions.py).
#   • Stars don't visibly move over years -> the J2000 catalog below IS today's
#     real star sky. Placed by real RA/Dec/parallax-distance.
#
# Frame: ICRS / J2000 equatorial, AU. Scene mapping (Godot, Y-up):
#     scene = Vector3(eq.x, eq.z, eq.y) * AU_TO_UNITS   (celestial north = +Y)
#
# SCALE (the one tunable knob — does NOT affect realism, only travel time):
#   1 scene unit = 0.1 AU   ->   AU_TO_UNITS = 10
# Real distance ratios are preserved exactly; this just sets the zoom so the
# solar system is the explorable arena (Sun ~10u, Neptune ~300u). The real stars
# then sit millions of units away, so they render as a direction-only backdrop
# shell (see PlanetSystem) — exactly how a real sky behaves.

const AU_TO_UNITS := 130.0   # 1 unit ≈ 0.0077 AU — mild bump: orbits spread ~30% wider so close planets clear the ship/star
const STAR_SHELL_RADIUS := 30000.0   # backdrop shell (well inside cam.far) — scaled with the system

# Visual radii are EXAGGERATED (a real planet is sub-pixel) — the one non-real
# thing, and it's just the "dots and glow" aesthetic. Positions stay real.
# eq = geocentric equatorial XYZ in AU (verified fallback for 2026-06-12).
# Optional "model" = a GLB the dot resolves into up close. "glow" = self-illum
# energy (no scene lights). Earth is the origin anchor; the Sun wears star.glb,
# which is also reused for every star (see PlanetSystem).
const PLANETS := [
	# Bigger now, with REAL masses (Earth = 1) so gravity is mass-based: the giants and
	# the Sun grab hard, Mercury/Mars barely tug. Radii follow real size order, gently
	# compressed so they read as dominant without engulfing neighbours.
	# AWE PASS (feat/scale-and-awe): Earth blown up 30× (5.6 → 170) so it OVERWHELMS the view from
	# the start, like looking down from a station. Moon scaled with it (see MOONS). The rest of Sol
	# is still at the old scale for now — the Sol-step rescales AU_TO_UNITS to match. Known temporary
	# artifact: the Sun (~130u out) now sits inside Earth's 170u radius — you start looking AWAY from
	# it, so it's hidden until we spread Sol out.
	{ "name": "Earth",   "id": "399", "eq": Vector3(0, 0, 0),               "radius": 170.0, "mass": 1.0,      "color": Color(0.169, 0.510, 0.788), "model": "res://assets/earth.glb", "glow": 0.12, "fixed": true },
	{ "name": "Sun",     "id": "10",  "eq": Vector3( 0.1640,  0.9194,  0.3985), "radius": 14.0, "mass": 333000.0, "color": Color(1.00, 0.85, 0.30), "star": true, "model": "res://assets/sol.obj", "glow": 2.0 },
	{ "name": "Mercury", "id": "199", "eq": Vector3(-0.2269,  0.7801,  0.3646), "radius": 2.2,  "mass": 0.055,    "color": Color(0.533, 0.533, 0.533) },
	{ "name": "Venus",   "id": "299", "eq": Vector3(-0.5535,  0.9404,  0.4534), "radius": 5.3,  "mass": 0.815,    "color": Color(0.890, 0.831, 0.714) },
	{ "name": "Mars",    "id": "499", "eq": Vector3( 1.4583,  1.4672,  0.6149), "radius": 3.0,  "mass": 0.107,    "color": Color(0.737, 0.353, 0.263) },
	{ "name": "Jupiter", "id": "599", "eq": Vector3(-2.6447,  4.9896,  2.2115), "radius": 20.0, "mass": 317.8,    "color": Color(0.690, 0.498, 0.208) },
	{ "name": "Saturn",  "id": "699", "eq": Vector3( 9.5512,  2.1483,  0.5020), "radius": 17.0, "mass": 95.2,     "color": Color(0.886, 0.749, 0.490), "ring": true },
	{ "name": "Uranus",  "id": "799", "eq": Vector3( 9.4808, 16.6122,  7.1397), "radius": 8.4,  "mass": 14.5,     "color": Color(0.294, 0.439, 0.867) },
	{ "name": "Neptune", "id": "899", "eq": Vector3(30.0174,  2.1421,  0.1558), "radius": 8.0,  "mass": 17.1,     "color": Color(0.153, 0.275, 0.529) },
	# The Voyagers — real interstellar probes, fetched LIVE from Horizons (spacecraft
	# IDs -31 / -32, same geocentric frame as the planets). The eq fallbacks are their
	# approximate 2026 positions (~160 / ~136 AU out) so they appear even offline. We
	# respect them: they sit at their true coordinates and get a safe-zone speed limit.
	# drift = constant outward speed (units/s). Real V1≈17.0 km/s, V2≈15.4 km/s are
	# microscopic at this scale, so these are visible speeds keeping the real ratio.
	{ "name": "Voyager 1", "id": "-31", "eq": Vector3(-33.2, -155.9, 33.9),  "radius": 8.0, "mass": 8000.0, "color": Color(0.82, 0.86, 0.92), "model": "res://assets/Space probe.glb", "glow": 0.1, "craft": true, "drift": 5.0 },
	{ "name": "Voyager 2", "id": "-32", "eq": Vector3(39.0, -67.6, -111.4),  "radius": 8.0, "mass": 8000.0, "color": Color(0.82, 0.86, 0.92), "model": "res://assets/Space probe.glb", "glow": 0.1, "craft": true, "drift": 4.5 },
]

# Major moons — they orbit their PARENT planet each frame (parent tracked live from
# Horizons). orbit_r is in scene units, EXAGGERATED for visibility like the planets
# (true lunar distances are sub-planet-radius at this scale). orbit_speed = rad/s.
const MOONS := [
	{ "name": "Moon",     "parent": "Earth",   "radius": 48.0, "mass": 0.0123, "orbit_r": 480.0, "orbit_speed": 0.45, "color": Color(0.78, 0.78, 0.80) },   # AWE PASS: scaled 30× with Earth (1.6→48, 16→480) so it clears the giant Earth
	# Mars's two tiny captured-asteroid moons. Real radii are ~11 km / ~6 km — invisible at
	# true scale, so radius is artistic (clearly smaller than the Moon). Phobos orbits faster
	# than Mars spins (7.6 h), so it gets the higher orbit_speed; masses are real (≈0, no pull).
	{ "name": "Phobos",   "parent": "Mars",    "radius": 0.5, "mass": 0.0000000018,  "orbit_r": 7.0,  "orbit_speed": 1.10, "color": Color(0.42, 0.40, 0.38) },
	{ "name": "Deimos",   "parent": "Mars",    "radius": 0.35,"mass": 0.00000000025, "orbit_r": 11.0, "orbit_speed": 0.55, "color": Color(0.46, 0.44, 0.41) },
	{ "name": "Io",       "parent": "Jupiter", "radius": 1.4, "mass": 0.015,  "orbit_r": 34.0, "orbit_speed": 0.80, "color": Color(0.95, 0.90, 0.50) },
	{ "name": "Europa",   "parent": "Jupiter", "radius": 1.3, "mass": 0.008,  "orbit_r": 45.0, "orbit_speed": 0.62, "color": Color(0.90, 0.88, 0.82) },
	{ "name": "Ganymede", "parent": "Jupiter", "radius": 1.8, "mass": 0.025,  "orbit_r": 57.0, "orbit_speed": 0.46, "color": Color(0.70, 0.64, 0.56) },
	{ "name": "Callisto", "parent": "Jupiter", "radius": 1.7, "mass": 0.018,  "orbit_r": 70.0, "orbit_speed": 0.34, "color": Color(0.50, 0.46, 0.44) },
	{ "name": "Titan",    "parent": "Saturn",  "radius": 1.7, "mass": 0.0225, "orbit_r": 42.0, "orbit_speed": 0.50, "color": Color(0.92, 0.66, 0.30) },
]

# Real nearby stars (J2000): RA(h,m,s), Dec(d,m,s), distance(ly). HYG/SIMBAD.
# color ~ real spectral type.
const STARS := [
	# mass = real stellar mass in EARTH masses (≈ solar × 333000) — drives the size of
	# the force-slow zone as you approach (heavier star = stronger, wider slow).
	{ "name": "Proxima Centauri", "ra": [14,29,42.9], "dec": [-62,40,46], "ly": 4.2465, "mass": 40000.0,  "color": Color(1.0, 0.60, 0.42) },
	{ "name": "Alpha Centauri",   "ra": [14,39,36.5], "dec": [-60,50, 2], "ly": 4.3650, "mass": 366000.0, "color": Color(1.0, 0.95, 0.82) },
	{ "name": "Barnard's Star",   "ra": [17,57,48.5], "dec": [  4,41,36], "ly": 5.9630, "mass": 48000.0,  "color": Color(1.0, 0.65, 0.45) },
	{ "name": "Wolf 359",         "ra": [10,56,29.2], "dec": [  7, 0,53], "ly": 7.8560, "mass": 30000.0,  "color": Color(1.0, 0.55, 0.40) },
	{ "name": "Lalande 21185",    "ra": [11, 3,20.2], "dec": [ 35,58,12], "ly": 8.3070, "mass": 130000.0, "color": Color(1.0, 0.70, 0.50) },
	{ "name": "Sirius",           "ra": [ 6,45, 8.9], "dec": [-16,42,58], "ly": 8.6110, "mass": 686000.0, "color": Color(0.80, 0.90, 1.0) },
	{ "name": "Epsilon Eridani",  "ra": [ 3,32,55.8], "dec": [ -9,27,30], "ly": 10.475, "mass": 270000.0, "color": Color(1.0, 0.85, 0.60) },
	{ "name": "Tau Ceti",         "ra": [ 1,44, 4.1], "dec": [-15,56,15], "ly": 11.912, "mass": 261000.0, "color": Color(1.0, 0.95, 0.85) },
]

const _CACHE_PATH := "user://ephemeris_cache.json"
const _HOST := "https://ssd.jpl.nasa.gov/api/horizons.api"

# Live geocentric eq-AU positions, keyed by name. Seeded from the verified
# fallback so the scene is correct from frame 1; patched as Horizons replies.
var _pos := {}
var _today := ""
var _idx := 0           # which planet we're currently fetching
var _http: HTTPRequest
var live := false   # true once any live position has landed (HUD can show it)


func _ready() -> void:
	for p in PLANETS:
		_pos[p.name] = p.eq
	var d := Time.get_date_dict_from_system()
	_today = "%04d-%02d-%02d" % [d.year, d.month, d.day]

	if _load_cache():
		live = true
		return
	_fetch_all()


# --- public: real geocentric position in SCENE units (Y-up) -----------------
func scene_pos(name: String) -> Vector3:
	var eq: Vector3 = _pos.get(name, Vector3.ZERO)
	return Vector3(eq.x, eq.z, eq.y) * AU_TO_UNITS   # eq(x,y,z) -> scene(x,z,y)


# Star direction*radius on the backdrop shell (real RA/Dec, fixed radius).
const UNITS_PER_LY := 6324107.7   # 63241.077 AU/ly × AU_TO_UNITS — real interstellar scale

func star_scene_pos(star: Dictionary) -> Vector3:
	var ra := _hms_deg(star.ra) * PI / 180.0
	var dec := _dms_deg(star.dec) * PI / 180.0
	var eq := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
	return Vector3(eq.x, eq.z, eq.y) * STAR_SHELL_RADIUS

# Real galaxy position at the star's TRUE distance (a floating-origin destination
# you can actually fly to — the distance counts down as you approach).
func star_true_pos(star: Dictionary) -> Vector3:
	return star_scene_pos(star).normalized() * (float(star.ly) * UNITS_PER_LY)


func _hms_deg(hms: Array) -> float:
	return (float(hms[0]) + float(hms[1]) / 60.0 + float(hms[2]) / 3600.0) * 15.0

func _dms_deg(dms: Array) -> float:
	var sign := -1.0 if (float(dms[0]) < 0.0 or float(dms[1]) < 0.0 or float(dms[2]) < 0.0) else 1.0
	return sign * (abs(float(dms[0])) + abs(float(dms[1])) / 60.0 + abs(float(dms[2])) / 3600.0)


# --- live JPL Horizons fetch (serial; Horizons throttles parallel requests) --
func _fetch_all() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_idx = 0
	_fetch_next()


func _fetch_next() -> void:
	if _idx >= PLANETS.size():
		_save_cache()
		_http.queue_free()
		return
	if PLANETS[_idx].get("fixed", false):   # Earth is the origin — never fetched
		_idx += 1
		_fetch_next()
		return
	var err := _http.request(_url_for(PLANETS[_idx].id))
	if err != OK:
		push_warning("Ephemeris: request failed for %s (using fallback)" % PLANETS[_idx].name)
		_idx += 1
		_fetch_next()


func _url_for(id: String) -> String:
	# One epoch (today 00:00), geocentric, ICRF frame, position vector in AU.
	var tomorrow := _date_plus_one()
	var q := {
		"format": "json", "COMMAND": "'%s'" % id, "EPHEM_TYPE": "VECTORS",
		"CENTER": "'500@399'", "REF_PLANE": "FRAME", "OUT_UNITS": "AU-D",
		"VEC_TABLE": "1", "START_TIME": "'%s'" % _today,
		"STOP_TIME": "'%s'" % tomorrow, "STEP_SIZE": "'1 d'",
	}
	var parts := PackedStringArray()
	for k in q:
		parts.append("%s=%s" % [k, String(q[k]).uri_encode()])
	return _HOST + "?" + "&".join(parts)


func _on_reply(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		var eq = _parse_vectors(body.get_string_from_utf8())
		if eq != null:
			_pos[PLANETS[_idx].name] = eq
			live = true
	_idx += 1
	_fetch_next()


# Pull "X = .. Y = .. Z = .." (AU) from the $$SOE/$$EOE block of a Horizons reply.
func _parse_vectors(text: String):
	var json = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY or not json.has("result"):
		return null
	var result: String = json["result"]
	var soe := result.find("$$SOE")
	var eoe := result.find("$$EOE")
	if soe < 0 or eoe < 0:
		return null
	var block := result.substr(soe, eoe - soe)
	var re := RegEx.new()
	re.compile("X\\s*=\\s*([-\\d.E+]+)\\s+Y\\s*=\\s*([-\\d.E+]+)\\s+Z\\s*=\\s*([-\\d.E+]+)")
	var m := re.search(block)
	if m == null:
		return null
	return Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))


# --- date-stamped cache so a potato doesn't re-fetch 8 bodies every launch ---
func _load_cache() -> bool:
	if not FileAccess.file_exists(_CACHE_PATH):
		return false
	var f := FileAccess.open(_CACHE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or data.get("date", "") != _today:
		return false
	for name in data.get("bodies", {}):
		var a = data["bodies"][name]
		if a is Array and a.size() == 3:
			_pos[name] = Vector3(a[0], a[1], a[2])
	return true


func _save_cache() -> void:
	var bodies := {}
	for name in _pos:
		var v: Vector3 = _pos[name]
		bodies[name] = [v.x, v.y, v.z]
	var f := FileAccess.open(_CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({ "date": _today, "bodies": bodies }))


func _date_plus_one() -> String:
	var d := Time.get_date_dict_from_system()
	var unix := Time.get_unix_time_from_datetime_dict(d) + 86400
	var n := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [n.year, n.month, n.day]
