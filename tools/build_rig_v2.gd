extends SceneTree

# A1/A2：重建骨架（22 根 Mixamo 映射骨 + 武器挂点 + 8 根裙摆链）
#   1. 网格烘到角色空间（脚底 y=0、x/z 居中、朝向 +Z）
#   2. 在 A-Pose 上算蒙皮权重
#   3. 手臂摆到 T-Pose（Mixamo 动画以 T-Pose 为基准）+ 骨点同步移动
#   4. 大剑按 PCA 求长轴，刚性变换到右手握持位，绑 socket_weapon.R
#   5. 双匕首 100% 绑 Hips（装饰）
#
# 用法: godot --headless --path . --script res://tools/build_rig_v2.gd

const SRC := "res://assets/characters/rogue_knight/Rogue Knight.fbx"
const OUT := "res://scenes/player/rogue_knight_v2.tscn"
const OFFSET := Vector3(1.465, -0.036, 0.068)

const MAX_INF := 4
const W_POWER := 4.0
const SMOOTH_ITERS := 3
const SMOOTH_FACTOR := 0.45

# 大剑握持参数（A2 阶段靠渲染迭代这两个值）
const GRIP_ALONG := Vector3(0, 0, 1)      # 剑身指向（角色空间）
const GRIP_SEC := Vector3(1, 0, 0)        # 刃面参考方向（与 GRIP_ALONG 正交）
const GRIP_END_INSET := 0.10              # 从剑格端往剑尖方向内缩比例（=握把位置）

var _segs: Array = []          # [name, head, tail] 用于最近骨段权重
var _bones: Array = []         # [name, parent, pos]
var _idx: Dictionary = {}


