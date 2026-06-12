class_name Combat
extends Node3D
# Dogfighting in floating-origin space. Aliens, your bolts and their bolts all
# live in absolute `true_pos` (same frame as the planets) and are rendered at
# (true_pos - ship.true_pos) every frame, so nothing drifts as you fly.
#
# You: left-click fires bolts where your nose points (aim by flying). Aliens:
# big GLB ships that drift toward you and auto-fire. Bolt↔target hits are simple
# sphere checks. Dead aliens pop and respawn after a beat.

const ALIEN_MODELS := ["res://Spaceship (1).glb", "res://Spaceship (2).glb"]
const ALIEN_COUNT := 3
const ALIEN_SIZE := 6.0           # big — longest axis in units
const ALIEN_HP := 3
const ALIEN_SPEED := 14.0
const ALIEN_KEEP_DIST := 30.0     # they hover around this range and strafe
const ALIEN_FIRE_EVERY := 2.2
const RESPAWN_AFTER := 4.0
const SPAWN_RADIUS := 60.0        # where new aliens appear around the player

const BOLT_SPEED := 750.0          # machine-gun fast bolts
const BOLT_LIFE := 2.5
const BOLT_COOLDOWN := 0.06        # ~16 shots/sec
const ALIEN_BOLT_SPEED := 90.0
const SHIP_HIT_RADIUS := 2.0
const PLAYER_MAX_HP := 100

var player_hp := PLAYER_MAX_HP
var kills := 0

var _aliens := []                 # { pos, vel, hp, node, fire_cd, alive, respawn }
var _bolts := []                  # player bolts: { pos, vel, life, node }
var _abolts := []                 # alien bolts:  { pos, vel, life, node }
var _cool := 0.0
var _bolt_mesh: SphereMesh
var _bolt_mat: StandardMaterial3D
var _abolt_mat: StandardMaterial3D
var _glow_tex: Texture2D


func _ready() -> void:
	_glow_tex = _make_glow()
	_bolt_mesh = SphereMesh.new()
	_bolt_mesh.radius = 0.25
	_bolt_mesh.height = 0.5
	_bolt_mesh.radial_segments = 8
	_bolt_mesh.rings = 4
	_bolt_mat = _bolt_material(Color(0.5, 0.9, 1.0))     # your bolts: cyan
	_abolt_mat = _bolt_material(Color(1.0, 0.4, 0.3))    # alien bolts: red
	for i in ALIEN_COUNT:
		_aliens.append(_make_alien())


# Respawn the fight when you change systems (fresh enemies in the new place).
func reset() -> void:
	for a in _aliens:
		if a.node != null:
			a.node.queue_free()
	_aliens.clear()
	for b in _bolts:
		b.node.queue_free()
	_bolts.clear()
	for b in _abolts:
		b.node.queue_free()
	_abolts.clear()
	player_hp = PLAYER_MAX_HP
	for i in ALIEN_COUNT:
		_aliens.append(_make_alien())


# Called by main each frame. `pressed` = is the fire button held.
func update(ship: Node3D, pressed: bool, delta: float) -> void:
	var sp: Vector3 = ship.true_pos
	var fwd: Vector3 = -ship.transform.basis.z

	# --- player firing ---
	_cool = maxf(_cool - delta, 0.0)
	if pressed and _cool <= 0.0:
		_cool = BOLT_COOLDOWN
		_spawn_bolt(_bolts, sp + fwd * 2.5, fwd * BOLT_SPEED, _bolt_mat)

	_step_bolts(_bolts, sp, delta, true)
	_step_bolts(_abolts, sp, delta, false)
	_step_aliens(ship, sp, delta)


# ---------------------------------------------------------------------------
func _step_aliens(ship: Node3D, sp: Vector3, delta: float) -> void:
	for a in _aliens:
		if not a.alive:
			a.respawn -= delta
			if a.respawn <= 0.0:
				_revive(a, sp)
			continue
		var to_ship: Vector3 = sp - a.pos
		var dist := to_ship.length()
		var dir: Vector3 = to_ship / maxf(dist, 0.001)
		# Close to keep-distance, then strafe sideways a little.
		var want := dir * ALIEN_SPEED
		if dist < ALIEN_KEEP_DIST:
			want = -dir * ALIEN_SPEED * 0.5
		var side := dir.cross(Vector3.UP).normalized()
		want += side * ALIEN_SPEED * 0.4 * sin(Time.get_ticks_msec() * 0.001 + a.phase)
		a.vel = a.vel.lerp(want, clampf(2.0 * delta, 0.0, 1.0))
		a.pos += a.vel * delta
		a.node.position = a.pos - sp
		# face the player (ship sits at the world origin); guard degenerate cases
		if a.node.position.length() > 0.5 and absf(dir.dot(Vector3.UP)) < 0.98:
			a.node.look_at(Vector3.ZERO, Vector3.UP)

		# auto-fire at the player
		a.fire_cd -= delta
		if a.fire_cd <= 0.0 and dist < SPAWN_RADIUS * 1.5:
			a.fire_cd = ALIEN_FIRE_EVERY
			var aim: Vector3 = (sp - a.pos).normalized()
			_spawn_bolt(_abolts, a.pos + aim * (ALIEN_SIZE * 0.5), aim * ALIEN_BOLT_SPEED, _abolt_mat)


