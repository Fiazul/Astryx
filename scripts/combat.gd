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
	"res://assets/ufo.glb", "res://assets/blob.glb", "res://assets/demon.glb", "res://assets/ghost.glb",
	"res://assets/enemy_small.glb", "res://assets/mushnub.glb", "res://assets/alien_ship.glb",
]
const ALIEN_COUNT := 3
const SWARM_COUNT := 14           # "large chunk" of aliens around every non-Sol star
const ALIEN_SIZE := 6.0           # big — longest axis in units
# Nose laser beam (Raptor II, right-click): a long continuous beam that melts whatever
# it sweeps over. Damage is applied on a steady tick so it uses integer HP cleanly.
const LASER_LEN := 5000.0
const LASER_RADIUS := 22.0        # hit radius around the beam line
const LASER_TICK := 0.08          # seconds between damage ticks
const LASER_TICK_DMG := 2         # HP per tick (~25 dps)
const ALIEN_HP := 3
const ALIEN_SPEED := 14.0
const ALIEN_KEEP_DIST := 30.0     # they hover around this range and strafe
const ALIEN_FIRE_EVERY := 1.4         # more aggressive (was 2.2)
const RESPAWN_AFTER := 4.0
const COMBAT_HOLD := 10.0          # stay "in combat" this long after the last attack (either way)
# Energy: two auto-regen bars (weapon + boost). Caps + consume rate are PER-SHIP
# (ship.energy_max / ship.energy_use): Raptor = big tank, low burn; Stella = small
# tank, high burn. Boost only burns where boost actually works (not in slow-zones).
const ENERGY_MAX := 100.0          # fallback cap if a ship doesn't specify one
const WEAPON_REGEN := 34.0         # rapid weapon-energy regen (per second)
const BOOST_REGEN := 22.0          # boost-energy regen (per second)
const BOLT_ENERGY := 7.0           # base per bolt (× ship.energy_use)
const LASER_ENERGY := 26.0         # base per second of beam (× ship.energy_use)
# Energy pickup — ONE ⚡ cell that appears only when you actually NEED it (boost tank
# below PICKUP_NEED_FRAC) and only in open interstellar flight. It spawns ahead in view,
# then HOMES to the ship so you always collect it (no chasing — that was the annoying part).
const PICKUP_EVERY := 1.5          # min gap between cells (only matters once one is collected)
const PICKUP_NEED_FRAC := 0.6      # only offer a cell when boost energy drops below 60%
const PICKUP_AHEAD := 700.0        # where it first appears ahead (scales up with speed)
const PICKUP_SCATTER := 120.0      # slight off-centre so it reads as "incoming", not pasted on
const PICKUP_HOME := 650.0         # homing speed ABOVE the ship's own speed → guaranteed catch
const PICKUP_COLLECT := 150.0      # grab radius (scales up with speed)
const PICKUP_LIFE := 14.0
const PICKUP_REFILL := 70.0        # energy restored to BOTH bars
const PICKUP_HEAL := 14            # hull restored
const PICKUP_CAP := 1              # only ever one in the air — it homes, you always get it
# Probes: rare beacons far out in empty space — fly to one for a big refuel.
const SPAWN_RADIUS := 60.0        # where new aliens appear around the player

# --- VORTEX: the boss. Vortex's own ship hull, scaled up huge and menacing. ---
const BOSS_MODEL := "res://assets/Spaceship (1).glb"   # Vortex's hull, kept as the boss design
const BOSS_SIZE := 60.0           # extremely big
const BOSS_HP := 60
const BOSS_SPEED := 7.0           # slow and heavy
const BOSS_KEEP_DIST := 80.0
const BOSS_FIRE_EVERY := 1.2
const BOSS_RESPAWN_AFTER := 9.0
const BOSS_SPAWN_DIST := 160.0

