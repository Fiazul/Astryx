extends Node3D
# Space Explorer — root orchestrator.
#
# Everything is spawned from code (the .tscn is a one-node stub) and wired with
# plain references — no @export drag-and-drop, so it just works on open.
#
# Floating origin: the Ship node stays pinned at (0,0,0) and only rotates. Its
# "true" position is tracked as data (ship.true_pos). Every body is rendered at
# (body.true_pos - ship.true_pos), and the starfield is a fixed backdrop on the
# world root (NOT a child of the ship), so it doesn't spin with the ship.
#
# Update order matters and is driven explicitly here: the ship integrates its
# motion first, then the planet system reads the fresh true_pos, then the HUD.

var ship: Ship
var planets: PlanetSystem
var props: Props
var hud: HUD
var eph: Ephemeris
var wormhole: Wormhole
var combat: Combat
var audio: GameAudio
var settings: SettingsMenu
var map: StarMap
var planet_data: PlanetData
var planet_info: PlanetInfo
var navigator: Navigator
var minimap: MiniMap
var codex: Codex
var _nav_target := ""         # Tab aim-help target (basic guidance; lowest priority)
var _nav_locked := ""         # LOCKED map waypoint (orange) — persists until cancelled
var coins := 0                # player currency; persisted to the profile
var _claimed := {}            # body name -> true once its capture reward is claimed
const PROFILE_PATH := "user://profile.cfg"
const CAPTURE_REWARD := 100
const NAV_COST := 40          # coins to buy a navigator (map Navigate / Auto-pilot)
var _nav_off := false         # NAV button: stop the Survey guide + waypoint marker entirely
var _was_boost_blocked := false   # edge-trigger for the "boost unavailable" toast
var _scan := 0.0             # scan progress 0..1 of the nearest body
var _scan_name := ""
const SCAN_SECONDS := 2.0
const SCAN_RANGE := 1500.0    # how close you must be to start a capture (generous)
const GUARD_RANGE := 2500.0   # approach a guarded body within this → its guardians activate
const GUARD_COUNT := 5        # guardian aliens per guarded body (placeholder meshes for now)
var _env: Environment

var docked := false
var _dock_in_range := false
var current_system := SystemDB.SOL
var _music: AudioStreamPlayer
const MUSIC_DB := -13.0    # bgm level once faded in — louder/present (engine ducks under it)
const MUSIC_OFF_DB := -60.0  # silent end of the fade
const MUSIC_FADE := 1.2    # fade speed (per second) for the gentle in/out

# Where the player starts, in absolute scene units (1u = 0.1 AU). You launch
# FROM Earth (the origin), parked just off it on the side away from the Sun, so
# you open looking at Earth up close with the Sun a bright disc in the distance
# beyond it (~13u). (Sun direction in scene ≈ (0.16, 0.39, 0.91).)
const START_POS := Vector3(-0.81, -1.97, -4.53)


