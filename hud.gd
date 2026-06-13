class_name HUD
extends Node3D
# Minimal HUD: a few code-spawned Labels on a CanvasLayer. No menus, no
# containers, no themes — just text, per the spec.
#
# refresh() is called by main.gd each frame.

# Scale conversions for the readouts. 1 unit = 0.1 AU (see ephemeris.gd).
const AU_PER_UNIT := 0.1
const LY_PER_AU := 1.0 / 63241.077

var ship: Ship
var planets: PlanetSystem
var combat: Combat           # for HP / kills readout
var codex: Codex             # discovery progress (set by main)
var origin_name := "Earth"   # what the distance readout measures from (per system)

# Scan/discovery state, fed by main each frame.
var scan_progress := 0.0     # 0..1 while scanning the nearest body
var scan_name := ""          # which body is being scanned
var scan_hint := ""          # "hold V to scan X" prompt when in range
var toast := ""              # transient "✓ discovered" message
var toast_t := 0.0

var _dist_label: Label
var _speed_label: Label
var _near_label: Label
var _prompt: Label    # "Press F to dock" near the station
var _menu: Label      # ship-swap panel while docked
var _combat_label: Label
var _boss_label: Label
var _reticle: Label
var _hitmarker: Label   # flashes on the crosshair when a shot lands
var _codex_label: Label # "Discovered N/M"
var _scan_label: Label  # scan prompt / progress (center-lower)
var _toast_label: Label # "✓ X discovered" pop
var teleport_button: Button   # connected by main -> teleport_home()
var details_button: Button    # connected by main -> PlanetInfo.open_for_nearest()
var map_button: Button        # -> StarMap.toggle()
var codex_button: Button      # -> CodexPanel.toggle()
var settings_button: Button   # -> SettingsMenu.toggle()
var _detail_range := 60.0     # show the Details button within this of a body


func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_dist_label = _make_label(canvas, Vector2(20, 18), 30)
	_speed_label = _make_label(canvas, Vector2(20, 58), 24)
	_near_label = _make_label(canvas, Vector2(20, 92), 26)
	_codex_label = _make_label(canvas, Vector2(20, 128), 20)
	_codex_label.modulate = Color(0.55, 0.9, 0.7)

	# Scan prompt/progress (center, below the crosshair) + discovery toast (center).
	_scan_label = _make_label(canvas, Vector2(0, 410), 22)
	_scan_label.size = Vector2(1280, 30)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scan_label.modulate = Color(0.6, 1.0, 0.85)
	_toast_label = _make_label(canvas, Vector2(0, 250), 30)
	_toast_label.size = Vector2(1280, 40)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate = Color(0.5, 1.0, 0.7, 0)

	_prompt = _make_label(canvas, Vector2(0, 600), 20)
	_prompt.size = Vector2(1280, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_menu = _make_label(canvas, Vector2(0, 200), 22)
	_menu.size = Vector2(1280, 320)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Combat readout (top-right) + a center aiming reticle.
	_combat_label = _make_label(canvas, Vector2(980, 18), 24)
	_combat_label.size = Vector2(280, 70)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Boss banner (top-center) — only shows while Vortex is alive.
	_boss_label = _make_label(canvas, Vector2(0, 46), 22)
	_boss_label.size = Vector2(1280, 30)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.modulate = Color(1.0, 0.35, 0.35)

	_reticle = _make_label(canvas, Vector2(0, 344), 28)
	_reticle.size = Vector2(1280, 32)
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.text = "+"
	_reticle.modulate = Color(0.6, 1.0, 0.9, 0.8)

	# Hitmarker — a bright ✕ that pops over the crosshair when a shot connects.
	_hitmarker = _make_label(canvas, Vector2(0, 338), 34)
	_hitmarker.size = Vector2(1280, 40)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.text = "✕"
	_hitmarker.modulate = Color(1, 1, 1, 0)

	_build_teleport_button(canvas)
	_build_button_bar(canvas)

	# "Details" button — appears (bottom-center) when you're near a planet.
	details_button = Button.new()
	details_button.position = Vector2(528, 640)
	details_button.size = Vector2(224, 48)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.add_theme_font_size_override("font_size", 18)
	details_button.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	details_button.add_theme_stylebox_override("normal", _metal_box(Color(0.55, 0.85, 1.0), 0.5))
	details_button.add_theme_stylebox_override("hover", _metal_box(Color(0.7, 0.95, 1.0), 0.9))
	details_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.8, 1.0, 1.0), 1.0))
	details_button.visible = false
	canvas.add_child(details_button)

	var hint := _make_label(canvas, Vector2(20, 686), 14)
	hint.text = "WASD · Shift boost · L-click fire · Tab waypoint · V scan · C codex · F dock/wormhole · M map · X Raptor mode · Esc cursor"


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "⌖  TELEPORT  EARTH"
	teleport_button.position = Vector2(1040, 660)
	teleport_button.size = Vector2(224, 46)
	teleport_button.focus_mode = Control.FOCUS_NONE
	teleport_button.add_theme_font_size_override("font_size", 16)
	teleport_button.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	teleport_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	teleport_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 0.85, 1.0), 0.45))
	teleport_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 0.95, 1.0), 0.85))
	teleport_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 1.0), 1.0))
	canvas.add_child(teleport_button)


