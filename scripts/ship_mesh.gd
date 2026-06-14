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


# --- Materials -------------------------------------------------------------

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
				# Polished metal that KEEPS the model's own texture so its colours tint
				# the alloy: white reads as SILVER, orange/warm as GOLD/copper. Needs the
				# hull light rig (added for metal ships). The emission floor uses the same
				# texture so it never goes fully black in the lightless scene.
				var tex: Texture2D = (orig as BaseMaterial3D).albedo_texture if orig is BaseMaterial3D else null
				m.albedo_texture = tex
				m.albedo_color = Color(1, 1, 1)
				m.metallic = 0.85
				m.metallic_specular = 0.9
				m.roughness = 0.22                  # smooth, mirror-like sheen
				m.rim_enabled = true
				m.rim = 0.3
				m.rim_tint = 0.4
				m.emission_enabled = true
				m.emission_texture = tex
				m.emission = Color(1, 1, 1)
				m.emission_energy_multiplier = 0.35  # self-lit floor, keeps the colours readable
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
					# Polished silver alloy. Metallic 1.0 / roughness 0.12 for a smooth
					# mirroring sheen; a small emission floor keeps it readable (no
					# reflection probe in scene, so pure metal would render near-black).
					m.albedo_color = Color(0.82, 0.84, 0.88)       # cool silver
					m.metallic = 1.0                               # true polished alloy
					m.roughness = 0.12                             # smooth mirroring sheen
					m.rim_enabled = false
					m.emission_enabled = true
					m.emission = Color(0.82, 0.84, 0.88)           # silver glow
					m.emission_energy_multiplier = 0.4             # slight glow over the plates
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
static func add_hull_lights(parent: Node3D, box: AABB) -> void:
	var s := box.size
	var reach: float = maxf(s.length(), 0.3)
	# Key: warm near-white, up/front/right — carves the faceted highlights.
	var key := OmniLight3D.new()
	key.position = Vector3(reach * 0.9, reach * 1.1, reach * 0.9)
	key.light_color = Color(1.0, 0.90, 0.93)
	key.light_energy = 1.3
	key.omni_range = reach * 3.0
	key.shadow_enabled = false
	parent.add_child(key)
	# Fill: soft pink, down/back/left — lifts the shadow side so it stays bright.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-reach * 0.9, -reach * 0.7, -reach * 0.9)
	fill.light_color = Color(1.0, 0.78, 0.88)
	fill.light_energy = 0.8
	fill.omni_range = reach * 3.0
	fill.shadow_enabled = false
	parent.add_child(fill)
	# Core: a soft pink glow sat right at the hull centre to fill the dark recessed
	# panels the key/fill miss (the empty pink pockets between plates).
	var core := OmniLight3D.new()
	core.position = Vector3(0.0, reach * 0.05, 0.0)
	core.light_color = Color(1.0, 0.62, 0.80)
	core.light_energy = 1.1
	core.omni_range = reach * 1.6
	core.shadow_enabled = false
	parent.add_child(core)


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