func _ready() -> void:
	_load_profile()
	_setup_environment()
	_setup_music()

	# Fixed star backdrop on the world root (never rotates with the ship).
	add_child(Starfield.new())

	# Player ship (visual + flight). Pinned at origin; we move the universe.
	ship = Ship.new()
	add_child(ship)
	ship.true_pos = START_POS
	ship.face_toward(-START_POS)   # open looking at Earth (the origin)

	# Chase camera lives on the world root; the ship drives its transform each
	# frame (with a little lag) so it isn't rigidly bolted to the hull.
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 100000.0
	add_child(cam)
	ship.camera = cam

	# Real positions: live JPL Horizons for Sun+planets, catalog for stars.
	eph = Ephemeris.new()
	add_child(eph)

	# Planets / stars as dot->body LOD (reads real positions from eph).
	planets = PlanetSystem.new()
	planets.eph = eph
	add_child(planets)

	# Two shadowless lights give the ship/Earth/station CONTRAST and form without
	# blowing them out: a bright warm KEY from the Sun's direction, plus a dim
	# cool FILL from roughly the opposite side so the shadowed half isn't black.
	# This lets ambient + self-emission stay low, so the hull keeps its panel
	# detail instead of washing pale. Stars/planets are emissive/unshaded, so the
	# "dots and glow" look is untouched. Shadows off = nearly free on a potato.
	var sun_dir: Vector3 = eph.scene_pos("Sun").normalized()
	var sun_light := DirectionalLight3D.new()
	sun_light.light_energy = 1.05
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	sun_light.shadow_enabled = false
	add_child(sun_light)
	sun_light.look_at(-sun_dir, Vector3.UP)   # rays travel from the Sun outward

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.72, 1.0)   # cool counter-light
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at(sun_dir + Vector3(0.0, -0.6, 0.0), Vector3.UP)  # opposite-ish, from below

	# Hand-placed GLB landmarks (station, planet, astronaut) near Earth.
	props = Props.new()
	add_child(props)

	# Wormhole portal + tunnel transit (interstellar travel between systems).
	wormhole = Wormhole.new()
	add_child(wormhole)
	wormhole.set_ship(ship)
	wormhole.set_system(current_system)

	# Code-spawned SFX (fire / engine / explosion).
	audio = GameAudio.new()
	add_child(audio)
	ship.audio = audio   # the ship drives the engine voice from fly()

	# Combat: alien dogfighters + your bolts (left-click to fire).
	combat = Combat.new()
	add_child(combat)
	combat.audio = audio
	combat.planets = planets                            # bolts curve through gravity wells
	combat.reset(SystemDB.is_hostile(current_system))   # Sol starts peaceful
	combat.player_hp = ship.max_hp                      # start at the hull's full defence
	ship.combat_ref = combat                            # shared energy pools (boost)

	# HUD labels (light-year distance, speed, nearest body).
	hud = HUD.new()
	add_child(hud)
	hud.ship = ship
	hud.ship_ref = ship          # used by the HUD layout editor to free/recapture the cursor
	hud.planets = planets
	hud.combat = combat
	hud.teleport_button.pressed.connect(teleport_home)
	hud.ship_selected.connect(_on_hangar_pick)   # click a hangar row to swap ship

	# Discovery progress (persisted) + real planet facts + the Details panel.
	codex = Codex.new()
	add_child(codex)
	hud.codex = codex
	planet_data = PlanetData.new()
	add_child(planet_data)
	planet_info = PlanetInfo.new()
	planet_info.data = planet_data
	planet_info.planets = planets
	planet_info.ship = ship
	planet_info.codex = codex
	planet_info.main = self
	add_child(planet_info)
	hud.details_button.pressed.connect(planet_info.open_for_nearest)
	# Codex logbook (C): browse discovered bodies, click to read.
	var codex_panel := CodexPanel.new()
	codex_panel.codex = codex
	codex_panel.info = planet_info
	codex_panel.ship = ship
	add_child(codex_panel)
	# Wire the styled top-right control bar to the panels.
	hud.codex_button.pressed.connect(codex_panel.toggle)

	# Settings overlay (Esc): volume, sensitivity, glow, render scale, fullscreen.
	settings = SettingsMenu.new()
	settings.ship = ship
	settings.env = _env
	settings.hud = hud           # for the "Edit HUD Layout" button
	add_child(settings)

	# Waypoint navigator (Tab) + corner radar.
	var nav_canvas := CanvasLayer.new()
	add_child(nav_canvas)
	navigator = Navigator.new()
	nav_canvas.add_child(navigator)
	minimap = MiniMap.new()
	minimap.position = Vector2(24, 466)
	nav_canvas.add_child(minimap)
	hud.register_movable("radar", minimap)   # make the corner radar drag-positionable too

	# Star map (M): click a system to jump.
	map = StarMap.new()
	map.main = self
	add_child(map)
	hud.map_button.pressed.connect(map.toggle)
	hud.settings_button.pressed.connect(settings.toggle)
	hud.nav_button.pressed.connect(toggle_nav)
	hud.cancel_nav_button.pressed.connect(cancel_locked_nav)


