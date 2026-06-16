class_name StarMap
extends CanvasLayer
# Star map overlay (M). The ~50-star catalogue plotted by real sky bearing (distance
# sqrt-compressed so near + far fit one chart). Each star clicks by its travel state
# (main.star_state): DISCOVERED → free fast-travel (main.travel_to); NAV → distance-scaled
# warp (main.warp_to); LOCKED → pay coins to chart a lane (main.unlock_nav); HERE → browse
# this system's bodies on the right. Pauses flight + frees the cursor; process_mode = ALWAYS
# so M keeps working while the tree is paused.

const DOT := 14.0           # star button diameter
const FIELD_RADIUS := 215.0 # chart half-extent in px (auto-fit scales stars into this)
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
		return
	# Click anywhere OUTSIDE the chart panel → close the map (a click on the panel or a
	# star button is consumed by them / lands inside the panel rect, so it won't close).
	# Skip while one of our own popups is open so its clicks don't dismiss the map under it.
	if _open and event is InputEventMouseButton and event.pressed \
			and not _body_menu.visible \
			and not _panel.get_global_rect().has_point(event.position):
		_close()
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
		main.notify_map_opened()             # advances onboarding (the map pauses the tree, so
		                                     #   main._process can't poll our _open flag itself)
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
	hint.text = "click a star → what it is + how to reach it   ·   ● gold discovered · ● cyan wormhole known · 🔒 locked   ·   M / Esc / click-outside to close"
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
	# Layout: real sky BEARINGS preserved (direction of each star from Sol), with distance
	# sqrt-compressed so the dense near cluster AND the far outliers both fit one chart.
	# (Travel cost/transit use the EXACT 3D distance — this compression is chart-only.)
	var maxc := 1.0
	for id in ids:
		maxc = maxf(maxc, sqrt(SystemDB.galaxy_pos(id).length()))
	var fit: float = FIELD_RADIUS / maxc
	var screen := {}
	for id in ids:
		var raw: Vector2 = SystemDB.galaxy_pos(id)
		var d := raw.length()
		var v: Vector2 = (raw / d) * sqrt(d) if d > 0.001 else Vector2.ZERO
		screen[id] = FIELD_CENTER + v * fit

	# Charted lanes: a faint line from Sol (origin) to each DISCOVERED star — your network.
	for id in ids:
		if main != null and main.star_state(id) == "discovered" and id != SystemDB.SOL and screen.has(SystemDB.SOL):
			var ln := Line2D.new()
			ln.add_point(screen[SystemDB.SOL])
			ln.add_point(screen[id])
			ln.width = 1.5
			ln.default_color = Color(0.5, 0.95, 1.0, 0.32)
			_field.add_child(ln)

	# Stars, coloured by travel state. Labels only for HERE + DISCOVERED so the chart isn't
	# buried in text (everything else reads via a rich tooltip / on click). See _star_col.
	for id in ids:
		var st: String = main.star_state(id) if main != null else "locked"
		var col := _star_col(st)
		var b := Button.new()
		b.size = Vector2(DOT, DOT)
		b.position = screen[id] - Vector2(DOT, DOT) * 0.5
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = _star_tip(id, st)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", _dot_box(col))
		b.add_theme_stylebox_override("hover", _dot_box(col.lightened(0.35)))
		b.add_theme_stylebox_override("pressed", _dot_box(col))
		b.pressed.connect(_on_star.bind(id, b))
		_field.add_child(b)

		# Only label the places that matter right now; the rest stay clean dots.
		if st == "here" or st == "discovered":
			var lbl := Label.new()
			lbl.text = "%s\n%s" % [SystemDB.display_name(id),
				"you are here" if st == "here" else "▸ %.1f ly" % SystemDB.light_years(id)]
			lbl.position = screen[id] + Vector2(-80, DOT * 0.5 + 2)
			lbl.size = Vector2(160, 32)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 11)
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
	_add_travel_action(sys, here)
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