# --- Guardian boss: ONE per guarded body, a distinct monster GLB with its own design
# (raw colours), that summons small "old vortex" minions (BOSS_MODEL) as its army.
# Clear the boss to capture the body. ---
const GUARD_BOSS_SIZE := 40.0   # EXTREMELY big, imposing monster guarding the star/body
const GUARD_BOSS_HP := 180      # base — scaled up further by star size in set_guardians
const GUARD_BOSS_SPEED := 9.0
const BOSS_FAST_EVERY := 2.2    # seconds between ultra-fast aimed shots (between specials)
const BOSS_FAST_SPEED := 320.0  # ultra-fast bullet/laser the player must dodge
const GUARD_BOSS_KEEP := 55.0
const GUARD_BOSS_FIRE := 0.9
const MINION_SIZE := 7.0          # small vortexes
const MINION_HP := 4
const MINION_SPEED := 16.0
const MINION_KEEP := 28.0
const MINION_FIRE := 1.3          # more aggressive minions (was 2.1)
const MINION_CAP := 6             # base live minions; scaled up by star size (bigger = waves)
const MINION_SUMMON_EVERY := 2.6  # seconds between summons
# Boss phases + telegraphed special. Phase 2 (enraged) triggers below this HP fraction:
# faster summons + faster specials. The special is a radial bolt burst preceded by a
# clear wind-up (the boss swells), so the player can dodge.
const BOSS_ENRAGE_AT := 0.5
const BOSS_SPECIAL_EVERY := 6.5   # seconds between special attacks (phase 1)
const BOSS_TELEGRAPH := 1.2       # wind-up time before the burst fires
const BOSS_BURST_COUNT := 12      # bolts in the radial burst

const BOLT_SPEED := 950.0          # fast tracers (swept collision keeps hits reliable)
const BOLT_LIFE := 2.5
const BOLT_COOLDOWN := 0.22        # ~4.5 shots/sec — same comfortable delay between shots
const ALIEN_BOLT_SPEED := 90.0
const HIT_RADIUS_MULT := 0.95      # enemy hit box as a fraction of body size (was 0.55 — more forgiving)
const SHIP_HIT_RADIUS := 2.0
# Bullet LOOK is decoupled from bullet HITBOX. The chase cam sits ~1 unit off the
# ship, so a fat bolt born at the muzzle fills the screen. These keep bolts as small,
# slim TRACERS that read by perspective (small downrange, modest near) instead of
# popping huge at the crosshair. Nudge BOLT_RADIUS/BOLT_LENGTH to taste.
const BOLT_RADIUS := 0.10          # tracer thickness (world units)
const BOLT_LENGTH := 2.4           # tracer streak length (stretched along travel)
const LASER_BOLT_RADIUS := 0.09    # Lyra/Neo laser bolts: a touch thinner + longer
const LASER_BOLT_LENGTH := 3.4
const BOLT_HIT_RADIUS := 0.55      # GAMEPLAY hit radius — stays generous regardless of visual size
# A soft "shadowy" tail behind each bolt: a dim, semi-transparent streak that anchors
# back at the firing point so shots clearly emanate from the nose, then trails the head.
const TRAIL_MAX := 14.0            # MIN tail reach behind the head (world units) — slow bolts
# Fast hulls (Stella/Neo at 1700 u/s) cover ~27 units in a single frame, outrunning a fixed
# 14-unit tail so the streak detaches and reads as a "line in the distance." Scale the reach
# with bolt speed (≈ this many seconds of travel) so the tail always stays pinned to the nose.
const TRAIL_REACH_SECONDS := 0.03
const TRAIL_WIDTH := 0.04          # thin wisp, like a booster plume — not a fat bar
const HANI_PINK := Color(1.0, 0.32, 0.72)   # HaniStar's signature bullet pink (matches her hull)
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
var _laser: MeshInstance3D        # the beam mesh (child of the ship, points out the nose)
var _laser_ring: MeshInstance3D   # glowing emitter "belt" the beam fires through
var _laser_tick := 0.0
var _combat_t := 0.0              # >0 while in combat (counts down from COMBAT_HOLD)
var _bolt_mesh: CapsuleMesh
var _laser_bolt_mesh: CapsuleMesh
var _strong_bolt_mesh: CapsuleMesh   # compact, round, "filled" bullet (HaniStar)
var _trail_mesh: CylinderMesh
var _trail_grad: Texture2D
var _bolt_trail_mat: StandardMaterial3D
var _abolt_trail_mat: StandardMaterial3D
var _laser_trail_mat: StandardMaterial3D
var _strong_trail_mat: StandardMaterial3D   # pink tail for HaniStar's strong bolts
var _bolt_mat: StandardMaterial3D
var _bolt_mat_strong: StandardMaterial3D   # extra-bright bolts (HaniStar)
var _abolt_mat: StandardMaterial3D
var _laser_bolt_mat: StandardMaterial3D   # Lyra's red laser bolts
var _glow_tex: Texture2D
var _splatters: Array[Texture2D] = []    # irregular hit-spark shapes, picked at random