func _process(delta: float) -> void:
	ship.fly(delta)
	planets.refresh(ship.true_pos, delta)
	ship.speed_limit = planets.speed_limit   # eases the ship down near a body
	ship.nearest_dir = planets.nearest_dir   # only ease down when approaching it
	ship.nearest_dist = planets.nearest_dist # warp ships ease out of warp on arrival
	ship.star_field_dist = planets.star_dist # FTL only unlocks beyond the star's gravity field
	ship.gravity = planets.gravity           # gentle pull toward bodies
	props.update(ship.true_pos, delta)
	ship.struct_limit = props.struct_speed_limit   # strict speed cap near stations/probes
	if wormhole.update(ship.true_pos, delta):
		_arrive(wormhole.dest_id)
	# Combat runs in normal flight (not mid-transit, not docked). Docking at a
	# station is a safe harbor — the fight pauses so you can swap ships in peace.
	var firing := false
	if not ship.transiting and not docked:
		var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		firing = captured \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not ship.is_hypersonic()        # no shooting at hypersonic speed
		# Right-click fires the nose laser beam (laser-equipped hulls only, e.g. Raptor II).
		var laser := captured and ship.has_laser \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and not ship.is_hypersonic()
		combat.update(ship, firing, delta, laser)
		ship.combat_lock = combat.in_combat()       # no interstellar speed mid-fight
	else:
		ship.combat_lock = false
	hud.firing = firing                          # blooms the dynamic crosshair
	hud.coins = coins
	hud.set_cancel_nav_visible(_nav_locked != "")
	# Tell the player (once) when they try to boost in a slow-zone where it does nothing.
	if ship.boost_blocked and not _was_boost_blocked:
		hud.toast = "⚠  Boost unavailable here — clear the slow-zone first"
		hud.toast_t = 1.6
	_was_boost_blocked = ship.boost_blocked
	_update_dock_ui()
	if ship.autopilot:
		ship.autopilot_target = ship.true_pos + planets.rel_of(ship.autopilot_name)
	_update_navigator()
	_update_minimap()
	_update_scan(delta)
	_update_music(delta)
	hud.refresh()


# Music only while you're travelling — pause when you've sat still a moment.
func _update_music(delta: float) -> void:
	if _music == null:
		return
	# The bgm is gated by the engine's continuous-drive clock: silent for the first
	# MUSIC_IN_TIME (8s) of a run — engine only — then it fades in. It never plays on
	# the platform or in a wormhole (drive_time resets to 0 there).
	var want := audio != null and not docked and not ship.transiting \
		and audio.drive_time() >= GameAudio.MUSIC_IN_TIME
	if want and _music.stream_paused:
		_music.stream_paused = false
	# Fade in/out smoothly rather than snapping on.
	var target_db := MUSIC_DB if want else MUSIC_OFF_DB
	_music.volume_db = lerpf(_music.volume_db, target_db, clampf(MUSIC_FADE * delta, 0.0, 1.0))
	if not want and _music.volume_db <= MUSIC_OFF_DB + 1.0:
		_music.stream_paused = true   # fully faded out — pause to idle


# Jump straight to a system from the star map (fast-travel, no tunnel).
func travel_to(id: String) -> void:
	if id == current_system:
		return
	_arrive(id)
	ship._set_capture(true)


# --- Corner radar: ship-relative blips for bodies / Earth / nearest / wormhole ---
func _update_minimap() -> void:
	if minimap == null:
		return
	if ship.transiting:
		minimap.set_blips([])
		return
	var binv := ship.transform.basis.inverse()
	var blips := []
	for bname in planets.targetables():
		var rel: Vector3 = planets.rel_of(bname)
		var role := MiniMap.BODY
		if codex.is_discovered(bname):
			role = MiniMap.CAPTURED                  # captured → gold beacon on the radar
		if bname == "Earth" and current_system == SystemDB.SOL:
			role = MiniMap.HOME
		elif bname == planets.nearest_name:
			role = MiniMap.NEAREST
		blips.append({ "local": binv * rel, "dist": rel.length(), "role": role, "name": bname })
	var wrel: Vector3 = wormhole.portal_rel(ship.true_pos)
	blips.append({ "local": binv * wrel, "dist": wrel.length(), "role": MiniMap.WORMHOLE, "name": "Wormhole" })
	minimap.set_blips(blips)


