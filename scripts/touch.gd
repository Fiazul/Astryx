class_name TouchControls
extends CanvasLayer
# On-screen controls for touch / mobile. The game reads keyboard + mouse via polling and
# _input; rather than rewrite all of that, this overlay SYNTHESISES the exact key/mouse
# events the game already listens for (verified: parse_input_event drives both
# is_physical_key_pressed and is_mouse_button_pressed). Steering feeds ship.add_touch_look
# directly (phones have no mouse capture). Built only on mobile / with --touch (see main).
#
# Layout (1280×720 reference, scaled by the project's canvas_items+expand stretch):
#   left  — THRUST toggle, BOOST (hold)
#   right — FIRE (hold), CAPTURE (hold), INTERACT/F, MAP/M, HOME/H
# All buttons sit ABOVE a full-screen drag region: drag empty space to look/steer.

var ship: Node
var main: Node

const LOOK_SENS := 0.6        # touch-drag → look multiplier (tune on device)

func _ready() -> void:
	layer = 90                                  # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS     # so MAP (M) still toggles while the map pauses the tree
	_build()


func _build() -> void:
	# Full-screen steer/look region (behind the buttons; buttons added after = on top).
	var look := Control.new()
	look.set_anchors_preset(Control.PRESET_FULL_RECT)
	look.mouse_filter = Control.MOUSE_FILTER_STOP
	look.gui_input.connect(_on_look_input)
	add_child(look)

	# Left cluster.
	_btn("THRUST", Rect2(30, 558, 132, 112), Color(0.4, 0.9, 0.6), true,
		func(on): if ship != null: ship.auto_cruise = on)
	_hold("BOOST", Rect2(30, 436, 132, 104), Color(0.5, 0.8, 1.0), KEY_SHIFT)

	# Right cluster.
	_hold("FIRE", Rect2(1118, 558, 132, 112), Color(1.0, 0.5, 0.35), -1)    # -1 = left mouse
	_hold("CAP", Rect2(978, 558, 124, 112), Color(0.6, 1.0, 0.7), KEY_V)
	_tap("INTERACT", Rect2(1118, 436, 132, 104), Color(0.55, 0.85, 1.0), KEY_F)
	_tap("MAP", Rect2(978, 436, 124, 104), Color(0.7, 0.8, 1.0), KEY_M)
	_tap("HOME", Rect2(1118, 326, 132, 96), Color(1.0, 0.7, 0.5), KEY_H)


# Drag the empty area to steer (touch on a phone, mouse-drag on desktop --touch testing).
func _on_look_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		ship.add_touch_look(event.relative * LOOK_SENS)
	elif event is InputEventMouseMotion and event.button_mask != 0:
		ship.add_touch_look(event.relative * LOOK_SENS)


# --- button builders -------------------------------------------------------
# A toggle button (THRUST): on(true/false) is pushed to `cb`.
func _btn(text: String, rect: Rect2, tint: Color, toggle: bool, cb: Callable) -> void:
	var b := _make_button(text, rect, tint)
	b.toggle_mode = toggle
	b.toggled.connect(func(p): cb.call(p))
	add_child(b)

# A hold button: holds a key (or left mouse when code == -1) down while pressed.
func _hold(text: String, rect: Rect2, tint: Color, code: int) -> void:
	var b := _make_button(text, rect, tint)
	b.button_down.connect(func(): _send(code, true))
	b.button_up.connect(func(): _send(code, false))
	add_child(b)

# A tap button: fires a single key press+release (for main._input actions: F / M / H).
func _tap(text: String, rect: Rect2, tint: Color, code: int) -> void:
	var b := _make_button(text, rect, tint)
	b.pressed.connect(func(): _send(code, true); _send(code, false))
	add_child(b)


func _make_button(text: String, rect: Rect2, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", _box(tint, 0.16))
	b.add_theme_stylebox_override("hover", _box(tint, 0.22))
	b.add_theme_stylebox_override("pressed", _box(tint, 0.5))
	b.add_theme_stylebox_override("focus", _box(tint, 0.0))
	return b

func _box(tint: Color, fill: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, fill)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	return sb


# Synthesise the input the game already polls. code == -1 → left mouse button (FIRE);
# otherwise a key, with BOTH keycode (for main._input) and physical_keycode (for the
# is_physical_key_pressed polling in ship/main) set.
func _send(code: int, pressed: bool) -> void:
	if code == -1:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		Input.parse_input_event(mb)
	else:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