func _ready() -> void:
	_glow_tex = _make_glow()
	# Bake a few random irregular spark shapes once; _hit_flash picks one per hit.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	for i in 5:
		_splatters.append(_make_splatter(rng))
	# Slim tracer capsules (stretched along travel), shared by all bolts. Small world
	# size -> perspective shrinks them downrange instead of them filling the lens.
	_bolt_mesh = CapsuleMesh.new()
	_bolt_mesh.radius = BOLT_RADIUS
	_bolt_mesh.height = BOLT_LENGTH
	_bolt_mesh.radial_segments = 8
	_bolt_mesh.rings = 2
	_laser_bolt_mesh = CapsuleMesh.new()
	_laser_bolt_mesh.radius = LASER_BOLT_RADIUS
	_laser_bolt_mesh.height = LASER_BOLT_LENGTH
	_laser_bolt_mesh.radial_segments = 8
	_laser_bolt_mesh.rings = 2
	# HaniStar's "filled" bullet: short + relatively fat -> a small round glowing pellet
	# instead of a long thin tracer. High segment/ring count keeps it smooth and pretty.
	_strong_bolt_mesh = CapsuleMesh.new()
	_strong_bolt_mesh.radius = 0.14
	_strong_bolt_mesh.height = 0.7
	_strong_bolt_mesh.radial_segments = 20
	_strong_bolt_mesh.rings = 8
	_bolt_mat = _bolt_material(Color(0.5, 0.9, 1.0))     # your bolts: cyan
	# HaniStar's bolts: hot PINK to match her hull, much brighter + whiter-hot core so they
	# read as strong as she is.
	_bolt_mat_strong = _bolt_material(HANI_PINK)
	_bolt_mat_strong.emission_energy_multiplier = 18.0
	_bolt_mat_strong.albedo_color = HANI_PINK.lerp(Color.WHITE, 0.7)
	_abolt_mat = _bolt_material(Color(1.0, 0.4, 0.3))    # alien bolts: red
	_laser_bolt_mat = _bolt_material(Color(1.0, 0.12, 0.08))   # Lyra: red laser bolts
	# Same gradient the ship's boosters use, so the bullet's tail fades like a plume.
	_trail_grad = ShipMesh.make_plume_gradient(true)     # bright at the head (+Y), clear at the tail
	_bolt_trail_mat = _trail_material(Color(0.5, 0.9, 1.0))
	_abolt_trail_mat = _trail_material(Color(1.0, 0.4, 0.3))
	_laser_trail_mat = _trail_material(Color(1.0, 0.12, 0.08))
	_strong_trail_mat = _trail_material(HANI_PINK)
	# A smooth cone (not a boxy prism): wide at the head, tapering to a SHARP point at
	# the tail. Length lives on Y (height=1), scaled per-frame. Enough sides to read round.
	_trail_mesh = CylinderMesh.new()
	_trail_mesh.height = 1.0
	_trail_mesh.top_radius = TRAIL_WIDTH    # +Y end -> oriented to the bolt head (wide)
	_trail_mesh.bottom_radius = 0.0         # -Y end -> the trailing point (sharp)
	_trail_mesh.radial_segments = 24   # higher = smooth, round cone instead of a faceted prism
	_trail_mesh.rings = 1
	_trail_mesh.cap_top = false
	_trail_mesh.cap_bottom = false
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
		b.trail.queue_free()
	_bolts.clear()
	for b in _abolts:
		b.node.queue_free()
		b.trail.queue_free()
	_abolts.clear()
	for p in _pickups:
		p.node.queue_free()
	_pickups.clear()
	player_hp = PLAYER_MAX_HP
	if active:
		for i in count:
			_aliens.append(_make_alien())
		if with_boss:
			_aliens.append(_make_boss())   # Vortex


