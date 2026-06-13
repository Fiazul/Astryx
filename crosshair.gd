extends Control
# Dynamic aiming reticle: four ticks around a center dot. The gap between them
# breathes — it blooms out while you're firing (and kicks on a confirmed hit),
# then eases back to a tight rest gap. Colour warms from cyan toward gold the more
# it's blooming. Driven by HUD.refresh() via set_target(); eased in _process().

const REST_GAP := 5.0      # tick gap at rest (tight)
const FIRE_GAP := 12.0     # extra gap while holding fire
const HIT_GAP := 9.0       # extra kick on a landed hit (decays with the hitmarker)
const TICK_LEN := 7.0
const THICK := 2.0
const EASE := 14.0         # how fast the gap chases its target

const C_CALM := Color(0.6, 1.0, 0.9, 0.85)
const C_HOT := Color(1.0, 0.85, 0.45, 0.95)

var _gap := REST_GAP
var _target := REST_GAP
var _heat := 0.0           # 0 calm .. 1 hot (drives colour)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# bloom 0..1 (firing), kick 0..1 (recent hit). Called each frame by the HUD.
func set_target(bloom: float, kick: float) -> void:
	_target = REST_GAP + FIRE_GAP * clampf(bloom, 0.0, 1.0) + HIT_GAP * clampf(kick, 0.0, 1.0)
	_heat = clampf(maxf(bloom, kick), 0.0, 1.0)

func _process(delta: float) -> void:
	var k := clampf(EASE * delta, 0.0, 1.0)
	_gap = lerpf(_gap, _target, k)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var col := C_CALM.lerp(C_HOT, _heat)
	var g := _gap
	draw_line(c + Vector2(-g - TICK_LEN, 0), c + Vector2(-g, 0), col, THICK, true)
	draw_line(c + Vector2(g, 0), c + Vector2(g + TICK_LEN, 0), col, THICK, true)
	draw_line(c + Vector2(0, -g - TICK_LEN), c + Vector2(0, -g), col, THICK, true)
	draw_line(c + Vector2(0, g), c + Vector2(0, g + TICK_LEN), col, THICK, true)
	draw_circle(c, 1.5, col)
