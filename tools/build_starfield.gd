extends SceneTree
# OFFLINE BAKER for the realistic star environment. Run once (needs the HYG CSV present):
#     godot --headless --script tools/build_starfield.gd
# Produces two ArrayMesh resources of PRIMITIVE_POINTS with per-star COLOUR (from the
# real B-V colour index) and per-star SIZE packed into UV.x (from apparent magnitude):
#     assets/starfield_low.res   — real HYG only (~120k): potato / accurate sky
#     assets/starfield_high.res  — HYG + procedural Milky-Way fill (~1M): cinematic
# starfield.gd loads one of these + a tiny additive point shader. Baking is one-time,
# so the game pays ZERO startup cost (just loads the finished mesh).

const HYG := "res://tools/data/hyg_v41.csv"
const SHELL := 6000.0
const FILL_TARGET := 500_000       # high-mesh total (HYG + procedural Milky-Way band fill)
const TYCHO_MAG_CUT := 10.0        # real-Tycho mesh keeps only stars brighter than this (~355k) — GPU-safe

# Column indices in HYG v41.
const C_ID := 0
const C_RA := 7      # right ascension, HOURS (0..24)
const C_DEC := 8     # declination, degrees
const C_DIST := 9
const C_MAG := 13    # apparent magnitude (lower = brighter)
const C_CI := 16     # B-V colour index (negative = hot/blue, positive = cool/red)

# Galactic north pole in equatorial coords (J2000) — used to thicken the Milky Way band.
const GAL_POLE_RA := 192.859    # deg
const GAL_POLE_DEC := 27.128    # deg


# Real B-V colour index -> RGB (classic Mitchell-Charity style approximation).
func bv2rgb(bv: float) -> Color:
	bv = clampf(bv, -0.4, 2.0)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var t := 0.0
	if bv < 0.0:
		t = (bv + 0.40) / 0.40; r = 0.61 + 0.11 * t + 0.1 * t * t
	elif bv < 0.4:
		t = bv / 0.40; r = 0.83 + 0.17 * t
	else:
		r = 1.0
	if bv < 0.0:
		t = (bv + 0.40) / 0.40; g = 0.70 + 0.07 * t + 0.1 * t * t
	elif bv < 0.4:
		t = bv / 0.40; g = 0.87 + 0.11 * t
	elif bv < 1.6:
		t = (bv - 0.40) / 1.20; g = 0.98 - 0.16 * t
	else:
		t = (bv - 1.60) / 0.40; g = 0.82 - 0.5 * t * t
	if bv < 0.4:
		b = 1.0
	elif bv < 1.5:
		t = (bv - 0.40) / 1.10; b = 1.00 - 0.47 * t + 0.1 * t * t
	else:
		t = (bv - 1.50) / 0.44; b = 0.63 - 0.6 * t * t
	return Color(clampf(r, 0, 1), clampf(g, 0, 1), clampf(b, 0, 1))


# RA(hours)/Dec(deg) -> a unit direction on the celestial sphere (Y up).
func dir_from(ra_h: float, dec_d: float) -> Vector3:
	var ra := deg_to_rad(ra_h * 15.0)
	var dec := deg_to_rad(dec_d)
	return Vector3(cos(dec) * cos(ra), sin(dec), cos(dec) * sin(ra))


# Apparent magnitude -> (size_px, intensity). Brighter (lower mag) = bigger + stronger.
# STEEP curve: faint stars are nearly invisible so the sky reads as black with a few
# crisp bright stars (not a uniform field of dots = "TV static").
func mag_look(mag: float) -> Array:
	var b := clampf((7.0 - mag) / 9.0, 0.0, 1.0)   # ~ -2 (Sirius) .. 7 (faint) -> 1..0
	var size: float = 1.0 + b * b * 6.5            # most stars ~1px; the few bright ones fat
	var intensity: float = clampf(pow(b, 1.7), 0.03, 1.0)
	return [size, intensity]


