extends SceneTree

# 从无骨架的静态 FBX 生成带 Skeleton3D + 蒙皮权重的新场景
# 用法: godot --headless --path . --script res://tools/build_rig.gd

const SRC := "res://assets/characters/rogue_knight/Rogue Knight.fbx"
const OUT := "res://scenes/player/rogue_knight_rigged.tscn"
const OFFSET := Vector3(1.465, -0.036, 0.068)  # 根空间 -> 角色空间(脚底y=0, x/z 居中)
const MAX_INFLUENCE := 4
const WEIGHT_POWER := 4.0
const SMOOTH_ITERS := 3
const SMOOTH_FACTOR := 0.45

var _segs: Array = []  # [[name, a, b], ...]


func _init() -> void:
	var ps: PackedScene = load(SRC)
	var src_root: Node3D = ps.instantiate()

	# ---------- 1. 收集网格顶点（烘到角色空间）----------
	var meshes: Array = []  # [{node, verts, arrays}]
	for m in src_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var baked := PackedVector3Array()
		baked.resize(v.size())
		for i in v.size():
			baked[i] = mi.transform * v[i] - OFFSET
		meshes.append({"node": mi, "verts": baked, "arrays": arr})

	# ---------- 2. 武器球心（用于放武器骨）----------
	var dagger_l := Vector3.ZERO
	var dagger_r := Vector3.ZERO
	var n_l := 0
	var n_r := 0
	var sword_c := Vector3.ZERO
	var n_s := 0
	for e in meshes:
		var nm: String = e.node.name
		var vs: PackedVector3Array = e.verts
		if nm == "Cube_002":
			for p in vs:
				if p.x < 0.0:
					dagger_l += p
					n_l += 1
				else:
					dagger_r += p
					n_r += 1
		elif nm == "Cube_009":
			for p in vs:
				sword_c += p
				n_s += 1
	dagger_l /= max(n_l, 1)
	dagger_r /= max(n_r, 1)
	sword_c /= max(n_s, 1)
	print("dagger.L=", dagger_l.snapped(Vector3.ONE * 0.01), " dagger.R=", dagger_r.snapped(Vector3.ONE * 0.01),
		" sword=", sword_c.snapped(Vector3.ONE * 0.01))

	# ---------- 3. 骨架定义 ----------
	var z := 0.02
	var bones: Array = []  # [name, parent, pos]
	bones.append(["root", "", Vector3(0, 0, 0)])
	bones.append(["hips", "root", Vector3(0, 1.00, z)])
	bones.append(["spine", "hips", Vector3(0, 1.16, z)])
	bones.append(["chest", "spine", Vector3(0, 1.38, z)])
	bones.append(["neck", "chest", Vector3(0, 1.66, z)])
	bones.append(["head", "neck", Vector3(0, 1.80, z)])
	for s in [-1.0, 1.0]:
		var sfx := ".R" if s < 0.0 else ".L"
		bones.append(["clavicle" + sfx, "chest", Vector3(0.06 * s, 1.58, z)])
		bones.append(["upper_arm" + sfx, "clavicle" + sfx, Vector3(0.30 * s, 1.57, z)])
		bones.append(["forearm" + sfx, "upper_arm" + sfx, Vector3(0.48 * s, 1.27, z)])
		bones.append(["hand" + sfx, "forearm" + sfx, Vector3(0.65 * s, 0.97, z)])
		bones.append(["thigh" + sfx, "hips", Vector3(0.15 * s, 0.98, z)])
		bones.append(["shin" + sfx, "thigh" + sfx, Vector3(0.225 * s, 0.56, z)])
		bones.append(["foot" + sfx, "shin" + sfx, Vector3(0.235 * s, 0.10, z)])
		bones.append(["toe" + sfx, "foot" + sfx, Vector3(0.235 * s, 0.02, z + 0.14)])
	bones.append(["weapon_dagger.L", "hips", dagger_l])
	bones.append(["weapon_dagger.R", "hips", dagger_r])
	bones.append(["weapon_sword", "chest", sword_c])

	# 蒙皮影响段（头 -> 尾），用于最近骨段权重
	for s in [-1.0, 1.0]:
		var sfx := ".R" if s < 0.0 else ".L"
		_segs.append(["clavicle" + sfx, Vector3(0.02 * s, 1.58, z), Vector3(0.30 * s, 1.57, z)])
		_segs.append(["upper_arm" + sfx, Vector3(0.30 * s, 1.57, z), Vector3(0.48 * s, 1.27, z)])
		_segs.append(["forearm" + sfx, Vector3(0.48 * s, 1.27, z), Vector3(0.65 * s, 0.97, z)])
		_segs.append(["hand" + sfx, Vector3(0.65 * s, 0.97, z), Vector3(0.73 * s, 0.87, z)])
		_segs.append(["thigh" + sfx, Vector3(0.15 * s, 0.98, z), Vector3(0.225 * s, 0.56, z)])
		_segs.append(["shin" + sfx, Vector3(0.225 * s, 0.56, z), Vector3(0.235 * s, 0.10, z)])
		_segs.append(["foot" + sfx, Vector3(0.235 * s, 0.10, z), Vector3(0.235 * s, 0.02, z + 0.16)])
		_segs.append(["toe" + sfx, Vector3(0.235 * s, 0.02, z + 0.16), Vector3(0.235 * s, 0.02, z + 0.28)])
	_segs.append(["hips", Vector3(0, 0.92, z), Vector3(0, 1.10, z)])
	_segs.append(["spine", Vector3(0, 1.10, z), Vector3(0, 1.30, z)])
	_segs.append(["chest", Vector3(0, 1.30, z), Vector3(0, 1.62, z)])
	_segs.append(["neck", Vector3(0, 1.62, z), Vector3(0, 1.78, z)])
	_segs.append(["head", Vector3(0, 1.78, z), Vector3(0, 2.10, z)])

	# ---------- 4. 建 Skeleton3D ----------
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var idx := {}
	for b in bones:
		var i := skel.get_bone_count()
		skel.add_bone(b[0])
		idx[b[0]] = i
	for b in bones:
		if b[1] != "":
			skel.set_bone_parent(idx[b[0]], idx[b[1]])
	for b in bones:
		var i: int = idx[b[0]]
		var local: Vector3 = b[2]
		if b[1] != "":
			local -= bones[idx[b[1]]][2]
		skel.set_bone_rest(i, Transform3D(Basis(), local))
	skel.reset_bone_poses()
	print("bones=", skel.get_bone_count())

	# ---------- 5. Skin ----------
	var skin := Skin.new()
	for i in skel.get_bone_count():
		skin.add_bind(i, skel.get_bone_global_rest(i).affine_inverse())

	# ---------- 6. 建蒙皮网格 ----------
	var root := Node3D.new()
	root.name = "RogueKnight"
	root.add_child(skel)
	skel.owner = root

	for e in meshes:
		var nm: String = e.node.name
		var verts: PackedVector3Array = e.verts
		var arrays: Array = e.arrays
		var w := _compute_weights(nm, verts, arrays, idx)
		var mesh := _build_mesh(nm, e.node, verts, arrays, w, idx)

		var mi := MeshInstance3D.new()
		mi.name = nm + "_skinned"
		mi.mesh = mesh
		mi.skin = skin
		mi.skeleton = NodePath("..")
		skel.add_child(mi)
		mi.owner = root
		print("  built ", mi.name, " verts=", verts.size())

	# 去掉骨架自带的 root 变换影响：root 骨在原点，无需处理
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		print("PACK_FAILED ", err)
		quit()
		return
	err = ResourceSaver.save(packed, OUT)
	print("SAVED ", OUT, " err=", err)
	src_root.free()
	quit()


