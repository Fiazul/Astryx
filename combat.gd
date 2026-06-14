class_name Combat
extends Node3D
# Dogfighting in floating-origin space. Aliens, your bolts and their bolts all
# live in absolute `true_pos` (same frame as the planets) and are rendered at
# (true_pos - ship.true_pos) every frame, so nothing drifts as you fly.
#
# You: left-click fires bolts where your nose points (aim by flying). Aliens:
# big GLB ships that drift toward you and auto-fire. Bolt↔target hits are simple
# sphere checks. Dead aliens pop and respawn after a beat.

# The monster roster — guardians/swarm pick one at random per spawn, so stars,
# planets and moons are defended by a mix of UFOs, blobs, demons, ghosts, etc.
const ALIEN_MODELS := [
	"res://ufo.glb", "res://blob.glb", "res://demon.glb", "res://ghost.glb",
	"res://enemy_small.glb", "res://mushnub.glb", "res://alien_ship.glb",
]
const ALIEN_COUNT := 3
const SWARM_COUNT := 14           # "large chunk" of aliens around every non-Sol star
const ALIEN_SIZE := 6.0           # big — longest axis in units
const ALIEN_HP := 3
const ALIEN_SPEED := 14.0
const ALIEN_KEEP_DIST := 30.0     # they hover around this range and strafe
const ALIEN_FIRE_EVERY := 2.2
const RESPAWN_AFTER := 4.0
const SPAWN_RADIUS := 60.0        # where new aliens appear around the player

# --- VORTEX: the boss. Vortex's own ship hull, scaled up huge and menacing. ---
const BOSS_MODEL := "res://Spaceship (1).glb"   # Vortex's hull, kept as the boss design
const BOSS_SIZE := 60.0           # extremely big
const BOSS_HP := 60
const BOSS_SPEED := 7.0           # slow and heavy
const BOSS_KEEP_DIST := 80.0
const BOSS_FIRE_EVERY := 1.2
const BOSS_RESPAWN_AFTER := 9.0
const BOSS_SPAWN_DIST := 160.0

const BOLT_SPEED := 950.0          # fast tracers (swept collision keeps hits reliable)
const BOLT_LIFE := 2.5
const BOLT_COOLDOWN := 0.22        # ~4.5 shots/sec — same comfortable delay between shots
const ALIEN_BOLT_SPEED := 90.0
const HIT_RADIUS_MULT := 0.95      # enemy hit box as a fraction of body size (was 0.55 — more forgiving)
const SHIP_HIT_RADIUS := 2.0
const PLAYER_MAX_HP := 100

var player_hp := PLAYER_MAX_HP
var player_max := PLAYER_MAX_HP   # current hull's max HP (set from the active ship)
var kills := 0
var hitmarker := 0.0              # >0 for a moment after a shot lands (HUD reads it)

var audio: GameAudio              # set by main; SFX for fire / explosion
var planets: PlanetSystem         # set by main; lets gravity wells bend bolts

var _aliens := []                 # { pos, vel, hp, node, fire_cd, alive, respawn }
var _bolts := []                  # player bolts: { pos, vel, life, node }
var _abolts := []                 # alien bolts:  { pos, vel, life, node }
var _cool := 0.0
var _bolt_mesh: SphereMesh
var _bolt_mat: StandardMaterial3D
var _abolt_mat: StandardMaterial3D
var _glow_tex: Texture2D
var _splatters: Array[Texture2D] = []    # irregular hit-spark shapes, picked at random


func _ready() -> void:
	_glow_tex = _make_glow()
	# Bake a few random irregular spark shapes once; _hit_flash picks one per hit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	for i in 5:
		_splatters.append(_make_splatter(rng))
	_bolt_mesh = SphereMesh.new()                # round "ball" bolts, slightly larger
	_bolt_mesh.radius = 0.48
	_bolt_mesh.height = 0.96
	_bolt_mesh.radial_segments = 12
	_bolt_mesh.rings = 6
	_bolt_mat = _bolt_material(Color(0.5, 0.9, 1.0))     # your bolts: cyan
	_abolt_mat = _bolt_material(Color(1.0, 0.4, 0.3))    # alien bolts: red
	# No enemies spawn until main calls reset(true) for a hostile system.