# Called by main each frame. `pressed` = left fire held; `laser` = right-click beam.
func update(ship: Node3D, pressed: bool, delta: float, laser := false) -> void:
	hitmarker = maxf(hitmarker - delta, 0.0)
	_combat_t = maxf(_combat_t - delta, 0.0)
	# Slow passive regen, then a fast top-up of both bars drawn from the storage reserve.
	# Per-ship cap; both bars auto-regen toward it (weapon faster than boost).
	e_max = float(ship.energy_max) if ship.has_method("is_hypersonic") else ENERGY_MAX
	energy = minf(energy + WEAPON_REGEN * delta, e_max)
	# Boost regen pauses WHILE boosting, so holding Shift visibly drains the bar.
	if not ship.is_boosting:
		boost_energy = minf(boost_energy + BOOST_REGEN * delta, e_max)
	var sp: Vector3 = ship.true_pos
	var fwd: Vector3 = -ship.transform.basis.z
	# Live muzzle, tracking the hull's cosmetic bank — bolts spawn here AND their trail tail
	# re-anchors here every frame, so the start stays glued to the nose even as you strafe.
	var muzzle_now: Vector3 = ship.muzzle_world() if ship.has_method("muzzle_world") else sp + fwd * ship.muzzle - ship.transform.basis.y * ship.muzzle_drop
	# You can only fire at regular (sublight) combat speed. main force-slows the ship to it
	# while you hold fire, so this just blocks the brief moment before the slowdown lands.
	var slow_enough: bool = ship.velocity.length() <= Ship.WEAPON_FIRE_SPEED * 1.05
	var laser_on: bool = laser and ship.can_fire and energy > 0.0 and slow_enough
	if laser_on:
		energy = maxf(energy - LASER_ENERGY * ship.energy_use * delta, 0.0)
	_update_laser(ship, laser_on, sp, fwd, delta)

	# Per-hull combat identity: defence (max HP), bullet speed and bullet size all come
	# from the active ship (see SHIP_MODELS). player_max drives the HUD's hull bar.
	player_max = ship.max_hp if ship.has_method("is_hypersonic") else PLAYER_MAX_HP
	player_hp = mini(player_hp, player_max)

	# --- player firing: pure straight shots, no aim assist (utility hulls can't fire) ---
	_cool = maxf(_cool - delta, 0.0)
	var bolt_cost: float = BOLT_ENERGY * ship.energy_use
	if pressed and slow_enough and _cool <= 0.0 and ship.can_fire and energy >= bolt_cost:
		_cool = ship.fire_cooldown if ship.has_method("is_hypersonic") else BOLT_COOLDOWN
		energy -= bolt_cost
		var bmat: StandardMaterial3D = _laser_bolt_mat if ship.bolt_laser else (_bolt_mat_strong if ship.bolt_strong else _bolt_mat)
		# Inherit the ship's OWN velocity so bolts never fall behind — even past warp speed the
		# bullet leaves the nose forward (relative to the ship it always travels fwd * bolt_speed).
		# Aim the tracer + trail down `fwd` (where you pointed), not the combined world vector.
		var bolt_vel: Vector3 = ship.velocity + fwd * ship.bolt_speed
		_spawn_bolt(_bolts, muzzle_now, bolt_vel, bmat, ship.bolt_scale, ship.bolt_damage, ship.bolt_laser, fwd, ship.bolt_speed)
		if _any_alien_alive():
			_combat_t = COMBAT_HOLD            # attacking while enemies are present = in combat
		if audio != null:
			audio.play_fire()

	_step_bolts(_bolts, sp, delta, true, muzzle_now)
	_step_bolts(_abolts, sp, delta, false)
	_step_aliens(ship, sp, delta)
	_step_boss(0.0, delta, sp)
	_step_pickups(ship, sp, fwd, delta)
	_sweep_dead_minions()


# True for COMBAT_HOLD seconds after the last attack (you fire at enemies, an alien
# fires, you get hit, or the laser connects). main reads this to lock out FTL.
func in_combat() -> bool:
	return _combat_t > 0.0

func _any_alien_alive() -> bool:
	for a in _aliens:
		if a.alive:
			return true
	return false


# Continuous nose laser. The beam mesh is a child of the ship (which sits at the
# origin and only rotates), so it always emerges from the nose and tracks heading.
func _update_laser(ship: Node3D, on: bool, sp: Vector3, fwd: Vector3, delta: float) -> void:
	if _laser == null:
		_build_laser(ship)
	var off: Vector3 = ship.laser_offset
	if _laser.get_parent() != ship:
		if _laser.get_parent() != null:
			_laser.get_parent().remove_child(_laser)
		ship.add_child(_laser)
	if _laser_ring.get_parent() != ship:
		if _laser_ring.get_parent() != null:
			_laser_ring.get_parent().remove_child(_laser_ring)
		ship.add_child(_laser_ring)
	# Start the beam exactly at the offset point (the under-hull pod), not the muzzle,
	# so it connects to the hull. Near end at local z = off.z, extends forward.
	_laser.position = Vector3(off.x, off.y, off.z - LASER_LEN * 0.5)
	_laser_ring.position = off + Vector3(0.0, 0.015, 0.0)   # ring sits a touch above the beam
	_laser.visible = on
	_laser_ring.visible = on
	if audio != null:
		audio.laser(on)
	if not on:
		return
	# Subtle flicker so the beam feels alive.
	var f := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.04)
	_laser.scale = Vector3(f, 1.0, f)
	# Damage everything the beam line passes through, on a steady tick.
	_laser_tick -= delta
	if _laser_tick > 0.0:
		return
	_laser_tick = LASER_TICK
	# Damage ray starts at the same pod point in world space (local off -> world).
	var b := ship.transform.basis
	var origin: Vector3 = sp + b.x * off.x + b.y * off.y - fwd * off.z
	var hit := false
	for a in _aliens:
		if not a.alive:
			continue
		var to: Vector3 = a.pos - origin
		var t := to.dot(fwd)
		if t < 0.0 or t > LASER_LEN:
			continue
		if (to - fwd * t).length() < a.size * 0.5 + LASER_RADIUS:
			_damage_alien(a, sp, LASER_TICK_DMG)
			hit = true
	if hit:
		hitmarker = 0.18
		_combat_t = COMBAT_HOLD