func _init() -> void:
	var ps: PackedScene = load(SRC)
	var src: Node3D = ps.instantiate()

	# ---------- 1. 收集网格（A-Pose / 角色空间）----------
	var meshes: Array = []
	for m in src.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var baked := PackedVector3Array()
		baked.resize(v.size())
		for i in v.size():
			baked[i] = mi.transform * v[i] - OFFSET
		meshes.append({"name": mi.name, "verts": baked, "arrays": arr, "xf": mi.transform,
			"mesh": mi.mesh})
		print("mesh ", mi.name, " verts=", v.size())

	# ---------- 2. A-Pose 骨点 ----------
	var z := 0.02
	var ap := {}   # name -> Vector3
	ap["Hips"] = Vector3(0, 1.00, z)
	ap["Spine"] = Vector3(0, 1.20, z)
	ap["Spine1"] = Vector3(0, 1.40, z)
	ap["Spine2"] = Vector3(0, 1.56, z)
	ap["Neck"] = Vector3(0, 1.68, z)
	ap["Head"] = Vector3(0, 1.82, z)
	for s in [1.0, -1.0]:
		var sfx: String = "Left" if s > 0.0 else "Right"
		ap[sfx + "Shoulder"] = Vector3(0.06 * s, 1.58, z)
		ap[sfx + "Arm"] = Vector3(0.30 * s, 1.57, z)
		ap[sfx + "ForeArm"] = Vector3(0.48 * s, 1.27, z)
		ap[sfx + "Hand"] = Vector3(0.65 * s, 0.97, z)
		ap[sfx + "UpLeg"] = Vector3(0.15 * s, 0.98, z)
		ap[sfx + "Leg"] = Vector3(0.225 * s, 0.56, z)
		ap[sfx + "Foot"] = Vector3(0.235 * s, 0.10, z)
		ap[sfx + "ToeBase"] = Vector3(0.235 * s, 0.02, z + 0.14)

	# 裙摆链（挂 Hips，四向各 3 节）
	var skirt_dirs := {"F": Vector3(0, 0, 1), "B": Vector3(0, 0, -1),
		"L": Vector3(1, 0, 0), "R": Vector3(-1, 0, 0)}
	var skirt_levels := [0.98, 0.70, 0.40]
	var skirt_rad := [0.24, 0.28, 0.30]
	for key in skirt_dirs:
		var d: Vector3 = skirt_dirs[key]
		for lv in 3:
			var nm := "skirt_%s%d" % [key, lv + 1]
			ap[nm] = Vector3(d.x * skirt_rad[lv], skirt_levels[lv], z + d.z * skirt_rad[lv])

	# ---------- 3. A-Pose 权重 ----------
	for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		_segs.append([b, ap[b], ap.get(_next_spine(b), ap[b] + Vector3(0, 0.16, 0))])
	for s in [1.0, -1.0]:
		var sfx: String = "Left" if s > 0.0 else "Right"
		_segs.append([sfx + "Shoulder", ap[sfx + "Shoulder"], ap[sfx + "Arm"]])
		_segs.append([sfx + "Arm", ap[sfx + "Arm"], ap[sfx + "ForeArm"]])
		_segs.append([sfx + "ForeArm", ap[sfx + "ForeArm"], ap[sfx + "Hand"]])
		_segs.append([sfx + "Hand", ap[sfx + "Hand"],
			ap[sfx + "Hand"] + (ap[sfx + "Hand"] - ap[sfx + "ForeArm"]).normalized() * 0.09])
		_segs.append([sfx + "UpLeg", ap[sfx + "UpLeg"], ap[sfx + "Leg"]])
		_segs.append([sfx + "Leg", ap[sfx + "Leg"], ap[sfx + "Foot"]])
		_segs.append([sfx + "Foot", ap[sfx + "Foot"], ap[sfx + "ToeBase"]])
		_segs.append([sfx + "ToeBase", ap[sfx + "ToeBase"], ap[sfx + "ToeBase"] + Vector3(0, 0, 0.12)])
	for key in skirt_dirs:
		for lv in 3:
			var nm := "skirt_%s%d" % [key, lv + 1]
			var head: Vector3 = ap[nm]
			var tail: Vector3 = ap[nm] + Vector3(0, -0.22, 0)
			_segs.append([nm, head, tail])

	var weights: Dictionary = {}
	for e in meshes:
		weights[e.name] = _compute_weights(e.name, e.verts, e.arrays)

	# ---------- 4. 手臂 T-Pose ----------
	var tpose_ang := {}
	for s in [1.0, -1.0]:
		var sfx: String = "Left" if s > 0.0 else "Right"
		var sh: Vector3 = ap[sfx + "Arm"]
		var el: Vector3 = ap[sfx + "ForeArm"]
		var hd: Vector3 = ap[sfx + "Hand"]
		var v2 := Vector2(el.x - sh.x, el.y - sh.y)
		var ang: float = v2.angle_to(Vector2(s, 0.0))
		tpose_ang[sfx] = ang
		var rot := Basis(Vector3.BACK, ang)
		ap[sfx + "ForeArm"] = sh + rot * (el - sh)
		ap[sfx + "Hand"] = ap[sfx + "ForeArm"] + rot * (hd - el)
		print("T-Pose ", sfx, " angle=", rad_to_deg(ang), "°  elbow=", ap[sfx + "ForeArm"].snapped(Vector3.ONE * 0.01),
			" hand=", ap[sfx + "Hand"].snapped(Vector3.ONE * 0.01))

	# 顶点按手臂权重比例混合着转过去（肩部平滑过渡）
	for e in meshes:
		var nm: String = e.name
		if nm == "Cube_002" or nm == "Cube_009":
			continue
		var vs: PackedVector3Array = e.verts
		var arr: Array = e.arrays
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var w: Array = weights[nm]
		var new_n := PackedVector3Array()
		new_n.resize(vs.size())
		var arm_set := ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]
		for i in vs.size():
			var wl := 0.0
			var wr := 0.0
			for k in w[i]:
				if k == "LeftArm" or k == "LeftForeArm" or k == "LeftHand":
					wl += w[i][k]
				elif k == "RightArm" or k == "RightForeArm" or k == "RightHand":
					wr += w[i][k]
			var side := ""
			var amt := 0.0
			if wl > wr and wl > 0.001:
				side = "Left"
				amt = wl
			elif wr > 0.001:
				side = "Right"
				amt = wr
			if side != "":
				var a: float = tpose_ang[side] * clampf(amt, 0.0, 1.0)
				var sh := Vector3(0.30 * (1.0 if side == "Left" else -1.0), 1.57, z)
				var rotv := Basis(Vector3.BACK, a)
				vs[i] = sh + rotv * (vs[i] - sh)
				if nrm != null:
					new_n[i] = (rotv * nrm[i]).normalized()
			elif nrm != null:
				new_n[i] = nrm[i]
		e.verts = vs
		if nrm != null:
			arr[Mesh.ARRAY_NORMAL] = new_n

	# ---------- 5. 大剑 → 右手 ----------
	var sword: Dictionary = {}
	for e in meshes:
		if e.name == "Cube_009":
			sword = e
	var grip_pos: Vector3 = ap["RightHand"]
	if not sword.is_empty():
		var sv: PackedVector3Array = sword.verts
		var cen := Vector3.ZERO
		for p in sv:
			cen += p
		cen /= float(sv.size())
		var cov := _covariance(sv, cen)
		var axis := _power_iteration(cov, Vector3(0.6, 0.8, 0))
		axis = axis.normalized()
		# 找两端
		var tmin := 1e9
		var tmax := -1e9
		var pmin := Vector3.ZERO
		var pmax := Vector3.ZERO
		for p in sv:
			var t: float = (p - cen).dot(axis)
			if t < tmin:
				tmin = t
				pmin = p
			if t > tmax:
				tmax = t
				pmax = p
		# 剑柄端 = y 更大的那端（原模型是柄朝上背在背后）
		var hilt: Vector3 = pmax if pmax.y > pmin.y else pmin
		var tip: Vector3 = pmin if pmax.y > pmin.y else pmax
		var blade_dir: Vector3 = (tip - hilt).normalized()
		var grip_pt: Vector3 = hilt + (tip - hilt) * GRIP_END_INSET
		print("sword axis=", axis.snapped(Vector3.ONE * 0.01), " hilt=", hilt.snapped(Vector3.ONE * 0.01),
			" tip=", tip.snapped(Vector3.ONE * 0.01), " grip=", grip_pt.snapped(Vector3.ONE * 0.01))

		# 目标朝向：剑身沿 GRIP_ALONG；用副轴定"刃面"朝向
		var target_dir: Vector3 = GRIP_ALONG.normalized()
		var sec := _second_axis(sv, cen, axis)
		var target_sec := GRIP_SEC
		# Gram-Schmidt 建目标基
		var tb1: Vector3 = target_dir
		var tb2: Vector3 = (target_sec - tb1 * target_sec.dot(tb1)).normalized()
		var tb3: Vector3 = tb1.cross(tb2)
		var sb1: Vector3 = blade_dir
		var sb2: Vector3 = (sec - sb1 * sec.dot(sb1)).normalized()
		var sb3: Vector3 = sb1.cross(sb2)
		var rot := (Basis(tb1, tb2, tb3) * Basis(sb1, sb2, sb3).transposed())
		var new_verts := PackedVector3Array()
		new_verts.resize(sv.size())
		for i in sv.size():
			new_verts[i] = grip_pos + rot * (sv[i] - grip_pt)
		sword.verts = new_verts
		var snrm: PackedVector3Array = sword.arrays[Mesh.ARRAY_NORMAL]
		if snrm != null:
			var nn := PackedVector3Array()
			nn.resize(snrm.size())
			for i in snrm.size():
				nn[i] = (rot * snrm[i]).normalized()
			sword.arrays[Mesh.ARRAY_NORMAL] = nn
		print("  sword moved: grip->", grip_pos.snapped(Vector3.ONE * 0.01), " blade->", target_dir)

	# ---------- 6. 建骨架 ----------
	_bones.clear()
	_bones.append(["root", "", Vector3.ZERO])
	var order := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
		"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
		"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
	var parent_of := {"Hips": "root", "Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1",
		"Neck": "Spine2", "Head": "Neck",
		"LeftShoulder": "Spine2", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
		"RightShoulder": "Spine2", "RightArm": "RightShoulder", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
		"LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
		"RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}
	for n in order:
		_bones.append([n, parent_of[n], ap[n]])
	_bones.append(["socket_weapon.R", "RightHand", grip_pos])
	for key in skirt_dirs:
		for lv in 3:
			var nm := "skirt_%s%d" % [key, lv + 1]
			_bones.append([nm, "Hips" if lv == 0 else "skirt_%s%d" % [key, lv], ap[nm]])

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for b in _bones:
		_idx[b[0]] = skel.get_bone_count()
		skel.add_bone(b[0])
	for b in _bones:
		if b[1] != "":
			skel.set_bone_parent(_idx[b[0]], _idx[b[1]])
	for b in _bones:
		var local: Vector3 = b[2]
		if b[1] != "":
			local -= _bones[_idx[b[1]]][2]
		skel.set_bone_rest(_idx[b[0]], Transform3D(Basis(), local))
	skel.reset_bone_poses()
	print("bones=", skel.get_bone_count())

	var skin := Skin.new()
	for i in skel.get_bone_count():
		skin.add_bind(i, skel.get_bone_global_rest(i).affine_inverse())

	# ---------- 7. 组装场景 ----------
	var root := Node3D.new()
	root.name = "RogueKnightV2"
	root.add_child(skel)
	skel.owner = root

	for e in meshes:
		var nm: String = e.name
		var w: Array = weights[nm]
		if nm == "Cube_002":
			w = _override(w, {"Hips": 1.0})
		elif nm == "Cube_009":
			w = _override(w, {"socket_weapon.R": 1.0})
		var mesh := _build_mesh(e, w)
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = mesh
		mi.skin = skin
		mi.skeleton = NodePath("..")
		skel.add_child(mi)
		mi.owner = root

	# ---------- 8. 连弩（挂在武器骨上，默认隐藏） ----------
	var att := BoneAttachment3D.new()
	att.name = "WeaponAttachment"
	skel.add_child(att)
	att.owner = root
	att.bone_name = "socket_weapon.R"
	var cb := _make_crossbow(root)
	att.add_child(cb)
	cb.owner = root
	for c in cb.get_children():
		c.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	print("pack=", err)
	err = ResourceSaver.save(packed, OUT)
	print("SAVED ", OUT, " err=", err)
	src.free()
	quit()


## 程序化连弩：弩臂 + 弩身 + 弦 + 握把 + 已上膛的弩箭，默认隐藏
func _make_crossbow(root: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Crossbow"
	holder.visible = false

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.17, 0.2)
	wood.metallic = 0.5
	wood.roughness = 0.45
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.36, 0.42)
	metal.metallic = 0.85
	metal.roughness = 0.3
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.albedo_color = Color(0.55, 0.9, 1.0)
	glow.emission = Color(0.55, 0.9, 1.0)
	glow.emission_energy_multiplier = 1.6

	# 弩身
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.055, 0.06, 0.42)
	stock.mesh = sm
	stock.material_override = wood
	stock.position = Vector3(0, 0, 0.11)
	holder.add_child(stock)

	# 握把
	var grip := MeshInstance3D.new()
	var gm2 := BoxMesh.new()
	gm2.size = Vector3(0.05, 0.15, 0.055)
	grip.mesh = gm2
	grip.material_override = wood
	grip.position = Vector3(0, -0.085, -0.03)
	grip.rotation_degrees = Vector3(-12, 0, 0)
	holder.add_child(grip)

	# 弩臂（左右各一，带一点后掠角）
	for s_ in [-1.0, 1.0]:
		var limb := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.27, 0.022, 0.05)
		limb.mesh = lm
		limb.material_override = metal
		limb.position = Vector3(0.135 * s_, 0.012, 0.29)
		limb.rotation_degrees = Vector3(0, 15.0 * s_, 0)
		holder.add_child(limb)

	# 弦
	var string := MeshInstance3D.new()
	var stm := BoxMesh.new()
	stm.size = Vector3(0.5, 0.008, 0.008)
	string.mesh = stm
	string.material_override = metal
	string.position = Vector3(0, 0.012, 0.2)
	holder.add_child(string)

	# 上膛的弩箭（弩槽内，指向 +Z）
	var bolt := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.0
	bm.bottom_radius = 0.009
	bm.height = 0.34
	bolt.mesh = bm
	bolt.material_override = glow
	bolt.position = Vector3(0, 0.048, 0.2)
	bolt.rotation_degrees = Vector3(-90, 0, 0)
	holder.add_child(bolt)

	return holder


