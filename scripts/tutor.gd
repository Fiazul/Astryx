class_name Tutor
extends CanvasLayer
# New-game onboarding notifications. Small, non-blocking tip boxes that fade in on the LEFT
# MIDDLE one at a time (on a random interval), each with a soft "ting-tong". A box shows a
# short line; CLICK it to expand the detail; DRAG it off the left edge to dismiss it. They
# auto-fade after a while. Only runs on a fresh game (main calls start()).

var audio                       # set by main, for the ting-tong chime
var main                        # set by main — lets us pace faster while Sol isn't unlocked

const MARGIN_X := 18.0          # gap from the left edge
const BOX_W := 300.0
const GAP := 10.0
const ANCHOR_Y := 250.0         # top of the stack (design space 1280×720) — left-of-middle
const LIFE := 16.0              # seconds a tip lingers before auto-fading
const DISMISS_X := -70.0        # drag the box left past this → dismissed

var _tips := [
	{ "t": "Open the Map", "s": "Press  M  for the star map.",
	  "d": "The map shows stars, wormholes, planets and platforms on toggleable layers. Pan, zoom, and pick destinations from it." },
	{ "t": "Aim a target", "s": "Aim down the line, press  Tab.",
	  "d": "Tab steps through the up-to-4 objects your aim ray passes nearest to (closest first). Move the cursor to re-rank. Unscanned ones read 'Unknown' until you scan them." },
	{ "t": "Lock navigation", "s": "Hold  X  to lock the target (orange).",
	  "d": "After Tab-ing a target, hold X for a second to LOCK it — the nav turns orange and sticks through aim changes and further Tabs. Only the ✖ Cancel Nav button clears it." },
	{ "t": "Free-look camera", "s": "Hold  T  (or right-click) to look around.",
	  "d": "Holding T orbits the camera a full 360° around your ship while you keep flying — great for lining up shots and screenshots. Release to fly normally." },
	{ "t": "Fire", "s": "Left-click to shoot.",
	  "d": "Your guns fire instant ray-bullets straight down the crosshair. Hold to keep firing; opening fire slows you to combat speed." },
	{ "t": "Dock & wormholes", "s": "Press  F  to dock or enter a wormhole.",
	  "d": "Near a station, F docks (swap ships, customize, teleport). Near a glowing wormhole, F dives through to a neighbouring system." },
	{ "t": "Scan to discover", "s": "Press  V  near a body to scan it.",
	  "d": "Scanning reveals a body's data in the Codex (C) and details panel (G), and completes its survey mission." },
	{ "t": "Mission Log", "s": "Press  J  for missions.",
	  "d": "Every star, planet and moon is a mission with a story and a coin bounty. Track one and the nav arrow guides you to it." },
	{ "t": "Boost & roll", "s": "Shift = boost · Q/E roll · Space/Ctrl up·down.",
	  "d": "WASD thrusts, Shift boosts (drains the boost bar), Q/E roll the hull, Space/Ctrl climb and dive. Heavier hulls drift more." },
	{ "t": "Warp", "s": "Hold  W  in open space to spool FTL.",
	  "d": "Once you're clear of a star's slow-zone, holding W spools the warp drive and you cross light-years. Near bodies you stay sublight." },
	{ "t": "Platform jumps", "s": "Dock, then open TELEPORT NETWORK.",
	  "d": "From any platform you've reached, open the teleport console and jump straight to another platform — then short-fly the rest." },
	{ "t": "Teleport home", "s": "Press  H  to return to Earth.",
	  "d": "An emergency jump back to Earth from anywhere. A light-ball wraps the ship, shrinks, and you're home." },
	{ "t": "Swap ships", "s": "Press  1–7  while docked.",
	  "d": "Each hull flies differently — tanky, glass-cannon, FTL, support, mother-ship. Some can be recoloured in the hangar." },
]

var _order := []
var _next := 0
var _timer := 0.0
var _running := false
var _active := []               # [{ panel, life, detail, dragging, moved }]
var _root: Control