# Styled top-right control bar: open the map / codex / settings by click.
func _build_button_bar(canvas: CanvasLayer) -> void:
	var y := 98.0
	map_button = _icon_button(canvas, "◎  MAP", Vector2(1006, y), Color(0.45, 0.85, 1.0))
	codex_button = _icon_button(canvas, "▤  CODEX", Vector2(1096, y), Color(0.55, 1.0, 0.8))
	settings_button = _icon_button(canvas, "⚙", Vector2(1186, y), Color(0.8, 0.85, 1.0))

func _icon_button(canvas: CanvasLayer, text: String, pos: Vector2, edge: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(84, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.4))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.85))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	canvas.add_child(b)
	return b


func _metal_box(edge: Color, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.17)       # dark brushed steel
	sb.set_border_width_all(2)
	sb.border_color = edge                       # cyan edge line (the "glow" rim)
	sb.set_corner_radius_all(3)                  # squared/boxed
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(edge.r, edge.g, edge.b, 0.5 * glow)
	sb.shadow_size = int(10 * glow)              # cyan halo glow around the box
	return sb


func set_prompt(text: String) -> void:
	_prompt.text = text

func set_menu(text: String) -> void:
	_menu.text = text


func refresh() -> void:
	if ship == null:
		return
	# Hide the crosshair when Vela is hypersonic — combat is disabled then.
	var hyper := ship.is_hypersonic()
	_reticle.visible = not hyper
	_hitmarker.visible = not hyper
	# Distance from Earth (the scene origin). Astronomical distances span a huge
	# range, so show AU in-system and switch to ly once it's large.
	var dist_au := float(ship.true_pos.length()) * AU_PER_UNIT
	_dist_label.text = "From %s:  %s" % [origin_name, _fmt_dist(dist_au)]
	var spd := ship.velocity.length()
	var spd_ly := spd * AU_PER_UNIT * LY_PER_AU
	if spd_ly >= 0.001:
		_speed_label.text = "Speed:  %.3f ly/s" % spd_ly
	else:
		_speed_label.text = "Speed:  %.0f u/s" % spd

	if combat != null:
		_combat_label.text = "Hull  %d%%\nKills  %d" % [combat.player_hp, combat.kills]
		# Hitmarker flash (alpha tracks the combat hit timer).
		var hm: float = clampf(combat.hitmarker / 0.18, 0.0, 1.0)
		_hitmarker.modulate = Color(1.0, 0.95, 0.55, hm)
		var bs: Dictionary = combat.boss_state()
		if bs.alive:
			_boss_label.text = "◼  VORTEX   %d%%" % int(round(100.0 * bs.hp / bs.max))
		else:
			_boss_label.text = ""

	# Discovery progress + scan prompt / progress + toast.
	if codex != null:
		_codex_label.text = "Discovered  %d / %d" % [codex.count(), codex.total()]
	if scan_progress > 0.0 and scan_name != "":
		_scan_label.text = "Scanning  %s …  %d%%" % [scan_name, int(scan_progress * 100.0)]
	else:
		_scan_label.text = scan_hint
	if toast_t > 0.0:
		_toast_label.text = toast
		_toast_label.modulate = Color(0.5, 1.0, 0.7, clampf(toast_t, 0.0, 1.0))
	else:
		_toast_label.text = ""

	if planets != null and planets.nearest_name != "":
		var near_au := planets.nearest_dist * AU_PER_UNIT
		_near_label.text = "Nearest:  %s  (%s)" % [planets.nearest_name, _fmt_dist(near_au)]
		# Offer the Details button when you're close to that body.
		var close := planets.nearest_dist < _detail_range
		details_button.visible = close
		if close:
			details_button.text = "ⓘ  %s  DETAILS  (G)" % planets.nearest_name
	elif details_button != null:
		details_button.visible = false


# AU when in-system, light-years when far enough that AU stops reading well.
func _fmt_dist(au: float) -> String:
	if au >= 1000.0:
		return "%.3f ly" % (au * LY_PER_AU)
	return "%.3f AU" % au


func _make_label(canvas: CanvasLayer, pos: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	canvas.add_child(label)
	return label