func _init() -> void:
	var pole := dir_from(GAL_POLE_RA / 15.0, GAL_POLE_DEC)   # galactic pole as a direction

	var hyg_pos := PackedVector3Array()
	var hyg_col := PackedColorArray()
	var hyg_uv := PackedVector2Array()

	var f := FileAccess.open(HYG, FileAccess.READ)
	if f == null:
		printerr("Cannot open ", HYG, " — download it first.")
		quit(1)
		return
	f.get_csv_line()   # skip header
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= C_CI:
			continue
		if row[C_ID] == "0":
			continue   # Sol — the player's origin, not a backdrop star
		var mag := float(row[C_MAG]) if row[C_MAG] != "" else 99.0
		if mag > 12.0:
			continue
		var ra_s := row[C_RA]
		var dec_s := row[C_DEC]
		if ra_s == "" or dec_s == "":
			continue
		var dir := dir_from(float(ra_s), float(dec_s))
		var ci := float(row[C_CI]) if row[C_CI] != "" else 0.6   # default sun-ish
		var look := mag_look(mag)
		var inten: float = look[1]
		var col := bv2rgb(ci)
		hyg_pos.append(dir * SHELL)
		hyg_col.append(Color(col.r * inten, col.g * inten, col.b * inten, 1.0))
		hyg_uv.append(Vector2(look[0], 0.0))
		n += 1
	f.close()
	print("HYG real stars baked: ", n)

	# --- procedural fill: a SUBTLE Milky Way band only (not an all-over field, which
	# reads as TV static). Sampled directly in galactic coords: longitude uniform, latitude
	# a narrow gaussian, so the points hug the galactic plane as a soft glowing band and the
	# rest of the sky stays the real-HYG sparse black. Very dim + tiny so it's a glow, not dots.
	var fill := maxi(FILL_TARGET - n, 0)
	var fp := PackedVector3Array()
	var fc := PackedColorArray()
	var fu := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260618
	# Orthonormal galactic basis: pole = plane normal; x_g,y_g span the plane.
	var x_g := Vector3(0, 1, 0).cross(pole).normalized()
	var y_g := pole.cross(x_g).normalized()
	var made := 0
	while made < fill:
		var l := rng.randf() * TAU                       # galactic longitude (around the band)
		var bgal := rng.randfn(0.0, 0.12)                # galactic latitude: tight ~7° band
		var cb := cos(bgal)
		var d := (x_g * cos(l) + y_g * sin(l)) * cb + pole * sin(bgal)
		# faint magnitudes (8..12): tiny dim points building a diffuse band
		var mag := rng.randf_range(8.0, 12.0)
		var look := mag_look(mag)
		# extra-dim so the band glows softly instead of sparkling like static
		var inten: float = rng.randf_range(0.05, 0.16)
		var ci := rng.randfn(0.7, 0.40)
		var col := bv2rgb(ci)
		fp.append(d * SHELL)
		fc.append(Color(col.r * inten, col.g * inten, col.b * inten, 1.0))
		fu.append(Vector2(1.0, 0.0))                     # 1px specks
		made += 1
	print("procedural Milky-Way fill stars: ", made)

	_save_points("res://assets/starfield_low.res", hyg_pos, hyg_col, hyg_uv)

	var all_pos := hyg_pos.duplicate()
	all_pos.append_array(fp)
	var all_col := hyg_col.duplicate()
	all_col.append_array(fc)
	var all_uv := hyg_uv.duplicate()
	all_uv.append_array(fu)
	_save_points("res://assets/starfield_high.res", all_pos, all_col, all_uv)

	_bake_tycho()

	print("DONE. low=", hyg_pos.size(), "  high=", all_pos.size())
	quit()


# Bake the REAL Tycho-2 catalogue (~2.54M stars) from the slim binary written by
# tools/parse_tycho.py (float32 [ra_deg, dec_deg, Vmag, B-V] per star). Same colour
# (B-V) and size (magnitude) logic as the HYG path, so it matches the rest.
func _bake_tycho() -> void:
	var path := "res://tools/data/tycho_slim.bin"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("(no tycho_slim.bin — skipping Tycho bake; run tools/parse_tycho.py)")
		return
	var raw := f.get_buffer(f.get_length())
	f.close()
	var d := raw.to_float32_array()
	var count := d.size() / 4
	# Magnitude cut: keep only the brightest stars (drop the faint majority) so the count
	# stays GPU-safe. 2.5M crashed; ~355k (mag<=10) is comfortably under the 1M that ran fine.
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	for i in count:
		var o := i * 4
		var vmag: float = d[o + 2]
		if vmag > TYCHO_MAG_CUT:
			continue
		var dir := dir_from(d[o] / 15.0, d[o + 1])   # slim RA is in DEGREES; dir_from wants hours
		var look := mag_look(vmag)
		var inten: float = look[1]
		var c := bv2rgb(d[o + 3])
		pos.append(dir * SHELL)
		col.append(Color(c.r * inten, c.g * inten, c.b * inten, 1.0))
		uv.append(Vector2(look[0], 0.0))
	_save_points("res://assets/starfield_tycho.res", pos, col, uv)
	print("Tycho real stars baked: ", pos.size(), " (of ", count, ", mag<=", TYCHO_MAG_CUT, ")")


func _save_points(path: String, pos: PackedVector3Array, col: PackedColorArray, uv: PackedVector2Array) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv   # UV.x carries per-star point size
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	# Big custom AABB so the points never get frustum-culled as a clump.
	mesh.custom_aabb = AABB(Vector3(-SHELL, -SHELL, -SHELL) * 1.2, Vector3(SHELL, SHELL, SHELL) * 2.4)
	var err := ResourceSaver.save(mesh, path)
	print("  saved ", path, " (", pos.size(), " pts) err=", err)
