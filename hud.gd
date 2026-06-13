class_name HUD
extends Node3D
# Heads-up display: code-spawned controls on a CanvasLayer, styled for a clean
# "space game" look — small text, soft drop-shadows, and frosted-glass panels
# (linear-gradient backdrops + glowing edge borders) instead of bare labels.
#
# Layout is authored against the 1280x720 reference (project stretch = canvas_items),
# so it scales to fullscreen. refresh() is called by main.gd each frame.

# Scale conversions for the readouts. 1 unit = 0.1 AU (see ephemeris.gd).
const AU_PER_UNIT := 0.1
const LY_PER_AU := 1.0 / 63241.077

# --- palette -----------------------------------------------------------------
const C_ACCENT := Color(0.45, 0.85, 1.0)     # cyan UI accent / edges
const C_TEXT := Color(0.84, 0.92, 1.0)       # primary readout text
const C_DIM := Color(0.55, 0.70, 0.88)       # secondary / labels
const C_GREEN := Color(0.55, 1.0, 0.80)      # discovery / scan
const C_WARN := Color(1.0, 0.45, 0.45)       # boss / danger

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

var _canvas: CanvasLayer
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
var _controls: PanelContainer   # the controls cheat-sheet menu (toggled by ?)
var teleport_button: Button   # connected by main -> teleport_home()
var details_button: Button    # connected by main -> PlanetInfo.open_for_nearest()
var map_button: Button        # -> StarMap.toggle()
var codex_button: Button      # -> CodexPanel.toggle()
var settings_button: Button   # -> SettingsMenu.toggle()
var controls_button: Button   # toggles the controls cheat-sheet
var _detail_range := 60.0     # show the Details button within this of a body


func _ready() -> void:
	_canvas = CanvasLayer.new()
	add_child(_canvas)

	# Top-left flight readout, grouped in one frosted-glass panel.
	var nav := _glass_panel(Vector2(16, 14), 250.0, C_ACCENT)
	_canvas.add_child(nav.panel)
	_dist_label = _add_line(nav.body, 19, C_TEXT)
	_speed_label = _add_line(nav.body, 13, C_DIM)
	_near_label = _add_line(nav.body, 14, C_TEXT)
	_codex_label = _add_line(nav.body, 12, C_GREEN)

	# Scan prompt/progress (center, below the crosshair) + discovery toast (center).
	_scan_label = _make_label(Vector2(0, 412), 15, C_GREEN)
	_scan_label.size = Vector2(1280, 24)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label = _make_label(Vector2(0, 252), 22, C_GREEN)
	_toast_label.size = Vector2(1280, 32)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0

	_prompt = _make_label(Vector2(0, 604), 16, C_TEXT)
	_prompt.size = Vector2(1280, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Centered overlay text — used for the wormhole-transit countdown.
	_menu = _make_label(Vector2(0, 210), 18, C_TEXT)
	_menu.size = Vector2(1280, 300)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.visible = false

	# Styled ship-pickup table (top-right, shown while docked).
	_build_hangar(_canvas)

	# Combat readout (top-right, frosted panel) + a center aiming reticle.
	var cstat := _glass_panel(Vector2(1108, 14), 156.0, C_ACCENT)
	cstat.panel.position.x = 1264.0 - 156.0
	_canvas.add_child(cstat.panel)
	_combat_label = _add_line(cstat.body, 15, C_TEXT)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Boss banner (top-center) — only shows while Vortex is alive.
	_boss_label = _make_label(Vector2(0, 64), 16, C_WARN)
	_boss_label.size = Vector2(1280, 24)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_reticle = _make_label(Vector2(0, 346), 24, Color(0.6, 1.0, 0.9, 0.75))
	_reticle.size = Vector2(1280, 28)
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.text = "+"

	# Hitmarker — a bright ✕ that pops over the crosshair when a shot connects.
	_hitmarker = _make_label(Vector2(0, 340), 30, Color(1, 1, 1, 0))
	_hitmarker.size = Vector2(1280, 36)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.text = "✕"

	_build_teleport_button(_canvas)
	_build_button_bar(_canvas)
	_build_controls_menu(_canvas)

	# "Details" button — appears (bottom-center) when you're near a planet.
	details_button = Button.new()
	details_button.position = Vector2(540, 646)
	details_button.size = Vector2(200, 40)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.add_theme_font_size_override("font_size", 15)
	details_button.add_theme_color_override("font_color", C_TEXT)
	details_button.add_theme_stylebox_override("normal", _metal_box(Color(0.55, 0.85, 1.0), 0.5))
	details_button.add_theme_stylebox_override("hover", _metal_box(Color(0.7, 0.95, 1.0), 0.9))
	details_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.8, 1.0, 1.0), 1.0))
	details_button.visible = false
	_canvas.add_child(details_button)


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "⌖  TELEPORT EARTH"
	teleport_button.position = Vector2(1066, 666)
	teleport_button.size = Vector2(198, 40)
	teleport_button.focus_mode = Control.FOCUS_NONE
	teleport_button.add_theme_font_size_override("font_size", 14)
	teleport_button.add_theme_color_override("font_color", C_TEXT)
	teleport_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	teleport_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 0.85, 1.0), 0.45))
	teleport_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 0.95, 1.0), 0.85))
	teleport_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 1.0), 1.0))
	canvas.add_child(teleport_button)