func _next_spine(b: String) -> String:
	match b:
		"Hips": return "Spine"
		"Spine": return "Spine1"
		"Spine1": return "Spine2"
		"Spine2": return "Neck"
		"Neck": return "Head"
	return ""


func _override(w: Array, keep: Dictionary) -> Array:
	var out: Array = []
	out.resize(w.size())
	for i in w.size():
		out[i] = keep.duplicate()
	return out


# ---------------- 权重 ----------------
func _compute_weights(nm: String, verts: PackedVector3Array, arrays: Array) -> Array:
	var n := verts.size()
	var out: Array = []
	out.resize(n)
	if nm == "Cube_002" or nm == "Cube_009":
		for i in n:
			out[i] = {"Hips": 1.0}
		return out

	var leg_segs: Array = []
	for s in _segs:
		if s[0].begins_with("LeftUpLeg") or s[0].begins_with("LeftLeg") or s[0].begins_with("LeftFoot") or s[0].begins_with("LeftToeBase") \
				or s[0].begins_with("RightUpLeg") or s[0].begins_with("RightLeg") or s[0].begins_with("RightFoot") or s[0].begins_with("RightToeBase"):
			leg_segs.append(s)
	var skirt_segs: Array = []
	for s in _segs:
		if s[0].begins_with("skirt_"):
			skirt_segs.append(s)
	var body_segs: Array = []
	for s in _segs:
		if not s[0].begins_with("skirt_"):
			body_segs.append(s)

	var cape := 0
	for i in n:
		var p := verts[i]
		# 裙摆：离腿远的下半身顶点交给裙摆链
		if p.y < 0.96:
			var dleg := 1e9
			for s in leg_segs:
				dleg = min(dleg, _seg_dist(p, s[1], s[2]))
			if dleg > 0.135:
				cape += 1
				out[i] = _skirt_weights(p, skirt_segs)
				continue

		var d: Array = []
		for s in body_segs:
			d.append([_seg_dist(p, s[1], s[2]), s[0]])
		d.sort_custom(func(a, b): return a[0] < b[0])
		var w := {}
		var tot := 0.0
		for k in mini(MAX_INF, d.size()):
			var ww: float = 1.0 / pow(d[k][0] + 0.015, W_POWER)
			w[d[k][1]] = ww
			tot += ww
		for key in w.keys():
			w[key] /= tot
		out[i] = w
	print("  ", nm, " cape_verts=", cape)

	# 邻接平滑
	var ind: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = {}
	for t in range(0, ind.size(), 3):
		var a: int = ind[t]
		var b: int = ind[t + 1]
		var c: int = ind[t + 2]
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
				var share: float = SMOOTH_FACTOR / float(nb.size())
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
	for i in n:
		var lst: Array = []
		for k in out[i]:
			lst.append([out[i][k], k])
		lst.sort_custom(func(a, b): return a[0] > b[0])
		var w := {}
		var tot := 0.0
		for k in mini(MAX_INF, lst.size()):
			if lst[k][0] <= 0.0001:
				continue
			w[lst[k][1]] = lst[k][0]
			tot += lst[k][0]
		for key in w.keys():
			w[key] /= tot
		out[i] = w
	return out


