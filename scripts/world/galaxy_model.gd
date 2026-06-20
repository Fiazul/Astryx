class_name GalaxyModel
extends Node3D
# The Milky Way as a real textured model (assets/galaxy.glb, CC-BY 4.0 — see CREDITS.md),
# placed as a distant backdrop toward the real Sgr A* direction. Its materials are made
# unshaded + additive so the spiral reads as glowing light in empty space (there are no
# lights out here). Auto-scaled to a target on-sky size so it doesn't matter what units the
# model shipped in. World-fixed (the ship sits at the origin and only rotates).

const GLB := "res://assets/galaxy.glb"
const DIR := Vector3(-0.0546, -0.4849, -0.8728)   # toward galactic centre (Sgr A*) — IN the plane
const POLE := Vector3(-0.868, 0.456, -0.198)      # galactic north pole = the disc's normal
const DIST := 3000.0            # centre toward Sgr; the ship (origin) sits INSIDE the disc radius
const TARGET_RADIUS := 4200.0   # huge: we're embedded in the disc, ~halfway out from the core
const BRIGHTNESS := 1.0         # edge-on is faint, so keep it up

# --- Voyage to the core (the looming approach) ---
# The real Sun→Sgr A* distance. The galaxy is a fixed backdrop, so to make it actually GROW as
# the Vela Iron Pulse flies the galactic drive toward it, we move the disc's CENTRE from DIST
# (the far backdrop look) in toward the origin as `remaining_ly` shrinks 26000 → 0. The disc
# keeps its physical size (TARGET_RADIUS), so when its centre reaches you the band wraps 360°
# and you're AT the core. CRUCIAL: we never use the real ~1.6e11-unit distance (float32 would
# shatter) — the render distance is a safe, bounded [0, DIST] mapping while the SCANNER still
# reports the true light-years. main calls advance_ly() each frame from ship.galactic_loom_rate().
const CORE_LY := 26000.0       # real distance to the galactic centre (the scanner's full reading)
var remaining_ly := CORE_LY    # live distance still to go; CORE_LY = far backdrop, 0 = at the core
var _dir_n := DIR.normalized() # cached core direction (render space)

# Sagittarius A* — the black hole at the dead centre, rendered to match its REAL Event Horizon
# Telescope photo: a dominant dark central SHADOW, wrapped by a thin, fuzzy, glowing-orange PHOTON
# RING, with one side brighter than the other (relativistic Doppler beaming — gas rotating toward us
# is boosted) plus a few bright clumps. Built procedurally on a flat quad tilted BH_TILT_DEG off the
# galactic plane (no model — a real BH is bent light, not a solid object): since we sit in the plane,
# the tilt foreshortens the ring into the iconic "donut from an angle". Parented to THIS node, so it
# sits at the disc centre and looms in as you fly the drive toward it. The hole is fixed (no spin).
const BLACKHOLE_RADIUS := 100.0   # on-screen size (half-extent) of the hole at the centre.
const BH_RISE := 1.0            # lift the hole UP off the dead centre (+ = up, - = down, 0 = centre)
const BH_ENERGY := 2.0          # ring brightness (drives the bloom halo)
const BH_SHADOW_FRAC := 0.34    # dark central shadow radius (fraction of the half-size)
const BH_RING_FRAC := 0.46      # radius of the bright photon-ring peak
const BH_RING_WIDTH := 0.075    # ring softness / fuzz (bigger = fuzzier, EHT-like)
const BH_OUTER_FRAC := 0.92     # radius where the glow fades to nothing
const BH_DOPPLER := 0.6         # brightness asymmetry: 0 = even ring, ~0.7 = strong bright side
const BH_DOPPLER_DEG := 90.0    # which side is the bright (approaching) side, in degrees
const BH_KNOTS := 0.35          # bright clumps around the ring (real Sgr A* isn't a smooth band)
const BH_TILT_DEG := 32.0       # tilt of the disc off the galactic plane. 0 = flat-in-plane (we're
								# in the plane, so that reads near edge-on); ~30 tips it toward us into
								# a foreshortened ellipse — the real "donut seen from an angle" look.
								# 90 = face-on circle. This is the knob for "the angle is off".