# --- Capture the nearest body (hold V within range). Guarded bodies (≈80%, never in
# peaceful Sol) spawn alien guardians you must clear first. Capture = beacon + rank. ---
func _update_scan(delta: float) -> void:
	hud.toast_t = maxf(hud.toast_t - delta, 0.0)
	var name := planets.nearest_name
	# Hub gate-suns (✦) and the Interstellar hub are travel markers — never captured or
	# guarded. Skip the whole flow there (no monsters in the hub, no fake captures).
	if not _capturable(name):
		_scan = maxf(_scan - delta * 2.0, 0.0)
		if _scan <= 0.0:
			_scan_name = ""
		hud.scan_progress = _scan
		hud.scan_name = _scan_name
		hud.scan_hint = ""
		return
	var captured := codex.is_discovered(name)
	var guarded := current_system != SystemDB.SOL and _is_guarded(name)

	# Approaching a guarded, un-captured body spawns its identity boss — but ONLY when
	# there's no boss currently alive and it's a different body. Without the
	# "not guard_boss_alive()" guard, a nearest_name that flips between two close bodies
	# (e.g. TRAPPIST's packed planets) would re-spawn a boss GLB every frame and freeze.
	if guarded and not captured and planets.nearest_dist < GUARD_RANGE \
			and combat.guard_body != name and not combat.guard_boss_alive() \
			and not ship.transiting and not docked:
		# Bigger bodies (stars) get a tougher boss + bigger waves (power scales with radius).
		var power: float = clampf(planets.nearest_radius / 7.0, 1.0, 3.0)
		combat.set_guardians(ship.true_pos + planets.rel_of(name), name, power)

	# Capturable once THIS body's boss is dead (its summoned fleet is endless till then).
	var guards := combat.guardians_alive()    # live hostile count (fixes the "0 hostiles" bug)
	var clear := not guarded or (combat.guard_body == name and not combat.guard_boss_alive())

	# Capture when within reach of the body's SURFACE (range scales with its size, so a
	# giant star/nebula is grabbable without diving to its centre).
	var cap_range := planets.nearest_radius + SCAN_RANGE
	var in_range := not docked and not ship.transiting and name != "" \
		and planets.nearest_dist < cap_range \
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var fresh := in_range and not captured and clear

	# Raptor 2 Neo auto-captures any clear body in range — no key needed.
	if fresh and (ship.auto_capture or Input.is_physical_key_pressed(KEY_V)):
		if name != _scan_name:
			_scan_name = name
			_scan = 0.0
		_scan = minf(_scan + delta / SCAN_SECONDS, 1.0)
		if _scan >= 1.0:
			if codex.discover(name):
				hud.toast = "✦  CAPTURED  %s   ·   press G and Claim %d coins" % [name, CAPTURE_REWARD]
				hud.toast_t = 4.0
				if combat.guard_body == name:
					combat.clear_guardians()
			_scan = 0.0
			_scan_name = ""
	else:
		_scan = maxf(_scan - delta * 2.0, 0.0)
		if _scan <= 0.0:
			_scan_name = ""

	hud.scan_progress = _scan
	hud.scan_name = _scan_name
	if name == "" or captured:
		hud.scan_hint = ""
	elif guarded and not clear:
		hud.scan_hint = "⚠  Defeat the fleet to capture %s  ·  %d defeated · %d hostiles left — kill the BOSS" % [name, combat.zone_kills, guards]
	elif in_range and _scan <= 0.0:
		hud.scan_hint = ("» auto-capturing %s «" % name) if ship.auto_capture else ("» hold V to capture %s «" % name)
	else:
		hud.scan_hint = ""


# Open the scanner detail panel for a specific body (called by the M-map list).
func open_details_for(body_name: String) -> void:
	if planet_info != null:
		planet_info.open_for(body_name)


# Lock the nav waypoint to a body (orange; persists until cancelled). PAID navigator.
func set_nav_target(body_name: String) -> void:
	if not buy_navigator():
		return
	_nav_off = false
	_nav_locked = body_name
	if hud != null:
		hud.set_nav_stopped(false)