## 裙摆：按水平方向选最近的链，按高度在两级之间混合，顶部混入 Hips
func _skirt_weights(p: Vector3, skirt_segs: Array) -> Dictionary:
	var d := Vector2(p.x, p.z)
	var best := {}
	var bestdot := -2.0
	for s in skirt_segs:
		var bd := Vector2(s[1].x, s[1].z)
		if bd.length_squared() < 0.0001:
			continue
		var dt: float = d.normalized().dot(bd.normalized())
		if dt > bestdot:
			bestdot = dt
			best = {"nm": s[0], "y": s[1].y, "dot": dt}
	# 找同链的上下两级做混合
	var nm: String = best.nm
	var lv := int(nm.substr(nm.length() - 1, 1))
	var key: String = nm.substr(6, 1)
	var y: float = p.y
	var w := {}
	# 锚定高度：0.98 / 0.70 / 0.40
	var ys := [0.98, 0.70, 0.40]
	var lo := 0
	while lo < 2 and y < ys[lo + 1]:
		lo += 1
	var t: float = 0.0
	if lo < 2:
		t = clampf((ys[lo] - y) / maxf(ys[lo] - ys[lo + 1], 0.0001), 0.0, 1.0)
	w["skirt_%s%d" % [key, lo + 1]] = 1.0 - t
	if t > 0.0 and lo < 2:
		w["skirt_%s%d" % [key, lo + 2]] = t
	# 顶部 8cm 混入 Hips，避免腰部硬折
	var hipw: float = clampf((y - 0.88) / 0.10, 0.0, 1.0) * 0.7
	if hipw > 0.0:
		for k in w.keys():
			w[k] *= (1.0 - hipw)
		w["Hips"] = w.get("Hips", 0.0) + hipw
	return w


