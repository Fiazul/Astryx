extends SceneTree

func _initialize() -> void:
	var ps := load("res://assets/galaxy.glb") as PackedScene
	print("PackedScene loaded: ", ps != null)
	if ps == null:
		quit(); return
	var inst := ps.instantiate() as Node3D
	print("root type: ", inst.get_class(), "  name: ", inst.name)
	get_root().add_child(inst)

	var meshes: Array = []
	_gather(inst, meshes)
	print("MeshInstance3D count: ", meshes.size())

	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	var inv := inst.global_transform.affine_inverse()
	for mi in meshes:
		print("  mesh '", mi.name, "' surfaces=", (mi.mesh.get_surface_count() if mi.mesh else 0),
			" local_aabb=", (mi.mesh.get_aabb() if mi.mesh else "none"),
			" visible=", mi.visible, " scale=", mi.scale)
		if mi.mesh == null: continue
		for s in range(mi.mesh.get_surface_count()):
			var m = mi.get_active_material(s)
			var tex = null
			if m is BaseMaterial3D:
				tex = (m as BaseMaterial3D).albedo_texture
			print("     surf", s, " mat=", (m.get_class() if m else "null"),
				" albedo_tex=", (tex != null), " albedo_color=",
				((m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else "?"))
			var ab: AABB = mi.mesh.get_aabb()
			for i in range(8):
				var c := Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
				var corner: Vector3 = (inv * mi.global_transform) * (ab.position + ab.size * c)
				mn = mn.min(corner)
				mx = mx.max(corner)
	print("COMBINED AABB min=", mn, " max=", mx, " size=", (mx - mn))
	var size := mx - mn
	print("longest extent=", maxf(size.x, maxf(size.y, size.z)))
	quit()

func _gather(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_gather(c, out)