# Auto-pilot: locks the orange waypoint AND flies there hands-off. PAID navigator.
func start_autopilot(body_name: String) -> void:
	if not buy_navigator():
		return
	_nav_off = false
	_nav_locked = body_name
	if hud != null:
		hud.set_nav_stopped(false)
	ship.start_autopilot(body_name)


# --- Coins / rewards ---
# A captured body's 100-coin reward isn't auto-given — the player CLAIMS it from the
# Details (G) panel. Claimable = captured but not yet claimed.
func can_claim(body_name: String) -> bool:
	return codex != null and codex.is_discovered(body_name) and not _claimed.has(body_name)

func claim_reward(body_name: String) -> int:
	if not can_claim(body_name):
		return 0
	coins += CAPTURE_REWARD
	_claimed[body_name] = true
	_save_profile()
	return CAPTURE_REWARD

# Map Navigate / Auto-pilot is a PAID navigator service. Returns true if it could pay.
func buy_navigator() -> bool:
	if coins < NAV_COST:
		hud.toast = "Not enough coins for a navigator (%d / %d)" % [coins, NAV_COST]
		hud.toast_t = 2.5
		return false
	coins -= NAV_COST
	_save_profile()
	return true


# --- Player profile (persisted to disk; will hold more than coins later) ---
func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		coins = int(cfg.get_value("player", "coins", 0))
		_claimed.clear()
		for n in cfg.get_value("player", "claimed", []):
			_claimed[n] = true

func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)            # keep any other keys we add later
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "claimed", _claimed.keys())
	cfg.save(PROFILE_PATH)


# A real body you can capture: not the Interstellar hub, not a hub gate-sun (✦).
func _capturable(body_name: String) -> bool:
	return body_name != "" and current_system != SystemDB.INTERSTELLAR and not body_name.contains("✦")

# ≈80% of bodies are guarded (deterministic per name, so it's stable across visits).
func _is_guarded(body_name: String) -> bool:
	return (hash(body_name) % 5 + 5) % 5 != 0

# Survey rank from how many bodies you've captured (the reward ladder).
func _rank_title() -> String:
	var n := codex.count()
	if n >= 24: return "Star-Marshal"
	elif n >= 14: return "Cartographer"
	elif n >= 6: return "Surveyor"
	return "Cadet"


# --- Navigation waypoint (Tab cycles: off -> each body -> wormhole -> off) ---
# Tab targeting, prioritised by AIM: the first press locks onto whatever you're
# pointing at (the targetable most aligned with your view); each further press steps
# to the next-most-aligned; past the last returns to the auto Survey guide.
func _cycle_nav_target() -> void:
	var cands := _aim_sorted_targets()
	if cands.is_empty():
		_nav_target = ""
		return
	var idx: int = cands.find(_nav_target)
	if idx < 0:
		_nav_target = cands[0]                 # → what you're aiming at
	elif idx + 1 < cands.size():
		_nav_target = cands[idx + 1]           # → next-most-aligned
	else:
		_nav_target = ""                       # cycled through all → back to auto guide

# Targetable names sorted by how closely they sit to the centre of your view.
func _aim_sorted_targets() -> Array:
	var fwd: Vector3 = -ship.camera.global_transform.basis.z
	var list := []
	for bname in planets.targetables():
		var rel: Vector3 = planets.rel_of(bname)
		if rel.length() > 0.001:
			list.append({ "name": bname, "align": fwd.dot(rel.normalized()) })
	var wrel: Vector3 = wormhole.portal_rel(ship.true_pos)
	if wrel.length() > 0.001:
		list.append({ "name": "Wormhole", "align": fwd.dot(wrel.normalized()) })
	list.sort_custom(func(a, b): return a.align > b.align)
	var names := []
	for it in list:
		names.append(it.name)
	return names

# NAV button: stop / resume the Survey guide and waypoint marker (the orientation
# gizmo always stays). Also clears any manual Tab target when stopping.
func toggle_nav() -> void:
	# N / NAV only toggles the FREE Survey guide. A paid locked waypoint is NOT
	# affected — it's cancelled only by the on-screen Cancel Nav button.
	_nav_off = not _nav_off
	if _nav_off:
		_nav_target = ""
	hud.set_nav_stopped(_nav_off)
	_update_navigator()


