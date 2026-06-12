class_name HUD
extends Node3D
# Minimal HUD: a few code-spawned Labels on a CanvasLayer. No menus, no
# containers, no themes — just text, per the spec.
#
# refresh() is called by main.gd each frame.

# Scale conversions for the readouts. 1 unit = 0.1 AU (see ephemeris.gd).
const AU_PER_UNIT := 0.1
const LY_PER_AU := 1.0 / 63241.077

var ship: Ship
var planets: PlanetSystem

var _dist_label: Label
var _speed_label: Label
var _near_label: Label
var _prompt: Label    # "Press F to dock" near the station
var _menu: Label      # ship-swap panel while docked


func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_dist_label = _make_label(canvas, Vector2(20, 18), 22)
	_speed_label = _make_label(canvas, Vector2(20, 50), 18)
	_near_label = _make_label(canvas, Vector2(20, 78), 18)

	_prompt = _make_label(canvas, Vector2(0, 600), 20)
	_prompt.size = Vector2(1280, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_menu = _make_label(canvas, Vector2(0, 200), 22)
	_menu.size = Vector2(1280, 320)
	_menu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var hint := _make_label(canvas, Vector2(20, 686), 14)
	hint.text = "WASD thrust  ·  Space/Ctrl up·down  ·  Q/E roll  ·  Shift boost  ·  mouse aim  ·  Esc free cursor"


func set_prompt(text: String) -> void:
	_prompt.text = text

func set_menu(text: String) -> void:
	_menu.text = text


func refresh() -> void:
	if ship == null:
		return
	# Distance from Earth (the scene origin). Astronomical distances span a huge
	# range, so show AU in-system and switch to ly once it's large.
	var dist_au := float(ship.true_pos.length()) * AU_PER_UNIT
	_dist_label.text = "From Earth:  %s" % _fmt_dist(dist_au)
	_speed_label.text = "Speed:  %.0f u/s" % ship.velocity.length()

	if planets != null and planets.nearest_name != "":
		var near_au := planets.nearest_dist * AU_PER_UNIT
		_near_label.text = "Nearest:  %s  (%s)" % [planets.nearest_name, _fmt_dist(near_au)]


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