func _ready() -> void:
	layer = 70
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # only the boxes catch input
	add_child(_root)


# Begin the onboarding sequence (fresh game only).
func start() -> void:
	_order = range(_tips.size()).duplicate()
	_order.shuffle()
	_next = 0
	_timer = 3.0          # first tip a few seconds in
	_running = true


func stop() -> void:
	_running = false


func _process(delta: float) -> void:
	# Spawn the next tip on a random interval — FASTER while the player hasn't fully unlocked
	# (scanned) the home Sol system, then it slows and stops once they've found their feet.
	if _running:
		_timer -= delta
		if _timer <= 0.0:
			var beginner: bool = main != null and not main._sol_fully_unlocked()
			if _next >= _order.size():
				if beginner:
					_order.shuffle()    # still learning → loop the tips
					_next = 0
				else:
					_running = false    # Sol unlocked → done after one pass
			if _running and _next < _order.size():
				_spawn(_tips[_order[_next]])
				_next += 1
				_timer = randf_range(4.0, 8.0) if beginner else randf_range(10.0, 16.0)
	# Age + fade active notes; drop the expired.
	for n in _active.duplicate():
		if not n.dragging:
			n.life -= delta
			if n.life <= 0.0:
				_dismiss(n)
				continue
			n.panel.modulate.a = clampf(n.life, 0.0, 1.0)   # fade out in the last second
	_restack()


func _spawn(tip: Dictionary) -> void:
	# Cap concurrent boxes — retire the oldest if we're full.
	while _active.size() >= 4:
		_dismiss(_active[0])

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(BOX_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.92)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.85, 1.0, 0.8)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var head := Label.new()
	head.text = "◈  %s" % str(tip.t)
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)

	var short := Label.new()
	short.text = str(tip.s)
	short.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	short.custom_minimum_size = Vector2(BOX_W - 20, 0)
	short.add_theme_font_size_override("font_size", 15)
	short.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	short.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(short)

	var detail := Label.new()
	detail.text = str(tip.d)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(BOX_W - 20, 0)
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.visible = false
	vb.add_child(detail)

	var foot := Label.new()
	foot.text = "click for more · drag away to dismiss"
	foot.add_theme_font_size_override("font_size", 10)
	foot.add_theme_color_override("font_color", Color(0.5, 0.6, 0.72))
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(foot)

	panel.position = Vector2(MARGIN_X, ANCHOR_Y)
	panel.modulate.a = 0.0
	_root.add_child(panel)
	var note := { "panel": panel, "life": LIFE, "detail": detail, "foot": foot,
		"dragging": false, "moved": false }
	panel.gui_input.connect(_on_note_input.bind(note))
	_active.append(note)
	if audio != null:
		audio.play_notify()


func _on_note_input(event: InputEvent, note: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			note.dragging = true
			note.moved = false
			note.panel.modulate.a = 1.0
		else:
			note.dragging = false
			if note.moved:
				if note.panel.position.x < DISMISS_X:
					_dismiss(note)        # flicked off the left → gone
			else:
				# A clean click toggles the detail and refreshes its lifetime.
				note.detail.visible = not note.detail.visible
				note.foot.text = "click to collapse · drag away to dismiss" if note.detail.visible \
					else "click for more · drag away to dismiss"
				note.life = LIFE
	elif event is InputEventMouseMotion and note.dragging:
		note.panel.position += event.relative
		if absf(event.relative.x) + absf(event.relative.y) > 1.5:
			note.moved = true


func _dismiss(note: Dictionary) -> void:
	var i := _active.find(note)
	if i >= 0:
		_active.remove_at(i)
	if is_instance_valid(note.panel):
		note.panel.queue_free()


# Stack the (non-dragged) boxes down the left-middle.
func _restack() -> void:
	var y := ANCHOR_Y
	for n in _active:
		if not n.dragging and is_instance_valid(n.panel):
			n.panel.position.x = MARGIN_X
			n.panel.position.y = y
			y += n.panel.size.y + GAP
