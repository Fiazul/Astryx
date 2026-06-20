class_name PlanetSystem
extends Node3D
# Real bodies with floating-origin LOD. Positions come from Ephemeris (live JPL
# Horizons for the Sun + planets, real catalog for the stars) — nothing here is
# hand-placed. See ephemeris.gd for the data, frame and scale.
#
# Two render paths, matching two physical realities:
#   • Sun + planets are within reach (Sun ~10u, Neptune ~300u at 1u=0.1AU) -> the
#     dot<->sphere crossfade LOD, translated every frame by floating origin.
#   • Stars are millions of units away -> a fixed direction-only backdrop shell
#     at STAR_SHELL_RADIUS (real RA/Dec), NOT floating-origin translated and NOT
#     subject to the camera far-plane problem. Real distance shows on the label.
#
# refresh() is called by main.gd with the ship's true position each frame.

# Approach speed-zone (units/s). Ceiling stays >= cruise so normal flight near a
# body isn't throttled.
# Force-slow "gravity safe-zones" (NO pull — just a speed cap). A body force-slows the
# ship within radius × zone-mult (stars get the wider zone, like a much bigger gravity
# reach), eased down to a floor that's LOWER for more massive bodies. Zones are finite,
# so you can always fly back out — and outside every zone you're free to warp.
const STAR_ZONE_MULT := 120.0    # star slow-zone radius = star radius × this (wider: felt sooner)
const STAR_ZONE_FLOOR := 45.0    # speed cap at a star's CENTRE. The approach still slows you (warp
								 # drops at the zone edge), but this floor stays high enough to fly
								 # straight THROUGH the sun instead of crawling to a near-stop.
const STAR_EDGE_SPEED := 64.0    # speed cap at a STAR's zone edge — lower than planets, so you
                                 # notice the drag the moment you enter a star's range
const PLANET_ZONE_MULT := 45.0   # planet/moon slow-zone radius = radius × this
# VISUAL size boost: planets/moons (and their moon-orbit spacing + LOD + capture range) are
# rendered this much bigger so they read as substantial worlds, not specks dwarfed by the ship.
# Heliocentric DISTANCES (real JPL positions) and gravity/slow-zones are NOT scaled — only the
# look. Relative geometry is preserved (moons scale with their parent, so they stay outside it).
const VISUAL_SCALE := 2.7   # mild bump: bodies a touch bigger so Mercury isn't dwarfed by the ship (stars stay unscaled)
# Visual orbital revolution: planets circle the Sun for life (they START at their real JPL
# position, then drift). Kepler-ordered: inner planets visibly orbit, outer ones crawl.
# Speeds are accelerated (real motion is invisible over a play session). Sun + Earth stay put.
const ORBIT_ENABLED := true
const ORBIT_K := 16.0      # bigger = faster orbits (angular speed = ORBIT_K / r^1.5)
# NOTE units: 1u = 0.01 AU, so 100 u/s = 1 AU/s. These are deliberately LOW so flight
# near Sol/any body is a slow crawl (fractions of an AU per second), never "a few AU
# per press". You only get warp-fast out in the deep, beyond every zone.
const ZONE_EDGE_SPEED := 90.0    # speed cap at the zone's outer edge (~0.9 AU/s)
const ZONE_FLOOR := 8.0          # slowest cap, at a very massive body's centre (~0.08 AU/s)

# Gravity: a gentle, mass-scaled tug toward each planet (mass ~ radius²), falling
# off with distance², clamped so thrust always wins. Retuned for the 0.1-AU scale.
const GRAVITY_ENABLED := false   # no gravitational pull — bodies are SAFE ZONES (speed-limited), not wells
# Mass-based gravity: accel = GRAV_G × mass(Earth=1) / dist². Real masses (see the
# body specs) make the giants + Sun grab hard while Mercury/Mars barely tug. Capped
# below thrust (~1650) so a planet can pull you in, but full throttle always escapes.
const GRAV_G := 31400.0             # gravity constant for the gameplay scale
const GRAVITY_MAX_ACCEL := 800.0    # per-body pull ceiling (units/s²)
const GRAVITY_RANGE_MULT := 60.0    # a body's well reaches within radius × this
# Stars are tiny on screen but carry a sun's mass — up close they pull hard enough to
# visibly bend your hull's path. Felt only within STAR_GRAVITY_RANGE. This is ON (the
# ship feels star gravity) while planet gravity + BOLT gravity stay OFF (GRAVITY_ENABLED):
# keeping gravity_at() returning zero means bullets fly dead-straight near every star.
const STAR_GRAVITY_ENABLED := true     # stars pull the SHIP (planets don't; bullets don't)
const STAR_GRAVITY_K := 18000000000.0  # accel = K / dist² (capped) — retuned for the ×10 spread
const STAR_GRAVITY_RANGE := 90000.0    # the well reaches out far enough to "call" you in
const STAR_GRAVITY_MAX := 160.0        # ceiling (units/s²); thrust (~1650) still wins

# Assigned by main before this node enters the tree.
@onready var eph := Ephemeris   # autoload

# Filled in by refresh(), read by the HUD / ship.
var nearest_name := ""
var nearest_dist := INF
var nearest_dir := Vector3.ZERO   # unit vector from ship toward the nearest body
var nearest_radius := 1.0         # visual radius of the nearest body (capture range scales with it)
var speed_limit := INF
var gravity := Vector3.ZERO
var star_dist := INF              # distance to this system's primary star (gates FTL / warp)
var speed_zones := true           # planet "safe zone" speed limit — ON in Sol, OFF elsewhere (set by main)
# Nearest named hub star you could "fly-arrive" into (id + distance + render offset). main reads
# these in the hub: fly close enough and it drops you into that star's local frame (see _arrive).
var hub_star_id := ""
var hub_star_dist := INF
var hub_star_rel := Vector3.ZERO   # render-space vector ship→star (so arrival keeps your spot)

var _bodies := []
var _stars := []        # named real stars as floating-origin destinations
var _dot_tex: Texture2D
var _rel := {}          # body name -> current render-space position (for navigator)

const STAR_RADIUS := 22.0     # visual size when you arrive
const STAR_SKY := 28000.0    # far dots clamp here so they read as sky points
const STAR_NEAR := 4200.0    # within this -> growing emissive sphere


# Names of bodies that can be navigation targets (planets, then named stars).
func targetables() -> Array:
	var out := []
	for b in _bodies:
		out.append(b.name)
	for st in _stars:
		out.append(st.name)
	return out

# Current render-space position of a body (relative to the ship).
func rel_of(name: String) -> Vector3:
	return _rel.get(name, Vector3.ZERO)


# Rich targetable list for the aim-based Tab picker: each entry carries the body's
# render-space offset, its kind (star/planet/moon/craft) and visual radius, so the
# picker can apply a per-type pick range (a big star reaches out many ly, a probe
# only a fraction of one). See main._aim_sorted_targets / _tab_pick_range.
func target_candidates() -> Array:
	var out := []
	for b in _bodies:
		var kind := "planet"
		if b.get("star", false):
			kind = "star"
		elif b.get("craft", false):
			kind = "craft"
		elif String(b.get("parent", "")) != "":
			kind = "moon"
		out.append({ "name": b.name, "rel": _rel.get(b.name, Vector3.ZERO),
			"kind": kind, "radius": float(b.radius) })
	for st in _stars:
		out.append({ "name": st.name, "rel": _rel.get(st.name, Vector3.ZERO),
			"kind": "star", "radius": STAR_RADIUS })
	return out


# Kind of a body by name: "star" | "planet" | "moon" | "craft" | "" (unknown). Used to label
# an undiscovered Tab target ("Unknown Star" / "Unknown Planet" …) without leaking its name.
func kind_of(name: String) -> String:
	for b in _bodies:
		if b.name == name:
			if b.get("star", false):
				return "star"
			elif b.get("craft", false):
				return "craft"
			elif String(b.get("parent", "")) != "":
				return "moon"
			return "planet"
	for st in _stars:
		if st.name == name:
			return "star"
	return ""


func _ready() -> void:
	_dot_tex = _make_dot_texture()
	load_system(SystemDB.bodies(SystemDB.SOL))
	_build_star_shell()


