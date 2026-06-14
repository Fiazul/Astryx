class_name HUD
extends Node3D
# Heads-up display: code-spawned controls on a CanvasLayer, styled for a clean
# "space game" look — small text, soft drop-shadows, and frosted-glass panels
# (linear-gradient backdrops + glowing edge borders) instead of bare labels.
#
# Layout is authored against the 1280x720 reference (project stretch = canvas_items),
# so it scales to fullscreen. refresh() is called by main.gd each frame.

# Scale conversions for the readouts. 1 unit = 0.01 AU (see ephemeris.gd, AU_TO_UNITS=100).
const AU_PER_UNIT := 0.01
const LY_PER_AU := 1.0 / 63241.077

# --- palette -----------------------------------------------------------------
const C_ACCENT := Color(0.45, 0.85, 1.0)     # cyan UI accent / edges
const C_TEXT := Color(0.84, 0.92, 1.0)       # primary readout text
const C_DIM := Color(0.55, 0.70, 0.88)       # secondary / labels
const C_GREEN := Color(0.55, 1.0, 0.80)      # discovery / scan
const C_WARN := Color(1.0, 0.45, 0.45)       # boss / danger

# Shared right margin (1280 reference width − 16px). The combat readout and the
# MAP/CODEX/?/⚙ bar below it both align their right edge here.
const RIGHT_EDGE := 1264.0

# Metallic gradient shader for glyph fills (see hud_text.gdshader). Each label gets
# its own ShaderMaterial so the gradient hue/height can match that label.
var _text_shader := load("res://shaders/hud_text.gdshader") as Shader

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
var _hull_label: Label       # "HULL  170 / 220" sitting over the hull bar
var _hull_fill: ColorRect    # the coloured fill of the player hull bar (top-left)
var _hull_bar_w := 0.0       # inner (fillable) width of the hull bar
var _boss_bar: Control       # red boss HP bar (top-center, shown only while a boss lives)
var _boss_fill: ColorRect
var _boss_bar_w := 0.0
var _reticle: Control   # dynamic crosshair (crosshair.gd)
var firing := false     # set by main each frame — blooms the crosshair while held
var _hitmarker: Label   # flashes on the crosshair when a shot lands
var _codex_label: Label # "Discovered N/M"
var _objective_label: Label # "→ <star> <dist>" — the Survey guide line
var _scan_label: Label  # scan prompt / progress (center-lower)
var _toast_label: Label # "✓ X discovered" pop
var _controls: PanelContainer   # the controls cheat-sheet menu (toggled by ?)
var teleport_button: Button   # connected by main -> teleport_home()
var details_button: Button    # connected by main -> PlanetInfo.open_for_nearest()
var map_button: Button        # -> StarMap.toggle()
var codex_button: Button      # -> CodexPanel.toggle()
var settings_button: Button   # -> SettingsMenu.toggle()
var controls_button: Button   # toggles the controls cheat-sheet
var _detail_range := 600.0    # show the Details button within this of a body (×10 spread)

# --- HUD layout editor -------------------------------------------------------
# Each movable widget is tracked by a stable id; positions are saved to disk and
# re-applied on launch. Edit mode (opened from Settings) lets you drag them.
const LAYOUT_PATH := "user://hud_layout.cfg"
var ship_ref: Ship                 # set by main, used to free/recapture the cursor in edit mode
var _movable: Array = []           # [{ id, node, def }]
var _saved := {}                   # id -> Vector2 position loaded from disk
var _saved_scale := {}             # id -> float scale loaded from disk
var _edit := false
var _drag: Control = null          # widget currently being dragged
var _drag_grab := Vector2.ZERO     # mouse offset within the dragged widget
var _btn_bar: Control              # container wrapping the MAP/CODEX/?/⚙ buttons
var _edit_ui: Control              # dim scrim + banner + Save/Reset/Done toolbar
var _edit_toolbar: Control         # the toolbar rect (clicks here aren't drags)