# ---------------- 权重计算 ----------------
func _compute_weights(nm: String, verts: PackedVector3Array, arrays: Array, idx: Dictionary) -> Array:
	var n := verts.size()
	var out: Array = []
	out.resize(n)

	if nm == "Cube_002":
		for i in n:
			out[i] = {"weapon_dagger.L" if verts[i].x < 0.0 else "weapon_dagger.R": 1.0}
		return out
	if nm == "Cube_009":
		for i in n:
			out[i] = {"weapon_sword": 1.0}
		return out
	if nm == "Plane_002":
		for i in n:
			out[i] = {"hips": 1.0}
		return out

	# 主体网格：最近骨段
	var leg_segs: Array = []
	for s in _segs:
		if s[0].begins_with("thigh") or s[0].begins_with("shin") or s[0].begins_with("foot") or s[0].begins_with("toe"):
			leg_segs.append(s)

	var stats := {"cape": 0, "leg": 0}
	for i in n:
		var p := verts[i]
		var d: Array = []
		for s in _segs:
			d.append([_seg_dist(p, s[1], s[2]), s[0]])
		d.sort_custom(func(a, b): return a[0] < b[0])

		# 裙摆/披风：离腿较远的下半身顶点统一绑骨盆，避免被双腿撕裂
		if p.y < 0.96:
			var dleg := 1e9
			for s in leg_segs:
				dleg = min(dleg, _seg_dist(p, s[1], s[2]))
			if dleg > 0.135:
				stats.cape += 1
				if p.y > 0.25:
					# 裙摆主体绑骨盆，仅给同侧大腿少量跟随，避免刚性撕裂
					var side := "thigh.L" if p.x > 0.0 else "thigh.R"
					out[i] = {"hips": 0.82, side: 0.18}
				else:
					out[i] = {"hips": 1.0}
				continue
			stats.leg += 1

		var w := {}
		var tot := 0.0
		for k in mini(MAX_INFLUENCE, d.size()):
			var ww: float = 1.0 / pow(d[k][0] + 0.015, WEIGHT_POWER)
			w[d[k][1]] = ww
			tot += ww
		for key in w.keys():
			w[key] = w[key] / tot
		out[i] = w
	print("  ", nm, " cape_verts=", stats.cape, " leg_verts=", stats.leg)

	# ---------- 邻接平滑（仅主网格）----------
	var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = {}
	for t in range(0, ind.size(), 3):
		var a := ind[t]
		var b := ind[t + 1]
		var c := ind[t + 2]
		adj[a][b] = true
		adj[a][c] = true
		adj[b][a] = true
		adj[b][c] = true
		adj[c][a] = true
		adj[c][b] = true

	for _it in SMOOTH_ITERS:
		var nxt: Array = []
		nxt.resize(n)
		for i in n:
			var acc := {}
			for k in out[i]:
				acc[k] = out[i][k] * (1.0 - SMOOTH_FACTOR)
			var nb: Dictionary = adj[i]
			if nb.size() > 0:
				var share := SMOOTH_FACTOR / float(nb.size())
				for j in nb.keys():
					for k in out[j]:
						acc[k] = acc.get(k, 0.0) + out[j][k] * share
			var tot := 0.0
			for k in acc:
				tot += acc[k]
			for k in acc:
				acc[k] = acc[k] / tot
			nxt[i] = acc
		out = nxt
	# 裁到 4 个影响并归一
	for i in n:
		var lst: Array = []
		for k in out[i]:
			lst.append([out[i][k], k])
		lst.sort_custom(func(a, b): return a[0] > b[0])
		var w := {}
		var tot := 0.0
		for k in mini(MAX_INFLUENCE, lst.size()):
			if lst[k][0] <= 0.0001:
				continue
			w[lst[k][1]] = lst[k][0]
			tot += lst[k][0]
		for key in w.keys():
			w[key] = w[key] / tot
		out[i] = w
	return out


