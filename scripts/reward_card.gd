class_name RewardCard
extends CanvasLayer
# A fancy, semi-transparent celebration card that pops on a CAPTURE — top-centre, without
# pausing flight or grabbing input. It congratulates you, shows the captured body + its
# reward, then fades away on its own after a few seconds.

var _panel: PanelContainer
var _name: Label
var _detail: Label
var _reward: Label
var _life := 0.0

const SHOW := 5.0      # total seconds on screen
const FADE_IN := 0.35
const FADE_OUT := 1.4


func _ready() -> void:
	layer = 78
	process_mode = Node.PROCESS_MODE_ALWAYS   # celebrate even if something paused the tree
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks clicks/flight
	# Anchor top-centre.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = 70
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.55)         # semi-transparent
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.82, 0.35, 0.9)       # warm gold edge
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(1.0, 0.7, 0.2, 0.25)
	sb.shadow_size = 18
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	var head := Label.new()
	head.text = "✦   C A P T U R E D   ✦"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	col.add_child(head)

	_name = _line(col, 30, Color(0.95, 0.98, 1.0))
	_detail = _line(col, 16, Color(0.75, 0.85, 0.95))
	_reward = _line(col, 22, Color(0.6, 1.0, 0.7))

	var congrats := Label.new()
	congrats.text = "Well flown, Captain."
	congrats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	congrats.add_theme_font_size_override("font_size", 14)
	congrats.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	col.add_child(congrats)

	_panel.modulate.a = 0.0
	_panel.visible = false


func _line(parent: VBoxContainer, size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


# Pop the card for a fresh capture. `detail` is a short subtitle (e.g. the mission title).
func celebrate(body: String, detail: String, reward: int) -> void:
	_name.text = body
	_detail.text = detail
	_reward.text = "+ %d  ✦  coins" % reward
	_life = SHOW
	_panel.visible = true
	_panel.modulate.a = 0.0


func _process(delta: float) -> void:
	if _life <= 0.0:
		return
	_life -= delta
	if _life <= 0.0:
		_panel.visible = false
		_panel.modulate.a = 0.0
		return
	var elapsed := SHOW - _life
	var a := 1.0
	if elapsed < FADE_IN:
		a = elapsed / FADE_IN                 # fade in
	elif _life < FADE_OUT:
		a = _life / FADE_OUT                  # fade out
	_panel.modulate.a = clampf(a, 0.0, 1.0)
	# A gentle floaty drift upward as it fades out, for a touch of life.
	_panel.offset_top = 70.0 - (1.0 - clampf(_life / FADE_OUT, 0.0, 1.0)) * 16.0
