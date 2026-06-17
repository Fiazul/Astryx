class_name Starfield
extends MeshInstance3D
# Background star field rendered from a BAKED real-catalogue points mesh — one mesh,
# one draw call, even at a million points. The geometry (positions on a 6000-unit shell,
# per-star colour from the real B-V index, per-star point size from apparent magnitude)
# is built offline by tools/build_starfield.gd, so the game pays ZERO startup cost.
#
# It lives on the world root and never moves: the ship stays at the origin and only
# rotates, so a fixed shell is a correct parallax-free backdrop (stars are effectively
# infinitely far away).
#
# Quality (potato switch):
#   HIGH (~1,000,000 pts) = real HYG stars + procedural Milky-Way fill — cinematic.
#   LOW  (~118,000 pts)   = real HYG only — accurate sky, featherweight.
# Both are one draw call; the cost difference is mostly fragment/overdraw from the extra
# faint points. Flip QUALITY_HIGH to false (or via a setting) on weak hardware.

# Quality tier — set this to taste / hardware:
#   "tycho" = REAL Tycho-2 catalogue, brightest ~355,360 (mag ≤ 10) — the default. See STARFIELD.md.
#   "high"  = real HYG (~118k) + procedural Milky-Way band (~500k total) — cinematic.
#   "low"   = real HYG only (~118k) — accurate, featherweight (potato).
const QUALITY := "tycho"
const MESHES := {
	"tycho": "res://assets/starfield_tycho.res",
	"high": "res://assets/starfield_high.res",
	"low": "res://assets/starfield_low.res",
}

# Per-star SIZE is baked into UV.x; per-star COLOUR (with magnitude baked into its
# intensity) is the vertex colour. A soft round additive glow sells each as a star.
# star_gain scales overall brightness live (no re-bake) — raise/lower if the field is too
# dim or too "busy". The baked colours already encode each star's magnitude.
const STAR_GAIN := 1.0
const STAR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float star_gain = 1.0;

void vertex() {
	POINT_SIZE = UV.x;   // baked per-star point size (apparent magnitude)
}

void fragment() {
	float d = distance(POINT_COORD, vec2(0.5));
	float a = smoothstep(0.5, 0.04, d);   // soft round falloff (no hard squares)
	ALBEDO = COLOR.rgb * star_gain;        // real B-V colour, magnitude in its brightness
	ALPHA = a;
}
"""


func _ready() -> void:
	var path: String = MESHES.get(QUALITY, MESHES["high"])
	var m := load(path) as ArrayMesh
	if m == null:
		push_warning("Starfield: baked mesh missing (%s) — run tools/build_starfield.gd" % path)
		return
	mesh = m

	var sh := Shader.new()
	sh.code = STAR_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	smat.set_shader_parameter("star_gain", STAR_GAIN)
	material_override = smat
	# Never frustum-culled as a clump; the shell surrounds the camera.
	extra_cull_margin = 20000.0