# Styled top-right control bar: open the map / codex / controls / settings by click.
func _build_button_bar(canvas: CanvasLayer) -> void:
	var y := 86.0
	map_button = _icon_button(canvas, "◎ MAP", Vector2(932, y), 78, C_ACCENT)
	codex_button = _icon_button(canvas, "▤ CODEX", Vector2(1016, y), 86, C_GREEN)
	controls_button = _icon_button(canvas, "?", Vector2(1108, y), 36, Color(0.8, 0.85, 1.0))
	settings_button = _icon_button(canvas, "⚙", Vector2(1150, y), 36, Color(0.8, 0.85, 1.0))
	controls_button.pressed.connect(toggle_controls)

func _icon_button(canvas: CanvasLayer, text: String, pos: Vector2, w: float, edge: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(w, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.4))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.85))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	canvas.add_child(b)
	return b


func _metal_box(edge: Color, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.92)   # dark brushed steel
	sb.set_border_width_all(1)
	sb.border_color = edge                         # cyan edge line (the "glow" rim)
	sb.set_corner_radius_all(4)                    # softly rounded
	sb.set_content_margin_all(7)
	sb.shadow_color = Color(edge.r, edge.g, edge.b, 0.45 * glow)
	sb.shadow_size = int(9 * glow)                 # cyan halo glow around the box
	return sb


func set_prompt(text: String) -> void:
	_prompt.text = text

func set_menu(text: String) -> void:
	_menu.text = text
	_menu.visible = text != ""   # hide the centered overlay when there's nothing to show


# --- Controls cheat-sheet menu --------------------------------------------------
# All the key bindings, folded out of the play screen into a frosted panel you
# pop open with the [?] button (keeps the flight view clean).
const CONTROLS := [
	["WASD", "Thrust / strafe"],
	["Shift", "Boost"],
	["L-Click", "Fire weapons"],
	["RMB / T", "Free-look"],
	["Tab", "Cycle waypoint"],
	["V", "Scan body"],
	["G", "Planet details"],
	["F", "Dock / wormhole"],
	["C", "Codex log"],
	["M", "Star map"],
	["X", "Raptor mode"],
	["H", "Teleport Earth"],
	["Esc", "Release cursor"],
]

func _build_controls_menu(canvas: CanvasLayer) -> void:
	# Dim full-screen scrim so the panel reads as a modal overlay.
	_controls = PanelContainer.new()
	_controls.position = Vector2(380, 150)
	_controls.custom_minimum_size = Vector2(520, 0)
	_controls.add_theme_stylebox_override("panel", _frame_box(C_ACCENT))

	var bg := TextureRect.new()
	bg.texture = _linear_gradient(
		Color(0.06, 0.11, 0.19, 0.97), Color(0.01, 0.02, 0.05, 0.97))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_child(bg)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_controls.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := _new_label(18, Color(0.7, 0.95, 1.0))
	title.text = "FLIGHT CONTROLS"
	col.add_child(title)

	# Two-column grid of keycap + action.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for row in CONTROLS:
		grid.add_child(_keycap(row[0]))
		var desc := _new_label(13, C_TEXT)
		desc.text = row[1]
		desc.custom_minimum_size = Vector2(150, 0)
		grid.add_child(desc)

	var close := Button.new()
	close.text = "CLOSE  [ ? ]"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", C_TEXT)
	close.add_theme_stylebox_override("normal", _metal_box(C_ACCENT, 0.4))
	close.add_theme_stylebox_override("hover", _metal_box(C_ACCENT.lightened(0.2), 0.85))
	close.add_theme_stylebox_override("pressed", _metal_box(C_ACCENT.lightened(0.4), 1.0))
	close.pressed.connect(toggle_controls)
	col.add_child(close)

	_controls.visible = false
	canvas.add_child(_controls)

