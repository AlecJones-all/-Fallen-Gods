extends SceneTree

# 武器补丁器（docs/19 P1–P3）
# 只往现有玩家场景里"加节点 + 换武器网格"，**不重生成骨架、不动动画库**。
# 场景先备份在 dist/_backup/，出问题直接拷回去。
#
# 用法:
#   godot --headless --path . --script res://tools/build_weapons.gd --dry   # 只看结果不写盘
#   godot --headless --path . --script res://tools/build_weapons.gd         # 写盘

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"

# 挂点姿态（要出图微调的就是这三个）
const XBOW_PIVOT_ROT := Vector3(-90.0, 0.0, 0.0)
const XBOW_PIVOT_POS := Vector3(0.0, 0.04, 0.0)
const AXE_PIVOT_ROT := Vector3(90.0, 0.0, 0.0)
const AXE_PIVOT_POS := Vector3(0.0, 0.0, 0.0)
## 斧的几何是按 1.203m 建出来的（柄 0.80 + 刃顶 0.898），比设计的 0.92m 长 30%。
## 统一缩到 0.94m：握把在原点，缩放不改变手心位置。
const AXE_SCALE := 0.78

const EMBER := Color(0.55, 0.10, 0.08)

var _m := {}
var _root: Node3D
var _dry := false


func _init() -> void:
	_dry = OS.get_cmdline_user_args().has("--dry")
	var ps: PackedScene = load(SCENE)
	if ps == null:
		push_error("场景加载失败")
		quit(1)
		return
	_root = ps.instantiate() as Node3D
	get_root().add_child(_root)

	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false)
	var clips_before := ap.get_animation_list().size() if ap != null else -1
	print("场景动画片段（改前）= ", clips_before)

	_build_materials()

	var att: Node3D = _root.find_child("WeaponAttachment", true, false)
	if att == null:
		push_error("找不到 WeaponAttachment")
		quit(1)
		return

	# ---- 旧弩整个删掉，按新设计重建 ----
	var old_xbow: Node = att.find_child("Crossbow", true, false)
	if old_xbow != null:
		old_xbow.get_parent().remove_child(old_xbow)
		old_xbow.queue_free()
		print("已移除旧 Crossbow")

	for nm in ["XbowPivot", "AxePivot"]:
		var old: Node = att.find_child(nm, true, false)
		if old != null:
			old.get_parent().remove_child(old)
			old.queue_free()
			print("已移除旧 ", nm)

	var xbow_pivot := Node3D.new()
	xbow_pivot.name = "XbowPivot"
	xbow_pivot.position = XBOW_PIVOT_POS
	xbow_pivot.rotation_degrees = XBOW_PIVOT_ROT
	att.add_child(xbow_pivot)
	xbow_pivot.owner = _root
	_build_crossbow(xbow_pivot)

	var axe_pivot := Node3D.new()
	axe_pivot.name = "AxePivot"
	axe_pivot.position = AXE_PIVOT_POS
	axe_pivot.rotation_degrees = AXE_PIVOT_ROT
	att.add_child(axe_pivot)
	axe_pivot.owner = _root
	_build_axe(axe_pivot)

	_report()

	if _dry:
		print("\n[--dry] 未写盘")
		quit(0)
		return

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	print("pack=", err)
	print("save=", ResourceSaver.save(packed, SCENE))
	quit(0)


# ================= 材质：复用全场三平面贴图，改成物体空间 =================
func _build_materials() -> void:
	var base := KitArt.build()
	_m["iron"] = _obj(base["iron_rust"], Color(1, 1, 1), 7.0)
	_m["iron_dark"] = _obj(base["iron_rust"], Color(0.58, 0.56, 0.55), 7.0)
	_m["iron_edge"] = _obj(base["iron_rust"], Color(1.35, 1.32, 1.28), 11.0, 0.55)
	_m["wood"] = _obj(base["wood_dry"], Color(1.0, 0.96, 0.9), 5.0)
	_m["rope"] = _obj(base["cloth_rot"], Color(0.85, 0.8, 0.72), 14.0)
	_m["bone"] = _obj(base["bone"], Color(1, 1, 1), 10.0)

	var ember := StandardMaterial3D.new()
	ember.albedo_color = EMBER
	ember.emission_enabled = true
	ember.emission = EMBER
	ember.emission_energy_multiplier = 1.2
	_m["ember"] = ember