# Cancel a locked (paid) map waypoint + any autopilot (the on-screen Cancel Nav button).
func cancel_locked_nav() -> void:
	_nav_locked = ""
	ship.autopilot = false
	hud.set_nav_stopped(false)
	_update_navigator()


func _update_navigator() -> void:
	if navigator == null:
		return
	var tname: String
	var rel: Vector3
	if ship.transiting:
		navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")   # gizmo only
		hud.set_objective("")
		return
	elif _nav_locked != "":
		# LOCKED (paid) map waypoint — orange, top priority, ignores the N toggle,
		# stays until the Cancel Nav button is clicked.
		tname = _nav_locked
		rel = wormhole.portal_rel(ship.true_pos) if tname == "Wormhole" else planets.rel_of(tname)
		var ld := _fmt_nav_dist(rel.length())
		navigator.update_nav(ship.camera, true, rel, tname, ld, true)
		hud.set_objective("◆  LOCKED  %s   %s" % [tname, ld])
		return
	elif _nav_off:
		navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")   # gizmo only
		hud.set_objective("")
		return
	elif _nav_target != "":
		# Tab aim-help target (basic guidance), picked by aim.
		tname = _nav_target
		rel = wormhole.portal_rel(ship.true_pos) if tname == "Wormhole" else planets.rel_of(tname)
	else:
		# Default: the Survey guide always points at the nearest unclaimed star, so
		# the player is never lost. Tab overrides it; cycling past the end returns here.
		var obj := _current_objective()
		if obj.is_empty():
			navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")
			hud.set_objective("")
			return
		tname = obj.name
		rel = obj.rel
	var dist_txt := _fmt_nav_dist(rel.length())
	navigator.update_nav(ship.camera, true, rel, tname, dist_txt)
	hud.set_objective("→  %s   %s" % [tname, dist_txt])


# The current guidance objective:
#  • In the Interstellar hub — the nearest destination gate (a system to dive into).
#  • In any normal system — the nearest UN-surveyed star to fly to. Once they're all
#    surveyed, fall back to guiding you to the exit gate so you know to move on.
func _current_objective() -> Dictionary:
	# CONTINUOUS cursor targeting: suggest whatever the CROSSHAIR is over — the body
	# whose on-screen position is nearest screen-centre (not the camera axis, which is
	# offset by the chase cam). Aim the cursor at things to read them; no Tab babysitting.
	if current_system == SystemDB.INTERSTELLAR:
		return _nearest_gate_objective()
	var cam := ship.camera
	if cam == null:
		return _nearest_gate_objective()
	var center: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var best := ""
	var best_px := 240.0              # body must be within this many px of the crosshair
	var best_rel := Vector3.ZERO
	for bname in planets.targetables():
		if not _capturable(bname):
			continue
		var rel: Vector3 = planets.rel_of(bname)
		if rel.length() < 0.001 or cam.is_position_behind(rel):
			continue
		var px: float = cam.unproject_position(rel).distance_to(center)
		if px < best_px:
			best_px = px
			best = bname
			best_rel = rel
	if best != "":
		return { "name": best, "rel": best_rel }
	return _nearest_gate_objective()

func _nearest_gate_objective() -> Dictionary:
	if wormhole == null:
		return {}
	var np := wormhole.nearest_portal(ship.true_pos)
	return {} if np.is_empty() else { "name": str(np.name), "rel": np.rel }

func _fmt_nav_dist(u: float) -> String:
	var au := u * 0.01
	if au >= 1000.0:
		return "%.2f ly" % (au / 63241.077)
	elif au >= 0.05:
		return "%.2f AU" % au
	return "%.0f u" % u


func teleport_home() -> void:
	_arrive(SystemDB.SOL)              # instant jump back to Earth (no transit)
	ship._set_capture(true)


