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
var quest_log: QuestLog
var planet_data: PlanetData
var planet_info: PlanetInfo
var navigator: Navigator
var minimap: MiniMap
var codex: Codex
var _nav_target := ""         # Tab aim-help target (basic guidance; lowest priority)
var _nav_locked := ""         # LOCKED map waypoint (orange) — persists until cancelled
var coins := 0                # player currency; persisted to the profile
var _claimed := {}            # body name -> true once its capture reward is claimed
var _loaded_custom := {}      # saved per-ship colour/bell/finish, applied to the ship in _ready
var _visited := {}            # system id -> true once reached (= DISCOVERED → free fast-travel)
var _nav_unlocked := {}       # star id -> true: navigation unlocked (paid or chest-dropped) →
							  #   its imaginary wormhole is known. Once visited it's discovered.
var _wormholes_found := {}    # star id -> true: this star's wormhole found by radar in the hub
var _nav_goal := ""           # star the map asked to guide to (orange waypoint). The guide
							  #   resolves the next hop each frame: in the hub → that star's
							  #   wormhole; in a system → the exit gate. Session-only (not saved).
var _onboarding_step := 0     # first-run guided tips: which step the player is on (see _onboarding)
var _map_seen := false        # latched true by StarMap when first opened (the map pauses the tree,
							  #   so _process can't poll map._open — the map notifies us instead)
const PROFILE_PATH := "user://profile.cfg"
const CAPTURE_REWARD := 100
const ARRIVAL_REWARD := 150   # coins granted the FIRST time you reach a new system
const NAV_COST := 40          # coins to buy a navigator (map Navigate / Auto-pilot)
const NAV_UNLOCK_BASE := 80   # base coin cost to unlock navigation to a LOCKED star…
const NAV_UNLOCK_PER_LY := 9  # …plus this per light-year of real distance (far = pricey)
const WORMHOLE_RADAR := 750.0 # hub range at which your radar finds an undiscovered wormhole

# First-run guided tips. Each step pairs its on-screen tip with the predicate that
# completes it, so the text and its advance-condition live together and can't drift
# apart (insert/reorder freely). Built once in _ready (predicates read live state at
# call time). Persisted as _onboarding_step so the guide runs once, in order, forever.
var _onboard: Array = []
# Missions are per-body now (MissionDB + QuestLog, key J): every star/planet/moon is a
# mission you complete by surveying it. The top-center tracker shows the nearest unsurveyed
# body in the current system; the full board is the J log. _log_seen latches when first opened
# (drives the last onboarding step, like _map_seen).
var _log_seen := false
# The TRACKED quest: a body name you chose to chase from the Mission Log (J). It's the single
# source of truth for quest guidance — the nav arrow routes to it (cross-system via wormholes,
# then to the body in-system) until you survey it, then it auto-advances to the next unsurveyed
# body in the system (or clears when the system's done). Persisted. Mutually exclusive with the
# map's _nav_goal / paid _nav_locked (each setter clears the others).
var _active_quest := ""
var _nav_off := false         # NAV button: stop the Survey guide + waypoint marker entirely
var _was_boost_blocked := false   # edge-trigger for the "boost unavailable" toast
var _touch := false               # touch/mobile input mode (no mouse capture) — set in _ready
var touch_controls: Node          # on-screen controls overlay (mobile only)
var _perf_on := false             # F3 perf/leak readout
var _perf_t := 0.0                # throttle for the perf text update
# Restored on boot: where you left off (system + position + active hull). See _restore_location.
var _saved_system := ""
var _saved_pos := Vector3.ZERO
var _has_saved_pos := false
var _saved_ship_index := -1
var _autosave_t := 5.0            # periodic position autosave (also guards against the crash)
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

# --- Dramatic teleport ritual (emergency home + station→station — the ONLY teleports).
# Travel between stars is always flown through wormholes; teleport is the rare, theatrical
# exception: ship held still, camera eases back, a hue-cycling RGB ring circles you, then
# you arrive. ~TELEPORT_TIME seconds. (Wormholes are NOT teleport.)
const TELEPORT_TIME := 12.0
const TELEPORT_PLATFORM_TIME := 7.0   # platform-network jump: snappier (user wants 5–8s)
const TELEPORT_ZOOM := 2.2     # camera pull-back during the ritual
var _tp_active := false
var _tp_t := 0.0
var _tp_dur := TELEPORT_TIME
var _tp_dest := ""
var _tp_label := ""
var _tp_ring: MeshInstance3D          # RGB containment cylinder around the ship
var _tp_ring_mat: StandardMaterial3D  # scrolling striped material → "pulling" motion
var _music: AudioStreamPlayer
var _music_default: AudioStream   # the shared bgm every hull flies to
var _music_hani: AudioStream      # HaniNebula's dedicated theme (null if missing)
var _music_track := ""            # which stream is loaded: "default" | "hani"
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
	ship.load_customization(_loaded_custom)   # restore saved per-ship colours/bell/finish

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
	wormhole.set_portals(_known_portals(current_system))   # this system's KNOWN neighbour links

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
	hud.tp_cancel_button.pressed.connect(cancel_teleport)   # abort an in-progress teleport
	hud.ship_selected.connect(_on_hangar_pick)   # click a hangar row to swap ship
	hud.ship_color_selected.connect(_on_ship_color_pick)   # click a swatch to recolour the hull
	hud.ship_bell_toggled.connect(_on_ship_bell_toggle)    # add/remove the booster engine bell
	hud.ship_finish_selected.connect(_on_ship_finish_pick)  # metallic / glassy surface finish
	hud.open_teleport_map.connect(_on_open_teleport_map)    # dock → open the teleport-network map

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

	# Mission log (J): every body is a mission — browse the story + navigate to it.
	quest_log = QuestLog.new()
	quest_log.main = self
	quest_log.codex = codex
	add_child(quest_log)
	hud.log_button.pressed.connect(quest_log.toggle)
	hud.settings_button.pressed.connect(settings.toggle)
	hud.nav_button.pressed.connect(toggle_nav)
	hud.cancel_nav_button.pressed.connect(cancel_locked_nav)

	# First-run guide: tip + its completion predicate, paired so they can't desync.
	_onboard = [
		{ "tip": "Hold  W  to thrust  ·  steer with the mouse, WASD to move",
			"done": func(): return ship.true_pos.distance_to(START_POS) > 6.0 },
		{ "tip": "Aim at a planet or star and hold  V  to survey it",
			"done": func(): return codex.count() > 0 },
		{ "tip": "Press  G  to claim your reward coins",
			"done": func(): return not _claimed.is_empty() },
		{ "tip": "Press  M  for the Star Map — it shows the wormhole network · pick a star, Navigate",
			"done": func(): return _map_seen },
		{ "tip": "Fly to a glowing  wormhole  and press  F  — it links to a neighbouring star",
			"done": func(): return _visited.size() > 1 },
		{ "tip": "Press  J  for the MISSION LOG — every star, planet & moon is a mission with a bounty",
			"done": func(): return _log_seen },
	]

	# Touch / mobile controls overlay (on a phone, or force on desktop with --touch to test).
	# Desktop keyboard+mouse play is completely unaffected when this is off.
	_touch = OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")
	if _touch:
		touch_controls = load("res://scripts/touch.gd").new()
		touch_controls.ship = ship
		touch_controls.main = self
		add_child(touch_controls)

	_restore_location()   # resume where you left off (system + position + hull)