# Swap the rendered bodies to a different star system (used on wormhole arrival).
# Clears the current bodies and rebuilds from the given specs.
func load_system(specs: Array) -> void:
	for b in _bodies:
		b.dot.queue_free()
		b.label.queue_free()
		if b.sphere != null:
			b.sphere.queue_free()
		if b.model != null:
			b.model.queue_free()
	_bodies.clear()
	for spec in specs:
		_build_planet(spec)
	# reset transient readouts so a stale name doesn't linger one frame
	nearest_name = ""
	nearest_dist = INF
	speed_limit = INF


func _build_planet(p: Dictionary) -> void:
	var is_star: bool = p.get("star", false)

	var dot := Sprite3D.new()
	dot.texture = _dot_tex
	dot.modulate = p.color
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.shaded = false
	dot.pixel_size = 0.02
	add_child(dot)

	# Close-up body: a GLB model if the data names one, else a procedural
	# emissive sphere. Either way it starts hidden and shows when you're near.
	var model: Node3D = null
	var sphere: MeshInstance3D = null
	var mat: StandardMaterial3D = null
	if p.has("model"):
		model = _make_glb_body(p)
	if model == null:
		sphere = MeshInstance3D.new()
		var mesh := SphereMesh.new()
		# Stars are NOT enlarged (already huge — scaling them swallowed close planets);
		# only planets/moons get the visual boost.
		var vis: float = 1.0 if is_star else VISUAL_SCALE
		mesh.radius = p.radius * vis
		mesh.height = p.radius * 2.0 * vis
		mesh.radial_segments = 24
		mesh.rings = 12
		sphere.mesh = mesh
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # alpha is animated for the far->near LOD fade
		# Write depth even though transparent, so the ring's far half is properly occluded by
		# the planet (no more per-frame sort flip / flicker between ring and body).
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		mat.emission_enabled = true
		# Albedo RGB = the body's real colour; alpha starts 0 and is ramped up by the
		# LOD crossfade in refresh(). (Same alpha-fade for stars and planets.)
		mat.albedo_color = Color(p.color.r, p.color.g, p.color.b, 0.0)
		if is_star:
			# A star is its own light source — stays fully self-lit.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission = p.color
			mat.emission_energy_multiplier = 2.5
		else:
			# A real planet REFLECTS the Sun — matte surface lit by the Sun key light, so it
			# shows a day/night terminator instead of glowing as a flat disc. Only a faint
			# emission floor so the night side isn't pure black.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.metallic = 0.0
			mat.roughness = 0.92
			mat.emission = p.color
			mat.emission_energy_multiplier = 0.05
		sphere.material_override = mat
		sphere.visible = false
		add_child(sphere)

	# Optional flat planetary ring (Saturn). A tilted annulus that tracks the body and
	# shows whenever the close-up body does.
	var ring: MeshInstance3D = null
	if p.get("ring", false):
		ring = MeshInstance3D.new()
		ring.mesh = _make_ring_mesh(float(p.radius) * 1.28 * VISUAL_SCALE, float(p.radius) * 2.35 * VISUAL_SCALE, 72)
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED      # visible from both faces
		rmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS   # depth-write -> ring & planet occlude correctly (no flicker)
		rmat.albedo_color = Color(0.86, 0.79, 0.60, 0.6)   # pale tan, semi-transparent
		ring.material_override = rmat
		ring.rotation = Vector3(deg_to_rad(26.7), 0.0, deg_to_rad(7.0))   # Saturn's tilt
		ring.visible = false
		add_child(ring)

	var label := Label3D.new()
	label.text = p.name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 16
	label.font_size = 72
	label.pixel_size = 0.0058
	label.no_depth_test = true
	add_child(label)

	# Craft (Voyagers) drift outward forever from their start point at a constant speed.
	var is_craft: bool = p.get("craft", false)
	var craft_pos := Vector3.ZERO
	var drift_vel := Vector3.ZERO
	if is_craft:
		craft_pos = eph.scene_pos(p.name)
		var dir := craft_pos.normalized()
		if dir == Vector3.ZERO:
			dir = Vector3(0, 0, -1)
		drift_vel = dir * float(p.get("drift", 0.0))
	_bodies.append({
		"name": p.name, "radius": float(p.radius),
		"mass": float(p.get("mass", float(p.radius) * float(p.radius) * 0.05)),   # Earth=1; fallback ~ size
		"craft": is_craft, "drift_vel": drift_vel,
		"live": p.get("live", true) and not is_craft,   # craft use their own drift, not live
		"pos": craft_pos if is_craft else p.get("pos", Vector3.ZERO),
		"star": is_star,                      # the system's primary — gates FTL (star field)
		"parent": p.get("parent", ""),        # non-empty => a moon orbiting that body
		"orbit_r": float(p.get("orbit_r", 0.0)),
		"orbit_speed": float(p.get("orbit_speed", 0.0)),
		"fixed": p.get("fixed", false),       # Earth: stays put (geocentric origin), no sun-orbit
		# Moons get a random start phase (spread them); planets start at 0 so they begin at
		# their real JPL position, then revolve.
		"orbit_a": (randf() * TAU if String(p.get("parent", "")) != "" else 0.0),
		"dot": dot, "sphere": sphere, "mat": mat, "model": model, "label": label,
		"ring": ring,
		"spin": randf_range(0.05, 0.2),
	})