const BH_RING_COLOR := Color(1.0, 0.55, 0.2)    # the orange of the ring body
const BH_HOT_COLOR := Color(1.0, 0.92, 0.72)    # the hotter white-orange at the ring peak
const BLACKHOLE_SHOW_LY := 30000.0 # reveal distance. Just under CORE_LY (26000) so it's HIDDEN in
								   # all normal play (distance sits at 26000 there), but appears as a
								   # distant speck the moment the voyage starts and looms the whole way.
								   # (The model's light, so rendering it across the approach is cheap.)
# Burned-star bulge around Sgr A* (the real nuclear star cluster): a dense swarm of dying stars.
# Pushed out past the now-bigger hole so the swarm rings it instead of sinking inside.
const BH_STAR_COUNT := 600
const BH_STAR_INNER := 1000.0     # cluster starts outside the (big) hole...
const BH_STAR_OUTER := 2800.0     # ...and thins out to here
const BH_STAR_SIZE := 16.0        # per-star sprite size
var _blackhole: Node3D            # the Sgr A* holder (camera-facing EHT disc); gated in _apply_loom
var _starcluster: MultiMeshInstance3D   # the burned-star bulge; gated alongside the hole


func _ready() -> void:
	var ps := load(GLB) as PackedScene
	if ps == null:
		push_warning("GalaxyModel: %s missing/not imported — open the project in the editor once." % GLB)
		return
	var inst := ps.instantiate() as Node3D
	if inst == null:
		push_warning("GalaxyModel: scene root is not Node3D")
		return
	add_child(inst)

	# Collect every MeshInstance, glow-ify its materials, and gather a combined AABB.
	var meshes: Array[MeshInstance3D] = []
	_gather(inst, meshes)
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	var inv := inst.global_transform.affine_inverse()
	for mi in meshes:
		_glowify(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 20000.0
		if mi.mesh == null:
			continue
		var to_root := inv * mi.global_transform
		var ab := mi.mesh.get_aabb()
		for i in range(8):
			var corner: Vector3 = to_root * (ab.position + ab.size * _CORNER[i])
			mn = mn.min(corner)
			mx = mx.max(corner)

	# Auto-fit: scale so the largest extent matches TARGET_RADIUS, and recentre.
	var size := mx - mn
	var longest: float = maxf(size.x, maxf(size.y, size.z))
	if longest > 0.0001:
		inst.scale = Vector3.ONE * (2.0 * TARGET_RADIUS / longest)
	inst.position = -((mn + mx) * 0.5) * inst.scale.x   # centre the model on this node

	# Physically correct view: lay the disc in the REAL galactic plane (its normal, local +Z,
	# aligned to the galactic pole) with its centre toward Sgr A*. The ship (origin) lies in
	# that plane and inside the disc radius, so the galaxy is seen EDGE-ON — a thin glowing band
	# brightest toward the core — exactly as you'd see it from inside the disc.
	var z := POLE.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	basis = Basis(x, y, z)
	_add_blackhole()
	_apply_loom()


# The Event Horizon Telescope look, drawn on a camera-facing quad (see BH_EHT_SHADER): a dark
# central shadow, a thin fuzzy orange photon ring, and a Doppler-bright side. Lives in a HOLDER we
# own (lifted by BH_RISE); a burned-star bulge (the real nuclear star cluster) rings it.
func _add_blackhole() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_blackhole = holder
	holder.visible = false   # _apply_loom turns it on only once the core is close (BLACKHOLE_SHOW_LY)

	var shader := Shader.new()
	shader.code = BH_EHT_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("shadow", BH_SHADOW_FRAC)
	mat.set_shader_parameter("ring", BH_RING_FRAC)
	mat.set_shader_parameter("ring_width", BH_RING_WIDTH)
	mat.set_shader_parameter("outer", BH_OUTER_FRAC)
	mat.set_shader_parameter("energy", BH_ENERGY)
	mat.set_shader_parameter("doppler", BH_DOPPLER)
	mat.set_shader_parameter("doppler_dir", deg_to_rad(BH_DOPPLER_DEG))
	mat.set_shader_parameter("knots", BH_KNOTS)
	mat.set_shader_parameter("ring_col", BH_RING_COLOR)
	mat.set_shader_parameter("hot_col", BH_HOT_COLOR)
	mat.render_priority = 1   # draw after the galaxy so the shadow occludes the bright core behind

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0 * BLACKHOLE_RADIUS, 2.0 * BLACKHOLE_RADIUS)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20000.0   # huge on approach — never cull by the tiny quad AABB
	holder.add_child(mi)

	# Lift it UP off the dead centre (world-up, converted into our local frame since the holder is
	# our child) so the hole sits where you're looking rather than dead-centre.
	holder.position = (basis.inverse() * Vector3.UP) * BH_RISE

	# Orient the disc: a REAL flat disc (no longer a billboard), laid in the galactic plane and then
	# tipped BH_TILT_DEG toward us. We sit IN the plane, so a perfectly flat disc would read edge-on;
	# the tilt swings its normal off the galactic pole, about an axis perpendicular to our line of
	# sight, so we view it foreshortened into an ellipse — the iconic "donut from an angle".
	var pole_local := Vector3(0, 0, 1)                       # galactic pole in our local frame (node +Z)
	var view_local := (basis.inverse() * _dir_n).normalized()  # local direction from us out to the core
	var tilt_axis := pole_local.cross(view_local)
	if tilt_axis.length() < 0.001:
		tilt_axis = Vector3(1, 0, 0)
	tilt_axis = tilt_axis.normalized()
	var normal := pole_local.rotated(tilt_axis, deg_to_rad(BH_TILT_DEG)).normalized()  # disc face dir
	holder.basis = _basis_from_normal(normal, tilt_axis)
	_build_burned_stars()