# Emerge from a wormhole in a new system: swap bodies, hard-reset the ship to a
# small LOCAL coord (so float precision is never stressed), re-aim the portal.
func _arrive(system_id: String) -> void:
	current_system = system_id
	planets.load_system(SystemDB.bodies(system_id))
	planets.speed_zones = (system_id == SystemDB.SOL)   # planet safe-zone limits: Sol only
	ship.true_pos = SystemDB.arrival_pos(system_id)
	ship.transiting = false
	ship.face_toward(-ship.true_pos)          # look back toward the system's star
	wormhole.set_system(system_id)
	props.set_system(system_id)                    # show this system's stations/probes
	# A large alien swarm haunts every star except peaceful Sol; Vortex (the boss)
	# still only holds the true hostile Alien zone.
	# Only the hostile Alien zone gets an always-on respawning swarm. Every other star
	# system is quiet until you approach a guarded body, which spawns ONE big boss you
	# kill once (the per-body guardians, no respawn).
	var fight := SystemDB.is_hostile(system_id)
	combat.reset(fight, SystemDB.is_hostile(system_id))
	combat.player_hp = ship.max_hp
	_nav_target = ""                               # clear the waypoint in the new system
	ship.autopilot = false                         # don't keep flying to an old-system target
	if docked:
		_set_docked(false)
	hud.origin_name = SystemDB.display_name(system_id) if system_id != SystemDB.SOL else "Earth"
	print("[wormhole] arrived at %s — ship.true_pos.length()=%.2f (must be small)"
		% [SystemDB.display_name(system_id), ship.true_pos.length()])


# --- Docking at the station + ship swap ---
# How far out (beyond dock_range) the landing zone begins force-slowing the ship.
const DOCK_SLOW_MARGIN := 40.0

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key == KEY_F:
		# One interact key: undock if docked, else open the wormhole if near it,
		# else dock if near the station.
		if docked:
			_set_docked(false)
		elif wormhole.in_range(ship.true_pos):
			wormhole.start_transit()
			ship.transiting = true
		elif _dock_in_range:
			_set_docked(true)
	elif key == KEY_TAB:
		_cycle_nav_target()
		get_viewport().set_input_as_handled()
	elif key == KEY_NUMLOCK:
		# Num Lock = auto-cruise: hold W + Shift hands-free until toggled off.
		ship.auto_cruise = not ship.auto_cruise
		hud.toast = "AUTO-CRUISE  ON  ·  hands-free W + boost" if ship.auto_cruise else "AUTO-CRUISE  OFF"
		hud.toast_t = 2.0
	elif key == KEY_N:
		toggle_nav()          # keyboard shortcut for the ⊘ NAV stop/resume button
	elif key == KEY_X:
		# Raptor only: toggle Combat <-> Warp mode.
		var mode := ship.toggle_warp_mode()
		if mode != "":
			hud.toast = "RAPTOR  ·  %s MODE" % mode
			hud.toast_t = 2.5
	elif key == KEY_ESCAPE and not ship.transiting and not ship.frozen:
		# Esc = release the mouse; press again to re-capture (back to flight).
		ship._set_capture(Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED)
	elif key == KEY_H and not ship.transiting:
		teleport_home()
	elif docked and key >= KEY_1 and key <= KEY_9:
		ship.swap_ship(key - KEY_1)
		combat.player_hp = ship.max_hp   # new hull -> its full defence


func _set_docked(d: bool) -> void:
	docked = d
	ship.set_frozen(d)


func _update_dock_ui() -> void:
	# Wormhole transit takes over the screen with its countdown.
	if ship.transiting:
		var rem := wormhole.transit_remaining()
		hud.set_prompt("")
		hud.set_hangar(false, PackedStringArray(), 0, "")
		hud.set_menu("— WORMHOLE TRANSIT —\n\n→ %s   ·   %.0f ly\n(light would take %.0f years)\n\nArriving in  %d:%02d"
			% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly, wormhole.dest_ly,
			int(rem) / 60, int(rem) % 60])
		return

	hud.set_menu("")
	# Docking: every system with a station has one (Earth + each exoplanet station).
	var dock_dist := (props.dock_pos - ship.true_pos).length() \
		if props.has_dock else INF
	_dock_in_range = dock_dist < props.dock_range
	# Force-slow the ship as it enters the landing zone (smooth, proximity-based):
	# 0 at the outer edge (dock_range + DOCK_SLOW_MARGIN), 1 once inside the pad.
	ship.dock_approach = clampf(1.0 - (dock_dist - props.dock_range) / DOCK_SLOW_MARGIN, 0.0, 1.0) \
		if dock_dist < INF else 0.0
	if docked:
		hud.set_prompt("")
		hud.set_hangar(true, _ship_names(), ship.current_index(), props.dock_name)
	else:
		hud.set_hangar(false, PackedStringArray(), 0, "")
		if _dock_in_range:
			hud.set_prompt("» Press F to dock at %s «" % props.dock_name)
		elif props.probe_in_range:
			hud.set_prompt(_probe_readout())   # drift up to a probe -> monster data
		elif wormhole.in_range(ship.true_pos):
			hud.set_prompt("» Press F to enter the wormhole to %s  (%.0f ly) «"
				% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly])
		else:
			hud.set_prompt("")