func _build_laser(ship: Node3D) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015   # very thin, round beam
	cyl.bottom_radius = 0.015
	cyl.height = LASER_LEN
	cyl.radial_segments = 16
	cyl.rings = 0
	_laser = MeshInstance3D.new()
	_laser.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.18, 0.12, 0.7)   # red beam
	_laser.material_override = mat
	_laser.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)   # cylinder +Y -> -Z (forward)
	_laser.visible = false
	# Emitter "belt": a glowing ring the beam fires through, sat at the muzzle point.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.022   # small hole — just bigger than the beam
	torus.outer_radius = 0.038
	torus.rings = 18
	torus.ring_segments = 10
	_laser_ring = MeshInstance3D.new()
	_laser_ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.02, 0.02, 0.03)   # small black emitter belt
	_laser_ring.material_override = rmat
	_laser_ring.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # hole faces forward (-Z)
	_laser_ring.visible = false


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
			_combat_t = COMBAT_HOLD            # an enemy is shooting at you = in combat


func _step_bolts(list: Array, sp: Vector3, delta: float, player: bool, muzzle := Vector3.ZERO) -> void:
	var i := list.size() - 1
	while i >= 0:
		var b = list[i]
		var prev: Vector3 = b.pos
		if planets != null:
			b.vel += planets.gravity_at(b.pos) * delta   # bolts curve through gravity wells
		b.pos += b.vel * delta
		b.life -= delta
		b.node.position = b.pos - sp
		# Re-anchor the trail tail to the LIVE nose: since the bolt inherited the ship's
		# velocity, (bolt - live_muzzle) stays exactly along `dir`, so the streak runs from
		# the current nose to the head — no drift when you strafe/bank after firing.
		if player:
			b.origin = muzzle
		_update_trail(b, sp)
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
				_combat_t = COMBAT_HOLD            # taking damage = in combat
				hit = true
		if hit or b.life <= 0.0:
			b.node.queue_free()
			b.trail.queue_free()
			list.remove_at(i)
		i -= 1


# Stretch a bolt's tail from its firing point toward the head: anchored at the muzzle
# while the head is within TRAIL_MAX, then a fixed-length streak chasing the bolt.
func _update_trail(b: Dictionary, sp: Vector3) -> void:
	var head: Vector3 = b.pos
	var trail: MeshInstance3D = b.trail
	# Anchor the tail to the LIVE muzzle (b.origin) and aim the streak straight DOWN the
	# nose->head line — not a fixed forward axis. So however the head drifts (e.g. it
	# inherited sideways velocity while strafing), the streak's START stays pinned to the
	# nose instead of sliding off to one side. Beyond `reach` it trails the head.
	var to_head: Vector3 = head - b.origin
	var dist: float = to_head.length()
	if dist < 0.01:
		trail.visible = false
		return
	var dir: Vector3 = to_head / dist
	var back: float = minf(b.reach, dist)
	var tail: Vector3 = head - dir * back
	var mid: Vector3 = (head + tail) * 0.5 - sp
	trail.position = mid
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	trail.look_at(trail.position + dir, up)                  # -Z faces the head...
	trail.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0)) # ...cone's long Y -> the line
	trail.scale = Vector3(b.tw, back, b.tw)                  # Y = length, X/Z = thickness
	trail.visible = true


func _damage_alien(a: Dictionary, sp: Vector3, dmg := 1) -> void:
	a.hp -= dmg
	if a.hp <= 0:
		a.alive = false
		a.respawn = a.respawn_after
		a.node.visible = false
		kills += 1
		if a.get("guardian", false):
			zone_kills += 1     # track hostiles defeated in this star zone
		_boom(a.pos - sp, a.size)
		if audio != null:
			audio.play_explosion()
		# Boss down → its summoned army vanishes and the body becomes capturable.
		if a.get("guardian_boss", false):
			_clear_minions()


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
		if a.is_boss or a.get("guardian_boss", false):
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