# Build an orthonormal basis whose +Z (a QuadMesh's facing normal) is `normal`, using `ref` as an
# in-plane hint for the +X axis so the disc's orientation is stable/predictable.
func _basis_from_normal(normal: Vector3, ref: Vector3) -> Basis:
	var z := normal.normalized()
	var x := ref - z * ref.dot(z)
	if x.length() < 0.001:
		x = Vector3.RIGHT - z * Vector3.RIGHT.dot(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


# The EHT photo, procedurally. A billboard quad (always face-on, so the ring reads correctly from
# any angle); the shadow is opaque black (occludes the bright galactic core behind it); the photon
# ring is a fuzzy gaussian band; Doppler beaming brightens one side. Unshaded, glows via EMISSION.
const BH_EHT_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float shadow = 0.34;
uniform float ring = 0.46;
uniform float ring_width = 0.075;
uniform float outer = 0.92;
uniform float energy = 2.0;
uniform float doppler = 0.6;
uniform float doppler_dir = 1.5708;
uniform float knots = 0.35;
uniform vec3 ring_col : source_color = vec3(1.0, 0.55, 0.2);
uniform vec3 hot_col : source_color = vec3(1.0, 0.92, 0.72);
// No vertex(): the quad uses its real (tilted) node transform, so the ring foreshortens into an
// ellipse exactly as a flat accretion disc would when viewed from an angle.
void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;             // 0 at centre → 1 at the edge
	if (r < shadow) {
		// the shadow: opaque black, swallows the bright galactic core behind it
		ALBEDO = vec3(0.0);
		EMISSION = vec3(0.0);
		ALPHA = 1.0;
	} else {
		float theta = atan(p.y, p.x);
		float band = exp(-pow((r - ring) / ring_width, 2.0));   // fuzzy photon-ring band
		float lip = smoothstep(shadow, ring, r);                 // soft ramp off the shadow edge
		float ofade = 1.0 - smoothstep(ring, outer, r);          // fade out past the ring
		float glow = band + 0.3 * lip * ofade;
		glow *= 1.0 + doppler * cos(theta - doppler_dir);        // Doppler: one side blinding-bright
		glow *= 1.0 + knots * (0.5 + 0.5 * sin(theta * 3.0 + 1.3)); // a few bright clumps round the ring
		glow = max(glow, 0.0);
		if (glow < 0.015) discard;
		vec3 col = mix(ring_col, hot_col, clamp(band, 0.0, 1.0));   // hotter (white) at the ring peak
		col = mix(vec3(0.25, 0.05, 0.02), col, clamp(lip, 0.0, 1.0)); // dark-red dust at the inner lip
		ALBEDO = vec3(0.0);
		EMISSION = col * glow * energy;
		ALPHA = clamp(glow, 0.0, 1.0);
	}
}
"""


# Per-star "burning" flicker. Billboard + keep-scale (so the MultiMesh sprites stay round and
# face the camera) done in the vertex stage, then each instance's brightness is modulated by a
# two-octave sine seeded off INSTANCE_ID — every star pulses at its own rate/phase, so the whole
# bulge restlessly smoulders like embers instead of sitting as dead dots. Additive, unshaded.
const BURNING_STAR_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color;
varying vec3 star_col;
varying float flick;
void vertex() {
	// Billboard the quad toward the camera while keeping each instance's own scale.
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = mv * mat4(vec4(sx,0.0,0.0,0.0), vec4(0.0,sy,0.0,0.0), vec4(0.0,0.0,1.0,0.0), vec4(0.0,0.0,0.0,1.0));
	star_col = COLOR.rgb;
	float seed = float(INSTANCE_ID);
	// Two octaves, each star with its own rate + phase → out-of-sync, fire-like flicker.
	float f = 0.70
		+ 0.28 * sin(TIME * (4.0 + fract(seed * 0.123) * 6.0) + seed)
		+ 0.12 * sin(TIME * (11.0 + fract(seed * 0.317) * 9.0) + seed * 1.7);
	flick = clamp(f, 0.25, 1.35);
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = star_col * flick;
	ALPHA = t.a;
}
"""


