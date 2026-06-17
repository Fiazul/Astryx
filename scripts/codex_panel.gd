class_name CodexPanel
extends CanvasLayer
# The logbook (C): every body across all systems, with discovered ones unlocked
# (click to read full data) and the rest shown as locked "◌ ???". Pauses while
# open like the other overlays. main wires `codex`, `info` (PlanetInfo), `ship`.

var codex: Codex
var info: PlanetInfo
var ship: Ship

var _root: Control
var _list: VBoxContainer
var _title: Label
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 96
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L and not _open:
			_open_panel()
			get_viewport().set_input_as_handled()
		elif _open and event.keycode in [KEY_L, KEY_ESCAPE]:
			_close()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_panel()

func _open_panel() -> void:
	_refresh()
	_open = true
	_root.visible = true
	get_tree().paused = true
	if ship != null:
		ship._set_capture(false)

func _close() -> void:
	_open = false
	_root.visible = false
	get_tree().paused = false
	if ship != null and not ship.frozen:
		ship._set_capture(true)


# ---------------------------------------------------------------------------
func _refresh() -> void:
	_title.text = "CODEX        %d / %d discovered" % [codex.count(), codex.total()]
	for c in _list.get_children():
		c.queue_free()
	for e in codex.entries():
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 20)
		row.flat = true
		if e.found:
			row.text = "  ✓  %s    —  %s" % [e.name, e.system]
			row.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
			row.add_theme_color_override("font_hover_color", Color(1, 1, 1))
			row.pressed.connect(_view.bind(e.name))
		else:
			row.text = "  ◌  ???    —  %s" % e.system
			row.disabled = true
			row.add_theme_color_override("font_color_disabled", Color(0.4, 0.45, 0.55))
		_list.add_child(row)

func _view(name: String) -> void:
	_close()                  # close the list, then open the detail panel
	if info != null:
		info.open_for(name)


func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.01, 0.02, 0.05, 0.95)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	col.add_child(_title)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var close := Label.new()
	close.text = "click a discovered body to read it   ·   C / Esc to close"
	close.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	col.add_child(close)
