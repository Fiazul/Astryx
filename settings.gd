class_name SettingsMenu
extends CanvasLayer
# Esc-toggled settings overlay: Master Volume, Mouse Sensitivity, and GFX
# (Glow quality, Render scale, Fullscreen). Opening pauses flight and frees the
# cursor; closing restores capture. process_mode = ALWAYS so it keeps running
# (and Esc keeps working) while the tree is paused.
#
# Spawned by main, which passes `ship` (sensitivity + capture) and `env` (glow).

const SENS_MIN := 0.0008
const SENS_MAX := 0.0050
const RENDER_SCALES := [1.0, 0.75, 0.5]   # matches the OptionButton rows below

var ship: Ship
var env: Environment

var _root: Control          # dim + panel; visibility is the open/closed state
var _open := false
var _master_bus := 0
var _fs_check: CheckButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_master_bus = AudioServer.get_bus_index("Master")
	_build()
	_root.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Esc only CLOSES settings (back) — it no longer opens it; the ⚙ button does.
		if event.keycode == KEY_ESCAPE and _open:
			_close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:          # global fullscreen toggle (works anytime)
			toggle_fullscreen()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		_close()
	else:
		_open_menu()


func _open_menu() -> void:
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
func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.55)            # dim the game behind the panel
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(380, 0)
	margin.add_child(col)

	col.add_child(_title("SETTINGS"))

	# --- Master Volume ---
	var vol := _slider(0.0, 1.0, 0.01, db_to_linear(AudioServer.get_bus_volume_db(_master_bus)))
	vol.value_changed.connect(_on_volume)
	col.add_child(_row("Master Volume", vol))

	# --- Mouse Sensitivity ---
	var cur_sens := ship.mouse_sens if ship != null else Ship.MOUSE_SENS
	var sens_t := clampf(inverse_lerp(SENS_MIN, SENS_MAX, cur_sens), 0.0, 1.0)
	var sens := _slider(0.0, 1.0, 0.01, sens_t)
	sens.value_changed.connect(_on_sensitivity)
	col.add_child(_row("Mouse Sensitivity", sens))

	# --- Glow quality ---
	var glow := OptionButton.new()
	glow.add_item("High")   # index 0
	glow.add_item("Low")    # index 1
	glow.selected = 0 if (env != null and env.glow_enabled) else 1
	glow.item_selected.connect(_on_glow)
	col.add_child(_row("Glow", glow))

	# --- Render scale ---
	var rs := OptionButton.new()
	rs.add_item("100%")
	rs.add_item("75%")
	rs.add_item("50%")
	rs.selected = RENDER_SCALES.find(get_viewport().scaling_3d_scale)
	if rs.selected < 0:
		rs.selected = 0
	rs.item_selected.connect(_on_render_scale)
	col.add_child(_row("Render Scale", rs))

	# --- Fullscreen ---
	_fs_check = CheckButton.new()
	_fs_check.button_pressed = _is_fullscreen()
	_fs_check.toggled.connect(_apply_fullscreen)
	col.add_child(_row("Fullscreen  (F11)", _fs_check))

	var resume := Button.new()
	resume.text = "Resume   (Esc)"
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(_close)
	col.add_child(resume)


# --- control callbacks ---
func _on_volume(v: float) -> void:
	AudioServer.set_bus_mute(_master_bus, v <= 0.001)
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(maxf(v, 0.001)))

func _on_sensitivity(t: float) -> void:
	if ship != null:
		ship.mouse_sens = lerpf(SENS_MIN, SENS_MAX, t)

func _on_glow(idx: int) -> void:
	if env != null:
		env.glow_enabled = (idx == 0)

func _on_render_scale(idx: int) -> void:
	get_viewport().scaling_3d_scale = RENDER_SCALES[idx]

func _is_fullscreen() -> bool:
	var m := get_window().mode
	return m == Window.MODE_FULLSCREEN or m == Window.MODE_EXCLUSIVE_FULLSCREEN

func _apply_fullscreen(on: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	if _fs_check != null:
		_fs_check.set_pressed_no_signal(on)

func toggle_fullscreen() -> void:
	_apply_fullscreen(not _is_fullscreen())


# --- small UI builders ---
func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(180, 0)
	return s

func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	return l

func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.40, 0.85, 1.0)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb
