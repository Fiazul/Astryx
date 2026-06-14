class_name Starfield
extends MultiMeshInstance3D
# Background star field as a single MultiMesh (one draw, thousands of points) —
# never thousands of nodes. Billboarded emissive quads scattered on a large
# sphere shell around the origin.
#
# It lives on the world root and never moves: the ship stays at the origin and
# only rotates, so a fixed shell is a correct parallax-free backdrop (the stars
# are effectively infinitely far away).

const COUNT := 1200
const SHELL := 6000.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true  # let per-instance color tint each star
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	material_override = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	# Per the MultiMesh API: set transform_format + use_colors BEFORE
	# instance_count (setting the count sizes the buffers).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = COUNT
	multimesh = mm

	for i in COUNT:
		var dir := Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
		while dir.length_squared() < 0.0001:
			dir = Vector3(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
		var pos := dir.normalized() * SHELL * randf_range(0.85, 1.0)
		var s := randf_range(8.0, 26.0)
		var basis := Basis().scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, pos))

		# Mostly white, a few blue-white and warm tints, varied brightness.
		var b := randf_range(0.5, 1.0)
		var tint := randf()
		var col := Color(b, b, b)
		if tint > 0.85:
			col = Color(b * 0.7, b * 0.85, b)   # blue-white
		elif tint < 0.15:
			col = Color(b, b * 0.85, b * 0.7)   # warm
		mm.set_instance_color(i, col)
