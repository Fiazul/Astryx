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

# Sagittarius A* — the black hole at the dead centre ("blackhole skyball" by CatLoveCheese,
# CC-BY 4.0, see CREDITS.md). A skyball: a circle/sphere with the black hole on ONE side.
# Parented to THIS node, so it sits at the disc centre and looms in as you fly the drive toward it.
const BLACKHOLE_GLB := "res://assets/blackhole_skyball.glb"
const BLACKHOLE_RADIUS := 300.0   # fitted on-screen size of the hole at the centre.
const BH_RISE := 15.0            # lift the hole UP off the dead centre (+ = up, - = down, 0 = centre)
# >>> ADJUST THE ANGLE HERE <<<  Euler rotation in DEGREES applied to the whole model — pitch (X),
# yaw (Y), roll (Z). Tweak these three numbers to aim the black-hole side wherever you want it.
const BH_ROT_DEG := Vector3(-5, 180, -30)
const BH_BLACKEN := false         # true = paint the whole model pure black; false = keep its own
								  # textures (so the skyball's painted black hole stays visible)
const BH_EDGE_FADE := 2.5         # how hard the silhouette edges fade to nothing (higher = softer
								  # bigger fade ring; ~1 = barely, ~4 = lots). 0 disables the fade.
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
var _blackhole: Node3D            # the Sgr A* model (a holder we tilt + spin); gated in _apply_loom
var _starcluster: MultiMeshInstance3D   # the burned-star bulge; gated alongside the hole
var _bh_fade_shader: Shader       # cached edge-fade shader (built once, shared by every surface)


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


# Build Sgr A* at the disc centre. The model goes inside a HOLDER node we own, so we can:
#   • centre + fit the model within it,
#   • aim it via the BH_ROT_DEG angle knob, and lift it with BH_RISE.
# Then a burned-star bulge is scattered around it (the real nuclear star cluster).
func _add_blackhole() -> void:
	var ps := load(BLACKHOLE_GLB) as PackedScene
	if ps == null:
		push_warning("GalaxyModel: %s missing/not imported — open the project in the editor once." % BLACKHOLE_GLB)
		return
	var model := ps.instantiate() as Node3D
	if model == null:
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(model)
	_blackhole = holder
	holder.visible = false   # _apply_loom turns it on only once the core is close (BLACKHOLE_SHOW_LY)
	var meshes: Array[MeshInstance3D] = []
	_gather(model, meshes)
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	var inv := model.global_transform.affine_inverse()
	for mi in meshes:
		if BH_BLACKEN:
			_blacken(mi)        # paint every surface pure black — the event horizon swallows all light
		elif BH_EDGE_FADE > 0.0:
			_fade_edges(mi)     # keep its glowing texture, but melt the silhouette rim into the void
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
	# Centre + fit the model WITHIN the holder (so the holder spins about the hole's centre).
	var size := mx - mn
	var longest: float = maxf(size.x, maxf(size.y, size.z))
	var msc := (2.0 * BLACKHOLE_RADIUS / longest) if longest > 0.0001 else 1.0
	model.scale = Vector3.ONE * msc
	model.position = -((mn + mx) * 0.5) * msc
	# Orientation: just the BH_ROT_DEG Euler angles (degrees). Tweak that constant up top to aim
	# the black-hole side of the skyball however you like. Relative to the galactic-plane frame.
	holder.rotation_degrees = BH_ROT_DEG
	# Lift it UP off the dead centre (world-up, converted into our local frame since the holder is
	# our child) — the model hangs low, so raising it puts the body where you're looking.
	holder.position = (basis.inverse() * Vector3.UP) * BH_RISE
	_build_burned_stars()


# Paint a black-hole surface ENTIRELY BLACK: opaque, unshaded, back-face culled. No light, no
# emission — a pure event-horizon silhouette against the glowing core.
func _blacken(mi: MeshInstance3D) -> void:
	var n := mi.mesh.get_surface_count() if mi.mesh != null else 0
	for s in range(n):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0, 0, 0)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.disable_receive_shadows = true
		mi.set_surface_override_material(s, mat)


# Edge fade: keep the skyball's own look (its albedo + emissive glow) but make the SILHOUETTE melt
# away — alpha drops to zero where the surface turns edge-on to the camera (a Fresnel term). On the
# sphere that's exactly its circular rim, so the hard disc edge dissolves into the starfield instead
# of cutting a sharp circle. Unshaded so it reads the same in the lightless void.
const BH_FADE_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;
uniform sampler2D albedo_tex : source_color;
uniform sampler2D emission_tex : source_color;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform vec3 emission_col : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform bool has_albedo_tex = false;
uniform bool has_emission_tex = false;
uniform float fade_power = 2.5;
void fragment() {
	vec4 a = albedo_col;
	if (has_albedo_tex) { a *= texture(albedo_tex, UV); }
	vec3 e = emission_col * emission_energy;
	if (has_emission_tex) { e *= texture(emission_tex, UV).rgb; }
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	ALBEDO = a.rgb + e;                   // its own colour + glow, unshaded
	ALPHA = a.a * pow(ndv, fade_power);   // 1 facing you → 0 at the silhouette edge
}
"""


# Apply the edge fade to one mesh, preserving its original albedo + emission so it looks the same
# except the rim now dissolves. Reads the imported material per surface and feeds it to the shader.
func _fade_edges(mi: MeshInstance3D) -> void:
	if _bh_fade_shader == null:
		_bh_fade_shader = Shader.new()
		_bh_fade_shader.code = BH_FADE_SHADER
	var n := mi.mesh.get_surface_count() if mi.mesh != null else 0
	for s in range(n):
		var orig := mi.get_active_material(s)
		var mat := ShaderMaterial.new()
		mat.shader = _bh_fade_shader
		mat.set_shader_parameter("fade_power", BH_EDGE_FADE)
		if orig is BaseMaterial3D:
			var bm := orig as BaseMaterial3D
			mat.set_shader_parameter("albedo_col", bm.albedo_color)
			mat.set_shader_parameter("albedo_tex", bm.albedo_texture)
			mat.set_shader_parameter("has_albedo_tex", bm.albedo_texture != null)
			mat.set_shader_parameter("emission_tex", bm.emission_texture)
			mat.set_shader_parameter("has_emission_tex", bm.emission_texture != null)
			if bm.emission_enabled:
				mat.set_shader_parameter("emission_col", bm.emission)
				mat.set_shader_parameter("emission_energy", bm.emission_energy_multiplier)
		mi.set_surface_override_material(s, mat)


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