# Resume the last session's location: rebuild the saved system if it isn't the Sol start,
# then drop the ship at the exact saved position with the saved hull, at FULL HP (resuming
# next to a boss at 5 HP would be a rage-quit). Reusing _arrive is safe — the system is
# already visited, so it grants no reward and clears transit/dock state for us.
func _restore_location() -> void:
	if _saved_system != "" and _saved_system != current_system:
		_arrive(_saved_system)
	if _has_saved_pos and _saved_pos.length() > 0.001:
		ship.true_pos = _saved_pos
		ship.face_toward(-_saved_pos)
	if _saved_ship_index >= 0 and _saved_ship_index < ship.ship_count() \
			and _saved_ship_index != ship.current_index():
		ship.swap_ship(_saved_ship_index)
	combat.player_hp = ship.max_hp
	ship.transiting = false
	_tp_active = false
	_save_profile()       # capture the exact restored position


# Save on window close so quitting preserves your exact spot (autosave covers crashes).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_profile()


func _process(delta: float) -> void:
	ship.fly(delta)
	planets.refresh(ship.true_pos, delta)
	ship.speed_limit = planets.speed_limit   # eases the ship down near a body
	ship.nearest_dir = planets.nearest_dir   # only ease down when approaching it
	ship.nearest_dist = planets.nearest_dist # warp ships ease out of warp on arrival
	ship.star_field_dist = planets.star_dist # FTL only unlocks beyond the star's gravity field
	ship.gravity = planets.gravity           # gentle pull toward bodies
	props.update(ship.true_pos, delta)
	# Harbour speed-cap: ease down near stations/probes AND near wormholes (so you can line
	# up and dive in instead of rocketing past) — whichever zone is slowing you most wins.
	ship.struct_limit = minf(props.struct_speed_limit, wormhole.slow_limit(ship.true_pos))
	if wormhole.update(ship.true_pos, delta):
		_arrive(wormhole.dest_id)
	# Combat runs in normal flight (not mid-transit, not docked). Docking at a
	# station is a safe harbor — the fight pauses so you can swap ships in peace.
	var want_fire := false
	var want_laser := false
	if not ship.transiting and not docked and not _tp_active:
		var captured := _touch or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		want_fire = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		# Right-click fires the nose laser beam (laser-equipped hulls only, e.g. Raptor II).
		want_laser = captured and ship.has_laser and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		combat.update(ship, want_fire, delta, want_laser)
		ship.combat_lock = combat.in_combat()       # no interstellar speed mid-fight
	else:
		ship.combat_lock = false
	# Holding fire force-slows you to regular combat speed (you can't shoot at warp/boost) —
	# set even while still fast so the slowdown engages; combat only spawns bolts once slow.
	ship.firing = (want_fire and ship.can_fire) or (want_laser and ship.has_laser)
	hud.firing = want_fire                       # blooms the dynamic crosshair
	hud.coins = coins
	hud.set_cancel_nav_visible(_nav_locked != "" or _nav_goal != "" or _active_quest != "")
	# Tell the player (once) when they try to boost in a slow-zone where it does nothing.
	if ship.boost_blocked and not _was_boost_blocked:
		hud.toast = "⚠  Boost unavailable here — clear the slow-zone first"
		hud.toast_t = 1.6
	_was_boost_blocked = ship.boost_blocked
	_update_teleport(delta)
	_update_dock_ui()
	if ship.autopilot:
		ship.autopilot_target = ship.true_pos + planets.rel_of(ship.autopilot_name)
	_update_navigator()
	_update_minimap()
	_update_wormhole_radar()
	_update_scan(delta)
	_update_music(delta)
	_update_onboarding()
	_update_quests()
	hud.lore_t = maxf(hud.lore_t - delta, 0.0)
	_update_debug(delta)
	# Periodic autosave of location (every 5s, only from a stable state) so a crash or
	# hard quit resumes you near where you were rather than back at Earth.
	_autosave_t -= delta
	if _autosave_t <= 0.0:
		_autosave_t = 5.0
		if not ship.transiting and not _tp_active:
			_save_profile()
	hud.refresh()


