class_name ShipMesh
extends RefCounted
# Stateless mesh / material / FX helpers for the player ship. Pulled out of ship.gd
# to keep that file focused on flight + state. Everything here is a static function
# that operates only on its arguments (no ship state), so it's safe to call from
# anywhere and easy to reason about.

# --- AABB / fitting --------------------------------------------------------

static func gather_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(gather_mesh_instances(c))
	return out


# Union of every child MeshInstance3D's AABB, expressed in `root`'s local space.
static func combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in gather_mesh_instances(root):
		if mi.mesh == null:
			continue
		var box := (inv * mi.global_transform) * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


# Scale `model` so its longest axis spans `target_len`, then recenter it. Measured in
# `mesh_root` space (the model's parent) so it accounts for the model's yaw/pitch.
static func fit_model(mesh_root: Node3D, model: Node3D, target_len: float) -> AABB:
	var box := combined_aabb(mesh_root)
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0001:
		return AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var factor := target_len / longest
	model.scale = model.scale * factor
	var center := box.position + size * 0.5
	model.position -= center * factor
	return AABB(-size * factor * 0.5, size * factor)


# Rebuild each mesh dropping every triangle whose centroid sits AFT of `cut_z`
# (in `mesh_root` space, +Z = tail). Used to lop off a model's messy rear so the
# booster ring disc can cap the clean cut. Preserves normals/uv/colour + material.
static func clip_behind(root: Node3D, mesh_root: Node3D, cut_z: float) -> void:
	var inv := mesh_root.global_transform.affine_inverse()
	for mi in gather_mesh_instances(root):
		if mi.mesh == null:
			continue
		var to_root := inv * mi.global_transform   # mesh-local vert -> mesh_root space
		var src := mi.mesh
		var new_mesh := ArrayMesh.new()
		var kept_any := false
		for si in src.get_surface_count():
			var orig_mat := mi.get_active_material(si)
			var a := src.surface_get_arrays(si)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var cols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var has_n := norms.size() == verts.size()
			var has_uv := uvs.size() == verts.size()
			var has_c := cols.size() == verts.size()
			var count := idx.size() if not idx.is_empty() else verts.size()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var wrote := false
			var t := 0
			while t < count - 2:
				var i0 := idx[t] if not idx.is_empty() else t
				var i1 := idx[t + 1] if not idx.is_empty() else t + 1
				var i2 := idx[t + 2] if not idx.is_empty() else t + 2
				var c := (verts[i0] + verts[i1] + verts[i2]) / 3.0
				if (to_root * c).z <= cut_z:   # forward of the cut -> keep
					for ii in [i0, i1, i2]:
						if has_n: st.set_normal(norms[ii])
						if has_uv: st.set_uv(uvs[ii])
						if has_c: st.set_color(cols[ii])
						st.add_vertex(verts[ii])
					wrote = true
				t += 3
			if wrote:
				st.set_material(orig_mat)
				st.commit(new_mesh)
				kept_any = true
		if kept_any:
			mi.mesh = new_mesh


# Split each mesh by height (in `mesh_root` space): triangles whose centroid is
# above `gold_y` get a champagne-GOLD metal material, the rest stay SILVER (keeping
# the model texture). Lets a single-surface GLB have a gold top wing + silver body.
static func metal_split(root: Node3D, mesh_root: Node3D, gold_y: float) -> void:
	var inv := mesh_root.global_transform.affine_inverse()
	for mi in gather_mesh_instances(root):
		if mi.mesh == null:
			continue
		var to_root := inv * mi.global_transform
		var orig_mat := mi.get_active_material(0)
		var tex: Texture2D = (orig_mat as BaseMaterial3D).albedo_texture if orig_mat is BaseMaterial3D else null
		var src := mi.mesh
		var st_lo := SurfaceTool.new(); st_lo.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st_hi := SurfaceTool.new(); st_hi.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wrote_lo := false
		var wrote_hi := false
		for si in src.get_surface_count():
			var a := src.surface_get_arrays(si)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var has_n := norms.size() == verts.size()
			var has_uv := uvs.size() == verts.size()
			var count := idx.size() if not idx.is_empty() else verts.size()
			var t := 0
			while t < count - 2:
				var i0 := idx[t] if not idx.is_empty() else t
				var i1 := idx[t + 1] if not idx.is_empty() else t + 1
				var i2 := idx[t + 2] if not idx.is_empty() else t + 2
				var c := (verts[i0] + verts[i1] + verts[i2]) / 3.0
				var hi := (to_root * c).y > gold_y
				var st: SurfaceTool = st_hi if hi else st_lo
				for ii in [i0, i1, i2]:
					if has_n: st.set_normal(norms[ii])
					if has_uv: st.set_uv(uvs[ii])
					st.add_vertex(verts[ii])
				if hi: wrote_hi = true
				else: wrote_lo = true
				t += 3
		var silver := StandardMaterial3D.new()
		silver.albedo_texture = tex
		silver.metallic = 0.75
		silver.metallic_specular = 0.6
		silver.roughness = 0.3
		silver.rim_enabled = true
		silver.rim = 0.2
		silver.rim_tint = 0.5
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(0.737, 0.651, 0.478)   # champagne gold
		gold.metallic = 1.0
		gold.roughness = 0.12
		var new_mesh := ArrayMesh.new()
		if wrote_lo:
			st_lo.set_material(silver)
			st_lo.commit(new_mesh)
		if wrote_hi:
			st_hi.set_material(gold)
			st_hi.commit(new_mesh)
		if new_mesh.get_surface_count() > 0:
			mi.mesh = new_mesh


