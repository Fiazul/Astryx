class_name PlanetData
extends Node
# Real planetary facts for the Details panel. Two layers:
#   1) BUNDLED — curated from NASA fact sheets (static; always available offline).
#   2) CACHE   — user://planet_data_cache.json, refreshed from the NASA Exoplanet
#      Archive at most once every REFRESH_DAYS. The game ALWAYS reads merged data
#      (cache wins over bundled), so a failed/never-run fetch just falls back.
#
# Solar-system facts don't change, so the periodic fetch only enriches the
# exoplanets (K2-18b, Proxima b, TRAPPIST-1 worlds). Non-blocking + best-effort.

const CACHE_PATH := "user://planet_data_cache.json"
const REFRESH_DAYS := 20
const TAP := "https://exoplanetarchive.ipac.caltech.edu/TAP/sync"

# Game body name -> NASA Exoplanet Archive pl_name (for the live refresh).
const EXO_NAMES := {
	"K2-18b": "K2-18 b", "Proxima b": "Proxima Cen b",
	"TRAPPIST-1b": "TRAPPIST-1 b", "TRAPPIST-1d": "TRAPPIST-1 d",
	"TRAPPIST-1e": "TRAPPIST-1 e", "TRAPPIST-1g": "TRAPPIST-1 g",
}

# Curated NASA fact sheets (nssdc.gsfc.nasa.gov/planetary/factsheet + JWST/archive).
const BUNDLED := {
	"Sun": {"type": "Star", "radius_km": 696340, "mass": "1.989×10³⁰ kg",
		"gravity": "274 m/s²", "day": "~25–35 days", "temp": "5,500 °C surface",
		"atmosphere": "Plasma — 73% H, 25% He", "moons": "—",
		"blurb": "A G-type main-sequence star holding 99.8% of the Solar System's mass."},
	"Mercury": {"type": "Planet", "radius_km": 2439, "mass": "3.30×10²³ kg",
		"gravity": "3.7 m/s²", "day": "1,408 h", "year": "88 days", "temp": "−173 to 427 °C",
		"atmosphere": "Trace — O, Na, H, He", "moons": 0,
		"blurb": "Smallest planet; a cratered, airless world with wild temperature swings."},
	"Venus": {"type": "Planet", "radius_km": 6051, "mass": "4.87×10²⁴ kg",
		"gravity": "8.9 m/s²", "day": "5,832 h", "year": "225 days", "temp": "464 °C",
		"atmosphere": "96.5% CO₂, 3.5% N₂ — crushing", "moons": 0,
		"blurb": "A runaway greenhouse; hotter than Mercury under sulfuric-acid clouds."},
	"Earth": {"type": "Planet", "radius_km": 6371, "mass": "5.97×10²⁴ kg",
		"gravity": "9.8 m/s²", "day": "24 h", "year": "365.25 days", "temp": "15 °C avg",
		"atmosphere": "78% N₂, 21% O₂, 1% Ar", "moons": 1,
		"blurb": "The only known world with liquid surface water and life."},
	"Mars": {"type": "Planet", "radius_km": 3389, "mass": "6.42×10²³ kg",
		"gravity": "3.7 m/s²", "day": "24.6 h", "year": "687 days", "temp": "−65 °C avg",
		"atmosphere": "95% CO₂, thin", "moons": 2,
		"blurb": "The Red Planet — rusty dust, polar ice, and the tallest volcano in the system."},
	"Jupiter": {"type": "Planet", "radius_km": 69911, "mass": "1.90×10²⁷ kg",
		"gravity": "24.8 m/s²", "day": "9.9 h", "year": "11.9 years", "temp": "−110 °C cloud-top",
		"atmosphere": "90% H₂, 10% He", "moons": 95,
		"blurb": "The giant — a banded gas world with a 350-year-old storm, the Great Red Spot."},
	"Saturn": {"type": "Planet", "radius_km": 58232, "mass": "5.68×10²⁶ kg",
		"gravity": "10.4 m/s²", "day": "10.7 h", "year": "29.4 years", "temp": "−140 °C cloud-top",
		"atmosphere": "96% H₂, 3% He", "moons": 146,
		"blurb": "The ringed jewel — a gas giant so light it would float in water."},
	"Uranus": {"type": "Planet", "radius_km": 25362, "mass": "8.68×10²⁵ kg",
		"gravity": "8.7 m/s²", "day": "17.2 h", "year": "84 years", "temp": "−195 °C",
		"atmosphere": "83% H₂, 15% He, 2% CH₄", "moons": 28,
		"blurb": "An ice giant tipped on its side, rolling around the Sun at a 98° tilt."},
	"Neptune": {"type": "Planet", "radius_km": 24622, "mass": "1.02×10²⁶ kg",
		"gravity": "11.0 m/s²", "day": "16.1 h", "year": "165 years", "temp": "−200 °C",
		"atmosphere": "80% H₂, 19% He, 1% CH₄", "moons": 16,
		"blurb": "The windiest world — 2,000 km/h gales on a deep-blue ice giant."},
	"K2-18b": {"type": "Exoplanet", "radius_km": 16800, "mass": "8.6 M⊕",
		"gravity": "~12 m/s²", "year": "33 days", "temp": "−23 °C (est.)",
		"atmosphere": "H₂-rich — CH₄ & CO₂ (JWST)", "moons": "?",
		"blurb": "A 'hycean' candidate 124 ly away; JWST found carbon-bearing molecules."},
	"Proxima b": {"type": "Exoplanet", "radius_km": 7160, "mass": "1.1 M⊕",
		"gravity": "~11 m/s²", "year": "11.2 days", "temp": "−39 °C (est.)",
		"atmosphere": "Unknown", "moons": "?",
		"blurb": "The nearest exoplanet (4.24 ly), in its red dwarf's habitable zone."},
	"TRAPPIST-1e": {"type": "Exoplanet", "radius_km": 5800, "mass": "0.69 M⊕",
		"gravity": "~8 m/s²", "year": "6.1 days", "temp": "−22 °C (est.)",
		"atmosphere": "Unknown — rocky", "moons": "?",
		"blurb": "One of seven Earth-sized worlds at TRAPPIST-1; among the most habitable."},
	# --- Nearby real stars (flyable destinations) ---
	"Proxima Centauri": {"type": "Star", "distance": "4.25 ly", "spectral": "M5.5V red dwarf",
		"blurb": "The closest star to the Sun; a flare star hosting Proxima b."},
	"Alpha Centauri": {"type": "Star", "distance": "4.37 ly", "spectral": "G2V + K1V + M5.5V",
		"blurb": "The nearest star SYSTEM — a triple, with Sun-like Alpha Cen A & B."},
	"Barnard's Star": {"type": "Star", "distance": "5.96 ly", "spectral": "M4V red dwarf",
		"blurb": "Has the largest proper motion of any star — it races across our sky."},
	"Wolf 359": {"type": "Star", "distance": "7.86 ly", "spectral": "M6V red dwarf",
		"blurb": "One of the faintest, lowest-mass stars known near the Sun."},
	"Lalande 21185": {"type": "Star", "distance": "8.31 ly", "spectral": "M2V red dwarf",
		"blurb": "A nearby red dwarf in Ursa Major with known planets."},
	"Sirius": {"type": "Star", "distance": "8.61 ly", "spectral": "A1V + white dwarf",
		"blurb": "The brightest star in Earth's night sky, with a white-dwarf companion (Sirius B)."},
	"Epsilon Eridani": {"type": "Star", "distance": "10.48 ly", "spectral": "K2V",
		"blurb": "A young Sun-like star ringed by a dusty debris disk."},
	"Tau Ceti": {"type": "Star", "distance": "11.91 ly", "spectral": "G8V",
		"blurb": "A stable, Sun-like star and a long-time target in the search for life."},
}