# Rebuild the fight when entering a system.
#   active    : spawn an alien swarm here (every star except peaceful Sol)
#   with_boss : also spawn Vortex (only the true hostile Alien zone)
#   count     : swarm size (defaults to the big SWARM_COUNT)
# Sol stays peaceful (active = false) — a safe home harbor.
func reset(active := false, with_boss := false, count := SWARM_COUNT) -> void:
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
	if active:
		for i in count:
			_aliens.append(_make_alien())
		if with_boss:
			_aliens.append(_make_boss())   # Vortex


# Called by main each frame. `pressed` = is the fire button held.
func update(ship: Node3D, pressed: bool, delta: float) -> void:
	hitmarker = maxf(hitmarker - delta, 0.0)
	var sp: Vector3 = ship.true_pos
	var fwd: Vector3 = -ship.transform.basis.z

	# Per-hull combat identity: defence (max HP), bullet speed and bullet size all come
	# from the active ship (see SHIP_MODELS). player_max drives the HUD's hull bar.
	player_max = ship.max_hp if ship.has_method("is_hypersonic") else PLAYER_MAX_HP
	player_hp = mini(player_hp, player_max)

	# --- player firing: pure straight shots, no aim assist (utility hulls can't fire) ---
	_cool = maxf(_cool - delta, 0.0)
	if pressed and _cool <= 0.0 and ship.can_fire:
		_cool = ship.fire_cooldown if ship.has_method("is_hypersonic") else BOLT_COOLDOWN
		_spawn_bolt(_bolts, sp + fwd * ship.muzzle, fwd * ship.bolt_speed, _bolt_mat, ship.bolt_scale, ship.bolt_damage)
		if audio != null:
			audio.play_fire()

	_step_bolts(_bolts, sp, delta, true)
	_step_bolts(_abolts, sp, delta, false)
	_step_aliens(ship, sp, delta)


# ---------------------------------------------------------------------------
func _step_aliens(ship: Node3D, sp: Vector3, delta: float) -> void:
	for a in _aliens:
		if not a.alive:
			if a.get("guardian", false):
				continue   # guardians don't respawn — once cleared, the body is yours
			a.respawn -= delta
			if a.respawn <= 0.0:
				_revive(a, sp)
			continue
		var to_ship: Vector3 = sp - a.pos
		var dist := to_ship.length()
		var dir: Vector3 = to_ship / maxf(dist, 0.001)
		# Close to keep-distance, then strafe sideways a little.
		var want: Vector3 = dir * float(a.speed)
		if dist < a.keep:
			want = -dir * float(a.speed) * 0.5
		var side := dir.cross(Vector3.UP).normalized()
		want += side * float(a.speed) * 0.4 * sin(Time.get_ticks_msec() * 0.001 + a.phase)
		a.vel = a.vel.lerp(want, clampf(2.0 * delta, 0.0, 1.0))
		a.pos += a.vel * delta
		a.node.position = a.pos - sp
		# face the player (ship sits at the world origin); guard degenerate cases
		if a.node.position.length() > 0.5 and absf(dir.dot(Vector3.UP)) < 0.98:
			a.node.look_at(Vector3.ZERO, Vector3.UP)

		# auto-fire at the player
		a.fire_cd -= delta
		if a.fire_cd <= 0.0 and dist < a.spawn_dist * 1.6:
			a.fire_cd = a.fire_every
			var aim: Vector3 = (sp - a.pos).normalized()
			_spawn_bolt(_abolts, a.pos + aim * (a.size * 0.5), aim * ALIEN_BOLT_SPEED, _abolt_mat)