var _zone_power := 1.0   # current guard zone's strength (scales with the body's size)
var zone_kills := 0      # hostiles defeated in the current guard zone (HUD reads this)
var energy := ENERGY_MAX       # weapon energy (HUD reads this)
var boost_energy := ENERGY_MAX # boost energy (drained by the ship's Shift boost)
var e_max := ENERGY_MAX        # current per-ship cap for BOTH bars (set each frame)
var _pickups := []             # { pos, node, life } — interstellar energy pickups
var _pickup_cd := PICKUP_EVERY

# `power` ~ the body's size; bigger stars get a tougher, bigger boss + bigger waves.
func set_guardians(center: Vector3, body: String, power := 1.0) -> void:
	clear_guardians()
	guard_body = body
	_zone_power = clampf(power, 1.0, 3.0)
	zone_kills = 0
	_aliens.append(_make_guardian_boss(center, _zone_power))

# One identity boss (a random monster GLB, big, raw colours) that defends a body and
# summons small vortex minions. Reuses the alien-model loader at boss scale.
func _make_guardian_boss(center: Vector3, power := 1.0) -> Dictionary:
	var size := GUARD_BOSS_SIZE * clampf(power, 1.0, 1.8)   # bigger stars = bigger boss
	var node := _load_alien_model(size)
	var a := _make_enemy(node, {
		"size": size, "hp": int(GUARD_BOSS_HP * power), "speed": GUARD_BOSS_SPEED,
		"keep": GUARD_BOSS_KEEP, "fire_every": GUARD_BOSS_FIRE, "respawn_after": -1.0,
		"spawn_dist": 0.0, "is_boss": false,
	})
	a["guardian"] = true
	a["guardian_boss"] = true
	a["summon_cd"] = MINION_SUMMON_EVERY
	a["special_cd"] = BOSS_SPECIAL_EVERY
	a["fast_cd"] = BOSS_FAST_EVERY
	a["telegraph_t"] = 0.0
	a["enraged"] = false
	a["base_scale"] = a.node.scale
	a.pos = center + _rand_dir() * (size * 2.0)
	a.node.position = a.pos
	return a

func _summon_minion(center: Vector3) -> void:
	var node := _load_boss_model(MINION_SIZE)   # small "old vortex"
	var a := _make_enemy(node, {
		"size": MINION_SIZE, "hp": MINION_HP, "speed": MINION_SPEED, "keep": MINION_KEEP,
		"fire_every": MINION_FIRE, "respawn_after": -1.0, "spawn_dist": 0.0, "is_boss": false,
	})
	a["guardian"] = true
	a["minion"] = true
	a.pos = center + _rand_dir() * (MINION_SIZE * 2.0 + 18.0)
	a.node.position = a.pos
	_aliens.append(a)

# Boss tick: summons (capped), phase change at low HP (enrage = faster), and a
# telegraphed radial burst the player can see coming and dodge.
func _step_boss(_unused: float, delta: float, sp := Vector3.ZERO) -> void:
	var minions := 0
	for a in _aliens:
		if a.get("minion", false) and a.alive:
			minions += 1
	for a in _aliens:
		if not (a.get("guardian_boss", false) and a.alive):
			continue
		var enraged: bool = a.hp <= a.max_hp * BOSS_ENRAGE_AT
		var rate := 0.6 if enraged else 1.0          # phase 2 = faster everything
		# Bigger stars sustain bigger waves; enrage pushes the cap higher still.
		var cap := MINION_CAP + int((_zone_power - 1.0) * 5.0) + (3 if enraged else 0)
		# Summon minions, faster when enraged.
		a.summon_cd -= delta
		if a.summon_cd <= 0.0:
			a.summon_cd = MINION_SUMMON_EVERY * rate
			if minions < cap:
				_summon_minion(a.pos)
				minions += 1
		# Ultra-fast aimed shot the player must dodge (between the big specials).
		a.fast_cd -= delta
		if a.fast_cd <= 0.0 and a.telegraph_t <= 0.0:
			a.fast_cd = BOSS_FAST_EVERY * rate
			var faim: Vector3 = (sp - a.pos).normalized()
			_spawn_bolt(_abolts, a.pos + faim * (a.size * 0.5), faim * BOSS_FAST_SPEED, _abolt_mat, 1.4, 2)
			_combat_t = COMBAT_HOLD
		# Telegraphed special: wind up (swell), then fire a radial burst.
		if a.telegraph_t > 0.0:
			a.telegraph_t -= delta
			var swell := 1.0 + 0.4 * sin((1.0 - a.telegraph_t / BOSS_TELEGRAPH) * PI)
			a.node.scale = a.base_scale * swell
			if a.telegraph_t <= 0.0:
				a.node.scale = a.base_scale
				_boss_burst(a, sp)
		else:
			a.special_cd -= delta
			if a.special_cd <= 0.0:
				a.special_cd = BOSS_SPECIAL_EVERY * rate
				a.telegraph_t = BOSS_TELEGRAPH        # start the wind-up

