class_name CombatFX
extends Node
# Transient combat visual effects + bolt/flash materials (Phase 3 extraction from combat.gd).
# Owns the small baked textures it needs (radial glow, ragged hit splatters, plume gradient) and
# parents its one-shot effect quads under itself. combat spawns one of these and drives it:
#   fx.boom(at) / fx.hit_flash(at) / fx.enemy_flash(at, size)   — fire-and-forget effects
#   fx.bolt_material(c) / fx.trail_material(c)                   — build combat's shared bolt mats

const DEFAULT_BOOM_SIZE := 6.0   # = combat.gd ALIEN_SIZE (longest-axis units of a standard alien)

var _glow_tex: Texture2D
var _splatters: Array[Texture2D] = []    # irregular hit-spark shapes, picked at random
var _trail_grad: Texture2D               # bright head → clear tail, for bolt plume trails


func _ready() -> void:
	_glow_tex = _make_glow()
	# Bake a few random irregular spark shapes once; hit_flash() picks one per hit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	for i in 5:
		_splatters.append(_make_splatter(rng))
	_trail_grad = ShipMesh.make_plume_gradient(true)   # bright at the head (+Y), clear at the tail


# A layered impact spark at a hit point (picks a random ragged splatter, grows + fades out).
func hit_flash(at: Vector3, scale := 1.0) -> void:
	var tex: Texture2D = _splatters[randi() % _splatters.size()]
	var layers := [
		{ "size": 2.4, "grow": 1.7, "col": Color(1.0, 0.95, 0.8, 0.45),  "t": 0.18 },
		{ "size": 4.0, "grow": 2.0, "col": Color(1.0, 0.55, 0.2, 0.28),  "t": 0.22 },
	]
	for L in layers:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new(); q.size = Vector2(L.size, L.size) * scale
		mi.mesh = q
		mi.material_override = _flash_mat(tex, L.col)
		mi.position = at
		mi.scale = Vector3(0.3, 0.3, 0.3)
		add_child(mi)
		var tw := create_tween()
		tw.tween_property(mi, "scale", Vector3(L.grow, L.grow, L.grow), L.t)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi.material_override, "albedo_color:a", 0.0, L.t)
		tw.tween_callback(mi.queue_free)


# A quick white flash sized to the enemy — it visibly reacts to being hit.
func enemy_flash(at: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(size * 1.5, size * 1.5)
	mi.mesh = q
	mi.material_override = _flash_mat(_glow_tex, Color(1.0, 1.0, 1.0, 0.9))
	mi.position = at
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.14)
	tw.tween_callback(mi.queue_free)


# A growing additive glow burst on death.
func boom(at: Vector3, size := DEFAULT_BOOM_SIZE) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(size * 2.2, size * 2.2)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _glow_tex
	mat.albedo_color = Color(1.0, 0.7, 0.3, 1.0)
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(2.5, 2.5, 2.5), 0.4)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(mi.queue_free)


func bolt_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.albedo_color = c.lerp(Color.WHITE, 0.6)    # white-hot core reads brighter
	# Kept LOW (was 20) so the HDR bloom can't balloon a bolt into a fat blob near the close
	# chase-cam — the same bounded-brightness trick that keeps Raptor 2's laser clean.
	m.emission_energy_multiplier = 4.0
	return m


# A mini engine-plume tail for a bolt — additive, double-sided, alpha driven by the plume gradient
# so it fades smoothly from a bright nozzle (at the bolt) to a clear point behind it.
func trail_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # both sides -> a full plume, not a half curve
	m.albedo_texture = _trail_grad               # gradient drives the nozzle->tail fade
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)  # tint; gradient handles the falloff
	return m


func _flash_mat(tex: Texture2D, col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = col
	return mat


func _make_glow() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.6)))
	return ImageTexture.create_from_image(img)


# A random irregular spark "splatter": a bright core whose alpha fades out to a ragged, NON-circular
# edge — the edge radius wobbles per-angle with a few random harmonics, baked once and picked per hit.
func _make_splatter(rng: RandomNumberGenerator) -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	var terms := []
	for i in rng.randi_range(3, 5):
		terms.append([float(rng.randi_range(3, 9)), rng.randf_range(0.08, 0.20), rng.randf_range(0.0, TAU)])
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5) - c
			var r := d.length() / (s * 0.5)
			var ang := atan2(d.y, d.x)
			var edge := 0.52
			for t in terms:
				edge += t[1] * sin(ang * t[0] + t[2])
			edge = clampf(edge, 0.16, 0.96)
			var a := pow(clampf(1.0 - r / edge, 0.0, 1.0), 1.7)   # bright core, soft ragged fade
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
