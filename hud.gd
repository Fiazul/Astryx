class_name HUD
extends Node3D
# Minimal HUD: a few code-spawned Labels on a CanvasLayer. No menus, no
# containers, no themes — just text, per the spec.
#
# refresh() is called by main.gd each frame.

# Scale conversions for the readouts. 1 unit = 0.1 AU (see ephemeris.gd).
const AU_PER_UNIT := 0.1
const LY_PER_AU := 1.0 / 63241.077

signal ship_selected(index: int)   # emitted when a hangar row is clicked

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
var _menu: Label      # centered overlay text (wormhole-transit countdown)
# Hangar: the styled, bordered, gradient-backed ship-pickup table (top-right).
var _hangar: PanelContainer
var _hangar_bg: TextureRect
var _hangar_title: Label
var _hangar_rows: VBoxContainer
var _hangar_sig := ""   # rebuild the rows only when the contents actually change
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

	# Centered overlay text — used for the wormhole-transit countdown.
	_menu = _make_label(canvas, Vector2(0, 200), 22)
	_menu.size = Vector2(1280, 320)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.visible = false

	# Styled ship-pickup table (top-right, shown while docked).
	_build_hangar(canvas)

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
	hint.text = "WASD · Shift boost · L-click fire · RMB/T free-look · Tab waypoint · V scan · C codex · F dock/wormhole · M map · X Raptor mode · Esc cursor"


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
	_menu.visible = text != ""   # hide the centered overlay when there's nothing to show


# --- Hangar (ship-pickup table) -------------------------------------------------
const HANGAR_W := 340.0
const HANGAR_X := 1280.0 - HANGAR_W - 18.0   # top-right, clear of the screen edge
const HANGAR_Y := 150.0                       # below the MAP/CODEX/⚙ button bar

# A bordered, gradient-backed panel in the top-right. Built once; set_hangar()
# fills/clears the rows and shows or hides it.
func _build_hangar(canvas: CanvasLayer) -> void:
	_hangar = PanelContainer.new()
	_hangar.position = Vector2(HANGAR_X, HANGAR_Y)
	_hangar.custom_minimum_size = Vector2(HANGAR_W, 0)
	_hangar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Outer frame: cyan border + soft glow (the table's outer border).
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)            # let the gradient backdrop show through
	frame.set_border_width_all(2)
	frame.border_color = Color(0.45, 0.85, 1.0, 0.9)
	frame.set_corner_radius_all(4)
	frame.shadow_color = Color(0.3, 0.7, 1.0, 0.35)
	frame.shadow_size = 8
	_hangar.add_theme_stylebox_override("panel", frame)

	# Linear-gradient backdrop, stretched to fill the panel (drawn behind content).
	_hangar_bg = TextureRect.new()
	_hangar_bg.texture = _linear_gradient(
		Color(0.07, 0.12, 0.20, 0.96), Color(0.01, 0.02, 0.05, 0.96))
	_hangar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hangar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_hangar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hangar.add_child(_hangar_bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_hangar.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_hangar_title = Label.new()
	_hangar_title.add_theme_font_size_override("font_size", 18)
	_hangar_title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	col.add_child(_hangar_title)

	var sub := Label.new()
	sub.text = "SELECT A SHIP  ·  PRESS A NUMBER"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.55, 0.75, 0.9))
	col.add_child(sub)

	_hangar_rows = VBoxContainer.new()
	_hangar_rows.add_theme_constant_override("separation", 0)   # rows touch -> a table grid
	col.add_child(_hangar_rows)

	var footer := Label.new()
	footer.text = "[ F ]   Undock"
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.6, 0.8, 0.95))
	col.add_child(footer)

	_hangar.visible = false
	canvas.add_child(_hangar)


# A top->bottom linear gradient as a texture (for the hangar backdrop / row fills).
func _linear_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 64
	return tex


# Show/refresh the ship-pickup table. Rebuilds rows only when the contents change
# (ship set, current selection, or station name), so it's cheap to call per frame.
func set_hangar(open: bool, names: PackedStringArray, current: int, station: String) -> void:
	var sig := ("%d|%s|%s" % [current, station, ",".join(names)]) if open else ""
	if sig == _hangar_sig:
		return
	_hangar_sig = sig
	_hangar.visible = open
	if not open:
		return
	_hangar_title.text = "HANGAR · %s" % station
	for c in _hangar_rows.get_children():
		c.queue_free()
	for i in names.size():
		_hangar_rows.add_child(_make_hangar_row(names[i], i, i == current))


# One bordered table row: ◈ icon · ship name · number key. Current ship is lit up.
func _make_hangar_row(ship_name: String, idx: int, is_current: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	if is_current:
		box.bg_color = Color(0.18, 0.45, 0.70, 0.45)
		box.border_color = Color(0.6, 0.95, 1.0, 0.95)
	else:
		box.bg_color = Color(0.10, 0.16, 0.24, 0.30)
		box.border_color = Color(0.35, 0.60, 0.80, 0.50)
	row.add_theme_stylebox_override("panel", box)
	# Clickable: pick this ship on left-click (number keys still work too).
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(_on_hangar_row_input.bind(idx))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks fall through to the row
	row.add_child(h)

	var icon := Label.new()
	icon.text = "◈"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color",
		Color(0.7, 1.0, 1.0) if is_current else Color(0.5, 0.75, 0.95))
	h.add_child(icon)

	var nm := Label.new()
	nm.text = ship_name
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color",
		Color(1, 1, 1) if is_current else Color(0.85, 0.92, 1.0))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)

	var key := Label.new()
	key.text = ("◄ %d" % (idx + 1)) if is_current else str(idx + 1)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_theme_font_size_override("font_size", 16)
	key.add_theme_color_override("font_color",
		Color(0.7, 1.0, 1.0) if is_current else Color(0.55, 0.75, 0.9))
	h.add_child(key)

	return row


func _on_hangar_row_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		ship_selected.emit(idx)


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
