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

	# Combat: alien dogfighters + your bolts (left-click to fire).
	combat = Combat.new()
	add_child(combat)

	# HUD labels (light-year distance, speed, nearest body).
	hud = HUD.new()
	add_child(hud)
	hud.ship = ship
	hud.planets = planets
	hud.combat = combat
	hud.teleport_button.pressed.connect(teleport_home)


func _process(delta: float) -> void:
	ship.fly(delta)
	planets.refresh(ship.true_pos, delta)
	ship.speed_limit = planets.speed_limit   # eases the ship down near a body
	ship.gravity = planets.gravity           # gentle pull toward bodies
	props.update(ship.true_pos, delta)
	if wormhole.update(ship.true_pos, delta):
		_arrive(wormhole.dest_id)
	# Combat runs in normal flight (not mid-transit). Left mouse = fire.
	if not ship.transiting:
		var firing := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		combat.update(ship, firing, delta)
	_update_dock_ui()
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
	combat.reset()                                 # fresh enemies in the new system
	if docked:
		_set_docked(false)
	hud.origin_name = SystemDB.display_name(system_id) if system_id != SystemDB.SOL else "Earth"
	print("[wormhole] arrived at %s — ship.true_pos.length()=%.2f (must be small)"
		% [SystemDB.display_name(system_id), ship.true_pos.length()])


# --- Docking at the station + ship swap ---
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key == KEY_F:
		if docked:
			_set_docked(false)
		elif _dock_in_range:
			_set_docked(true)
	elif key == KEY_J and not docked and wormhole.in_range(ship.true_pos):
		wormhole.start_transit()
		ship.transiting = true
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
		hud.set_menu("— WORMHOLE TRANSIT —\n\n→ %s   ·   %.0f ly\n(light would take %.0f years)\n\nArriving in  %d:%02d"
			% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly, wormhole.dest_ly,
			int(rem) / 60, int(rem) % 60])
		return

	hud.set_menu("")
	# Docking is Sol-only (the station lives there).
	_dock_in_range = current_system == SystemDB.SOL and props.has_dock \
		and (props.dock_pos - ship.true_pos).length() < props.dock_range
	if docked:
		hud.set_prompt("")
		hud.set_menu(_menu_text())
	elif _dock_in_range:
		hud.set_prompt("» Press F to dock at %s «" % props.dock_name)
	elif wormhole.in_range(ship.true_pos):
		hud.set_prompt("» Press J to open wormhole to %s  (%.0f ly) «"
			% [SystemDB.display_name(wormhole.dest_id), wormhole.dest_ly])
	else:
		hud.set_prompt("")


func _menu_text() -> String:
	var t := "— DOCKED · %s —\n\nSwap ship  (press a number):\n\n" % props.dock_name
	for i in ship.ship_count():
		var cur := "    ◄ current" if i == ship.current_index() else ""
		t += "[ %d ]   %s%s\n" % [i + 1, ship.ship_name_at(i), cur]
	t += "\n[ F ]   Undock"
	return t


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
	_music.volume_db = -14.0
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

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.glow_strength = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.4)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(5, 1.0)

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
