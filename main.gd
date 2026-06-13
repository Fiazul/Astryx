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
var _nav_index := -1          # -1 = no waypoint; else index into nav targets
var _scan := 0.0             # scan progress 0..1 of the nearest body
var _scan_name := ""
const SCAN_SECONDS := 2.0
const SCAN_RANGE := 55.0      # how close you must be to scan a body
var _env: Environment

var docked := false
var _dock_in_range := false
var current_system := SystemDB.SOL
var _music: AudioStreamPlayer
var _slow_t := 0.0   # how long we've been near-stationary (for music gating)

# Where the player starts, in absolute scene units (1u = 0.1 AU). You launch
# FROM Earth (the origin), parked just off it on the side away from the Sun, so
# you open looking at Earth up close with the Sun a bright disc in the distance
# beyond it (~13u). (Sun direction in scene ≈ (0.16, 0.39, 0.91).)
const START_POS := Vector3(-0.81, -1.97, -4.53)


func _ready() -> void:
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

	# Combat: alien dogfighters + your bolts (left-click to fire).
	combat = Combat.new()
	add_child(combat)
	combat.audio = audio
	combat.reset(SystemDB.is_hostile(current_system))   # Sol starts peaceful

	# HUD labels (light-year distance, speed, nearest body).
	hud = HUD.new()
	add_child(hud)
	hud.ship = ship
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
	add_child(settings)

	# Waypoint navigator (Tab) + corner radar.
	var nav_canvas := CanvasLayer.new()
	add_child(nav_canvas)
	navigator = Navigator.new()
	nav_canvas.add_child(navigator)
	minimap = MiniMap.new()
	minimap.position = Vector2(24, 466)
	nav_canvas.add_child(minimap)

	# Star map (M): click a system to jump.
	map = StarMap.new()
	map.main = self
	add_child(map)
	hud.map_button.pressed.connect(map.toggle)
	hud.settings_button.pressed.connect(settings.toggle)


func _process(delta: float) -> void:
	ship.fly(delta)
	planets.refresh(ship.true_pos, delta)
	ship.speed_limit = planets.speed_limit   # eases the ship down near a body
	ship.nearest_dir = planets.nearest_dir   # only ease down when approaching it
	ship.gravity = planets.gravity           # gentle pull toward bodies
	props.update(ship.true_pos, delta)
	if wormhole.update(ship.true_pos, delta):
		_arrive(wormhole.dest_id)
	# Combat runs in normal flight (not mid-transit). Left mouse = fire.
	if not ship.transiting:
		var firing := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and not ship.is_hypersonic()        # no shooting at hypersonic speed
		combat.update(ship, firing, delta)
	_update_dock_ui()
	_update_navigator()
	_update_minimap()
	_update_scan(delta)
	_update_music(delta)
	hud.refresh()


# Music only while you're travelling — pause when you've sat still a moment.
func _update_music(delta: float) -> void:
	if _music == null:
		return
	var spd := ship.velocity.length()
	if spd < 4.0:
		_slow_t += delta
	else:
		_slow_t = 0.0
	var should_play := spd > 12.0 or (_music.stream_paused == false and _slow_t < 1.5)
	_music.stream_paused = not should_play


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
		if bname == "Earth" and current_system == SystemDB.SOL:
			role = MiniMap.HOME
		elif bname == planets.nearest_name:
			role = MiniMap.NEAREST
		blips.append({ "local": binv * rel, "dist": rel.length(), "role": role, "name": bname })
	var wrel: Vector3 = wormhole.portal_rel(ship.true_pos)
	blips.append({ "local": binv * wrel, "dist": wrel.length(), "role": MiniMap.WORMHOLE, "name": "Wormhole" })
	minimap.set_blips(blips)


# --- Scan-to-discover the nearest body (hold V within range) ---
func _update_scan(delta: float) -> void:
	hud.toast_t = maxf(hud.toast_t - delta, 0.0)
	var name := planets.nearest_name
	var in_range := not docked and not ship.transiting and name != "" \
		and planets.nearest_dist < SCAN_RANGE \
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var fresh := in_range and not codex.is_discovered(name)

	if fresh and Input.is_physical_key_pressed(KEY_V):
		if name != _scan_name:
			_scan_name = name
			_scan = 0.0
		_scan = minf(_scan + delta / SCAN_SECONDS, 1.0)
		if _scan >= 1.0:
			if codex.discover(name):
				hud.toast = "✓  %s  DISCOVERED" % name
				hud.toast_t = 3.0
			_scan = 0.0
			_scan_name = ""
	else:
		_scan = maxf(_scan - delta * 2.0, 0.0)
		if _scan <= 0.0:
			_scan_name = ""

	hud.scan_progress = _scan
	hud.scan_name = _scan_name
	hud.scan_hint = "» hold V to scan %s «" % name if (fresh and _scan <= 0.0) else ""


# --- Navigation waypoint (Tab cycles: off -> each body -> wormhole -> off) ---
func _cycle_nav_target() -> void:
	var count := planets.targetables().size() + 1   # + the wormhole
	_nav_index += 1
	if _nav_index >= count:
		_nav_index = -1

func _update_navigator() -> void:
	if navigator == null:
		return
	var bodies: Array = planets.targetables()
	var count := bodies.size() + 1
	if ship.transiting or _nav_index < 0 or _nav_index >= count:
		navigator.update_nav(ship.camera, false, Vector3.ZERO, "", "")   # gizmo only
		return
	var tname: String
	var rel: Vector3
	if _nav_index < bodies.size():
		tname = bodies[_nav_index]
		rel = planets.rel_of(tname)
	else:
		tname = "Wormhole"
		rel = wormhole.portal_rel(ship.true_pos)
	navigator.update_nav(ship.camera, true, rel, tname, _fmt_nav_dist(rel.length()))

func _fmt_nav_dist(u: float) -> String:
	var au := u * 0.1
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
	ship.true_pos = SystemDB.arrival_pos(system_id)
	ship.transiting = false
	ship.face_toward(-ship.true_pos)          # look back toward the system's star
	wormhole.set_system(system_id)
	props.visible = (system_id == SystemDB.SOL)   # the station/astronaut are Sol-only
	combat.reset(SystemDB.is_hostile(system_id))   # enemies only in hostile systems
	_nav_index = -1                                # clear the waypoint in the new system
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
	# Docking is Sol-only (the station lives there).
	var dock_dist := (props.dock_pos - ship.true_pos).length() \
		if current_system == SystemDB.SOL and props.has_dock else INF
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
		elif wormhole.in_range(ship.true_pos):
			hud.set_prompt("» Press F to enter the wormhole to %s  (%.0f ly) «"
				% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly])
		else:
			hud.set_prompt("")


func _ship_names() -> PackedStringArray:
	var names := PackedStringArray()
	for i in ship.ship_count():
		names.append(ship.ship_name_at(i))
	return names


# Clicking a hangar row swaps to that ship — only meaningful while docked.
func _on_hangar_pick(index: int) -> void:
	if docked and index >= 0 and index < ship.ship_count():
		ship.swap_ship(index)


# Looping background music, spawned from code like everything else. Kept low so
# the dogfight/SFX sit on top of it later.
func _setup_music() -> void:
	var stream := load("res://bgm.mp3")
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true   # seamless loop
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = -24.0   # background music is low priority — sits well under engine/SFX
	_music.bus = "Master"
	add_child(_music)
	_music.play()
	_music.stream_paused = true   # silent until you're actually travelling


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
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
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