func _ready() -> void:
	# ALWAYS so the layout editor still receives input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	_load_layout()

	# Top-left flight readout, grouped in one frosted-glass panel.
	var nav := _glass_panel(Vector2(16, 14), 198.0, C_ACCENT)
	_canvas.add_child(nav.panel)
	_track("nav", nav.panel)
	_dist_label = _add_line(nav.body, 14, C_TEXT)
	_speed_label = _add_line(nav.body, 10, C_DIM)
	_near_label = _add_line(nav.body, 11, C_TEXT)
	_codex_label = _add_line(nav.body, 10, C_GREEN)
	_objective_label = _add_line(nav.body, 11, C_ACCENT)   # Survey guide: next unclaimed star

	# Scan prompt/progress (center, below the crosshair) + discovery toast (center).
	_scan_label = _make_label(Vector2(0, 416), 12, C_GREEN)
	_scan_label.size = Vector2(1280, 24)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label = _make_label(Vector2(0, 256), 17, C_GREEN)
	_toast_label.size = Vector2(1280, 32)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0

	_prompt = _make_label(Vector2(0, 608), 13, C_TEXT)
	_prompt.size = Vector2(1280, 24)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Centered overlay text — used for the wormhole-transit countdown.
	_menu = _make_label(Vector2(0, 210), 15, C_TEXT)
	_menu.size = Vector2(1280, 300)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.visible = false

	# Styled ship-pickup table (top-right, shown while docked).
	_build_hangar(_canvas)

	# Combat readout (top-right, frosted panel) + a center aiming reticle.
	# Wide enough that "HULL 100% · KILLS 188" never clips; its right edge sits at
	# RIGHT_EDGE so it lines up with the button bar below.
	var cw := 182.0
	var cstat := _glass_panel(Vector2(RIGHT_EDGE - cw, 14), cw, C_ACCENT)
	cstat.panel.position.x = RIGHT_EDGE - cw
	_canvas.add_child(cstat.panel)
	_track("combat", cstat.panel)
	_combat_label = _add_line(cstat.body, 12, C_TEXT)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Player hull bar (top-left, under the nav panel). A real coloured bar; the
	# top-right box keeps just the kill count. Draggable/resizable in the HUD editor.
	_build_hull_bar(_canvas)

	# Boss banner (top-center) — only shows while Vortex is alive — with a red HP bar.
	_boss_label = _make_label(Vector2(0, 64), 13, C_WARN)
	_boss_label.size = Vector2(1280, 24)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_boss_bar(_canvas)

	# Dynamic aiming reticle (custom-drawn): blooms while firing, kicks on a hit.
	_reticle = load("res://scripts/crosshair.gd").new()
	_reticle.size = Vector2(80, 80)
	_reticle.position = Vector2(640.0 - 40.0, 360.0 - 40.0)
	_canvas.add_child(_reticle)

	# Hitmarker — a bright ✕ that pops over the crosshair when a shot connects.
	_hitmarker = _make_label(Vector2(0, 344), 23, Color(1, 1, 1, 0))
	_hitmarker.size = Vector2(1280, 36)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.text = "✕"

	_build_teleport_button(_canvas)
	_build_button_bar(_canvas)
	_build_controls_menu(_canvas)

	# "Details" button — appears (bottom-center) when you're near a planet.
	details_button = Button.new()
	details_button.position = Vector2(552, 650)
	details_button.size = Vector2(176, 32)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.add_theme_color_override("font_color", C_TEXT)
	details_button.add_theme_stylebox_override("normal", _metal_box(Color(0.55, 0.85, 1.0), 0.5))
	details_button.add_theme_stylebox_override("hover", _metal_box(Color(0.7, 0.95, 1.0), 0.9))
	details_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.8, 1.0, 1.0), 1.0))
	details_button.visible = false
	_canvas.add_child(details_button)
	_track("details", details_button)

	_build_edit_ui(_canvas)


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "⌖  TELEPORT EARTH"
	teleport_button.size = Vector2(176, 32)
	teleport_button.position = Vector2(RIGHT_EDGE - 176.0, 674)
	teleport_button.focus_mode = Control.FOCUS_NONE
	teleport_button.add_theme_font_size_override("font_size", 12)
	teleport_button.add_theme_color_override("font_color", C_TEXT)
	teleport_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	teleport_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 0.85, 1.0), 0.45))
	teleport_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 0.95, 1.0), 0.85))
	teleport_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 1.0), 1.0))
	canvas.add_child(teleport_button)
	_track("teleport", teleport_button)