func _build_mesh(nm: String, src_mi: MeshInstance3D, verts: PackedVector3Array, arrays: Array, weights: Array, idx: Dictionary) -> ArrayMesh:
	var new_arrays := []
	new_arrays.resize(Mesh.ARRAY_MAX)
	new_arrays[Mesh.ARRAY_VERTEX] = verts
	var xf: Transform3D = src_mi.transform

	if arrays[Mesh.ARRAY_NORMAL] != null:
		var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var nrm := PackedVector3Array()
		nrm.resize(src_n.size())
		for i in src_n.size():
			nrm[i] = (xf.basis * src_n[i]).normalized()
		new_arrays[Mesh.ARRAY_NORMAL] = nrm
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var src_t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var tan := PackedFloat32Array()
		tan.resize(src_t.size())
		for i in range(0, src_t.size(), 4):
			var v := (xf.basis * Vector3(src_t[i], src_t[i + 1], src_t[i + 2])).normalized()
			tan[i] = v.x
			tan[i + 1] = v.y
			tan[i + 2] = v.z
			tan[i + 3] = src_t[i + 3]
		new_arrays[Mesh.ARRAY_TANGENT] = tan
	if arrays[Mesh.ARRAY_COLOR] != null:
		new_arrays[Mesh.ARRAY_COLOR] = arrays[Mesh.ARRAY_COLOR]
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		new_arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
	if arrays[Mesh.ARRAY_TEX_UV2] != null:
		new_arrays[Mesh.ARRAY_TEX_UV2] = arrays[Mesh.ARRAY_TEX_UV2]
	new_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]

	var vb := PackedInt32Array()
	var wb := PackedFloat32Array()
	vb.resize(verts.size() * 4)
	wb.resize(verts.size() * 4)
	for i in verts.size():
		var lst: Array = []
		for k in weights[i]:
			lst.append([weights[i][k], k])
		lst.sort_custom(func(a, b): return a[0] > b[0])
		for s in 4:
			if s < lst.size():
				vb[i * 4 + s] = idx[lst[s][1]]
				wb[i * 4 + s] = lst[s][0]
			else:
				vb[i * 4 + s] = 0
				wb[i * 4 + s] = 0.0
	new_arrays[Mesh.ARRAY_BONES] = vb
	new_arrays[Mesh.ARRAY_WEIGHTS] = wb

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	var mat: Material = src_mi.mesh.surface_get_material(0)
	if mat:
		mesh.surface_set_material(0, mat.duplicate())
	return mesh


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
