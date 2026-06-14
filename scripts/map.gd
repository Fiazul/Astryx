class_name StarMap
extends CanvasLayer
# Star map overlay (M). Shows every system as a star on a chart, your current
# location highlighted; click any other system to jump there. Pauses flight and
# frees the cursor while open, like the settings menu. process_mode = ALWAYS so
# M keeps working while the tree is paused.
#
# main wires `main` (reads main.current_system, calls main.travel_to(id)).

const DOT := 18.0           # star button diameter
const FIELD_SCALE := 1.7    # galaxy-units -> pixels
# Wider panel: galaxy chart on the LEFT, current-system body list on the RIGHT.
const PANEL := Vector2(980, 520)
const PANEL_POS := Vector2((1280 - 980) * 0.5, (720 - 520) * 0.5)
const FIELD_CENTER := PANEL_POS + Vector2(260.0, PANEL.y * 0.5 + 18.0)   # left-column centre

var main: Node

var _root: Control      # dim full-screen scrim
var _panel: PanelContainer
var _field: Control
var _sys_list: VBoxContainer   # right column: current-system bodies + details
var _title: Label
var _body_menu: PopupMenu      # Navigate / Auto-pilot / Inspect for a clicked body
var _menu_body := ""
var _view_system := ""         # which system's bodies the right panel is showing
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_map()


func _open_map() -> void:
	_open = true
	if main != null:
		_view_system = main.current_system   # start on the system you're in
	_refresh()
	_root.visible = true
	get_tree().paused = true
	if main != null and main.ship != null:
		main.ship._set_capture(false)


func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if main != null and main.ship != null and not main.ship.frozen:
		main.ship._set_capture(true)