# The burned-star bulge: a dense swarm of dying stars packed around Sgr A* (the real nuclear
# cluster). One MultiMesh = one draw call. Colours skew to a hot old-population palette — deep
# reds and ambers (red giants / dying stars) with a few searing blue-white youngsters near the
# centre. Each star "burns" — a per-instance brightness flicker (see BURNING_STAR_SHADER).
# Child of THIS (the disc centre), so it looms with the core but does NOT spin.
func _build_burned_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(BH_STAR_SIZE, BH_STAR_SIZE)
	mm.mesh = quad
	mm.instance_count = BH_STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB1ACE   # fixed seed → the cluster looks the same every run
	for i in BH_STAR_COUNT:
		# Spherical bulge, denser toward the centre (cubic falloff on the radius).
		var dir := Vector3(rng.randfn(), rng.randfn() * 0.6, rng.randfn()).normalized()
		var t := rng.randf()
		var r := lerpf(BH_STAR_INNER, BH_STAR_OUTER, t * t * t)
		mm.set_instance_transform(i, Transform3D(Basis(), dir * r))
		mm.set_instance_color(i, _burned_star_color(rng))
	_starcluster = MultiMeshInstance3D.new()
	_starcluster.multimesh = mm
	_starcluster.extra_cull_margin = 20000.0
	_starcluster.visible = false
	var sh := Shader.new()
	sh.code = BURNING_STAR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", _star_sprite())   # soft round sprite, tinted+flickered per star
	_starcluster.material_override = mat
	add_child(_starcluster)


# Hot old-population palette: mostly deep red / amber dying stars, a few hot blue-white.
func _burned_star_color(rng: RandomNumberGenerator) -> Color:
	var roll := rng.randf()
	if roll < 0.55:
		return Color(1.0, rng.randf_range(0.30, 0.50), 0.12)   # deep red giants
	elif roll < 0.85:
		return Color(1.0, rng.randf_range(0.62, 0.80), 0.30)   # amber / orange
	else:
		return Color(rng.randf_range(0.70, 0.85), 0.85, 1.0)   # rare hot blue-white


# Soft round star sprite (radial alpha falloff) for the bulge points.
func _star_sprite() -> Texture2D:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a   # tight bright core, soft halo
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# Place the disc centre at the render distance for the current `remaining_ly`. Linear map:
# remaining = CORE_LY → DIST (far backdrop, the normal look); remaining = 0 → origin (you're
# inside the core). Bounded in [0, DIST], so coordinates stay tiny and float-safe the whole way.
func _apply_loom() -> void:
	position = _dir_n * (DIST * remaining_ly / CORE_LY)
	# Only pay for the black hole + star bulge when the core is genuinely close (into the voyage).
	var show := remaining_ly < BLACKHOLE_SHOW_LY
	if _blackhole != null:
		_blackhole.visible = show
	if _starcluster != null:
		_starcluster.visible = show