func _build_mesh(e: Dictionary, weights: Array) -> ArrayMesh:
	var arrays: Array = e.arrays
	var verts: PackedVector3Array = e.verts
	var new_arrays := []
	new_arrays.resize(Mesh.ARRAY_MAX)
	new_arrays[Mesh.ARRAY_VERTEX] = verts
	for key in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[key] != null:
			new_arrays[key] = arrays[key]
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
				vb[i * 4 + s] = _idx[lst[s][1]]
				wb[i * 4 + s] = lst[s][0]
			else:
				vb[i * 4 + s] = 0
				wb[i * 4 + s] = 0.0
	new_arrays[Mesh.ARRAY_BONES] = vb
	new_arrays[Mesh.ARRAY_WEIGHTS] = wb

	# 法线/切线随 T-Pose 旋转已在外部处理；切线按简化处理
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	var mat: Material = e.mesh.surface_get_material(0)
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


func _covariance(pts: PackedVector3Array, cen: Vector3) -> Basis:
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for p in pts:
		var d := p - cen
		xx += d.x * d.x
		xy += d.x * d.y
		xz += d.x * d.z
		yy += d.y * d.y
		yz += d.y * d.z
		zz += d.z * d.z
	var n := float(pts.size())
	# 存成 Basis 的三个列向量仅为搬运，实际用对角+非对角读取
	return Basis(Vector3(xx / n, xy / n, xz / n), Vector3(xy / n, yy / n, yz / n), Vector3(xz / n, yz / n, zz / n))


func _power_iteration(cov: Basis, seed: Vector3) -> Vector3:
	var v := seed.normalized()
	for _i in 40:
		var nv := cov * v
		if nv.length_squared() < 1e-12:
			break
		v = nv.normalized()
	return v


func _second_axis(pts: PackedVector3Array, cen: Vector3, first: Vector3) -> Vector3:
	# 用与主轴正交且方差最大的方向作为刃面法向的参考
	var best := Vector3.ZERO
	var best_var := -1.0
	for cand in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
		var c: Vector3 = (cand - first * cand.dot(first)).normalized()
		var var_ := 0.0
		for p in pts:
			var d: float = (p - cen).dot(c)
			var_ += d * d
		if var_ > best_var:
			best_var = var_
			best = c
	return best