func _obj(src: Material, tint: Color, tri: float, rough: float = -1.0) -> StandardMaterial3D:
	var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = tint
	# 关键：KitArt 给的是世界三平面，武器会动，必须换成物体空间否则贴图会在刀身上滑动
	m.uv1_world_triplanar = false
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * tri
	if rough >= 0.0:
		m.roughness = rough
		m.metallic = 0.55
	return m


# ================= 连弩 =================
func _build_crossbow(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Crossbow"
	root.visible = false
	parent.add_child(root)
	root.owner = _root

	# 弩身
	_box(root, "Stock", Vector3(0.048, 0.072, 0.38), Vector3(0, 0.02, 0.10), Vector3.ZERO, "iron")
	# 箭槽两条侧壁，夹出 0.028 宽的槽
	_box(root, "RailL", Vector3(0.010, 0.018, 0.22), Vector3(-0.014, 0.058, 0.15), Vector3.ZERO, "iron_dark")
	_box(root, "RailR", Vector3(0.010, 0.018, 0.22), Vector3(0.014, 0.058, 0.15), Vector3.ZERO, "iron_dark")
	# 弩机（扳机室）——"这是弩不是木头"的识别点
	_box(root, "TriggerHousing", Vector3(0.050, 0.055, 0.075), Vector3(0, -0.045, 0.03), Vector3.ZERO, "iron")
	_box(root, "Trigger", Vector3(0.012, 0.045, 0.014), Vector3(0, -0.062, 0.055), Vector3(-20, 0, 0), "iron_dark")
	_torus(root, "TriggerGuard", 0.020, 0.028, Vector3(0, -0.072, 0.062), Vector3(90, 0, 0), "iron_dark")
	# 握把
	_box(root, "Grip", Vector3(0.042, 0.13, 0.048), Vector3(0, -0.085, -0.02), Vector3(-15, 0, 0), "wood")
	# 前段弩臂座
	_box(root, "ProdMount", Vector3(0.062, 0.050, 0.052), Vector3(0, 0.03, 0.285), Vector3.ZERO, "iron")
	# 瞄具（前端小立片）
	_box(root, "Sight", Vector3(0.006, 0.032, 0.012), Vector3(0, 0.076, 0.265), Vector3.ZERO, "iron_dark")

	# 弩臂：每侧 3 段递进转角 + 端头，做出弧与后掠
	var tips := []
	for s in [-1.0, 1.0]:
		var segs := [
			[Vector3(0.090, 0.020, 0.030), Vector3(0.052, 0.030, 0.300), 12.0],
			[Vector3(0.088, 0.019, 0.028), Vector3(0.133, 0.030, 0.318), 28.0],
			[Vector3(0.082, 0.018, 0.026), Vector3(0.203, 0.030, 0.352), 46.0],
		]
		for i in segs.size():
			var d: Array = segs[i]
			var sz: Vector3 = d[0]
			var p: Vector3 = d[1]
			_box(root, "Limb%d%s" % [i, "L" if s < 0 else "R"], sz,
				Vector3(p.x * s, p.y, p.z), Vector3(0, float(d[2]) * s, 0), "iron")
		var tip := Vector3(0.238 * s, 0.030, 0.392)
		_box(root, "Tip%s" % ("L" if s < 0 else "R"), Vector3(0.022, 0.016, 0.024), tip,
			Vector3(0, 48.0 * s, 0), "iron_dark")
		tips.append(tip)

	# 弦：从一侧端头到后钩再到另一侧
	var nock := Vector3(0, 0.030, 0.075)
	_beam(root, "StringL", tips[0], nock, 0.007, 0.007, "bone")
	_beam(root, "StringR", tips[1], nock, 0.007, 0.007, "bone")

	# 绑绳：3 圈
	for i in 3:
		_torus(root, "Bind%d" % i, 0.030, 0.040, Vector3(0, 0.02, -0.03 + 0.11 * i), Vector3(90, 0, 0), "rope")

	# 已上膛弩箭
	var bolt := MeshInstance3D.new()
	bolt.name = "Bolt"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0055
	cyl.bottom_radius = 0.0055
	cyl.height = 0.30
	cyl.radial_segments = 6
	cyl.rings = 1
	bolt.mesh = cyl
	bolt.material_override = _m["bone"]
	bolt.position = Vector3(0, 0.052, 0.17)
	bolt.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(bolt)
	bolt.owner = _root

	var head := MeshInstance3D.new()
	head.name = "BoltHead"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0005
	cone.bottom_radius = 0.011
	cone.height = 0.045
	cone.radial_segments = 4
	head.mesh = cone
	head.material_override = _m["iron_edge"]
	head.position = Vector3(0, 0.052, 0.335)
	head.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(head)
	head.owner = _root

	# 烬纹：弩机侧面一小条
	_box(root, "Ember", Vector3(0.003, 0.014, 0.048), Vector3(0.026, -0.045, 0.03), Vector3.ZERO, "ember")


# ================= 斧 =================
func _build_axe(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Axe"
	root.visible = false
	root.scale = Vector3.ONE * AXE_SCALE
	parent.add_child(root)
	root.owner = _root

	# 斧柄：握把在原点，柄从 y=-0.30 到 +0.50
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.019
	cyl.bottom_radius = 0.023
	cyl.height = 0.80
	cyl.radial_segments = 10
	cyl.rings = 2
	handle.mesh = cyl
	handle.material_override = _m["wood"]
	handle.position = Vector3(0, 0.10, 0)
	handle.scale = Vector3(1.12, 1.0, 0.88)
	root.add_child(handle)
	handle.owner = _root

	# 斧颈（两段截锥）
	_cyl(root, "Collar0", 0.026, 0.030, 0.070, Vector3(0, 0.500, 0), "iron_dark")
	_cyl(root, "Collar1", 0.022, 0.026, 0.050, Vector3(0, 0.545, 0), "iron_dark")

	# 斧刃（SurfaceTool 挤出剖面）
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	blade.mesh = _blade_mesh()
	blade.material_override = _m["iron"]
	root.add_child(blade)
	blade.owner = _root

	# 刃口亮面（沿刃口一条，用发光提亮磨刃感）
	_box(root, "EdgeHighlight", Vector3(0.030, 0.075, 0.004), Vector3(0.425, 0.660, 0), Vector3(0, 0, 8), "iron_edge")

	# 背钩
	_beam(root, "HookA", Vector3(-0.02, 0.560, 0), Vector3(-0.105, 0.600, 0), 0.020, 0.026, "iron_dark")
	_beam(root, "HookB", Vector3(-0.105, 0.600, 0), Vector3(-0.120, 0.660, 0), 0.016, 0.020, "iron_dark")

	# 缠绳（握把 4 圈）
	for i in 4:
		_torus(root, "Wrap%d" % i, 0.021, 0.028, Vector3(0, -0.13 + 0.065 * i, 0), Vector3(90, 0, 0), "rope")

	# 柄顶铁楔
	_box(root, "WedgeA", Vector3(0.040, 0.016, 0.006), Vector3(0, 0.500, 0), Vector3(0, 0, 0), "iron_dark")
	_box(root, "WedgeB", Vector3(0.006, 0.016, 0.036), Vector3(0, 0.500, 0), Vector3(0, 0, 0), "iron_dark")

	# 柄尾配重环
	_torus(root, "Pommel", 0.020, 0.030, Vector3(0, -0.305, 0), Vector3(90, 0, 0), "iron")

	# 烬纹：刃根一道暗红（满蓄力时在代码里点亮 emission）
	_box(root, "Ember", Vector3(0.006, 0.110, 0.012), Vector3(0.070, 0.720, 0), Vector3(0, 0, -12), "ember")


## 斧刃剖面挤出：8 点贝旦斧轮廓，厚度随 x 从 14mm 收到 2.5mm
func _blade_mesh() -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(0.020, 0.560), Vector2(0.160, 0.542), Vector2(0.310, 0.572),
		Vector2(0.412, 0.628), Vector2(0.438, 0.700), Vector2(0.372, 0.800),
		Vector2(0.200, 0.872), Vector2(0.020, 0.898),
	]
	var n := profile.size()
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	var cx := 0.0
	var cy := 0.0
	for p in profile:
		cx += p.x
		cy += p.y
	var center := Vector3(cx / n, cy / n, 0.0)
	for p in profile:
		var t := lerpf(0.014, 0.0025, clampf((p.x - 0.020) / 0.418, 0.0, 1.0)) * 0.5
		front.append(Vector3(p.x, p.y, t))
		back.append(Vector3(p.x, p.y, -t))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 正面（法线 +Z）：从中心扇形；profile 为逆时针
	for i in n:
		st.add_vertex(center)
		st.add_vertex(front[i])
		st.add_vertex(front[(i + 1) % n])
	# 背面（法线 -Z）：反向
	for i in n:
		st.add_vertex(center)
		st.add_vertex(back[(i + 1) % n])
		st.add_vertex(back[i])
	# 侧壁
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(front[i])
		st.add_vertex(back[i])
		st.add_vertex(back[j])
		st.add_vertex(front[i])
		st.add_vertex(back[j])
		st.add_vertex(front[j])
	st.generate_normals()
	return st.commit()


# ================= 几何小工具 =================
func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, rot_deg: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _m[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	mi.owner = _root
	return mi


func _cyl(parent: Node3D, name: String, top_r: float, bot_r: float, h: float, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = _m[mat]
	mi.position = pos
	parent.add_child(mi)
	mi.owner = _root
	return mi


func _torus(parent: Node3D, name: String, inner: float, outer: float, pos: Vector3, rot_deg: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 10
	tm.ring_segments = 5
	mi.mesh = tm
	mi.material_override = _m[mat]
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	mi.owner = _root
	return mi


## 两点之间拉一根方料（弦、背钩）
func _beam(parent: Node3D, name: String, a: Vector3, b: Vector3, w: float, h: float, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	var d := b - a
	bm.size = Vector3(w, h, d.length())
	mi.mesh = bm
	mi.material_override = _m[mat]
	mi.position = (a + b) * 0.5
	var dir := d.normalized()
	if dir.length_squared() > 0.001:
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		mi.basis = Basis.looking_at(dir, up)
	parent.add_child(mi)
	mi.owner = _root
	return mi


# ================= 自检输出 =================
func _report() -> void:
	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false)
	print("\n=== 自检 ===")
	print("动画片段 = ", ap.get_animation_list().size() if ap != null else -1, "（必须仍是原来的数量）")
	print("剑 Cube_009 存在 = ", _root.find_child("Cube_009", true, false) != null)
	for nm in ["WeaponAttachment", "XbowPivot", "AxePivot"]:
		var n: Node = _root.find_child(nm, true, false)
		print("%-16s = %s" % [nm, n != null])
	var xb: Node = _root.find_child("Crossbow", true, false)
	var ax: Node = _root.find_child("Axe", true, false)
	print("Crossbow 子件 = ", xb.get_child_count() if xb != null else -1)
	print("Axe 子件 = ", ax.get_child_count() if ax != null else -1)
	var tris := 0
	for mi in _all_mesh(_root.find_child("WeaponAttachment", true, false)):
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var iv: Variant = arr[Mesh.ARRAY_INDEX]
				if iv != null:
					tris += (iv as PackedInt32Array).size() / 3
				else:
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					tris += vv.size() / 3
	print("武器总三角面 ≈ ", tris)


func _all_mesh(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