# --- Materials -------------------------------------------------------------

# Glassy finish: REAL see-through tinted glass — the body colour as a translucent,
# wet, edge-lit pane you can partly see through, not an opaque gloss. Applied after recolor.
static func set_glassy(model: Node3D) -> void:
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m = mi.get_active_material(si)
			if m is BaseMaterial3D:
				var mm := m as BaseMaterial3D
				# Translucent: keep the colour but let it read as glass you see THROUGH.
				mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var a: Color = mm.albedo_color
				a.a = 0.38                         # see-through pane
				mm.albedo_color = a
				mm.metallic = 0.0                  # glass isn't metal
				mm.metallic_specular = 1.0         # sharp surface reflections / glints
				mm.roughness = 0.03                # clear, polished glass
				mm.clearcoat_enabled = true
				mm.clearcoat = 1.0
				mm.clearcoat_roughness = 0.02
				# Bright fresnel edge so the glass silhouette reads; kill most of the
				# self-glow so light passes through instead of looking like a lit solid.
				mm.rim_enabled = true
				mm.rim = 0.6
				mm.rim_tint = 0.2
				if mm.emission_enabled:
					mm.emission_energy_multiplier *= 0.25


# Metallic finish: PURE SMOOTH polished metal — drop the brushed roughness to a clean,
# mirror-sharp sheen while keeping the role's colour + self-glow (a full mirror in this
# probe-less scene would read as glass, so we don't touch metallic/emission). Glass
# surfaces (e.g. canopy/illuminators) are left alone so they stay see-through.
static func set_polished(model: Node3D) -> void:
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m = mi.get_active_material(si)
			if m is BaseMaterial3D:
				var mm := m as BaseMaterial3D
				if mm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue   # leave glass/illuminators see-through
				mm.roughness = minf(mm.roughness, 0.1)          # polished, mirror-sharp
				mm.metallic_specular = maxf(mm.metallic_specular, 0.9)
				mm.clearcoat_enabled = false                    # clean metal, no wet coat