# Music only while you're travelling — pause when you've sat still a moment.
func _update_music(delta: float) -> void:
	if _music == null:
		return
	# Swap to the equipped hull's track only while the music is silent (paused or fully
	# faded out) so the change is never an audible cut. We reset to MUSIC_OFF_DB so the
	# new track always fades IN from zero (and the old one has already faded OUT before
	# we get here). HaniNebula flies to her own theme; everyone else shares the bgm.
	var track := _desired_music_track()
	if track != _music_track \
		and (_music.stream_paused or _music.volume_db <= MUSIC_OFF_DB + 1.0):
		_music_track = track
		_music.stream = _music_hani if track == "hani" else _music_default
		_music.volume_db = MUSIC_OFF_DB   # start silent -> _update_music fades it in
		_music.play()
		_music.stream_paused = true
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


# Which bgm the equipped hull should fly to: the T2 hulls (HaniNebula + Raptor 2 Neo)
# share the dedicated theme; every other ship shares the default bgm. Falls back to
# default if the track failed to load.
const T2_HULLS := ["HaniNebula", "Raptor 2 Neo"]
func _desired_music_track() -> String:
	if _music_hani != null and ship != null \
		and ship.ship_name_at(ship.current_index()) in T2_HULLS:
		return "hani"
	return "default"


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
	# All known wormholes, live (not just the nearest) — each its own gold blip on the radar.
	for wp in wormhole.portals_rel(ship.true_pos):
		var wrel: Vector3 = wp.rel
		blips.append({ "local": binv * wrel, "dist": wrel.length(), "role": MiniMap.WORMHOLE,
			"name": "→ %s" % SystemDB.display_name(wp.dest) })
	minimap.set_blips(blips)


# --- Capture the nearest body (hold V within range). Guarded bodies (≈80%, never in
# peaceful Sol) spawn alien guardians you must clear first. Capture = beacon + rank. ---
func _update_scan(delta: float) -> void:
	hud.toast_t = maxf(hud.toast_t - delta, 0.0)
	if _tp_active:
		return                       # no scanning/capturing mid-teleport
	# Guardian LEASH: if an active guardian fight's body is now far behind us, abandon it.
	# A parked, unreachable boss otherwise keeps summoning/firing (no distance gate in
	# _step_boss) → in_combat() stays true → warp bleeds to sublight → you're stranded.
	# Runs independent of the capturable check below so it fires even out in empty space.
	if combat.guard_body != "":
		var grel: Vector3 = planets.rel_of(combat.guard_body)
		if grel != Vector3.ZERO and grel.length() > GUARD_RANGE * 2.5:
			combat.abandon_combat()
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
		and (_touch or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
	var fresh := in_range and not captured and clear

	# Raptor 2 Neo auto-captures any clear body in range — no key needed.
	if fresh and (ship.auto_capture or Input.is_physical_key_pressed(KEY_V)):
		if name != _scan_name:
			_scan_name = name
			_scan = 0.0
		_scan = minf(_scan + delta / SCAN_SECONDS, 1.0)
		if _scan >= 1.0:
			if codex.discover(name):
				# Mission complete: this body's per-mission bounty (see MissionDB), claimed via G.
				hud.toast = "✦  MISSION — %s surveyed   ·   press G to claim %d coins" \
					% [name, MissionDB.reward(name)]
				hud.toast_t = 4.0
				if name == _active_quest:
					_advance_quest()    # tracked quest done → guide the next unsurveyed body here
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
	_active_quest = ""        # a manual waypoint supersedes quest tracking
	_nav_locked = body_name
	if hud != null:
		hud.set_nav_stopped(false)


# Auto-pilot: locks the orange waypoint AND flies there hands-off. PAID navigator.
func start_autopilot(body_name: String) -> void:
	if not buy_navigator():
		return
	_nav_off = false
	_active_quest = ""        # autopilot supersedes quest tracking
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
	var bounty := MissionDB.reward(body_name)   # per-mission bounty (see MissionDB)
	coins += bounty
	_claimed[body_name] = true
	_save_profile()
	return bounty

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
		# Saved per-ship colour/bell/finish choices — applied to the ship once it exists.
		_loaded_custom = cfg.get_value("player", "customization", {})
		# Which systems the player has already reached (= discovered → instant fast-travel).
		_visited.clear()
		for s in cfg.get_value("player", "visited", []):
			_visited[s] = true
		# Stars you've unlocked navigation to (paid / chest-dropped) but not yet discovered.
		_nav_unlocked.clear()
		for s in cfg.get_value("player", "nav_unlocked", []):
			_nav_unlocked[s] = true
		_wormholes_found.clear()
		for s in cfg.get_value("player", "wormholes_found", []):
			_wormholes_found[s] = true
		_onboarding_step = int(cfg.get_value("player", "onboarding_step", 0))
		_active_quest = str(cfg.get_value("player", "active_quest", ""))
		# Where you left off last session (restored after the world is built — see
		# _restore_location). Position is only ever saved from a STABLE state.
		_saved_system = str(cfg.get_value("player", "system", ""))
		_has_saved_pos = cfg.has_section_key("player", "pos")
		_saved_pos = cfg.get_value("player", "pos", Vector3.ZERO)
		_saved_ship_index = int(cfg.get_value("player", "ship_index", -1))
	# Home (Sol) is always known — you start there, so it's instant-travel from frame one.
	_visited[SystemDB.SOL] = true

func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)            # keep any other keys we add later
	cfg.set_value("player", "coins", coins)
	cfg.set_value("player", "claimed", _claimed.keys())
	cfg.set_value("player", "visited", _visited.keys())
	cfg.set_value("player", "nav_unlocked", _nav_unlocked.keys())
	cfg.set_value("player", "wormholes_found", _wormholes_found.keys())
	cfg.set_value("player", "onboarding_step", _onboarding_step)
	cfg.set_value("player", "active_quest", _active_quest)
	if ship != null:
		cfg.set_value("player", "customization", ship.customization_state())
		# Persist your location + active hull — but ONLY from a stable state. Mid-wormhole
		# or mid-teleport we leave the last good values so a restore can't wedge the ship.
		if not ship.transiting and not _tp_active:
			cfg.set_value("player", "system", current_system)
			cfg.set_value("player", "pos", ship.true_pos)
			cfg.set_value("player", "ship_index", ship.current_index())
	cfg.save(PROFILE_PATH)