# A bar widget: dark frame + a coloured fill that we resize to the value ratio.
# Returns { root, fill, inner_w }. The caller positions/sizes/adds `root`.
func _build_bar(width: float, height: float, fill: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(width, height)
	root.size = Vector2(width, height)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.72)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.7)
	sb.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", sb)
	root.add_child(frame)
	var bar := ColorRect.new()
	bar.color = fill
	bar.position = Vector2(2, 2)
	bar.size = Vector2(width - 4, height - 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return { "root": root, "fill": bar, "inner_w": width - 4 }


# Player hull bar (top-left) — green→amber→red as the hull falls.
func _build_hull_bar(canvas: CanvasLayer) -> void:
	var holder := Control.new()
	holder.position = Vector2(16, 96)
	holder.size = Vector2(184, 26)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hull_label = _new_label(10, C_DIM)
	_hull_label.position = Vector2(1, 0)
	holder.add_child(_hull_label)
	var bar := _build_bar(184, 12, C_GREEN)
	bar.root.position = Vector2(0, 14)
	holder.add_child(bar.root)
	_hull_fill = bar.fill
	_hull_bar_w = bar.inner_w
	canvas.add_child(holder)
	_track("hull", holder)


# Boss HP bar (top-center) — a wide red bar under the boss banner.
func _build_boss_bar(canvas: CanvasLayer) -> void:
	_boss_bar = Control.new()
	_boss_bar.position = Vector2(640 - 170, 84)
	_boss_bar.size = Vector2(340, 12)
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := _build_bar(340, 12, C_WARN)
	_boss_bar.add_child(bar.root)
	_boss_fill = bar.fill
	_boss_bar_w = bar.inner_w
	_boss_bar.visible = false
	canvas.add_child(_boss_bar)


# Styled top-right control bar: open the map / codex / controls / settings by click.
func _build_button_bar(canvas: CanvasLayer) -> void:
	# The four buttons live inside one Control container laid out left-to-right, so
	# the whole bar drags as a single unit. The container's right edge sits at
	# RIGHT_EDGE so it lines up with the combat readout above it.
	var gap := 6.0
	var w_map := 66.0
	var w_codex := 74.0
	var w_icon := 28.0
	var bar_w := w_map + gap + w_codex + gap + w_icon + gap + w_icon
	_btn_bar = Control.new()
	_btn_bar.position = Vector2(RIGHT_EDGE - bar_w, 80.0)
	_btn_bar.size = Vector2(bar_w, 26)
	canvas.add_child(_btn_bar)

	var x_map := 0.0
	var x_codex := x_map + w_map + gap
	var x_controls := x_codex + w_codex + gap
	var x_settings := x_controls + w_icon + gap
	map_button = _icon_button(_btn_bar, "◎ MAP", Vector2(x_map, 0), w_map, C_ACCENT)
	codex_button = _icon_button(_btn_bar, "▤ CODEX", Vector2(x_codex, 0), w_codex, C_GREEN)
	controls_button = _icon_button(_btn_bar, "?", Vector2(x_controls, 0), w_icon, Color(0.8, 0.85, 1.0))
	settings_button = _icon_button(_btn_bar, "⚙", Vector2(x_settings, 0), w_icon, Color(0.8, 0.85, 1.0))
	controls_button.pressed.connect(toggle_controls)
	_track("buttons", _btn_bar)

func _icon_button(parent: Node, text: String, pos: Vector2, w: float, edge: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(w, 26)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.4))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.85))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	parent.add_child(b)
	return b


# --- HUD layout editor ---------------------------------------------------------
# Register a movable widget under a stable id, remembering its built-in position
# as the "default", and snap it to any saved position. Called for the built-in
# widgets in _ready, and by main for external ones (e.g. the radar).
func _track(id: String, node: Control) -> void:
	_movable.append({ "id": id, "node": node, "def": node.position, "defs": node.scale })
	if _saved.has(id):
		node.position = _saved[id]
	if _saved_scale.has(id):
		var s: float = _saved_scale[id]
		node.scale = Vector2(s, s)

func register_movable(id: String, node: Control) -> void:
	_track(id, node)

# Reference resolution: 1280×720 (project stretch base) — clamp drags to it.
const SCREEN := Vector2(1280, 720)
const HUD_SCALE_MIN := 0.5
const HUD_SCALE_MAX := 1.4

func _load_layout() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LAYOUT_PATH) != OK:
		return
	if cfg.has_section("layout"):
		for id in cfg.get_section_keys("layout"):
			_saved[id] = cfg.get_value("layout", id)
	if cfg.has_section("scale"):
		for id in cfg.get_section_keys("scale"):
			_saved_scale[id] = cfg.get_value("scale", id)

func _save_layout() -> void:
	var cfg := ConfigFile.new()
	for item in _movable:
		cfg.set_value("layout", item.id, item.node.position)
		cfg.set_value("scale", item.id, item.node.scale.x)
		_saved[item.id] = item.node.position       # keep the cancel-baseline in sync
		_saved_scale[item.id] = item.node.scale.x
	cfg.save(LAYOUT_PATH)

func _reset_layout() -> void:
	for item in _movable:
		item.node.position = item.def
		item.node.scale = item.defs
	_saved.clear()
	_saved_scale.clear()
	var cfg := ConfigFile.new()   # write an empty file so the reset persists
	cfg.save(LAYOUT_PATH)