# A ring of bolts fired outward (plus one straight at the player) on the special.
func _boss_burst(a: Dictionary, sp: Vector3) -> void:
	for i in BOSS_BURST_COUNT:
		var ang := float(i) / float(BOSS_BURST_COUNT) * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		_spawn_bolt(_abolts, a.pos + dir * (a.size * 0.5), dir * ALIEN_BOLT_SPEED, _abolt_mat)
	var aim: Vector3 = (sp - a.pos).normalized()
	_spawn_bolt(_abolts, a.pos + aim * (a.size * 0.5), aim * (ALIEN_BOLT_SPEED * 1.4), _abolt_mat)
	_combat_t = COMBAT_HOLD

# Energy cell: only ever offered when the boost tank is actually low, and only in open
# interstellar flight. It appears ahead in view, then HOMES to the ship (faster than the
# ship moves) so it always reaches you — no chasing. Floating-origin: world pos stored,
# drawn relative to the ship; the ⚡ label is fixed-size so it stays readable at any range.
func _step_pickups(ship: Node3D, sp: Vector3, fwd: Vector3, delta: float) -> void:
	var min_limit: float = minf(ship.speed_limit, ship.struct_limit)
	var open_space: bool = min_limit >= ship.SUBLIGHT_MAX and not ship.transiting
	var speed: float = ship.velocity.length()
	_pickup_cd -= delta
	# Offer a cell only when you NEED it — boost tank under PICKUP_NEED_FRAC of full.
	var need: bool = boost_energy < PICKUP_NEED_FRAC * e_max
	if open_space and need and _pickup_cd <= 0.0 and _pickups.size() < PICKUP_CAP:
		_pickup_cd = PICKUP_EVERY
		var ahead: float = maxf(PICKUP_AHEAD, speed * 1.3)   # lead grows with speed so it's on-screen long enough to see
		_spawn_pickup(sp + fwd * ahead + _rand_dir() * PICKUP_SCATTER)
	var i := _pickups.size() - 1
	while i >= 0:
		var p = _pickups[i]
		p.life -= delta
		# Home to the ship at MORE than the ship's own speed → distance always shrinks, so
		# the cell is guaranteed to catch you (the "100% hit" feel).
		p.pos = p.pos.move_toward(sp, (speed + PICKUP_HOME) * delta)
		p.node.position = p.pos - sp
		var d: float = sp.distance_to(p.pos)
		var grab: float = PICKUP_COLLECT + speed * 0.4   # window widens with speed
		if d < grab:
			energy = minf(energy + PICKUP_REFILL, e_max)
			boost_energy = minf(boost_energy + PICKUP_REFILL, e_max)
			player_hp = mini(player_hp + PICKUP_HEAL, player_max)
			_boom(p.pos - sp, 9.0)
			if audio != null:
				audio.play_pickup()
			p.node.queue_free()
			_pickups.remove_at(i)
		elif p.life <= 0.0:
			p.node.queue_free()
			_pickups.remove_at(i)
		i -= 1


func _spawn_pickup(world_pos: Vector3) -> void:
	# A meaningful ⚡ energy cell — a bright, fixed-size billboard glyph that reads instantly
	# as "boost juice" and stays the same size on screen however far out it spawns.
	var lbl := Label3D.new()
	lbl.text = "⚡"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.fixed_size = true            # constant on-screen size regardless of distance
	lbl.pixel_size = 0.0016
	lbl.font_size = 96
	lbl.no_depth_test = true         # never hidden behind a body — it's a HUD-ish cue
	lbl.modulate = Color(1.0, 0.92, 0.35)        # electric yellow
	lbl.outline_modulate = Color(0.1, 0.25, 0.5, 0.9)
	lbl.outline_size = 12
	add_child(lbl)
	_pickups.append({ "pos": world_pos, "node": lbl, "life": PICKUP_LIFE })


func clear_guardians() -> void:
	var keep := []
	for a in _aliens:
		if a.get("guardian", false):
			a.node.queue_free()
		else:
			keep.append(a)
	_aliens = keep
	guard_body = ""