# Probe scan readout: the "monster data" a drifting probe reports for its sector
# (how many hostiles, whether Vortex is here, your kill tally). Nothing else.
func _probe_readout() -> String:
	var t := combat.threat_report()
	var out := "◇ PROBE SCAN · %s ◇\n" % SystemDB.display_name(current_system)
	if int(t.total) <= 0:
		return out + "No hostiles detected in this sector."
	out += "Hostiles: %d / %d active\n" % [t.alive, t.total]
	var boss: Dictionary = t.boss
	if boss.alive:
		out += "⚠ VORTEX present — %d/%d HP\n" % [boss.hp, boss.max]
	return out + "Confirmed kills: %d" % t.kills


func _ship_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in ship.ship_count():
		names.append(ship.ship_name_at(i))
	return names


# Clicking a hangar row swaps to that ship — only meaningful while docked.
func _on_hangar_pick(index: int) -> void:
	if docked and index >= 0 and index < ship.ship_count():
		ship.swap_ship(index)
		combat.player_hp = ship.max_hp   # new hull -> its full defence


# Looping background music, spawned from code like everything else.
# Mix hierarchy (loudest/most present first): gunfire/SFX > engine > music.
# Music is a backdrop that only plays while flying outside (not on the platform);
# the engine has real weight over it (see audio.gd ENGINE_*), SFX punch over both.
func _setup_music() -> void:
	# OGG Vorbis, not MP3: MP3 carries encoder padding that leaves an audible gap at
	# the loop point. Vorbis loops seamlessly, so the track repeats cleanly.
	var stream := load("res://assets/bgm.ogg")
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true   # seamless loop, no gap
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = MUSIC_OFF_DB   # starts silent; _update_music fades it in once driving
	_music.bus = "Master"
	add_child(_music)
	_music.play()
	_music.stream_paused = true   # silent until you've been flying for MUSIC_IN_TIME


func _setup_environment() -> void:
	# Glow does the heavy lifting for the "dots and glow" look. No Light3D
	# anywhere — bodies are emissive, ambient fills the rest. Shadows are moot
	# without lights, so nothing to disable.
	var env := Environment.new()

	# Clean black space (no sky gradient — the Sun key light defines form now).
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.34)
	env.ambient_light_energy = 0.2    # low — key+fill lights define form now, so the
									  # hull keeps contrast/detail instead of washing pale
	# (Affects only lit objects — stars/planets are emissive, background stays black.)

	# Glow ONLY the genuinely bright things (stars, the Sun) — not lit surfaces.
	# glow_bloom>0 was haloing the lit metal hull into a "bulb"; with bloom 0 and
	# an HDR threshold, only pixels brighter than 1.0 (emissive bodies) bloom, so
	# the ship reads as shiny lit metal with a gradient, not a glowing bulb.
	env.glow_enabled = true
	env.glow_normalized = true     # normalize levels so the neon thruster bloom blends evenly
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15          # subtle bleed on emissive parts (was haloing the hull)
	env.glow_strength = 0.85
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.2)
	env.set_glow_level(3, 0.4)
	env.set_glow_level(5, 0.7)

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.7   # global -30% brightness (keeps colour + specular)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env   # kept so the Settings menu can toggle glow quality