# Dim scrim + banner + Save/Reset/Done toolbar. Hidden until enter_edit().
func _build_edit_ui(canvas: CanvasLayer) -> void:
	_edit_ui = Control.new()
	_edit_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edit_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE   # drags are handled in _input
	_edit_ui.visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.10, 0.45)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_ui.add_child(scrim)

	var banner := _new_label(15, C_ACCENT)
	banner.text = "◇  HUD LAYOUT  —  drag to move  ·  scroll to resize"
	banner.position = Vector2(0, 24)
	banner.size = Vector2(SCREEN.x, 24)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_ui.add_child(banner)

	# Bottom-center toolbar. Clicks inside its rect are NOT treated as drags.
	_edit_toolbar = HBoxContainer.new()
	_edit_toolbar.add_theme_constant_override("separation", 10)
	_edit_toolbar.position = Vector2(SCREEN.x * 0.5 - 170, SCREEN.y - 60)
	_edit_toolbar.add_child(_edit_btn("✓  SAVE", C_GREEN, func(): _exit_edit(true)))
	_edit_toolbar.add_child(_edit_btn("↺  RESET", C_WARN, _reset_layout))
	_edit_toolbar.add_child(_edit_btn("✕  CANCEL", C_ACCENT, func(): _exit_edit(false)))
	_edit_ui.add_child(_edit_toolbar)

	canvas.add_child(_edit_ui)