# Capture is gated on the BOSS being dead (minions are endless until then).
func guard_boss_alive() -> bool:
	for a in _aliens:
		if a.get("guardian_boss", false) and a.alive:
			return true
	return false

func guardians_alive() -> int:
	var n := 0
	for a in _aliens:
		if a.get("guardian", false) and a.alive:
			n += 1
	return n

# Free DEAD boss-summoned minions immediately instead of letting their hidden nodes pile
# up in _aliens for the whole fight. The summon cap (line ~594) only counts LIVE minions,
# so without this a long boss fight spawns unbounded GLB instances that persist (each
# duplicating its materials) until the boss dies — a steady leak during combat. Dead
# minions are never referenced again (every loop skips `not alive`), so freeing is safe.
func _sweep_dead_minions() -> void:
	var i := _aliens.size() - 1
	while i >= 0:
		var a = _aliens[i]
		if a.get("minion", false) and not a.alive:
			a.node.queue_free()
			_aliens.remove_at(i)
		i -= 1


func _clear_minions() -> void:
	var keep := []
	for a in _aliens:
		if a.get("minion", false):
			a.node.queue_free()
		else:
			keep.append(a)
	_aliens = keep


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


func _load_boss_model(size := BOSS_SIZE) -> Node3D:
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


func _load_alien_model(size := ALIEN_SIZE) -> Node3D:
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


func _spawn_bolt(list: Array, pos: Vector3, vel: Vector3, mat: StandardMaterial3D, scale := 1.0, dmg := 1, laser := false, aim := Vector3.ZERO, reach_speed := -1.0) -> void:
	# Every gun fires a slim TRACER aligned to its travel — small in world space so
	# perspective (not a screen clamp) does the work: modest near the nose, shrinking
	# downrange toward the crosshair. per-ship `scale` nudges thickness/length.
	# `aim` overrides the visual forward (the firing direction) for bolts that inherit the
	# ship's velocity, so the tracer points down the nose instead of along the world vector.
	var look_dir: Vector3 = aim if aim.length() > 0.001 else vel
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.mesh = _laser_bolt_mesh if laser else (_strong_bolt_mesh if mat == _bolt_mat_strong else _bolt_mesh)
	add_child(mi)
	mi.global_position = pos
	if look_dir.length() > 0.001:
		var d := look_dir.normalized()
		var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		mi.look_at(pos + look_dir, up)                         # -Z faces travel...
		mi.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0)) # ...capsule's long Y -> travel
	mi.scale = Vector3.ONE * scale
	# Trailing "shadow" streak: anchored at the firing point (the nose), it stretches to
	# the bolt so shots visibly leave the ship, then trails the head as it flies.
	var trail := MeshInstance3D.new()
	trail.mesh = _trail_mesh
	if mat == _laser_bolt_mat:
		trail.material_override = _laser_trail_mat
	elif mat == _abolt_mat:
		trail.material_override = _abolt_trail_mat
	elif mat == _bolt_mat_strong:
		trail.material_override = _strong_trail_mat
	else:
		trail.material_override = _bolt_trail_mat
	add_child(trail)
	# HITBOX is decoupled from the (now small) visual: stays generous so guns still land.
	# Streak length tracks the RELATIVE tracer speed (reach_speed), not the warp-inflated
	# world speed — so the shadow stays a short tail instead of stretching across the sky.
	var rs: float = reach_speed if reach_speed >= 0.0 else vel.length()
	list.append({ "pos": pos, "vel": vel, "life": BOLT_LIFE, "node": mi, "dmg": dmg,
		"r": BOLT_HIT_RADIUS * scale, "trail": trail, "origin": pos,
		"dir": (look_dir.normalized() if look_dir.length() > 0.001 else Vector3.FORWARD), "tw": scale,
		"reach": maxf(TRAIL_MAX, rs * TRAIL_REACH_SECONDS) })


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
	m.albedo_color = c.lerp(Color.WHITE, 0.6)    # white-hot core reads brighter
	m.emission_energy_multiplier = 10.0          # well above the glow HDR threshold (1.0) so they bloom hard
	return m


# A mini engine-plume tail for a bolt — built exactly like the ship's boosters: an
# additive, double-sided cone whose alpha is driven by the plume gradient so it fades
# smoothly from a bright nozzle (at the bolt) to a clear point behind it.
func _trail_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # both sides -> a full plume, not a half curve
	m.albedo_texture = _trail_grad               # gradient drives the nozzle->tail fade
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)  # tint; gradient handles the falloff
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