# True once the player has reached this system at least once (the map only
# fast-travels to KNOWN systems; unknown ones must be flown via the wormhole first).
func is_visited(id: String) -> bool:
	return _visited.has(id)

# --- Star travel states (read by the map) ---------------------------------------
# "here" | "discovered" (visited → free instant fast-travel) | "nav" (navigation unlocked,
# warp-able but undiscovered) | "locked" (must pay coins or get a chest location drop).
func star_state(id: String) -> String:
	if id == current_system:
		return "here"
	if _visited.has(id):
		return "discovered"
	if is_wormhole_known(id):          # nav unlocked (paid/chest) OR wormhole found by radar
		return "nav"
	return "locked"

# Coin cost to unlock navigation to a LOCKED star — scales with REAL distance from where
# you are now (the far dark is expensive to chart a lane to).
func nav_cost(id: String) -> int:
	var d: float = SystemDB.coord(current_system).distance_to(SystemDB.coord(id))
	return NAV_UNLOCK_BASE + int(d * NAV_UNLOCK_PER_LY)

# Pay to unlock navigation to a locked star (map action). Returns true if it could pay.
func unlock_nav(id: String) -> bool:
	if star_state(id) != "locked":
		return false
	var cost := nav_cost(id)
	if coins < cost:
		hud.toast = "Not enough coins to chart a lane to %s  (%d / %d)" % [SystemDB.display_name(id), coins, cost]
		hud.toast_t = 2.5
		return false
	coins -= cost
	_nav_unlocked[id] = true
	_save_profile()
	hud.toast = "◇  Navigation unlocked — %s  (-%d coins)" % [SystemDB.display_name(id), cost]
	hud.toast_t = 3.0
	return true

# Free nav-unlock from a treasure-chest "star location" drop (Stage 4). No-op if already
# reachable. Returns true if it actually revealed a new lane.
func grant_nav_location(id: String) -> bool:
	if id == "" or _visited.has(id) or _nav_unlocked.has(id):
		return false
	_nav_unlocked[id] = true
	_save_profile()
	return true

# A wormhole LINK (a,b) is KNOWN once either endpoint is a discovered system, or it's been
# charted/gifted. This auto-produces "go to Proxima first, then Alpha": the Sol→Alpha link
# doesn't exist in the graph, and Proxima→Alpha only becomes known once you've REACHED Proxima.
func is_edge_known(a: String, b: String) -> bool:
	return _visited.has(a) or _visited.has(b) or _nav_unlocked.has(a) or _nav_unlocked.has(b)

# This system's portals filtered to the links the player knows (what set_portals shows).
# Star systems: arriving in a system reveals all its exit wormholes (is_edge_known is true
# via the system you're standing in). The Interstellar HUB is the exception — it's a junction,
# not a place you "discover onward from", so it shows ONLY wormholes whose DESTINATION the
# player has actually unlocked (visited or charted). Otherwise visiting the hub would leak the
# whole network, since the hub itself counts as visited.
func _known_portals(id: String) -> Array:
	var out := []
	var hub := id == SystemDB.INTERSTELLAR
	for p in SystemDB.portals(id):
		var known: bool = (_visited.has(p.dest) or _nav_unlocked.has(p.dest)) if hub \
			else is_edge_known(id, p.dest)
		if known:
			out.append(p)
	return out

# A star is "reachable" (map 'nav' state) when a KNOWN multi-hop route to it exists from here.
func is_wormhole_known(id: String) -> bool:
	return id != current_system and SystemDB.next_hop(current_system, id, Callable(self, "is_edge_known")) != ""

# In the hub, flying within WORMHOLE_RADAR of an UNDISCOVERED wormhole reveals it: a happy
# notification, it's added to the known field, and the portal pops in. (Only in the hub.)
func _update_wormhole_radar() -> void:
	# Disabled pending graph-rework: wormhole links are now known via the visited frontier
	# (is_edge_known), not radar-found in a central hub. Re-add a per-system radar later.
	return

# Map "Navigate": set the orange guide toward a star. You FLY there — the guide resolves the
# next hop each frame (this star's wormhole when you're in the hub; the exit gate when you're
# in a system). Persists until toggled off (Cancel Nav button / cancel_locked_nav).
func navigate_to(id: String) -> void:
	if id == "" or id == current_system:
		return
	_nav_goal = id
	_active_quest = ""        # a map-navigate goal supersedes quest tracking
	_nav_locked = ""          # the goal-guide supersedes any old fixed waypoint
	_nav_off = false
	if hud != null:
		hud.set_nav_stopped(false)

# Survey rank = how many distinct systems you've reached. Cheap, derived stat — no
# separate counter to keep in sync. Sol counts, so a fresh player is rank 1.
func survey_rank() -> int:
	return _visited.size()