# A flat annulus (planetary ring) in the XZ plane, double-sided via the material.
func _make_ring_mesh(inner: float, outer: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var ci0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var co0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var ci1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var co1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		st.set_normal(Vector3.UP)
		st.add_vertex(ci0); st.add_vertex(co0); st.add_vertex(co1)
		st.add_vertex(ci0); st.add_vertex(co1); st.add_vertex(ci1)
	return st.commit()


# Instantiate a GLB body, scale it to the visual radius, self-light it (no scene
# lights) and add it hidden. Returns null if the model can't load (-> sphere).
func _make_glb_body(p: Dictionary) -> Node3D:
	# Loads a PackedScene (.glb/.gltf) OR a bare Mesh (.obj) — wrap a Mesh in a
	# MeshInstance3D so both paths produce a model Node3D.
	var res := load(p.model)
	var inst: Node3D = null
	if res is PackedScene:
		inst = (res as PackedScene).instantiate() as Node3D
	elif res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		inst = mi
	if inst == null:
		push_warning("PlanetSystem: couldn't load %s — using sphere" % p.model)
		return null
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(inst)
	# Stars keep their real size; only planets/moons are visually enlarged.
	var vis: float = 1.0 if p.get("star", false) else VISUAL_SCALE
	_fit(holder, inst, float(p.radius) * 2.0 * vis)   # longest axis == diameter
	_self_light(inst, p.color, float(p.get("glow", 1.0)), p.get("star", false))
	holder.visible = false
	return holder


# Named real stars at their TRUE distances — floating-origin destinations you can
# fly to. Far away they read as labelled sky points (clamped); up close they bloom
# into an emissive sphere. Positions/labels update every frame in refresh().
func _build_star_shell() -> void:
	for s in Ephemeris.STARS:
		var dot := Sprite3D.new()
		dot.texture = _dot_tex
		dot.modulate = s.color
		dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dot.shaded = false
		dot.pixel_size = 5.0
		dot.no_depth_test = true
		add_child(dot)

		var sphere := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = STAR_RADIUS
		mesh.height = STAR_RADIUS * 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		sphere.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = s.color
		mat.emission_enabled = true
		mat.emission = s.color
		mat.emission_energy_multiplier = 2.2
		sphere.material_override = mat
		sphere.visible = false
		add_child(sphere)

		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(s.color, 0.9)
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.outline_size = 12
		label.font_size = 46
		label.pixel_size = 1.0
		label.no_depth_test = true
		add_child(label)

		_stars.append({
			"name": s.name, "id": SystemDB.id_for_name(s.name),
			"true_pos": eph.star_true_pos(s), "ly": s.ly,
			"mass": float(s.get("mass", 333000.0)),
			"dot": dot, "sphere": sphere, "label": label,
		})


func refresh(ship_pos: Vector3, delta: float) -> void:
	nearest_dist = INF
	nearest_name = ""
	speed_limit = INF
	gravity = Vector3.ZERO
	star_dist = INF
	hub_star_dist = INF
	hub_star_id = ""
	nearest_radius = 1.0

	# Render positions computed THIS frame, by name. Moons read their parent from here so
	# they track the planet's visually-revolved position, not its raw Horizons spot (planets
	# are built before moons in _sol(), so a parent is always present by the time a moon needs
	# it). Without this, fast inner planets (Mars) drift off and their moons orbit empty space.
	var frame_pos := {}
	for b in _bodies:
		var rad: float = b.radius
		var vrad: float = rad * (1.0 if b.star else VISUAL_SCALE)   # rendered radius (stars unscaled); for visuals/LOD/capture, NOT gravity
		# Moons orbit their (live) parent; Sol bodies read live Horizons positions; others static.
		var bpos: Vector3
		if b.get("craft", false):
			b.pos += b.drift_vel * delta       # Voyagers drift outward forever
			bpos = b.pos
		elif b.parent != "":
			b.orbit_a += float(b.orbit_speed) * delta
			var oa: float = b.orbit_a
			var off: Vector3 = Vector3(cos(oa), 0.18 * sin(oa * 0.5), sin(oa)) * float(b.orbit_r) * VISUAL_SCALE
			# Follow the parent's revolved render position (this frame), falling back to its raw
			# Horizons spot if for some reason it wasn't computed yet.
			bpos = frame_pos.get(b.parent, eph.scene_pos(b.parent)) + off
		elif b.live:
			bpos = eph.scene_pos(b.name)
			# Visual revolution around the Sun (planets only). Advance the phase and rotate the
			# real heliocentric vector about the ecliptic-ish up axis.
			if ORBIT_ENABLED and not b.star and not b.fixed:
				var sunp: Vector3 = eph.scene_pos("Sun")
				var h: Vector3 = bpos - sunp
				var r := h.length()
				if r > 0.01:
					b.orbit_a += (ORBIT_K / pow(r, 1.5)) * delta
					bpos = sunp + h.rotated(Vector3.UP, b.orbit_a)
		else:
			# Authored systems: spread the static planet layout by the same factor the planets
			# grew, so bigger bodies don't end up inside their (unscaled) star. Star sits at origin.
			bpos = b.pos * (1.0 if b.star else VISUAL_SCALE)
		frame_pos[b.name] = bpos   # parents are computed before their moons (see _sol order)
		var rel: Vector3 = bpos - ship_pos  # floating origin
		var dist := rel.length()

		if GRAVITY_ENABLED and dist > 0.001 and dist < rad * GRAVITY_RANGE_MULT:
			var a := minf(GRAV_G * float(b.mass) / (dist * dist), GRAVITY_MAX_ACCEL)
			gravity += (rel / dist) * a

		# Force-slow safe-zone (NO pull): cap speed within a mass/size-scaled radius, eased from
		# the edge speed down to a floor at the body. Stars use a HIGHER floor (STAR_ZONE_FLOOR)
		# so you still decelerate on approach but can fly THROUGH the sun, not crawl to a stop.
		var zone: float = rad * (STAR_ZONE_MULT if b.star else PLANET_ZONE_MULT)
		if dist < zone:
			var zt := dist / zone
			var edge: float = STAR_EDGE_SPEED if b.star else ZONE_EDGE_SPEED
			var floor_spd: float = STAR_ZONE_FLOOR if b.star else _slow_min(float(b.mass))
			speed_limit = minf(speed_limit, lerpf(floor_spd, edge, zt))

		b.dot.position = rel
		b.label.position = rel + Vector3(0.0, vrad * 1.5 + 0.5, 0.0)
		_rel[b.name] = rel        # for the navigator (render-space position)

		if dist < nearest_dist:
			nearest_dist = dist
			nearest_name = b.name
			nearest_radius = vrad
		if b.get("star", false) and dist < star_dist:
			star_dist = dist   # how far we are from this system's sun (FTL gate)

		# crossfade: dot (far) -> body (near), scaled to the RENDERED body size
		var far_d := vrad * 70.0
		var near_d := vrad * 18.0
		var frac := clampf((dist - near_d) / maxf(far_d - near_d, 0.001), 0.0, 1.0)
		var sphere_a := 1.0 - frac

		if b.model != null:
			# A GLB can't fade per-surface cheaply, so swap it in past the
			# midpoint; the soft dot lingers as a glow until then.
			var on: bool = sphere_a > 0.45
			b.model.visible = on
			if on:
				b.model.position = rel
				b.model.rotate_y(b.spin * delta)
		else:
			b.sphere.position = rel
			b.sphere.rotate_y(b.spin * delta)
			b.sphere.visible = sphere_a > 0.02
			if b.sphere.visible:
				var col: Color = b.mat.albedo_color
				col.a = sphere_a
				b.mat.albedo_color = col

		# Planetary ring (Saturn): track the body, fade in with the close-up sphere.
		if b.ring != null:
			b.ring.position = rel
			b.ring.visible = sphere_a > 0.02
			if b.ring.visible:
				var rc: Color = b.ring.material_override.albedo_color
				rc.a = 0.6 * sphere_a
				b.ring.material_override.albedo_color = rc

		b.dot.visible = frac > 0.02
		if b.dot.visible:
			var dc: Color = b.dot.modulate
			dc.a = frac
			b.dot.modulate = dc
			b.dot.pixel_size = clampf(dist * 0.0008, 0.02, 2.0)

		var label_range := maxf(vrad * 130.0, 500.0)
		var la := clampf((label_range - dist) / (label_range * 0.3), 0.0, 1.0)
		b.label.visible = la > 0.02
		if b.label.visible:
			var lc: Color = b.label.modulate
			lc.a = la
			b.label.modulate = lc

	# Named stars: floating-origin destinations. Far -> a labelled sky point in the
	# right direction (clamped); near -> a growing emissive sphere. Live distance.
	for st in _stars:
		var srel: Vector3 = st.true_pos - ship_pos
		var sdist := srel.length()
		_rel[st.name] = srel
		# A star's gravity well — strong up close, so a near pass bends your trajectory.
		if STAR_GRAVITY_ENABLED and sdist > 0.001 and sdist < STAR_GRAVITY_RANGE:
			var sa := minf(STAR_GRAVITY_K / (sdist * sdist), STAR_GRAVITY_MAX)
			gravity += (srel / sdist) * sa
		if sdist < nearest_dist:
			nearest_dist = sdist
			nearest_name = st.name
			nearest_radius = STAR_RADIUS
		# Nearest star you could fly-arrive into (must be a real travel destination).
		if st.get("id", "") != "" and sdist < hub_star_dist:
			hub_star_dist = sdist
			hub_star_id = str(st.id)
			hub_star_rel = srel
		# Force-slow safe-zone around the star (no pull) — this is what eases you out
		# of warp as you arrive, scaled by the star's mass.
		var szone := STAR_RADIUS * STAR_ZONE_MULT
		if sdist < szone:
			# Higher floor (STAR_ZONE_FLOOR) than planets so you fly THROUGH the star, not crawl.
			speed_limit = minf(speed_limit, lerpf(STAR_ZONE_FLOOR, STAR_EDGE_SPEED, sdist / szone))
		var sdir: Vector3 = srel.normalized()
		if sdist < STAR_NEAR:
			st.sphere.visible = true
			st.sphere.position = srel
			st.dot.visible = false
			st.label.position = srel + Vector3(0.0, STAR_RADIUS * 1.6 + 2.0, 0.0)
		else:
			st.sphere.visible = false
			st.dot.visible = true
			var rd := minf(sdist, STAR_SKY)         # clamp far dots onto the "sky"
			st.dot.position = sdir * rd
			st.dot.pixel_size = clampf(rd * 0.0022, 1.5, 7.0)
			st.label.position = sdir * rd + Vector3(0.0, 14.0, 0.0)
		st.label.text = "%s\n%s" % [st.name, _fmt_star_dist(sdist)]

	# speed_limit was accumulated above from each body's force-slow zone (min cap).
	# Direction toward the nearest body (for the warp arrival ease-out).
	nearest_dir = _rel.get(nearest_name, Vector3.ZERO).normalized()


# Adaptive distance label for a star: light-years when genuinely far, but AU once you're
# in-system so the number actually CHANGES as you move closer/away (instead of "0.00 ly").
# (1 unit = 0.01 AU; Ephemeris.UNITS_PER_LY converts to light-years.)
func _fmt_star_dist(units: float) -> String:
	var ly := units / Ephemeris.UNITS_PER_LY
	if ly >= 0.05:
		return "%.2f ly" % ly
	var au := units * 0.01
	if au >= 10.0:
		return "%.1f AU" % au
	return "%.2f AU" % au


# Slowest speed cap a body imposes at its centre, from its mass (Earth=1): heavier =>
# slower. log() keeps the enormous mass range (Mercury 0.05 → Sun 333000) sensible.
func _slow_min(mass: float) -> float:
	return clampf(ZONE_EDGE_SPEED / (1.0 + log(1.0 + maxf(mass, 0.0)) * 0.42), ZONE_FLOOR, ZONE_EDGE_SPEED)


# Gravitational acceleration at an arbitrary true-space position, summed over every
# planet and star. Used by combat.gd so bullets curve through gravity wells too.
func gravity_at(pos: Vector3) -> Vector3:
	var g := Vector3.ZERO
	if not GRAVITY_ENABLED:
		return g
	var frame_pos := {}   # parent render positions this call (planets precede moons in _sol)
	for b in _bodies:
		var bpos: Vector3
		if b.parent != "":
			var oa: float = b.orbit_a
			var off: Vector3 = Vector3(cos(oa), 0.18 * sin(oa * 0.5), sin(oa)) * float(b.orbit_r) * VISUAL_SCALE
			bpos = frame_pos.get(b.parent, eph.scene_pos(b.parent)) + off
		elif b.live:
			bpos = eph.scene_pos(b.name)
			if ORBIT_ENABLED and not b.star and not b.fixed:
				var sunp: Vector3 = eph.scene_pos("Sun")
				var h: Vector3 = bpos - sunp
				if h.length() > 0.01:
					bpos = sunp + h.rotated(Vector3.UP, b.orbit_a)   # read-only (refresh advances the phase)
		else:
			bpos = b.pos * (1.0 if b.star else VISUAL_SCALE)   # match refresh's authored-system spread
		frame_pos[b.name] = bpos
		var rel: Vector3 = bpos - pos
		var d := rel.length()
		if d > 0.001 and d < float(b.radius) * GRAVITY_RANGE_MULT:
			var a := minf(GRAV_G * float(b.mass) / (d * d), GRAVITY_MAX_ACCEL)
			g += (rel / d) * a
	for st in _stars:
		var rel: Vector3 = st.true_pos - pos
		var d := rel.length()
		if d > 0.001 and d < STAR_GRAVITY_RANGE:
			var a := minf(STAR_GRAVITY_K / (d * d), STAR_GRAVITY_MAX)
			g += (rel / d) * a
	return g


# --- GLB helpers (scale, recenter, self-light) ------------------------------
func _fit(holder: Node3D, model: Node3D, target_len: float) -> void:
	var box := _combined_aabb(holder)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return
	var factor := target_len / longest
	model.scale = model.scale * factor
	model.position -= (box.position + size * 0.5) * factor


func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in _gather(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _gather(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_gather(c))
	return out


# Self-illuminate every surface so the body reads without scene lights. Stars
# burn from their own color; planets emit their texture so the map shows.
func _self_light(model: Node3D, tint: Color, glow: float, is_star: bool) -> void:
	for mi in _gather(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var m: BaseMaterial3D
			if orig is BaseMaterial3D:
				m = orig.duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.emission_enabled = true
			if is_star:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.emission = tint
				m.albedo_color = tint
			else:
				# A planet surface, NOT metal. glTF defaults metalness to 1.0,
				# which hides the texture (this is why Earth looked colourless) —
				# force it matte so the map shows, lit by the Sun key light. Tint
				# the (desaturated) map toward the body colour so Earth reads blue.
				m.metallic = 0.0
				m.roughness = 0.9
				m.albedo_color = tint
				m.emission = tint   # dim flat floor; night side stays dark-ish
			m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)


# Soft radial glow circle, generated once (no binary asset to ship).
func _make_dot_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
