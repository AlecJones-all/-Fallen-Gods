extends SceneTree

# 蒸汽朋克弩：自动找弩身轴与握把，烘成可直接挂 XbowPivot 的 tscn
# 阶段 1: godot --headless --path . --script res://tools/fit_xbow_steampunk.gd
# 阶段 2: godot --headless --path . --import
# 阶段 3: godot --headless --path . --script res://tools/fit_xbow_steampunk.gd -- tex

const SRC := "res://assets/weapons/xbow_steampunk/source/steampunk_xbow.fbx"
const DST := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"
const TEX_DIR := "res://assets/weapons/xbow_steampunk/tex"
const MESH_DIR := "res://assets/weapons/xbow_steampunk/mesh"
const TARGET_LEN := 0.62
const TEX_SIZE := 512

var _tex_mode := false


func _initialize() -> void:
	_tex_mode = OS.get_cmdline_user_args().has("tex")
	if _tex_mode:
		_assign_textures()
	else:
		_bake()
	quit(0)


# ---------------- 阶段 3：贴图接上（导入之后） ----------------
func _assign_textures() -> void:
	var packed: PackedScene = load(DST)
	var root: Node3D = packed.instantiate() as Node3D
	get_root().add_child(root)
	var n := 0
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mi.material_override = mat
		var path := "%s/part_%d_albedo.png" % [TEX_DIR, n]
		if ResourceLoader.exists(path):
			mat.albedo_texture = load(path)
		mat.roughness = 0.82
		mat.metallic = 0.15
		mat.metallic_specular = 0.45
		n += 1
	var out := PackedScene.new()
	print("re-pack=", out.pack(root), " save=", ResourceSaver.save(out, DST))
	print("接上贴图 = ", n)
	quit(0)


# ---------------- 阶段 1：拟合 + 烘焙 ----------------
func _bake() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MESH_DIR))

	var ps: PackedScene = load(SRC)
	var model: Node3D = ps.instantiate() as Node3D
	get_root().add_child(model)

	var pts: PackedVector3Array = PackedVector3Array()
	var meshes: Array[MeshInstance3D] = []
	for m: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes.append(mi)
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)

	var n := pts.size()
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(n)

	var cov := Basis()
	for p in pts:
		var d := p - c
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	cov.x /= float(n)
	cov.y /= float(n)
	cov.z /= float(n)
	var axis := (cov * Vector3(1, 1, 1)).normalized()
	for i in 60:
		axis = (cov * axis).normalized()

	var tmin := 1e9
	var tmax := -1e9
	for p in pts:
		var t := (p - c).dot(axis)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
	var span := tmax - tmin

	# 半径剖面
	var bins := 160
	var rad := PackedFloat32Array()
	rad.resize(bins)
	for p in pts:
		var d := p - c
		var t := d.dot(axis)
		var bi := int(clampf((t - tmin) / span * (bins - 1), 0, bins - 1))
		rad[bi] = maxf(rad[bi], (d - axis * t).length())
	var step := span / float(bins)

	# 握把：连续细段（半径 0.03–0.075）
	var best_start := -1
	var best_len := 0
	var run := 0
	for i in bins:
		if rad[i] > 0.028 and rad[i] < 0.085:
			run += 1
			if run > best_len:
				best_len = run
				best_start = i - run + 1
		else:
			run = 0

	# 调试：打印半径剖面（每 4 格）
	var dbg := ""
	for i in range(0, bins, 4):
		dbg += "%d:%.3f " % [i, rad[i]]
	print("剖面 ", dbg)

	# 握把位置：从弩尾（tmin）往弩头方向 22% 处（缠绳段中心）
	var grip_t := tmin + span * 0.22
	var grip := c + axis * grip_t

	# 头在远端：比较两端 15% 的最大半径
	var lo_max := 0.0
	var hi_max := 0.0
	for p in pts:
		var d := p - c
		var t := d.dot(axis)
		var r := (d - axis * t).length()
		if t < tmin + span * 0.15:
			lo_max = maxf(lo_max, r)
		elif t > tmax - span * 0.15:
			hi_max = maxf(hi_max, r)
	var head_sign := 1.0 if hi_max > lo_max else -1.0
	var barrel := axis * head_sign

	var up := Vector3.UP - barrel * Vector3.UP.dot(barrel)
	if up.length() < 0.1:
		up = Vector3.RIGHT - barrel * Vector3.RIGHT.dot(barrel)
	up = up.normalized()
	var right := up.cross(barrel).normalized()
	var fit := Basis(right, up, barrel).inverse()
	var s := TARGET_LEN / span

	print("span=%.3f  轴=%s  握把=%s  头在 %s  缩放=%.4f" % [span, axis, grip, "hi" if head_sign > 0 else "lo", s])
	print("握把段 %d 格 半径 %.3f..%.3f" % [best_len, rad[best_start] if best_start >= 0 else -1.0, rad[best_start + best_len - 1] if best_start >= 0 else -1.0])

	for mi in meshes:
		var center := Vector3.ZERO
		var cnt2 := 0
		for s2 in mi.mesh.get_surface_count():
			var arr2: Array = mi.mesh.surface_get_arrays(s2)
			for v in (arr2[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				center += mi.global_transform * v
				cnt2 += 1
		center /= maxf(float(cnt2), 1.0)
		print("  子件 %s 投影 t=%.3f (0=尾 %.2f=头)" % [mi.name.substr(0, 8), (center - c).dot(axis), tmax - tmin])

	# ---- 组节点 ----
	var root := Node3D.new()
	root.name = "XbowSteampunk"
	root.scale = Vector3.ONE * s
	get_root().add_child(root)

	var holder := Node3D.new()
	holder.name = "Model"
	holder.basis = fit
	holder.position = -(fit * grip)
	root.add_child(holder)

	var i := 0
	for mi in meshes:
		# 关键：重建一份 ArrayMesh 再存，不能直接存导入资源（那会变成对 FBX 的引用，删源即失效）
		var mesh_path := "%s/part_%d.res" % [MESH_DIR, i]
		var baked := ArrayMesh.new()
		for s_idx in mi.mesh.get_surface_count():
			baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(s_idx))
		ResourceSaver.save(baked, mesh_path)
		var nm := MeshInstance3D.new()
		nm.name = "Part_%d" % i
		nm.mesh = load(mesh_path)
		# 用相对模型根的整体变换（FBX 里有 3 层 -90 旋转，只取局部会丢两层）
		nm.transform = mi.global_transform
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.82
		mat.metallic = 0.15
		nm.material_override = mat
		holder.add_child(nm)
		nm.owner = root
		i += 1
	holder.owner = root

	# 贴图（512），阶段 3 再挂
	var ti := 0
	for mi in meshes:
		var src_tex: Texture2D = null
		var om := mi.material_override as StandardMaterial3D
		if om != null:
			src_tex = om.albedo_texture
		if src_tex == null:
			var m0 := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if m0 != null:
				src_tex = m0.albedo_texture
		if src_tex != null:
			var img: Image = src_tex.get_image()
			if img != null:
				img.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)
				img.save_png(ProjectSettings.globalize_path("%s/part_%d_albedo.png" % [TEX_DIR, ti]))
		ti += 1

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, DST))
	print("面数 = ", _tris(root), "  长度 = %.3f m" % (span * s))
	quit(0)


func _tris(n: Node) -> int:
	var t := 0
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var iv: Variant = arr[Mesh.ARRAY_INDEX]
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			t += ((iv as PackedInt32Array).size() / 3) if iv != null else (vv.size() / 3)
	return t