# The Survey's rank titles (lore.md): the count climbs toward a name, not a gate.
func survey_rank_title() -> String:
	var n := survey_rank()
	if n >= 5:    return "Star-Marshal"
	elif n >= 4:  return "Cartographer"
	elif n >= 2:  return "Surveyor"
	return "Cadet"


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
	list.sort_custom(func(a, b): return a.align > b.align)
	var names := []
	for it in list:
		names.append(it.name)
	# Wormholes are the priority Tab target: if this system has a known link, it's the FIRST
	# pick (the first Tab press locks the way out), ahead of any body.
	var wrel: Vector3 = wormhole.portal_rel(ship.true_pos)
	if wrel.length() > 0.001:
		names.push_front("Wormhole")
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


# Cancel a locked (paid) map waypoint + any autopilot + a tracked quest (the Cancel Nav button).
func cancel_locked_nav() -> void:
	_nav_locked = ""
	_nav_goal = ""            # also clear a map "Navigate" guide
	_active_quest = ""        # and stop tracking a quest
	ship.autopilot = false
	hud.set_nav_stopped(false)
	_save_profile()
	_update_navigator()


func active_quest() -> String:
	return _active_quest

# Track a quest (free) — the nav arrow + tracker will guide you to this body until you survey
# it, routing through wormholes if it's in another system. Supersedes the map's other guides.
func track_quest(body_name: String) -> void:
	_active_quest = body_name
	_nav_goal = ""
	_nav_locked = ""
	_nav_off = false
	ship.autopilot = false
	if hud != null:
		hud.set_nav_stopped(false)
	_save_profile()
	_update_navigator()

# Nearest UN-surveyed mission body in the current system ("" if the system's fully surveyed).
func _nearest_unsurveyed_body() -> String:
	if codex == null:
		return ""
	var best := ""
	var nd := INF
	for body in MissionDB.bodies_in(current_system):
		if codex.is_discovered(body):
			continue
		var d: float = planets.rel_of(body).length()
		if d < nd:
			nd = d
			best = body
	return best

# After surveying the tracked quest, advance to the next unsurveyed body here; clear if none.
func _advance_quest() -> void:
	_active_quest = _nearest_unsurveyed_body()
	_save_profile()

# ONE router for cross-system guidance (shared by the quest guide + the map's Navigate): the
# render-space offset of THIS system's wormhole leading toward `sys`, over the KNOWN links.
# { ok=false } when no known route exists yet.
func _route_to(sys: String) -> Dictionary:
	var hop := SystemDB.next_hop(current_system, sys, Callable(self, "is_edge_known"))
	if hop == "":
		return { "ok": false }
	return { "ok": true, "hop": hop, "rel": wormhole.portal_rel_for(hop, ship.true_pos) }


func _update_navigator() -> void:
	if navigator == null:
		return
	var tname: String
	var rel: Vector3
	if ship.transiting:
		navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")   # gizmo only
		hud.set_objective("")
		return
	elif _active_quest != "" and not _nav_off:
		# TRACKED QUEST guide (free, top priority): route to the body's system via wormholes,
		# then point straight at the body once you're in its system. Completion normally clears
		# it in the capture path; this backstop advances if it's already surveyed.
		if codex != null and codex.is_discovered(_active_quest):
			_advance_quest()
		if _active_quest == "":
			navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")
			hud.set_objective("")
			return
		var qbody := _active_quest
		var qsys := MissionDB.system_of(qbody)
		var qtitle := MissionDB.title_for(qbody)
		if qsys == current_system:
			rel = planets.rel_of(qbody)
			navigator.update_nav(ship.camera, true, rel, "QUEST: %s" % qbody, _fmt_nav_dist(rel.length()), true)
			hud.set_objective("✦  QUEST  %s  —  survey %s   %s" % [qtitle, qbody, _fmt_nav_dist(rel.length())])
		else:
			var rt := _route_to(qsys)
			if not rt.ok:
				navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")
				hud.set_objective("✦  QUEST  %s  —  no known route yet, explore on" % qtitle)
				return
			var hopname := SystemDB.display_name(rt.hop)
			navigator.update_nav(ship.camera, true, rt.rel, "QUEST → %s" % hopname, _fmt_nav_dist(rt.rel.length()), true)
			hud.set_objective("✦  QUEST  %s  —  %s via %s   %s" % [qtitle, SystemDB.display_name(qsys), hopname, _fmt_nav_dist(rt.rel.length())])
		return
	elif _nav_goal != "":
		# Map "Navigate" guide (orange): route over KNOWN links and point at THIS system's
		# wormhole leading to the next hop ("go to Proxima first, then Alpha").
		var gname := SystemDB.display_name(_nav_goal)
		var rg := _route_to(_nav_goal)
		if not rg.ok:
			navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")   # gizmo only
			hud.set_objective("◆  NAVIGATE  %s  —  no known route yet, explore on" % gname)
			return
		rel = rg.rel
		var hopname := SystemDB.display_name(rg.hop)
		tname = ("WORMHOLE → %s" % hopname) if rg.hop == _nav_goal else ("→ %s  via %s" % [gname, hopname])
		var gd := _fmt_nav_dist(rel.length())
		navigator.update_nav(ship.camera, true, rel, tname, gd, true)
		var via := "" if rg.hop == _nav_goal else "   (next: %s)" % hopname
		hud.set_objective("◆  NAVIGATE  %s%s   %s" % [gname, via, gd])
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
	# Initial phase: onboarding's final step asks the player to reach the wormhole, so
	# point the guide arrow straight at the gate (overriding nearby-star targeting) — they
	# can't miss where to go.
	if not _onboard.is_empty() and _onboarding_step == _onboard.size() - 1:
		return _nearest_gate_objective()
	# The hub has no bodies — guide to the nearest gate to dive into.
	if current_system == SystemDB.INTERSTELLAR:
		return _nearest_gate_objective()
	# QUEST FIRST: with nothing explicitly tracked, the arrow points at the nearest UNSURVEYED
	# body — the next mission to finish right here. Once the system is fully surveyed it falls
	# back to the nearest wormhole (the way onward), so the arrow's never dead.
	var best := ""
	var best_d := INF
	var best_rel := Vector3.ZERO
	for bname in planets.targetables():
		if not _capturable(bname) or codex.is_discovered(bname):
			continue
		var rel: Vector3 = planets.rel_of(bname)
		var d := rel.length()
		if d > 0.001 and d < best_d:
			best_d = d
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


