extends SceneTree

# 诸葛连弩（200 万面 OBJ）→ 顶点聚类降面 → 烘成可装配 tscn
# 用法: godot --headless --path . --script res://tools/fit_xbow_zhuge.gd [目标面数]

const SRC := "res://assets/weapons/xbow_zhuge/source/zhuge.obj"
const DST := "res://assets/weapons/xbow_zhuge/xbow_zhuge.tscn"
const TEX_DIR := "res://assets/weapons/xbow_zhuge/tex"
const MESH_PATH := "res://assets/weapons/xbow_zhuge/zhuge_lp.res"
const TARGET_LEN := 0.52
const TEX_SIZE := 512
const TARGET_TRIS := 90000


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))
	var target := TARGET_TRIS
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		target = int(a[0])

	var mesh: Mesh = load(SRC)
	if mesh == null:
		push_error("OBJ 加载失败")
		quit(1)
		return
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	print("原始 顶点=", verts.size(), " 索引=", idx.size(), " 面=", idx.size() / 3, " uv=", uvs.size())

	var box := mesh.get_aabb()
	print("AABB size=", box.size, " pos=", box.position)

	# ---- 固定步长聚类降面 ----
	var g := 0.008
	var a2 := OS.get_cmdline_user_args()
	if a2.size() > 0 and not a2.has("tex"):
		g = float(a2[0])
	var res: Dictionary = _cluster(verts, idx, uvs, g)
	print("  聚类步长 %.3f → 面 %d" % [g, (res["idx"] as PackedInt32Array).size() / 3])

	var nv: PackedVector3Array = res["verts"]
	var ni: PackedInt32Array = res["idx"]
	var nuv: PackedVector2Array = res["uvs"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nv.size():
		st.set_uv(nuv[i] if i < nuv.size() else Vector2.ZERO)
		st.add_vertex(nv[i])
	for i in ni.size():
		st.add_index(ni[i])
	st.generate_normals()
	var lp: ArrayMesh = st.commit()
	var save_err := ResourceSaver.save(lp, MESH_PATH)
	print("低模 顶点=", lp.get_surface_count(), " 保存=", save_err)

	# ---- 拟合：长轴 = X，头在宽的那端 ----
	# 10 段切片，比较各段 Z 跨度
	var slices := 10
	var zspan := PackedFloat32Array()
	zspan.resize(slices)
	for p in nv:
		var bi := int(clampf((p.x - box.position.x) / box.size.x * (slices - 1), 0, slices - 1))
		zspan[bi] = maxf(zspan[bi], absf(p.z - (box.position.z + box.size.z * 0.5)))
	var head_at_max := zspan[slices - 1] > zspan[0]
	print("  Z 跨度 头侧=%.3f 尾侧=%.3f → 头在 %s" % [zspan[slices - 1], zspan[0], "max" if head_at_max else "min"])

	# 基：把 +X（或 -X）转到 +Z，Y 保持向上
	var sx := 1.0 if head_at_max else -1.0
	var barrel := Vector3(sx, 0, 0)
	var up := Vector3.UP
	var right := up.cross(barrel).normalized()
	var fit := Basis(right, up, barrel).inverse()

	var grip_frac := 0.34  # 从弩尾往前的比例
	var x_tail: float = box.position.x if sx > 0 else box.position.x + box.size.x
	var grip := Vector3(x_tail + (box.size.x * grip_frac) * sx, box.position.y + box.size.y * 0.5, box.position.z + box.size.z * 0.5)
	var s := TARGET_LEN / box.size.x

	var root := Node3D.new()
	root.name = "XbowZhuge"
	root.scale = Vector3.ONE * s
	get_root().add_child(root)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.basis = fit
	holder.position = -(fit * grip)
	root.add_child(holder)

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = load(MESH_PATH)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	mat.metallic = 0.2
	if ResourceLoader.exists(TEX_DIR + "/body_albedo.png"):
		mat.albedo_texture = load(TEX_DIR + "/body_albedo.png")
	mi.material_override = mat
	holder.add_child(mi)
	mi.owner = root
	holder.owner = root

	var packed := PackedScene.new()
	print("pack=", packed.pack(root), " save=", ResourceSaver.save(packed, DST), " 缩放=%.3f" % s)

	# 贴图 512
	var src_tex := load("res://assets/weapons/xbow_zhuge/source/body_albedo.JPEG")
	if src_tex == null:
		print("  （贴图不在工程里，跳过）")
	else:
		var img: Image = (src_tex as Texture2D).get_image()
		img.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(TEX_DIR + "/body_albedo.png"))
		print("  贴图已写 512")
	quit(0)


func _cluster(verts: PackedVector3Array, idx: PackedInt32Array, uvs: PackedVector2Array, g: float) -> Dictionary:
	var map := {}
	var out_v: PackedVector3Array = PackedVector3Array()
	var acc: Array[Vector3] = []
	var acc_uv: Array[Vector2] = []
	var acc_n: Array[int] = []
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var key := Vector3i(int(floor(v.x / g)), int(floor(v.y / g)), int(floor(v.z / g)))
		var id: int = map.get(key, -1)
		if id < 0:
			id = out_v.size()
			map[key] = id
			out_v.append(v)
			acc.append(v)
			acc_uv.append(uvs[i] if i < uvs.size() else Vector2.ZERO)
			acc_n.append(1)
		else:
			acc[id] += v
			if i < uvs.size():
				acc_uv[id] += uvs[i]
			acc_n[id] += 1
		remap[i] = id
	for i in out_v.size():
		out_v[i] = acc[i] / float(acc_n[i])

	var out_i: PackedInt32Array = PackedInt32Array()
	var seen := {}
	var out_uv: PackedVector2Array = PackedVector2Array()
	out_uv.resize(out_v.size())
	for i in out_v.size():
		out_uv[i] = acc_uv[i] / float(acc_n[i])
	var tri_n := idx.size() / 3
	for t in tri_n:
		var a := remap[idx[t * 3]]
		var b := remap[idx[t * 3 + 1]]
		var c := remap[idx[t * 3 + 2]]
		if a == b or b == c or a == c:
			continue
		var k1 := mini(a, mini(b, c))
		var k3 := maxi(a, maxi(b, c))
		var k2 := a + b + c - k1 - k3
		var key: int = (k1 * 73856093) ^ (k2 * 19349663) ^ (k3 * 83492791)
		if seen.has(key):
			continue
		seen[key] = true
		out_i.append(a)
		out_i.append(b)
		out_i.append(c)
	return {"verts": out_v, "idx": out_i, "uvs": out_uv}