func _step_bolts(list: Array, sp: Vector3, delta: float, player: bool) -> void:
	var i := list.size() - 1
	while i >= 0:
		var b = list[i]
		b.pos += b.vel * delta
		b.life -= delta
		b.node.position = b.pos - sp
		var hit := false
		if player:
			for a in _aliens:
				if a.alive and a.pos.distance_to(b.pos) < ALIEN_SIZE * 0.5:
					_damage_alien(a, sp)
					hit = true
					break
		else:
			if b.pos.distance_to(sp) < SHIP_HIT_RADIUS:
				player_hp = maxi(player_hp - 8, 0)
				hit = true
		if hit or b.life <= 0.0:
			b.node.queue_free()
			list.remove_at(i)
		i -= 1


func _damage_alien(a: Dictionary, sp: Vector3) -> void:
	a.hp -= 1
	if a.hp <= 0:
		a.alive = false
		a.respawn = RESPAWN_AFTER
		a.node.visible = false
		kills += 1
		_boom(a.pos - sp)


func _revive(a: Dictionary, sp: Vector3) -> void:
	a.hp = ALIEN_HP
	a.alive = true
	a.pos = sp + _rand_dir() * SPAWN_RADIUS
	a.vel = Vector3.ZERO
	a.node.position = a.pos - sp
	a.node.visible = true


# ---------------------------------------------------------------------------
func _make_alien() -> Dictionary:
	var node := _load_alien_model()   # already added to the tree (so fit can measure it)
	var a := {
		"pos": _rand_dir() * SPAWN_RADIUS, "vel": Vector3.ZERO, "hp": ALIEN_HP,
		"node": node, "fire_cd": randf_range(0.5, ALIEN_FIRE_EVERY), "alive": true,
		"respawn": 0.0, "phase": randf_range(0.0, TAU),
	}
	node.position = a.pos
	return a


func _load_alien_model() -> Node3D:
	for path in ALIEN_MODELS:
		var packed := load(path) as PackedScene
		if packed != null:
			var holder := Node3D.new()
			add_child(holder)                        # in tree BEFORE fitting (needs global xform)
			var inst := packed.instantiate() as Node3D
			holder.add_child(inst)
			_fit_and_light(holder, inst, ALIEN_SIZE)
			return holder
	# fallback: a menacing emissive prism if the GLBs aren't there yet
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new(); m.size = Vector3(ALIEN_SIZE, ALIEN_SIZE * 0.4, ALIEN_SIZE * 0.7)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.3)
	mat.emission_energy_multiplier = 0.6
	mi.material_override = mat
	add_child(mi)
	return mi


func _spawn_bolt(list: Array, pos: Vector3, vel: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	list.append({ "pos": pos, "vel": vel, "life": BOLT_LIFE, "node": mi })


func _boom(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(ALIEN_SIZE * 2.2, ALIEN_SIZE * 2.2)
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


# ---------------------------------------------------------------------------
func _bolt_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.albedo_color = c
	m.emission_energy_multiplier = 3.0
	return m


func _rand_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()


func _fit_and_light(holder: Node3D, model: Node3D, target: float) -> void:
	var box := _aabb(holder)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.0001:
		var f := target / longest
		model.scale = model.scale * f
		model.position -= (box.position + box.size * 0.5) * f
	for mi in _meshes(model):
		for si in mi.mesh.get_surface_count():
			var o = mi.get_active_material(si)
			var m: BaseMaterial3D = o.duplicate() if o is BaseMaterial3D else StandardMaterial3D.new()
			m.metallic = 0.2
			m.emission_enabled = true
			m.emission = Color(0.7, 0.3, 0.9)   # alien purple-green glow so they pop
			m.emission_energy_multiplier = 0.5
			mi.set_surface_override_material(si, m)


func _aabb(root: Node3D) -> AABB:
	var out := AABB(); var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _meshes(root):
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _make_glow() -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.6)))
	return ImageTexture.create_from_image(img)
