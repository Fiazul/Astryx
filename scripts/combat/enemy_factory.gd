class_name EnemyFactory
extends Node3D
# Builds enemy units for combat (Phase 3 extraction from combat.gd): loads + normalizes the
# monster GLBs, paints them, and packs each into the state Dictionary combat's loops drive.
# combat spawns ONE of these as a child — at the origin, so models it loads share combat's
# floating-origin frame — and asks it for units:
#   factory.make_alien() / make_boss()                      — a ready swarm alien / Vortex unit
#   factory.make_enemy(node, cfg)                            — pack a loaded node into a unit dict
#   factory.load_alien_model(size) / load_boss_model(size)  — bare, size-normalized model nodes
#   factory.menace_paint(node)                              — dark hull + red-hot glow override mats
#   factory.find_mesh(node)                                 — first MeshInstance3D's mesh (helper)
# The guardian-wave bosses/minions are still assembled in combat.gd from these primitives.

# The monster roster — one is picked at random per spawn, so stars, planets and moons are
# defended by a mix of UFOs, blobs, demons, ghosts, etc.
const ALIEN_MODELS := [
	"res://assets/ufo.glb", "res://assets/blob.glb", "res://assets/demon.glb", "res://assets/ghost.glb",
	"res://assets/enemy_small.glb", "res://assets/mushnub.glb", "res://assets/alien_ship.glb",
]
const ALIEN_SIZE := 6.0           # big — longest axis in units
const ALIEN_HP := 3
const ALIEN_SPEED := 14.0
const ALIEN_KEEP_DIST := 30.0     # they hover around this range and strafe
const ALIEN_FIRE_EVERY := 1.4     # aggressive
const RESPAWN_AFTER := 4.0
const SPAWN_RADIUS := 60.0        # where new aliens appear around the player

# VORTEX — the boss. Vortex's own hull, scaled up huge with a red-hot menace tint.
const BOSS_MODEL := "res://assets/Spaceship (1).glb"   # Vortex's hull, kept as the boss design
const BOSS_SIZE := 60.0           # extremely big
const BOSS_HP := 60
const BOSS_SPEED := 7.0           # slow and heavy
const BOSS_KEEP_DIST := 80.0
const BOSS_FIRE_EVERY := 1.2
const BOSS_RESPAWN_AFTER := 9.0
const BOSS_SPAWN_DIST := 160.0

# Boss names — combat sticks one to each guarded body (deterministic by name, so a body
# always faces the same warlord); an ordinary hostile borrows one for flavour. Crude/savage
# tone to match the mission log.
const BOSS_NAMES := [
	"Gut-Render", "Skullfister", "Lord Ballsack", "The Anal Vortex", "Cunthammer",
	"Pisslord Vex", "Maggot-King", "Shitslinger", "The Choad Reaver", "Arsemaw",
	"Bonegrinder", "Twatcrusher", "Rotgut the Foul", "Spunkbubble", "The Festering Hole",
	"Knobrot", "Dr. Fuckwidget", "Smegmar the Vile", "Cock-Mortis", "Bumghoul",
]


func make_alien() -> Dictionary:
	var node := load_alien_model()   # already added to the tree (so fit can measure it)
	return make_enemy(node, {
		"size": ALIEN_SIZE, "hp": ALIEN_HP, "speed": ALIEN_SPEED, "keep": ALIEN_KEEP_DIST,
		"fire_every": ALIEN_FIRE_EVERY, "respawn_after": RESPAWN_AFTER,
		"spawn_dist": SPAWN_RADIUS, "is_boss": false,
	})


# VORTEX — the boss. Vortex's own hull, scaled up huge with a red-hot menace tint.
func make_boss() -> Dictionary:
	var node := load_boss_model()
	var b := make_enemy(node, {
		"size": BOSS_SIZE, "hp": BOSS_HP, "speed": BOSS_SPEED, "keep": BOSS_KEEP_DIST,
		"fire_every": BOSS_FIRE_EVERY, "respawn_after": BOSS_RESPAWN_AFTER,
		"spawn_dist": BOSS_SPAWN_DIST, "is_boss": true,
	})
	b["boss_name"] = "Vortex"
	b["name"] = "Vortex"
	return b


# Build an enemy state dict (regular alien or boss) around an already-added node.
func make_enemy(node: Node3D, cfg: Dictionary) -> Dictionary:
	var sd: float = cfg.spawn_dist
	var a := {
		"pos": _rand_dir() * sd, "vel": Vector3.ZERO, "hp": cfg.hp, "max_hp": cfg.hp,
		"node": node, "fire_cd": randf_range(0.5, cfg.fire_every), "alive": true,
		"respawn": 0.0, "phase": randf_range(0.0, TAU),
		"size": cfg.size, "speed": cfg.speed, "keep": cfg.keep,
		"fire_every": cfg.fire_every, "respawn_after": cfg.respawn_after,
		"spawn_dist": sd, "is_boss": cfg.is_boss,
		"name": _enemy_name(),   # so the HUD can show WHO you're hitting (overridden for bosses)
	}
	node.position = a.pos
	return a


# A crude/savage name for an ordinary hostile (reuses the boss-name pool for flavour).
func _enemy_name() -> String:
	return BOSS_NAMES[randi() % BOSS_NAMES.size()]


# Make a guardian boss read as DANGEROUS: near-black metallic hull with a red-hot emissive
# glow. Returns the override materials so combat's _step_boss can pulse them (a menacing throb).
func menace_paint(node: Node3D) -> Array:
	var mats := []
	for mi in _meshes(node):
		for si in mi.mesh.get_surface_count():
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.05, 0.04, 0.06)     # near-black hull
			m.metallic = 0.7
			m.roughness = 0.35
			m.emission_enabled = true
			m.emission = Color(1.0, 0.18, 0.12)          # red-hot menace
			m.emission_energy_multiplier = 2.0
			mi.set_surface_override_material(si, m)
			mats.append(m)
	return mats


func load_alien_model(size := ALIEN_SIZE) -> Node3D:
	var paths := ALIEN_MODELS.duplicate()
	paths.shuffle()                  # random monster type per spawn → variety
	for path in paths:
		var packed := load(path) as PackedScene
		if packed != null:
			var holder := Node3D.new()
			add_child(holder)                        # in tree BEFORE fitting (needs global xform)
			var inst := packed.instantiate() as Node3D
			holder.add_child(inst)
			_fit_and_light(holder, inst, size)
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


func load_boss_model(size := BOSS_SIZE) -> Node3D:
	var packed := load(BOSS_MODEL) as PackedScene
	if packed != null:
		var holder := Node3D.new()
		add_child(holder)                       # in tree BEFORE fitting (needs global xform)
		var inst := packed.instantiate() as Node3D
		holder.add_child(inst)
		_fit_and_light(holder, inst, size)
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


func find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m = find_mesh(child)
		if m:
			return m
	return null


func _fit_and_light(holder: Node3D, model: Node3D, target: float) -> void:
	var box := _aabb(holder)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.0001:
		var f := target / longest
		model.scale = model.scale * f
		model.position -= (box.position + box.size * 0.5) * f
	# Keep each monster's AUTHORED design/colours — render unshaded so the GLB's own
	# albedo/texture/vertex-colours show in our light-less scene (no purple overpaint).
	for mi in _meshes(model):
		for si in mi.mesh.get_surface_count():
			var o = mi.get_active_material(si)
			var m: BaseMaterial3D = o.duplicate() if o is BaseMaterial3D else StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.emission_enabled = false
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


func _rand_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized()