# Loom the core in by `ly` light-years this frame (SIGNED: positive = toward the core / looms in,
# negative = flying back out / recedes). main feeds this from ship.galactic_loom_rate(), the fixed
# voyage pace — decoupled from the ship's real translation, so true_pos is never moved astronomically.
# Clamped to [0, CORE_LY]; the signed form is what lets you actually LEAVE the core instead of being
# trapped at 0.
func advance_ly(ly: float) -> void:
	remaining_ly = clampf(remaining_ly - ly, 0.0, CORE_LY)
	_apply_loom()


# Snap the backdrop back to its full far distance. main calls this on every system arrival
# (wormhole hop, emergency jump home), since you're then ~26,000 ly from the core again — so
# you never stay wrapped inside the core/clouds after leaving the voyage.
func reset_distance() -> void:
	remaining_ly = CORE_LY
	_apply_loom()


# Scanner readouts (the Iron Pulse's live core-distance gauge, surfaced on the ship + HUD).
func remaining() -> float:
	return remaining_ly

func total() -> float:
	return CORE_LY


const _CORNER := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
	Vector3(1, 1, 0), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1),
]


func _gather(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_gather(c, out)


# Radial-fade shader for the flat disc card: additive glow that fades to ZERO before the
# UV edge, so the low-poly (82-vert) card's straight polygon silhouette never shows as a
# hard "pentagon" outline — the glow ends in a soft round falloff instead.
const DISC_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color;
uniform float brightness = 1.0;
uniform float fade_start = 0.2 ;
uniform float fade_end = .98;
void fragment() {
	vec4 c = texture(tex, UV);
	float d = length(UV - vec2(0.5)) * 2.0;      // 0 at centre, 1 at edge-midpoint
	float mask = 1.0 - smoothstep(fade_start, fade_end, d);
	ALBEDO = c.rgb * brightness;
	ALPHA = mask;                                 // additive contribution fades to 0 at the rim
}
"""


# Make a mesh glow. The flat disc card (it has an albedo texture) gets the radial-fade shader
# so its polygon edge disappears. The round core sphere keeps the simple additive path.
func _glowify(mi: MeshInstance3D) -> void:
	var n := mi.mesh.get_surface_count() if mi.mesh != null else 0
	for s in range(n):
		var src := mi.get_active_material(s)

		# Disc card → radial-fade shader (rounds off the polygon silhouette).
		if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
			var b := src as BaseMaterial3D
			var tex := b.emission_texture
			if tex == null:
				tex = b.albedo_texture
			var sh := Shader.new()
			sh.code = DISC_SHADER
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("tex", tex)
			sm.set_shader_parameter("brightness", BRIGHTNESS)
			mi.set_surface_override_material(s, sm)
			continue

		var mat: BaseMaterial3D
		if src is BaseMaterial3D:
			mat = (src as BaseMaterial3D).duplicate()
		else:
			mat = StandardMaterial3D.new()
		# The model is authored to GLOW via its emissive texture (black base colour). Respect
		# that — keep it shaded so emission shows, the black albedo stays dark, and the spiral's
		# real colours/structure survive (additive would wash it into a moon-like blob). We only:
		#  - scale the emissive energy by BRIGHTNESS (dim it for the deep/distant look),
		#  - show both faces (cull off) so it reads from any side,
		#  - never cast shadows (the GPU-crash lesson).
		mat.emission_enabled = true
		mat.emission_energy_multiplier = BRIGHTNESS
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_receive_shadows = true
		# ADDITIVE: the spiral lives in an emissive texture on a BLACK, OPAQUE base, so by
		# default the dark disc renders as a solid wall that occludes the starfield behind it
		# ("dark mass behind us" bug). Additive blend makes black contribute nothing (stars
		# show through) while the glowing arms add light — the correct look for a galaxy in
		# space. Stays SHADED (unshaded ignores emission); with no lights out here the black
		# albedo adds ~0, so only the emission shows. Don't write depth (it's a backdrop).
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.set_surface_override_material(s, mat)