func _edit_btn(text: String, edge: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size = Vector2(110, 34)
	b.custom_minimum_size = Vector2(110, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_stylebox_override("normal", _metal_box(edge, 0.5))
	b.add_theme_stylebox_override("hover", _metal_box(edge.lightened(0.2), 0.9))
	b.add_theme_stylebox_override("pressed", _metal_box(edge.lightened(0.4), 1.0))
	b.pressed.connect(cb)
	return b


# Open/close the editor. Pauses flight and frees the cursor so panels can be dragged.
func enter_edit() -> void:
	if _edit:
		return
	_edit = true
	_edit_ui.visible = true
	get_tree().paused = true
	if ship_ref != null:
		ship_ref._set_capture(false)

func _exit_edit(save: bool) -> void:
	if save:
		_save_layout()
	else:
		# Cancel: restore whatever was on disk (or defaults) before this session.
		for item in _movable:
			item.node.position = _saved.get(item.id, item.def)
			var s: float = _saved_scale.get(item.id, item.defs.x)
			item.node.scale = Vector2(s, s)
	_edit = false
	_edit_ui.visible = false
	get_tree().paused = false
	if ship_ref != null and not ship_ref.frozen:
		ship_ref._set_capture(true)


# Drag the movable widgets while in edit mode. Handled here (not via each widget's
# gui_input) so the click is consumed before buttons fire, while toolbar clicks
# still fall through to the toolbar.
func _input(event: InputEvent) -> void:
	if not _edit:
		return
	var mpos := _edit_ui.get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _edit_toolbar.get_global_rect().has_point(mpos):
				return   # let the toolbar buttons handle their own click
			for item in _movable:
				var node: Control = item.node
				if node.visible and node.get_global_rect().has_point(mpos):
					_drag = node
					_drag_grab = mpos - node.position
					get_viewport().set_input_as_handled()
					break
		elif _drag != null:
			_drag = null
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag != null:
		var sz := _drag.get_global_rect().size
		_drag.position = Vector2(
			clampf(mpos.x - _drag_grab.x, 0.0, SCREEN.x - sz.x),
			clampf(mpos.y - _drag_grab.y, 0.0, SCREEN.y - sz.y))
		get_viewport().set_input_as_handled()
	# Scroll the wheel over a widget to resize it (HUD scale, persisted with position).
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		for item in _movable:
			var node: Control = item.node
			if node.visible and node.get_global_rect().has_point(mpos):
				var step := 0.06 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.06
				var s := clampf(node.scale.x + step, HUD_SCALE_MIN, HUD_SCALE_MAX)
				node.scale = Vector2(s, s)
				get_viewport().set_input_as_handled()
				break


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


func set_objective(text: String) -> void:
	if _objective_label != null:
		_objective_label.text = text

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
	["R", "Air-brake (Vela)"],
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

	var title := _new_label(15, Color(0.7, 0.95, 1.0))
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
		var desc := _new_label(11, C_TEXT)
		desc.text = row[1]
		desc.custom_minimum_size = Vector2(150, 0)
		grid.add_child(desc)

	var close := Button.new()
	close.text = "CLOSE  [ ? ]"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 11)
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
	var l := _new_label(11, Color(0.75, 0.95, 1.0))
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

	_hangar_title = _new_label(13, Color(0.7, 0.95, 1.0))
	col.add_child(_hangar_title)

	var sub := _new_label(10, C_DIM)
	sub.text = "SELECT A SHIP  ·  PRESS A NUMBER"
	col.add_child(sub)

	_hangar_rows = VBoxContainer.new()
	_hangar_rows.add_theme_constant_override("separation", 0)   # rows touch -> a table grid
	col.add_child(_hangar_rows)

	var footer := _new_label(10, C_DIM)
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
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
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

	var icon := _new_label(13, Color(0.7, 1.0, 1.0) if is_current else Color(0.5, 0.75, 0.95))
	icon.text = "◈"
	h.add_child(icon)

	var nm := _new_label(13, Color(1, 1, 1) if is_current else C_TEXT)
	nm.text = ship_name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)

	var key := _new_label(11, Color(0.7, 1.0, 1.0) if is_current else C_DIM)
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
	var armed := ship.can_fire and not hyper   # utility hulls show no crosshair
	_reticle.visible = armed
	_hitmarker.visible = armed
	# Feed the dynamic crosshair: bloom while firing, kick on a fresh hit.
	var kick := clampf(combat.hitmarker / 0.18, 0.0, 1.0) if combat != null else 0.0
	_reticle.set_target(1.0 if firing else 0.0, kick)
	# Distance from Earth (the scene origin). Astronomical distances span a huge
	# range, so show AU in-system and switch to ly once it's large.
	var dist_au := float(ship.true_pos.length()) * AU_PER_UNIT
	_dist_label.text = "From %s   %s" % [origin_name, _fmt_dist(dist_au)]
	var spd := ship.velocity.length()
	var spd_ly := spd * AU_PER_UNIT * LY_PER_AU
	if spd_ly >= 0.001:
		_speed_label.text = "Speed   %.3f ly/s  ⚡FTL" % spd_ly
	elif ship.warp > 1.0:
		# Sublight cruise: tell the pilot whether FTL is available yet.
		var tag := "  ▲ FTL READY" if ship.warp_ready() else "  · sublight (clear the star)"
		_speed_label.text = "Speed   %.0f u/s%s" % [spd, tag]
	else:
		_speed_label.text = "Speed   %.0f u/s" % spd

	if combat != null:
		# Top-right box keeps just the kill count; the hull bar (top-left) is the HP gauge.
		_combat_label.text = "KILLS  %d" % combat.kills
		var hp_ratio: float = clampf(float(combat.player_hp) / maxf(float(combat.player_max), 1.0), 0.0, 1.0)
		_hull_label.text = "HULL   %d / %d" % [combat.player_hp, combat.player_max]
		_hull_fill.size.x = _hull_bar_w * hp_ratio
		# Green when healthy, amber at half, red when critical.
		_hull_fill.color = Color(0.4, 1.0, 0.55).lerp(Color(1.0, 0.35, 0.3), 1.0 - hp_ratio)
		# Hitmarker flash (alpha tracks the combat hit timer).
		var hm: float = clampf(combat.hitmarker / 0.18, 0.0, 1.0)
		_hitmarker.modulate = Color(1.0, 0.95, 0.55, hm)
		var bs: Dictionary = combat.boss_state()
		_boss_bar.visible = bs.alive
		if bs.alive:
			var br: float = clampf(float(bs.hp) / maxf(float(bs.max), 1.0), 0.0, 1.0)
			_boss_label.text = "◼  VORTEX   %d%%" % int(round(100.0 * br))
			_boss_fill.size.x = _boss_bar_w * br
		else:
			_boss_label.text = ""

	# Discovery progress + scan prompt / progress + toast.
	if codex != null:
		_codex_label.text = "Discovered  %d / %d" % [codex.count(), codex.total()]
	if scan_progress > 0.0 and scan_name != "":
		_scan_label.text = "Capturing  %s …  %d%%" % [scan_name, int(scan_progress * 100.0)]
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
	# White fill so the shader's luminance test treats glyphs as "fill" (the hue
	# comes from the gradient material). Thin dark outline + soft shadow keep it
	# readable over the starfield; the shader leaves those dark passes alone.
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("outline_size", 2)
	label.material = _grad_material(color, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# A per-label ShaderMaterial: a bright highlight up top fading to `color` at the
# bottom, spanning roughly one glyph's height — a lit-metal sheen in the label hue.
func _grad_material(color: Color, font_size: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _text_shader
	m.set_shader_parameter("top_color", color.lightened(0.55))
	m.set_shader_parameter("bottom_color", color.darkened(0.05))
	m.set_shader_parameter("grad_height", float(font_size) * 1.2)
	return m

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