# ---------------------------------------------------------------------------
func _build() -> void:
	# Dim full-screen scrim (you can still see the stars faintly behind it).
	_root = ColorRect.new()
	_root.color = Color(0.01, 0.01, 0.04, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Compact frosted-glass chart panel, centered.
	_panel = PanelContainer.new()
	_panel.position = PANEL_POS
	_panel.size = PANEL
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(0.45, 0.85, 1.0, 0.9)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(0.3, 0.7, 1.0, 0.35)
	frame.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", frame)
	_root.add_child(_panel)

	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.06, 0.11, 0.19, 0.97))
	grad.set_color(1, Color(0.01, 0.02, 0.05, 0.97))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8; gt.height = 64
	bg.texture = gt
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)

	_title = Label.new()
	_title.text = "STAR  MAP"
	_title.position = PANEL_POS + Vector2(0, 16)
	_title.size = Vector2(PANEL.x, 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(_title)

	# Right column: a scrollable list of this system's bodies (the "detailed radar").
	var sys_header := Label.new()
	sys_header.text = "SYSTEM  BODIES"
	sys_header.position = PANEL_POS + Vector2(540, 70)
	sys_header.size = Vector2(400, 20)
	sys_header.add_theme_font_size_override("font_size", 13)
	sys_header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_root.add_child(sys_header)

	var scroll := ScrollContainer.new()
	scroll.position = PANEL_POS + Vector2(536, 92)
	scroll.size = Vector2(404, PANEL.y - 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	_sys_list = VBoxContainer.new()
	_sys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sys_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sys_list)

	# Per-location action menu (Navigate / Auto-pilot / Inspect).
	_body_menu = PopupMenu.new()
	_body_menu.add_item("◇ Navigate here", 0)
	_body_menu.add_item("» Auto-pilot", 1)
	_body_menu.add_item("ⓘ Inspect (details)", 2)
	_body_menu.id_pressed.connect(_on_body_menu)
	add_child(_body_menu)


	var hint := Label.new()
	hint.text = "left: click a system to jump   ·   right: click a body for details   ·   M / Esc to close"
	hint.position = PANEL_POS + Vector2(0, 46)
	hint.size = Vector2(PANEL.x, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_root.add_child(hint)

	# Field that holds route lines + star buttons (rebuilt each open).
	_field = Control.new()
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_field)


func _refresh() -> void:
	for c in _field.get_children():
		c.queue_free()
	_refresh_system_list()

	var ids: Array = SystemDB.all()
	var screen := {}
	for id in ids:
		screen[id] = FIELD_CENTER + SystemDB.galaxy_pos(id) * FIELD_SCALE

	# Wormhole routes (drawn first, behind the stars). A system can have several
	# portals (Earth has one per destination), so draw a line for each.
	for id in ids:
		for portal in SystemDB.portals(id):
			var dest: String = portal.dest
			if screen.has(dest):
				var ln := Line2D.new()
				ln.add_point(screen[id])
				ln.add_point(screen[dest])
				ln.width = 2.0
				ln.default_color = Color(0.45, 0.35, 0.85, 0.5)
				_field.add_child(ln)

	# Stars.
	for id in ids:
		var here: bool = main != null and id == main.current_system
		var pos: Vector2 = screen[id]
		var b := Button.new()
		b.size = Vector2(DOT, DOT)
		b.position = pos - Vector2(DOT, DOT) * 0.5
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = SystemDB.display_name(id)
		var col := Color(0.5, 1.0, 0.6) if here else Color(1.0, 0.7, 0.35)
		b.add_theme_stylebox_override("normal", _dot_box(col))
		b.add_theme_stylebox_override("hover", _dot_box(col.lightened(0.3)))
		b.add_theme_stylebox_override("pressed", _dot_box(col))
		b.pressed.connect(_view_system_bodies.bind(id, b))   # drill in — never jumps
		_field.add_child(b)

		var lbl := Label.new()
		var ly: float = SystemDB.light_years(id)
		lbl.text = "%s\n%s" % [SystemDB.display_name(id),
			"you are here" if here else "%.0f ly" % ly]
		lbl.position = pos + Vector2(-80, DOT * 0.5 + 3)
		lbl.size = Vector2(160, 34)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		_field.add_child(lbl)


# Build the right-column body list for the current system: each row shows type,
# captured ✓, and distance; clicking opens that body's full scanner details.
func _refresh_system_list() -> void:
	if _sys_list == null or main == null:
		return
	for c in _sys_list.get_children():
		c.queue_free()
	if _view_system == "":
		_view_system = main.current_system
	var sys: String = _view_system
	var here: bool = sys == main.current_system
	if _title != null:
		_title.text = "STAR  MAP   ·   %s%s" % [SystemDB.display_name(sys), "  (you are here)" if here else ""]
	var rows := []
	for spec in SystemDB.bodies(sys):
		var bname: String = spec.name
		if bname.contains("✦"):
			continue                      # hub gate markers aren't real bodies
		# Distance only means something for the system you're actually in.
		var dist: float = main.planets.rel_of(bname).length() if here else 0.0
		rows.append({ "name": bname, "star": spec.get("star", false), "dist": dist, "here": here })
	rows.sort_custom(func(a, b): return a.dist < b.dist)
	for r in rows:
		var bname: String = r.name
		var captured: bool = main.codex != null and main.codex.is_discovered(bname)
		var info: Dictionary = PlanetData.BUNDLED.get(bname, {})
		var dtxt: String = ("%6.2f AU" % (r.dist / float(Ephemeris.AU_TO_UNITS))) if r.here else "   —   "
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		if captured:
			# Unlocked: full type; click opens the Navigate / Auto-pilot / Inspect menu.
			var kind: String = info.get("type", "Star" if r.star else "Body")
			b.text = "✦  %-16s  %-9s  %s" % [bname, kind, dtxt]
			b.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
		else:
			# Locked: data hidden until captured.
			b.text = "🔒  %-16s  %-9s  %s" % ["? ? ?", "locked", dtxt]
			b.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		b.pressed.connect(_open_body_menu.bind(bname, captured, r.here, b))
		_sys_list.add_child(b)


# Open the action menu for a body. Navigate/Auto-pilot only work in the system you're
# actually in; Inspect needs the body captured. (Other systems are browse-only.)
func _open_body_menu(bname: String, captured: bool, here: bool, btn: Control = null) -> void:
	_click_fx(btn)
	_menu_body = bname
	_body_menu.set_item_disabled(0, not here)                 # Navigate (must be in-system)
	_body_menu.set_item_disabled(1, not (here and captured))  # Auto-pilot
	_body_menu.set_item_disabled(2, not captured)             # Inspect
	var mp := Vector2i(get_viewport().get_mouse_position())
	_body_menu.popup(Rect2i(mp, Vector2i(10, 10)))


# Soft click sound + a quick press-pulse so clicking feels responsive.
func _click_fx(c: Control = null) -> void:
	if main != null and main.audio != null:
		main.audio.play_click()
	if c != null:
		c.pivot_offset = c.size * 0.5
		var tw := create_tween()
		tw.tween_property(c, "scale", Vector2(0.93, 0.93), 0.05)
		tw.tween_property(c, "scale", Vector2(1, 1), 0.08)


func _on_body_menu(id: int) -> void:
	_click_fx()
	var bname := _menu_body
	if main == null or bname == "":
		return
	match id:
		0:                                   # Navigate
			_close()
			if main.has_method("set_nav_target"):
				main.set_nav_target(bname)
		1:                                   # Auto-pilot (cinematic)
			_close()
			if main.has_method("start_autopilot"):
				main.start_autopilot(bname)
		2:                                   # Inspect / details
			_close()
			if main.has_method("open_details_for"):
				main.open_details_for(bname)


# Clicking a galaxy system just DRILLS IN — shows that system's bodies on the right.
# The ship never moves; nothing jumps. Browse freely.
func _view_system_bodies(id: String, btn: Control = null) -> void:
	_click_fx(btn)
	_view_system = id
	_refresh_system_list()


func _dot_box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(DOT * 0.5))     # round dot
	sb.shadow_color = Color(c.r, c.g, c.b, 0.6)
	sb.shadow_size = 8
	return sb