# --- First-run onboarding -----------------------------------------------------
# A tiny staged guide that teaches the core loop using actions the player already
# performs. Each step shows one tip; doing the thing advances to the next. Once past
# the last tip it never shows again (persisted in the profile). Hidden while docked
# or mid-transit so it doesn't clutter those screens.
# Called by StarMap when the map is first opened. The map pauses the scene tree, so
# main._process can't observe map._open itself — the map notifies us instead.
func notify_map_opened() -> void:
	_map_seen = true

# Latched by QuestLog the first time the mission log is opened (drives the final onboarding
# tip — the log pauses the tree, so _process can't observe its open flag directly).
func notify_log_opened() -> void:
	_log_seen = true


func _update_onboarding() -> void:
	if _onboarding_step >= _onboard.size() or docked or ship.transiting:
		hud.set_tip("")
		return
	# Goal met? Advance (and persist). set_tip itself no-ops when the text is unchanged.
	if _onboard[_onboarding_step].done.call():
		_onboarding_step += 1
		_save_profile()
		if _onboarding_step >= _onboard.size():
			hud.toast = "✦  The dark is yours to chart. Good flying, pilot."
			hud.toast_t = 4.0
			hud.set_tip("")
			return
	hud.set_tip(_onboard[_onboarding_step].tip)


# The top-center quest tracker. A TRACKED quest (chosen in the J log) takes priority and shows
# where it's guiding you; otherwise it points at the nearest UNSURVEYED body in the system
# you're in, so there's always a "next thing to scan". When the system's fully surveyed it
# shows overall progress and nudges you to the J log. The full board lives in QuestLog (J).
func _update_quests() -> void:
	if codex == null:
		return
	# A tracked quest drives the tracker (self-heal if it was already surveyed).
	if _active_quest != "" and codex.is_discovered(_active_quest):
		_advance_quest()
	if _active_quest != "":
		var qsys := MissionDB.system_of(_active_quest)
		var where: String = "here — survey it" if qsys == current_system else "→ %s" % SystemDB.display_name(qsys)
		hud.set_quest("✦  TRACKING · %s   (%s · %d coins)"
			% [MissionDB.title_for(_active_quest), where, MissionDB.reward(_active_quest)])
		return
	var next_body := ""
	var nd := INF
	for body in MissionDB.bodies_in(current_system):
		if codex.is_discovered(body):
			continue
		var d: float = planets.rel_of(body).length()
		if d < nd:
			nd = d
			next_body = body
	if next_body != "":
		hud.set_quest("✦  MISSION · %s   —  survey %s  (%d coins)"
			% [MissionDB.title_for(next_body), next_body, MissionDB.reward(next_body)])
	else:
		var total := 0
		var done := 0
		for m in MissionDB.all_missions():
			total += 1
			if codex.is_discovered(m.body):
				done += 1
		if done >= total:
			hud.set_quest("✦  EVERY BODY SURVEYED — pilot of the Survey")
		else:
			hud.set_quest("✦  %s fully surveyed   ·   %d/%d catalogue  ·  press J for the next mission"
				% [SystemDB.display_name(current_system), done, total])


# Emergency return to Sol — the panic button. Always available; runs the full ritual.
func teleport_home() -> void:
	start_teleport(SystemDB.SOL, "EMERGENCY RETURN — HOME")


# The platform network you can fast-travel between: every system with a dockable platform
# that you've already REACHED (visited), minus the one you're docked at right now.
func _unlocked_platforms() -> Array:
	var out := []
	for id in SystemDB.all():
		if id == current_system or id == SystemDB.INTERSTELLAR:
			continue
		if SystemDB.has_station(id) and _visited.has(id):
			out.append({ "id": id, "name": SystemDB.display_name(id) })
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out


# True if `id` is a valid teleport destination: has a station, you've reached it, and it's
# not where you are now. Used by the teleport-mode map to decide whether to offer "confirm".
func is_teleport_unlocked(id: String) -> bool:
	return id != current_system and id != SystemDB.INTERSTELLAR \
		and SystemDB.has_station(id) and _visited.has(id)


# Dock → "TELEPORT NETWORK" button: open the star map in teleport mode (only unlocked
# platforms are jump targets). The map's confirm button calls teleport_to_platform().
func _on_open_teleport_map() -> void:
	if _tp_active or ship.transiting:
		return
	if _unlocked_platforms().is_empty():
		hud.toast = "No platforms unlocked yet — visit a station to add it to the network."
		hud.toast_t = 3.0
		return
	map.open_teleport()


# Dock → pick a platform from the teleport map: undock, then run the (shorter) teleport
# ritual to that system (the ritual's countdown doubles as the load delay; _arrive swaps
# systems at the end). Called by StarMap's teleport-mode confirm button.
func teleport_to_platform(id: String) -> void:
	if _tp_active or ship.transiting:
		return
	_set_docked(false)
	start_teleport(id, "PLATFORM JUMP → %s" % SystemDB.display_name(id), TELEPORT_PLATFORM_TIME)


