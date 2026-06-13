class_name StarMap
extends CanvasLayer
# Star map overlay (M). Shows every system as a star on a chart, your current
# location highlighted; click any other system to jump there. Pauses flight and
# frees the cursor while open, like the settings menu. process_mode = ALWAYS so
# M keeps working while the tree is paused.
#
# main wires `main` (reads main.current_system, calls main.travel_to(id)).

const DOT := 20.0           # star button diameter
const FIELD_SCALE := 2.1    # galaxy-units -> pixels
# The chart now lives in a compact centered panel rather than the whole screen.
const PANEL := Vector2(720, 460)
const PANEL_POS := Vector2((1280 - 720) * 0.5, (720 - 460) * 0.5)
const FIELD_CENTER := PANEL_POS + Vector2(PANEL.x * 0.5, PANEL.y * 0.5 + 24.0)

var main: Node

var _root: Control      # dim full-screen scrim
var _panel: PanelContainer
var _field: Control
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

	var title := Label.new()
	title.text = "STAR  MAP"
	title.position = PANEL_POS + Vector2(0, 16)
	title.size = Vector2(PANEL.x, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(title)

	var hint := Label.new()
	hint.text = "click a system to jump  ·  M / Esc to close"
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
		if here:
			b.disabled = true
			b.add_theme_stylebox_override("disabled", _dot_box(col))
		else:
			b.pressed.connect(_on_jump.bind(id))
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


func _on_jump(id: String) -> void:
	_close()
	if main != null and main.has_method("travel_to"):
		main.travel_to(id)


func _dot_box(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(DOT * 0.5))     # round dot
	sb.shadow_color = Color(c.r, c.g, c.b, 0.6)
	sb.shadow_size = 8
	return sb