func toggle_controls() -> void:
	_controls.visible = not _controls.visible

# A little dark "keycap" chip with a glowing edge — the key you press.
func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.27, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = C_ACCENT
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	cap.add_theme_stylebox_override("panel", sb)
	cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _new_label(13, Color(0.75, 0.95, 1.0))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap


# --- Hangar (ship-pickup table) -------------------------------------------------
const HANGAR_W := 320.0
const HANGAR_X := 1280.0 - HANGAR_W - 16.0   # top-right, clear of the screen edge
const HANGAR_Y := 132.0                       # below the MAP/CODEX/⚙ button bar

# A bordered, gradient-backed panel in the top-right. Built once; set_hangar()
# fills/clears the rows and shows or hides it.
func _build_hangar(canvas: CanvasLayer) -> void:
	_hangar = PanelContainer.new()
	_hangar.position = Vector2(HANGAR_X, HANGAR_Y)
	_hangar.custom_minimum_size = Vector2(HANGAR_W, 0)
	_hangar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hangar.add_theme_stylebox_override("panel", _frame_box(C_ACCENT))

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
	col.add_theme_constant_override("separation", 7)
	margin.add_child(col)

	_hangar_title = _new_label(16, Color(0.7, 0.95, 1.0))
	col.add_child(_hangar_title)

	var sub := _new_label(11, C_DIM)
	sub.text = "SELECT A SHIP  ·  PRESS A NUMBER"
	col.add_child(sub)

	_hangar_rows = VBoxContainer.new()
	_hangar_rows.add_theme_constant_override("separation", 0)   # rows touch -> a table grid
	col.add_child(_hangar_rows)

	var footer := _new_label(12, C_DIM)
	footer.text = "[ F ]   Undock"
	col.add_child(footer)

	_hangar.visible = false
	canvas.add_child(_hangar)


# Outer frame stylebox: transparent fill (so a gradient TextureRect shows through),
# glowing cyan edge + soft halo. Shared by the hangar and controls panels.
func _frame_box(edge: Color) -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(edge.r, edge.g, edge.b, 0.9)
	frame.set_corner_radius_all(6)
	frame.shadow_color = Color(edge.r, edge.g, edge.b, 0.35)
	frame.shadow_size = 10
	return frame


# A frosted-glass info panel: gradient backdrop + glowing edge + a VBox body you
# pour styled lines into. Returns { panel, body }.
func _glass_panel(pos: Vector2, min_w: float, edge: Color) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = Vector2(min_w, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _frame_box(edge))

	var bg := TextureRect.new()
	bg.texture = _linear_gradient(
		Color(0.06, 0.11, 0.18, 0.82), Color(0.01, 0.02, 0.05, 0.82))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	return { "panel": panel, "body": col }


# A top->bottom linear gradient as a texture (for the panel backdrops / row fills).
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

	var icon := _new_label(16, Color(0.7, 1.0, 1.0) if is_current else Color(0.5, 0.75, 0.95))
	icon.text = "◈"
	h.add_child(icon)

	var nm := _new_label(16, Color(1, 1, 1) if is_current else C_TEXT)
	nm.text = ship_name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)

	var key := _new_label(14, Color(0.7, 1.0, 1.0) if is_current else C_DIM)
	key.text = ("◄ %d" % (idx + 1)) if is_current else str(idx + 1)
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
	_dist_label.text = "From %s   %s" % [origin_name, _fmt_dist(dist_au)]
	var spd := ship.velocity.length()
	var spd_ly := spd * AU_PER_UNIT * LY_PER_AU
	if spd_ly >= 0.001:
		_speed_label.text = "Speed   %.3f ly/s" % spd_ly
	else:
		_speed_label.text = "Speed   %.0f u/s" % spd

	if combat != null:
		_combat_label.text = "HULL  %d%%   ·   KILLS  %d" % [combat.player_hp, combat.kills]
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
		_near_label.text = "Nearest  %s  (%s)" % [planets.nearest_name, _fmt_dist(near_au)]
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


# A styled standalone label (soft drop-shadow + thin outline for legibility over
# the busy starfield). Not parented — the caller positions/adds it.
func _new_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# A styled label placed at an absolute canvas position.
func _make_label(pos: Vector2, font_size: int, color := C_TEXT) -> Label:
	var label := _new_label(font_size, color)
	label.position = pos
	_canvas.add_child(label)
	return label

# A styled line added into a panel's VBox body.
func _add_line(body: VBoxContainer, font_size: int, color: Color) -> Label:
	var label := _new_label(font_size, color)
	body.add_child(label)
	return label