# Top of the right panel: tells you what this place is, whether you can get there, and HOW —
# with a NAVIGATE button (sets the orange guide + closes the map; you FLY there via wormholes)
# or a CHART LANE button (pay coins to reveal its wormhole). The map never moves the ship.
func _add_travel_action(sys: String, here: bool) -> void:
	if _sys_list == null or main == null:
		return
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(384, 0)
	info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	if here:
		info.text = "◉  You are here."
		info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		_sys_list.add_child(info)
		_sys_list.add_child(_spacer())
		return
	if sys == SystemDB.SOL:
		info.text = "⌂  Home. Use Emergency Return (H) to teleport back."
		info.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		_sys_list.add_child(info)
		_sys_list.add_child(_spacer())
		return
	if main.is_wormhole_known(sys):
		var discovered: bool = main.star_state(sys) == "discovered"
		var route: String = "Fly to its wormhole and enter it." if main.current_system == SystemDB.INTERSTELLAR \
			else "Take the exit wormhole to the hub, then its wormhole."
		info.text = ("✦  Discovered.  " if discovered else "◇  Wormhole known.  ") + route
		info.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4) if discovered else Color(0.45, 0.85, 1.0))
		_sys_list.add_child(info)
		var nav := Button.new()
		nav.text = "»   NAVIGATE  HERE"
		nav.focus_mode = Control.FOCUS_NONE
		nav.add_theme_font_size_override("font_size", 13)
		nav.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
		nav.pressed.connect(func():
			_click_fx(nav)
			main.navigate_to(sys)
			_close())
		_sys_list.add_child(nav)
	else:
		info.text = "🔒  Wormhole unknown — chart a lane, or find it by radar out in the hub."
		info.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
		_sys_list.add_child(info)
		var pay := Button.new()
		pay.text = "◇   CHART LANE   —   %d coins" % main.nav_cost(sys)
		pay.focus_mode = Control.FOCUS_NONE
		pay.add_theme_font_size_override("font_size", 13)
		pay.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
		pay.pressed.connect(func():
			_click_fx(pay)
			if main.unlock_nav(sys):
				_refresh())
		_sys_list.add_child(pay)
	_sys_list.add_child(_spacer())


func _spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s


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


# Clicking the system you're IN, or one you've never reached, just DRILLS IN — shows
# that system's bodies on the right. The ship never moves; nothing jumps. Browse freely.
func _view_system_bodies(id: String, btn: Control = null) -> void:
	_click_fx(btn)
	_view_system = id
	_refresh_system_list()


# The map NEVER moves the ship — it's a chart you read. Clicking a star only selects it to
# browse its bodies on the right. You travel by FLYING (radar-find within range → fly there).
func _on_star(id: String, btn: Control = null) -> void:
	_click_fx(btn)
	if main == null:
		return
	_view_system = id
	_refresh_system_list()


# Locked star → a one-item menu offering to pay coins to chart a navigation lane there.
# On success the star becomes NAV-UNLOCKED (warp-able); the chart refreshes in place.
func _locked_menu(id: String) -> void:
	var pm := PopupMenu.new()
	pm.add_item("◇  Chart lane to %s   —   %d coins" % [SystemDB.display_name(id), main.nav_cost(id)], 0)
	add_child(pm)
	pm.id_pressed.connect(func(_choice):
		if main.unlock_nav(id):
			_refresh())
	pm.popup_hide.connect(pm.queue_free)
	pm.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i(10, 10)))


func _star_col(st: String) -> Color:
	match st:
		"here":       return Color(0.5, 1.0, 0.6)     # green — you are here
		"discovered": return Color(1.0, 0.78, 0.32)   # gold — charted, free fast-travel
		"nav":        return Color(0.45, 0.85, 1.0)   # cyan — navigation unlocked, warp-able
		_:            return Color(0.5, 0.55, 0.62)    # dim grey — locked


func _star_tip(id: String, st: String) -> String:
	var head := "%s — %s · %.1f ly" % [SystemDB.display_name(id), SystemDB.spectral(id), SystemDB.light_years(id)]
	match st:
		"here":       return "%s\nyou are here" % head
		"discovered": return "%s\n▸ click: fast-travel" % head
		"nav":        return "%s\n» click: warp here" % head
		_:            return "%s\n🔒 click: chart lane (%d coins)" % [head, main.nav_cost(id)]


func _dot_box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(DOT * 0.5))     # round dot
	sb.shadow_color = Color(c.r, c.g, c.b, 0.6)
	sb.shadow_size = 8
	return sb