# Begin the teleport ritual to `dest`. Freezes the ship, eases the camera back, and spins
# up the RGB ring; _update_teleport drives the countdown and does the actual _arrive at the
# end. `dur` is the ritual length. No-op if already teleporting or mid-wormhole.
func start_teleport(dest: String, label: String, dur := TELEPORT_TIME) -> void:
	if _tp_active or ship.transiting:
		return
	_tp_active = true
	_tp_t = 0.0
	_tp_dur = dur
	_tp_dest = dest
	_tp_label = label
	ship.set_frozen(true)            # hold still + slow turntable (see ship.fly frozen branch)
	ship._set_capture(false)         # free the cursor so the Cancel button is clickable
	ship._cam_zoom = TELEPORT_ZOOM   # camera eases back (smoothed in ship._update_camera)
	if _tp_ring == null:
		_build_teleport_vfx()
	_tp_ring.visible = true
	hud.tp_cancel_button.visible = true   # let the player abort the ritual
	if audio != null:
		audio.play_click()


# Abort an in-progress teleport: stop the countdown, drop the cylinder, hand control back.
# The ship stays in the current system (it was already undocked when the ritual began).
func cancel_teleport() -> void:
	if not _tp_active:
		return
	_tp_active = false
	if _tp_ring != null:
		_tp_ring.visible = false
	hud.tp_cancel_button.visible = false
	hud.set_menu("")
	ship.set_frozen(false)
	ship._cam_zoom = 1.0
	ship._set_capture(true)
	hud.toast = "Teleport cancelled."
	hud.toast_t = 2.0
	if audio != null:
		audio.play_click()


func _update_teleport(delta: float) -> void:
	if not _tp_active:
		return
	_tp_t += delta
	# Hue-cycling RGB cylinder enclosing the ship; bright bands stream UP the tube and
	# accelerate → the ship reads as being "pulled" up the beam.
	var hue: float = fmod(_tp_t * 0.4, 1.0)
	var col := Color.from_hsv(hue, 0.8, 1.0)
	_tp_ring_mat.emission = col
	_tp_ring_mat.albedo_color = col
	var pull: float = 1.2 + _tp_t * 0.7                       # bands speed up over time
	_tp_ring_mat.uv1_offset = Vector3(0.0, -_tp_t * pull, 0.0)
	_tp_ring_mat.emission_energy_multiplier = 2.6 + 1.4 * absf(sin(_tp_t * 6.0))
	_tp_ring.rotate_y(0.9 * delta)
	var s: float = 1.0 + 0.05 * sin(_tp_t * 5.0)
	_tp_ring.scale = Vector3(s, 1.0, s)
	# Countdown overlay (reuses the centered menu label).
	var rem: int = int(ceil(maxf(_tp_dur - _tp_t, 0.0)))
	hud.set_menu("◇  TELEPORT  ◇\n\n%s\n\nLocking coordinates…\n\nArriving in  %d" % [_tp_label, rem])
	if _tp_t >= _tp_dur:
		_tp_active = false
		_tp_ring.visible = false
		hud.tp_cancel_button.visible = false
		hud.set_menu("")
		ship.set_frozen(false)
		ship._cam_zoom = 1.0
		_arrive(_tp_dest)
		ship._set_capture(true)


# An RGB "containment cylinder" that encloses the ship during a teleport. The side is a
# tiled stripe texture; scrolling its UV upward (in _update_teleport) makes glowing bands
# stream up the tube → the ship looks like it's being pulled up a transporter beam.
func _build_teleport_vfx() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.1
	cyl.bottom_radius = 2.1
	cyl.height = 13.0
	cyl.radial_segments = 48
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_tp_ring = MeshInstance3D.new()
	_tp_ring.mesh = cyl
	_tp_ring_mat = StandardMaterial3D.new()
	_tp_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tp_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tp_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tp_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED       # visible from inside the tube too
	_tp_ring_mat.emission_enabled = true
	_tp_ring_mat.emission = Color(1, 0, 0)
	_tp_ring_mat.albedo_color = Color(1, 0, 0)
	_tp_ring_mat.emission_energy_multiplier = 2.8
	var stripes := _tp_stripe_texture()
	_tp_ring_mat.albedo_texture = stripes
	_tp_ring_mat.emission_texture = stripes
	_tp_ring_mat.uv1_scale = Vector3(6.0, 10.0, 1.0)           # bands around + many up the tube
	_tp_ring.material_override = _tp_ring_mat
	_tp_ring.visible = false
	ship.add_child(_tp_ring)


# Soft horizontal band that tiles seamlessly up the cylinder (transparent → bright → transparent).
func _tp_stripe_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.5, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 64
	return t