var _cache := {}      # name -> dict (live-fetched overrides)
var _http: HTTPRequest


func _ready() -> void:
	_load_cache()
	if _needs_refresh():
		_refresh()


# Merged facts for a body (cache over bundled), or null if we have nothing.
func get_facts(name: String):
	var base = BUNDLED.get(name, null)
	var over = _cache.get(name, null)
	if base == null and over == null:
		return null
	var out := {}
	if base != null:
		out.merge(base)
	if over != null:
		out.merge(over, true)   # live values win
	return out

func has(name: String) -> bool:
	return BUNDLED.has(name) or _cache.has(name)


# ---------------------------------------------------------------------------
func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_cache = data

func _needs_refresh() -> bool:
	var last := float(_cache.get("_fetched", 0.0))
	return Time.get_unix_time_from_system() - last > REFRESH_DAYS * 86400.0

func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_cache))


# Best-effort live refresh of the exoplanets from the NASA Exoplanet Archive.
func _refresh() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_refresh_done)
	var names := []
	for n in EXO_NAMES.values():
		names.append("'%s'" % n)
	var q := "select pl_name,pl_rade,pl_bmasse,pl_eqt,pl_orbper from ps where pl_name in (%s)" % ", ".join(names)
	var url := "%s?query=%s&format=json" % [TAP, q.uri_encode()]
	var err := _http.request(url)
	if err != OK:
		_http.queue_free()

func _on_refresh_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		var rows = JSON.parse_string(body.get_string_from_utf8())
		if rows is Array:
			var archive_to_game := {}
			for k in EXO_NAMES:
				archive_to_game[EXO_NAMES[k]] = k
			for row in rows:
				var game_name = archive_to_game.get(row.get("pl_name", ""), "")
				if game_name == "":
					continue
				var upd := {}
				if row.get("pl_rade") != null:
					upd["radius_km"] = int(round(float(row["pl_rade"]) * 6371.0))
				if row.get("pl_bmasse") != null:
					upd["mass"] = "%.2f M⊕" % float(row["pl_bmasse"])
				if row.get("pl_eqt") != null:
					upd["temp"] = "%.0f °C (eq.)" % (float(row["pl_eqt"]) - 273.15)
				if row.get("pl_orbper") != null:
					upd["year"] = "%.1f days" % float(row["pl_orbper"])
				if not upd.is_empty():
					_cache[game_name] = upd
			_cache["_fetched"] = Time.get_unix_time_from_system()
			_save_cache()
			print("[planet_data] refreshed %d exoplanets from NASA Exoplanet Archive" % rows.size())
	if _http != null:
		_http.queue_free()