func _step_bolts(list: Array, sp: Vector3, delta: float, player: bool) -> void:
	var i := list.size() - 1
	while i >= 0:
		var b = list[i]
		var prev: Vector3 = b.pos
		if planets != null:
			b.vel += planets.gravity_at(b.pos) * delta   # bolts curve through gravity wells
		b.pos += b.vel * delta
		b.life -= delta
		b.node.position = b.pos - sp
		var hit := false
		if player:
			# Swept test: the bolt moves far each frame, so check the whole
			# segment it travelled, not just its end point (no tunnelling).
			for a in _aliens:
				if a.alive and _seg_point_dist(prev, b.pos, a.pos) < a.size * HIT_RADIUS_MULT + b.r:
					_damage_alien(a, sp, int(b.dmg))
					_hit_flash(b.pos - sp)            # impact pop
					_enemy_flash(a.pos - sp, a.size)  # the enemy lights up
					hitmarker = 0.18                  # HUD crosshair confirms the hit
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


func _damage_alien(a: Dictionary, sp: Vector3, dmg := 1) -> void:
	a.hp -= dmg
	if a.hp <= 0:
		a.alive = false
		a.respawn = a.respawn_after
		a.node.visible = false
		kills += 1
		_boom(a.pos - sp, a.size)
		if audio != null:
			audio.play_explosion()


func _revive(a: Dictionary, sp: Vector3) -> void:
	a.hp = a.max_hp
	a.alive = true
	a.pos = sp + _rand_dir() * a.spawn_dist
	a.vel = Vector3.ZERO
	a.node.position = a.pos - sp
	a.node.visible = true


# Boss state for the HUD: returns alive/hp/max for Vortex (or alive=false).
func boss_state() -> Dictionary:
	for a in _aliens:
		if a.is_boss:
			return { "alive": a.alive, "hp": a.hp, "max": a.max_hp }
	return { "alive": false, "hp": 0, "max": 1 }


# Monster data for a probe scan: how many hostiles are loose, total swarm size,
# whether Vortex is present/alive, and your running kill count.
func threat_report() -> Dictionary:
	var alive := 0
	var total := 0
	for a in _aliens:
		if a.is_boss:
			continue
		total += 1
		if a.alive:
			alive += 1
	return { "alive": alive, "total": total, "boss": boss_state(), "kills": kills }


# --- Guardians: a non-respawning cluster that defends a capturable body. main spawns
# them when you approach a guarded body, and the body is capturable once they're clear.
var guard_body := ""    # name of the body these guardians defend ("" = none)

func set_guardians(center: Vector3, count: int, body: String) -> void:
	clear_guardians()
	guard_body = body
	for i in count:
		var a := _make_alien()
		a["guardian"] = true
		a["respawn_after"] = -1.0                       # never respawn
		a.pos = center + _rand_dir() * (float(a.size) * 6.0 + 40.0)
		a.node.position = a.pos                          # rendered at pos - ship each frame
		_aliens.append(a)

func clear_guardians() -> void:
	var keep := []
	for a in _aliens:
		if a.get("guardian", false):
			a.node.queue_free()
		else:
			keep.append(a)
	_aliens = keep
	guard_body = ""

func guardians_alive() -> int:
	var n := 0
	for a in _aliens:
		if a.get("guardian", false) and a.alive:
			n += 1
	return n


# ---------------------------------------------------------------------------
func _make_alien() -> Dictionary:
	var node := _load_alien_model()   # already added to the tree (so fit can measure it)
	return _make_enemy(node, {
		"size": ALIEN_SIZE, "hp": ALIEN_HP, "speed": ALIEN_SPEED, "keep": ALIEN_KEEP_DIST,
		"fire_every": ALIEN_FIRE_EVERY, "respawn_after": RESPAWN_AFTER,
		"spawn_dist": SPAWN_RADIUS, "is_boss": false,
	})


# VORTEX — the boss. Vortex's own hull, scaled up huge with a red-hot menace tint.
func _make_boss() -> Dictionary:
	var node := _load_boss_model()
	return _make_enemy(node, {
		"size": BOSS_SIZE, "hp": BOSS_HP, "speed": BOSS_SPEED, "keep": BOSS_KEEP_DIST,
		"fire_every": BOSS_FIRE_EVERY, "respawn_after": BOSS_RESPAWN_AFTER,
		"spawn_dist": BOSS_SPAWN_DIST, "is_boss": true,
	})