static func recolor(model: Node3D, tint: Color, glow: float, chrome := false, raw := false, pbr := false, roles := [], metal := false) -> void:
	for mi in gather_mesh_instances(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var orig := mi.get_active_material(si)
			var m: BaseMaterial3D
			if orig is BaseMaterial3D:
				m = orig.duplicate() as BaseMaterial3D
			else:
				m = StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			if metal:
				# Polished alloy that KEEPS the model's texture so its colours tint the
				# metal: white -> SILVER, orange -> GOLD, black trim stays dark. No
				# emission (so no bulb glow); the neutral hull light rig does the shading.
				var tex: Texture2D = (orig as BaseMaterial3D).albedo_texture if orig is BaseMaterial3D else null
				m.albedo_texture = tex
				m.albedo_color = Color(1, 1, 1)
				m.metallic = 0.75
				m.metallic_specular = 0.6
				m.roughness = 0.3
				m.rim_enabled = true
				m.rim = 0.2
				m.rim_tint = 0.5
				m.emission_enabled = false
			elif pbr:
				# Feminine pink-crystal hull (HaniStar). Each surface gets a ROLE:
				#   "hull" -> light pastel-pink porcelain/crystal with a soft rim aura
				#   "gold" -> shiny rose-gold metallic accent (keel, top, wings)
				#   "orb"  -> soft neon-pink lit accent
				# Roles can be set per surface index via the model's "surf_roles" list;
				# otherwise we auto-classify from the GLB's authored colour.
				var oc := Color(0.8, 0.8, 0.8)
				if orig is BaseMaterial3D:
					oc = (orig as BaseMaterial3D).albedo_color
				var role := ""
				if si < roles.size():
					role = String(roles[si])
				else:
					var sat: float = maxf(oc.r, maxf(oc.g, oc.b)) - minf(oc.r, minf(oc.g, oc.b))
					if oc.r > 0.6 and oc.g > 0.5 and oc.b < 0.45:
						role = "gold"
					elif sat > 0.3:
						role = "orb"
					else:
						role = "hull"
				m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				m.albedo_texture = null
				m.emission_texture = null
				if role == "gold":
					# Brushed silver alloy. Metallic kept MODERATE (not 1.0): a full mirror in
					# this probe-less scene just reflects the empty starfield and reads as glass.
					# 0.6 + a bright self-glow shows solid silver with a metal sheen.
					m.albedo_color = Color(0.82, 0.84, 0.88)       # cool silver
					m.metallic = 0.6
					m.metallic_specular = 0.85
					m.roughness = 0.22                             # soft brushed sheen, not a mirror
					m.rim_enabled = true
					m.rim = 0.25
					m.emission_enabled = true
					m.emission = Color(0.82, 0.84, 0.88)           # silver glow
					m.emission_energy_multiplier = 0.5
				elif role == "glass":
					# Tinted canopy glass for the top front view — clear, glossy, reflective.
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.albedo_color = Color(0.62, 0.80, 1.0, 0.30)  # light blue tinted glass
					m.metallic = 0.0
					m.metallic_specular = 0.9
					m.roughness = 0.04
					m.rim_enabled = true
					m.rim = 0.5
					m.rim_tint = 0.2
					m.emission_enabled = false
				elif role == "orb":
					# Soft neon-pink lit accent.
					m.albedo_color = Color(1.0, 0.714, 0.757)      # #ffb6c1
					m.metallic = 0.0
					m.roughness = 0.4
					m.rim_enabled = false
					m.emission_enabled = true
					m.emission = Color(1.0, 0.714, 0.757)          # bright magenta-pink
					m.emission_energy_multiplier = 0.7             # subtle lit accent, no flare
				elif role == "silver":
					# Steel-BLUE metal. Metallic moderate (0.55) so the blue diffuse shows
					# instead of mirroring the empty starfield (which reads as glass).
					m.albedo_color = Color(0.42, 0.60, 0.95)
					m.metallic = 0.55
					m.metallic_specular = 0.8
					m.roughness = 0.26
					m.rim_enabled = true
					m.rim = 0.3
					m.rim_tint = 0.3                               # bluish edge
					m.emission_enabled = true
					m.emission = Color(0.42, 0.60, 0.95)
					m.emission_energy_multiplier = 0.5
				elif role == "red":
					# Pure BLOOD-RED metal with a self-lit floor so it reads in the dark.
					m.albedo_color = Color(0.62, 0.03, 0.03)
					m.metallic = 0.7
					m.metallic_specular = 0.6
					m.roughness = 0.28
					m.rim_enabled = true
					m.rim = 0.35
					m.rim_tint = 0.2                               # red-tinted edge
					m.emission_enabled = true
					m.emission = Color(0.55, 0.03, 0.03)
					m.emission_energy_multiplier = 0.45
				elif role == "goldtrim":
					# Shiny champagne-gold accent with a small floor for visibility.
					m.albedo_color = Color(0.737, 0.651, 0.478)
					m.metallic = 1.0
					m.roughness = 0.14
					m.rim_enabled = false
					m.emission_enabled = true
					m.emission = Color(0.737, 0.651, 0.478)
					m.emission_energy_multiplier = 0.3
				elif role == "dark":
					# Dark gunmetal (engine block / recesses).
					m.albedo_color = Color(0.08, 0.08, 0.10)
					m.metallic = 0.6
					m.roughness = 0.5
					m.rim_enabled = false
					m.emission_enabled = false
				# --- Accent palettes (HaniNebula body). METALLIC must stay MODERATE: at 1.0 the
				# surface has no diffuse and only reflects the empty starfield -> reads as clear
				# glass. ~0.55 keeps a metal sheen while the colour shows; emission = the colour
				# itself so it self-lights and never goes glassy/black in the probe-less scene.
				elif role == "rosegold":
					m.albedo_color = Color(0.86, 0.58, 0.52); m.metallic = 0.55; m.metallic_specular = 0.8; m.roughness = 0.30
					m.emission_enabled = true; m.emission = Color(0.86, 0.58, 0.52); m.emission_energy_multiplier = 0.45
				elif role == "blush":
					m.albedo_color = Color(0.96, 0.74, 0.76); m.metallic = 0.4; m.roughness = 0.34
					m.emission_enabled = true; m.emission = Color(0.96, 0.74, 0.76); m.emission_energy_multiplier = 0.4
				elif role == "navy":
					m.albedo_color = Color(0.16, 0.24, 0.60); m.metallic = 0.55; m.metallic_specular = 0.8; m.roughness = 0.28
					m.emission_enabled = true; m.emission = Color(0.16, 0.24, 0.60); m.emission_energy_multiplier = 0.5
				elif role == "teal":
					m.albedo_color = Color(0.09, 0.64, 0.64); m.metallic = 0.55; m.metallic_specular = 0.8; m.roughness = 0.26
					m.emission_enabled = true; m.emission = Color(0.09, 0.64, 0.64); m.emission_energy_multiplier = 0.5
				elif role == "charcoal":
					m.albedo_color = Color(0.11, 0.11, 0.13); m.metallic = 0.4; m.roughness = 0.55   # matte gunmetal
					m.rim_enabled = true; m.rim = 0.2; m.emission_enabled = false
				elif role == "emerald":
					m.albedo_color = Color(0.06, 0.48, 0.24); m.metallic = 0.55; m.metallic_specular = 0.8; m.roughness = 0.26
					m.emission_enabled = true; m.emission = Color(0.06, 0.48, 0.24); m.emission_energy_multiplier = 0.5
				elif role == "burgundy":
					m.albedo_color = Color(0.48, 0.08, 0.17); m.metallic = 0.55; m.metallic_specular = 0.8; m.roughness = 0.27
					m.emission_enabled = true; m.emission = Color(0.48, 0.08, 0.17); m.emission_energy_multiplier = 0.5
				elif role == "champagne":
					# Polished champagne-gold metal — high metallic, low roughness for a real gold sheen.
					m.albedo_color = Color(0.83, 0.69, 0.42); m.metallic = 0.85; m.metallic_specular = 0.9; m.roughness = 0.16
					m.emission_enabled = true; m.emission = Color(0.83, 0.69, 0.42); m.emission_energy_multiplier = 0.4
				elif role == "ash":
					# Bright light-grey polished alloy. Emission floor keeps it luminous, not flat.
					m.albedo_color = Color(0.74, 0.76, 0.80); m.metallic = 0.55; m.metallic_specular = 0.85; m.roughness = 0.22
					m.emission_enabled = true; m.emission = Color(0.74, 0.76, 0.80); m.emission_energy_multiplier = 0.5
				elif role == "graphite":
					# Dark grey gunmetal with a soft sheen — reads as solid mid-dark metal.
					m.albedo_color = Color(0.30, 0.31, 0.34); m.metallic = 0.6; m.metallic_specular = 0.8; m.roughness = 0.30
					m.emission_enabled = true; m.emission = Color(0.30, 0.31, 0.34); m.emission_energy_multiplier = 0.4
				elif role == "onyx":
					# Brightened glossy black — deep, but a sheen + emission floor so it never goes dead-black.
					m.albedo_color = Color(0.10, 0.10, 0.12); m.metallic = 0.7; m.metallic_specular = 0.9; m.roughness = 0.16
					m.emission_enabled = true; m.emission = Color(0.13, 0.13, 0.16); m.emission_energy_multiplier = 0.35
				else:
					# Light pink crystal body with a feminine rim aura.
					m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON   # clean gradients on low-poly faces
					m.albedo_color = Color(1.0, 0.60, 0.74)        # deeper pink (was washing out white)
					m.metallic = 0.15                              # porcelain sheen, not dark metal
					m.roughness = 0.38                             # softer highlights so pink reads, not white
					m.rim_enabled = true
					m.rim = 0.35                                   # soft pink outer-shell outline
					m.rim_tint = 1.0                               # light pink-white edge
					m.emission_enabled = false
			elif raw:
				# Keep the model's AUTHORED colours/textures exactly (its beautiful
				# design), and render them UNSHADED so they show full-colour in our
				# light-less scene — no flat tint, no washout.
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.vertex_color_use_as_albedo = true   # honour per-vertex colours if any
				m.emission_enabled = false
			elif chrome:
				# Pure sci-fi white brushed metal with a cyan edge glow — drop the
				# model's own (purple) texture and make a clean polished hull.
				m.albedo_texture = null
				m.albedo_color = Color(0.86, 0.90, 0.96)
				m.metallic = 0.85
				m.metallic_specular = 0.85
				m.roughness = 0.3
				m.rim_enabled = true
				m.rim = 0.7
				m.rim_tint = 0.0                    # bright white fresnel edge
				m.emission_enabled = true
				m.emission_texture = null
				m.emission = Color(0.15, 0.7, 1.0)  # cyan self-glow accent
				m.emission_energy_multiplier = 0.25
			else:
				# Painted hull: low metalness so the model's own colour texture
				# shows under the key+fill lights; dim flat emission floor only.
				m.albedo_color = tint
				m.metallic = 0.1
				m.metallic_specular = 0.5
				m.roughness = 0.5
				m.rim_enabled = true
				m.rim = 0.25
				m.rim_tint = 0.5
				m.emission_enabled = true
				m.emission_texture = null
				m.emission = tint
				m.emission_energy_multiplier = glow
			mi.set_surface_override_material(si, m)


# A small key + fill + core light rig parented to the hull (travels with the ship).
# The scene has no Light3D otherwise — these are what let the lit pink-crystal
# material (toon diffuse, rim aura, sharp low-poly highlights) actually show. Range
# is kept to a few hull-lengths so they light the ship, not the wider scene.
# `accent` tints the fill + core lights (HaniStar = pink). `energy` scales the whole
# rig — metallic hulls (Lyra) need it low or they blow out into a bloom blob.
static func add_hull_lights(parent: Node3D, box: AABB, accent := Color(1.0, 0.70, 0.84), energy := 1.0) -> void:
	var s := box.size
	var reach: float = maxf(s.length(), 0.3)
	# Key: warm near-white, up/front/right — carves the faceted highlights.
	var key := OmniLight3D.new()
	key.position = Vector3(reach * 0.9, reach * 1.1, reach * 0.9)
	key.light_color = Color(1.0, 0.90, 0.93)
	key.light_energy = 1.3 * energy
	key.omni_range = reach * 3.0
	key.shadow_enabled = false
	parent.add_child(key)
	# Fill: accent-tinted, down/back/left — lifts the shadow side.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-reach * 0.9, -reach * 0.7, -reach * 0.9)
	fill.light_color = accent
	fill.light_energy = 0.8 * energy
	fill.omni_range = reach * 3.0
	fill.shadow_enabled = false
	parent.add_child(fill)
	# Core: a soft accent glow at the hull centre to fill recessed panels.
	var core := OmniLight3D.new()
	core.position = Vector3(0.0, reach * 0.05, 0.0)
	core.light_color = accent
	core.light_energy = 1.1 * energy
	core.omni_range = reach * 1.6
	core.shadow_enabled = false
	parent.add_child(core)


# A filled heart silhouette in the XY plane (point down), triangle-fanned from the
# centre. Used as a gold backing plate behind a booster cluster to cover the gaps
# between bells. `half` ≈ half the width.
static func make_heart_mesh(half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var pts: Array[Vector2] = []
	for i in n:
		var t := float(i) / float(n) * TAU
		var hx := 16.0 * pow(sin(t), 3.0)
		var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(hx, hy) / 17.0 * half)
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		st.set_normal(Vector3(0, 0, 1)); st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3(0, 0, 1)); st.add_vertex(Vector3(b.x, b.y, 0.0))
		st.set_normal(Vector3(0, 0, 1)); st.add_vertex(Vector3(a.x, a.y, 0.0))
	return st.commit()


# --- Procedural FX textures ------------------------------------------------

# Vertical alpha ramp for the booster plume: opaque at the nozzle, fading to clear at
# the tail. Which mesh end is which depends on UV winding, so `flip` swaps it.
static func make_plume_gradient(flip: bool) -> Texture2D:
	var h := 64
	var img := Image.create(2, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)  # 0 at image top .. 1 at bottom
		if flip:
			t = 1.0 - t
		var a := pow(1.0 - t, 1.4)        # bright at t=0, easing to 0
		for x in 2:
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


# Soft radial glow circle, generated once (no binary asset to ship).
static func make_glow_texture() -> Texture2D:
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