# Emerge from a wormhole in a new system: swap bodies, hard-reset the ship to a
# small LOCAL coord (so float precision is never stressed), re-aim the portal.
func _arrive(system_id: String) -> void:
	var first_visit := not _visited.has(system_id)
	_visited[system_id] = true       # now a KNOWN system → instant map fast-travel hereafter
	_nav_unlocked.erase(system_id)   # discovered → no longer just a "nav-unlocked" lane
	current_system = system_id
	planets.load_system(SystemDB.bodies(system_id))
	planets.speed_zones = (system_id == SystemDB.SOL)   # planet safe-zone limits: Sol only
	ship.true_pos = SystemDB.arrival_pos(system_id)
	ship.transiting = false
	ship.face_toward(-ship.true_pos)          # look back toward the system's star
	# Show this system's neighbour wormholes that the player KNOWS — fly through any to
	# transit straight to that neighbour (no central hub in the loop anymore).
	wormhole.set_portals(_known_portals(system_id))
	if system_id == _nav_goal:
		_nav_goal = ""                             # reached the guided star — clear the guide
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
	# First time here = the trip paid off: coins, a rank bump, and a lore card. Re-visits
	# (fast-travel, teleport home) are silent — the reward is for discovery, not commuting.
	if first_visit and system_id != SystemDB.SOL:
		coins += ARRIVAL_REWARD
		hud.toast = "✦  NEW SYSTEM — %s   ·   +%d coins   ·   %s (%d charted)" \
			% [SystemDB.display_name(system_id), ARRIVAL_REWARD, survey_rank_title(), survey_rank()]
		hud.toast_t = 5.0
		var lore: String = SystemDB.lore(system_id)
		if lore != "":
			hud.show_lore("%s\n\n%s" % [SystemDB.display_name(system_id), lore])
	_save_profile()                                # persist visited set + any reward
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
	elif key == KEY_H and not ship.transiting and not _tp_active:
		teleport_home()
	elif key == KEY_F3:
		_perf_on = not _perf_on          # toggle the perf/leak readout
		if not _perf_on:
			hud.set_debug("")
	elif key == KEY_S and ship.auto_cruise:
		# Tapping reverse drops you out of hands-free auto-cruise (don't consume the
		# event — S still applies reverse thrust this frame).
		ship.auto_cruise = false
		hud.toast = "AUTO-CRUISE  OFF"
		hud.toast_t = 2.0
	elif docked and key >= KEY_1 and key <= KEY_9:
		ship.swap_ship(key - KEY_1)
		combat.player_hp = ship.max_hp   # new hull -> its full defence


func _set_docked(d: bool) -> void:
	docked = d
	ship.set_frozen(d)


# F3 perf/leak readout (throttled to ~3 Hz so the text relayout is cheap). Watch which
# counter climbs during play: OBJ/ORPHAN rising = node/resource leak; RAM rising = memory
# leak; RENDER rising = draw-load growth (e.g. too many hub portals/stations on screen).
func _update_debug(delta: float) -> void:
	if not _perf_on:
		return
	_perf_t -= delta
	if _perf_t > 0.0:
		return
	_perf_t = 0.33
	var obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var orphan := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var ram := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var rend := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var fps := int(Performance.get_monitor(Performance.TIME_FPS))
	hud.set_debug("FPS %d  ·  OBJ %d  ·  ORPHAN %d  ·  RAM %.0f MB  ·  RENDER %d" \
		% [fps, obj, orphan, ram, rend])


func _update_dock_ui() -> void:
	if _tp_active:
		return                       # the teleport ritual owns the centered overlay
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
	# Dock target: in a star system it's that system's station (props). In the Interstellar
	# hub there's no props station — instead ~half the KNOWN wormholes carry a space
	# PLATFORM, so the target is the NEAREST platform (wormhole.nearest_station), letting
	# you dock/swap close to wherever you are rather than flying back home.
	var has_dock := props.has_dock
	var dock_pos := props.dock_pos
	var dock_name := props.dock_name
	var dock_range := props.dock_range
	if current_system == SystemDB.INTERSTELLAR:
		var st := wormhole.nearest_station(ship.true_pos)
		has_dock = not st.is_empty()
		if has_dock:
			dock_pos = st.pos
			dock_name = st.name
			dock_range = st.range
	var dock_dist := (dock_pos - ship.true_pos).length() if has_dock else INF
	_dock_in_range = dock_dist < dock_range
	# Force-slow the ship as it enters the landing zone (smooth, proximity-based):
	# 0 at the outer edge (dock_range + DOCK_SLOW_MARGIN), 1 once inside the pad.
	ship.dock_approach = clampf(1.0 - (dock_dist - dock_range) / DOCK_SLOW_MARGIN, 0.0, 1.0) \
		if dock_dist < INF else 0.0
	if docked:
		hud.set_prompt("")
		hud.set_hangar(true, _ship_names(), ship.current_index(), dock_name, _unlocked_platforms())
	else:
		hud.set_hangar(false, PackedStringArray(), 0, "")
		if _dock_in_range:
			hud.set_prompt("» Press F to dock at %s «" % dock_name)
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
		out += "⚠ %s present — %d/%d HP\n" % [String(boss.get("name", "VORTEX")).to_upper(), boss.hp, boss.max]
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


func _on_ship_color_pick(part: String, key: String) -> void:
	if docked:
		ship.set_ship_color(part, key)
		_save_profile()   # remember this hull's colour across sessions


func _on_ship_bell_toggle(on: bool) -> void:
	if docked:
		ship.set_ship_bell(on)
		_save_profile()


func _on_ship_finish_pick(key: String) -> void:
	if docked:
		ship.set_ship_finish(key)
		_save_profile()


# Looping background music, spawned from code like everything else.
# Mix hierarchy (loudest/most present first): gunfire/SFX > engine > music.
# Music is a backdrop that only plays while flying outside (not on the platform);
# the engine has real weight over it (see audio.gd ENGINE_*), SFX punch over both.
func _setup_music() -> void:
	# OGG Vorbis, not MP3: MP3 carries encoder padding that leaves an audible gap at
	# the loop point. Vorbis loops seamlessly, so the track repeats cleanly.
	_music_default = _load_music("res://assets/bgm.ogg")
	if _music_default == null:
		return
	# HaniNebula gets her own dedicated theme — swapped in while docked (see _update_music).
	_music_hani = _load_music("res://assets/bgm_hani.ogg")
	_music = AudioStreamPlayer.new()
	_music.stream = _music_default
	_music_track = "default"
	_music.volume_db = MUSIC_OFF_DB   # starts silent; _update_music fades it in once driving
	_music.bus = "Master"
	add_child(_music)
	_music.play()
	_music.stream_paused = true   # silent until you've been flying for MUSIC_IN_TIME


# Load a bgm track and flag it as a seamless loop (null if the file is missing).
func _load_music(path: String) -> AudioStream:
	var stream := load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true   # seamless loop, no gap
	return stream


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