func _load_boss_model() -> Node3D:
	var packed := load(BOSS_MODEL) as PackedScene
	if packed != null:
		var holder := Node3D.new()
		add_child(holder)                       # in tree BEFORE fitting (needs global xform)
		var inst := packed.instantiate() as Node3D
		holder.add_child(inst)
		_fit_and_light(holder, inst, BOSS_SIZE)
		# Overpaint with a menacing red-hot emission so the boss reads as a threat.
		for mi in _meshes(inst):
			for si in mi.mesh.get_surface_count():
				var o = mi.get_active_material(si)
				var m: BaseMaterial3D = o.duplicate() if o is BaseMaterial3D else StandardMaterial3D.new()
				m.metallic = 0.6
				m.emission_enabled = true
				m.emission = Color(0.95, 0.12, 0.15)
				m.emission_energy_multiplier = 1.0
				mi.set_surface_override_material(si, m)
		return holder
	# fallback: a big red box if the GLB can't load
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size = Vector3(BOSS_SIZE, BOSS_SIZE, BOSS_SIZE)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.15, 0.2)
	mat.emission_energy_multiplier = 1.3
	mi.material_override = mat
	add_child(mi)
	return mi


# Build an enemy state dict (regular alien or boss) around an already-added node.
func _make_enemy(node: Node3D, cfg: Dictionary) -> Dictionary:
	var sd: float = cfg.spawn_dist
	var a := {
		"pos": _rand_dir() * sd, "vel": Vector3.ZERO, "hp": cfg.hp, "max_hp": cfg.hp,
		"node": node, "fire_cd": randf_range(0.5, cfg.fire_every), "alive": true,
		"respawn": 0.0, "phase": randf_range(0.0, TAU),
		"size": cfg.size, "speed": cfg.speed, "keep": cfg.keep,
		"fire_every": cfg.fire_every, "respawn_after": cfg.respawn_after,
		"spawn_dist": sd, "is_boss": cfg.is_boss,
	}
	node.position = a.pos
	return a


func _load_alien_model() -> Node3D:
	var paths := ALIEN_MODELS.duplicate()
	paths.shuffle()                  # random monster type per spawn → variety
	for path in paths:
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


func _spawn_bolt(list: Array, pos: Vector3, vel: Vector3, mat: StandardMaterial3D, scale := 1.0, dmg := 1) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = Vector3.ONE * scale   # per-hull bullet size (Lyra's big, Stella's small)
	add_child(mi)
	# A bigger bolt also lands fatter: its radius widens the swept hit test below.
	list.append({ "pos": pos, "vel": vel, "life": BOLT_LIFE, "node": mi, "dmg": dmg, "r": _bolt_mesh.radius * scale })


# Shortest distance from point p to the segment a→b (for swept bolt hits).
func _seg_point_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# A small, soft spark where a bolt hits an enemy. Deliberately understated and
# semi-transparent (and a random IRREGULAR shape, not a bright clean circle, that
# fades out to a ragged edge) so it confirms the hit WITHOUT washing out the
# crosshair hitmarker. No shockwave ring — that circle was the worst offender.
func _hit_flash(at: Vector3, scale := 1.0) -> void:
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
func _enemy_flash(at: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(size * 1.5, size * 1.5)
	mi.mesh = q
	mi.material_override = _flash_mat(_glow_tex, Color(1.0, 1.0, 1.0, 0.9))
	mi.position = at
	add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.14)
	tw.tween_callback(mi.queue_free)


func _flash_mat(tex: Texture2D, col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = col
	return mat


func _boom(at: Vector3, size := ALIEN_SIZE) -> void:
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


# ---------------------------------------------------------------------------
func _bolt_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.albedo_color = c.lerp(Color.WHITE, 0.45)   # white-hot core reads brighter
	m.emission_energy_multiplier = 7.0           # well above the glow HDR threshold (1.0) so they bloom
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


# A random irregular spark "splatter": a bright core whose alpha fades out to a
# ragged, NON-circular edge — the edge radius wobbles per-angle with a few random
# harmonics. We bake a handful of these and pick one per hit so impacts vary.
func _make_splatter(rng: RandomNumberGenerator) -> Texture2D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	# a few random angular harmonics define the ragged outline: [freq, amp, phase]
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
