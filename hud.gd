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
var combat: Combat           # for HP / kills readout
var origin_name := "Earth"   # what the distance readout measures from (per system)

var _dist_label: Label
var _speed_label: Label
var _near_label: Label
var _prompt: Label    # "Press F to dock" near the station
var _menu: Label      # ship-swap panel while docked
var _combat_label: Label
var _reticle: Label
var teleport_button: Button   # connected by main -> teleport_home()


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

	# Combat readout (top-right) + a center aiming reticle.
	_combat_label = _make_label(canvas, Vector2(1000, 18), 18)
	_combat_label.size = Vector2(260, 60)
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_reticle = _make_label(canvas, Vector2(0, 344), 28)
	_reticle.size = Vector2(1280, 32)
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.text = "+"
	_reticle.modulate = Color(0.6, 1.0, 0.9, 0.8)

	_build_teleport_button(canvas)

	var hint := _make_label(canvas, Vector2(20, 686), 14)
	hint.text = "WASD thrust  ·  Space/Ctrl up·down  ·  Q/E roll  ·  Shift boost  ·  L-click fire  ·  J wormhole  ·  H/btn home  ·  Esc cursor"


# Squared, brushed-metal, cyan-glow sci-fi button: "⌖ TELEPORT EARTH".
func _build_teleport_button(canvas: CanvasLayer) -> void:
	teleport_button = Button.new()
	teleport_button.text = "⌖  TELEPORT  EARTH"
	teleport_button.position = Vector2(1040, 660)
	teleport_button.size = Vector2(224, 46)
	teleport_button.focus_mode = Control.FOCUS_NONE
	teleport_button.add_theme_font_size_override("font_size", 16)
	teleport_button.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	teleport_button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	teleport_button.add_theme_stylebox_override("normal", _metal_box(Color(0.40, 0.85, 1.0), 0.45))
	teleport_button.add_theme_stylebox_override("hover", _metal_box(Color(0.55, 0.95, 1.0), 0.85))
	teleport_button.add_theme_stylebox_override("pressed", _metal_box(Color(0.7, 1.0, 1.0), 1.0))
	canvas.add_child(teleport_button)


func _metal_box(edge: Color, glow: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.17)       # dark brushed steel
	sb.set_border_width_all(2)
	sb.border_color = edge                       # cyan edge line (the "glow" rim)
	sb.set_corner_radius_all(3)                  # squared/boxed
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(edge.r, edge.g, edge.b, 0.5 * glow)
	sb.shadow_size = int(10 * glow)              # cyan halo glow around the box
	return sb


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
	_dist_label.text = "From %s:  %s" % [origin_name, _fmt_dist(dist_au)]
	_speed_label.text = "Speed:  %.0f u/s" % ship.velocity.length()

	if combat != null:
		_combat_label.text = "Hull  %d%%\nKills  %d" % [combat.player_hp, combat.kills]

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
