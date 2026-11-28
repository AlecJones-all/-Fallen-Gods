extends SceneTree

# 斧刃轮廓：现版 vs 两个新版（只读，不碰场景）
# 用法: godot --path . --script res://tools/_axe_blades.gd
# 产物: docs/19_武器模型/review/sheet_axe_blade.png

const OUT_DIR := "res://docs/19_武器模型/review"
const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

const HANDLE_BOT := -0.30
const PIVOT_ROT := Vector3(90, 0, 0)  # 与场景里 AxePivot 一致

# 新版轮廓用参数生成：eye_top / horn / edge_bottom / eye_bottom + 三段弧的鼓度
const SPECS := [
	{
		"name": "现版（对照）",
		"note": "柄轴→刃口 0.42 · 刃口弧高 0.17 → 像菜刀",
		"raw": [
			Vector2(-0.035, 0.560), Vector2(0.160, 0.542), Vector2(0.310, 0.572),
			Vector2(0.412, 0.628), Vector2(0.438, 0.700), Vector2(0.372, 0.800),
			Vector2(0.200, 0.872), Vector2(-0.035, 0.898),
		],
	},
	{
		"name": "新版 A 胡须斧",
		"note": "柄轴→刃口 0.24 · 刃口高 0.34 · 下挂胡须",
		"spec": {
			"eye_top": Vector2(-0.035, 0.600),
			"horn": Vector2(0.190, 0.678),
			"edge_bottom": Vector2(0.216, 0.348),
			"eye_bottom": Vector2(-0.035, 0.452),
			"bulge_top": -0.018,
			"bulge_edge": 0.050,
			"bulge_beard": -0.038,
		},
	},
	{
		"name": "新版 B 窄刃",
		"note": "柄轴→刃口 0.19 · 刃口高 0.30 · 更轻快",
		"spec": {
			"eye_top": Vector2(-0.035, 0.586),
			"horn": Vector2(0.152, 0.652),
			"edge_bottom": Vector2(0.176, 0.352),
			"eye_bottom": Vector2(-0.035, 0.450),
			"bulge_top": -0.012,
			"bulge_edge": 0.042,
			"bulge_beard": -0.030,
		},
	},
]

var _cells: Array[Node3D] = []
var _pivots: Array[Node3D] = []
var _cam: Camera3D
var _lname: Label3D
var _lnote: Label3D
var _lrow: Label3D
var _frame := 0
var _i := 0
var _pending := false
var _mat := {}
var _composed := false
var _profiles: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_materials()

	for sp in SPECS:
		if sp.has("raw"):
			_profiles.append(sp["raw"])
		else:
			_profiles.append(_profile_from(sp["spec"]))

	var stage := Node3D.new()
	get_root().add_child(stage)
	for i in SPECS.size():
		var cell := Node3D.new()
		stage.add_child(cell)
		_cells.append(cell)
		var pivot := Node3D.new()
		pivot.rotation_degrees = PIVOT_ROT
		cell.add_child(pivot)
		_pivots.append(pivot)
		_build_axe(pivot, i)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.105, 0.10, 0.093)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.73, 0.79)
	env.ambient_light_energy = 1.0
	we.environment = env
	get_root().add_child(we)

	for l in [
		[Vector3(-30, -35, 0), 2.4, Color(1, 1, 1)],
		[Vector3(-10, 140, 0), 1.1, Color(1, 1, 1)],
		[Vector3(-160, 200, 0), 1.3, Color(0.92, 0.95, 1.0)],
	]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_energy = l[1]
		dl.light_color = l[2]
		get_root().add_child(dl)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)

	_lname = Label3D.new()
	_lname.font = load(FONT)
	_lname.font_size = 40
	_lname.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lname.modulate = Color(0.97, 0.94, 0.87)
	_lname.no_depth_test = true
	_lname.render_priority = 10
	_cam.add_child(_lname)

	_lnote = Label3D.new()
	_lnote.font = load(FONT)
	_lnote.font_size = 21
	_lnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lnote.modulate = Color(0.70, 0.70, 0.66)
	_lnote.no_depth_test = true
	_lnote.render_priority = 10
	_cam.add_child(_lnote)

	_lrow = Label3D.new()
	_lrow.font = load(FONT)
	_lrow.font_size = 19
	_lrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lrow.modulate = Color(0.55, 0.56, 0.54)
	_lrow.no_depth_test = true
	_lrow.render_priority = 10
	_cam.add_child(_lrow)


## 由 4 个关键点 + 三段弧生成闭合轮廓
func _profile_from(sp: Dictionary) -> Array:
	var eye_top: Vector2 = sp["eye_top"]
	var horn: Vector2 = sp["horn"]
	var edge_bottom: Vector2 = sp["edge_bottom"]
	var eye_bottom: Vector2 = sp["eye_bottom"]
	var out: Array = [eye_top]
	out.append_array(_arc(eye_top, horn, float(sp["bulge_top"]), 3))
	out.append_array(_arc(horn, edge_bottom, float(sp["bulge_edge"]), 7))
	out.append_array(_arc(edge_bottom, eye_bottom, float(sp["bulge_beard"]), 6))
	out.append(eye_bottom)
	return out


## 二次曲线取点（不含两端）
func _arc(a: Vector2, b: Vector2, bulge: float, n: int) -> Array:
	var d := b - a
	var perp := Vector2(-d.y, d.x).normalized()
	var ctrl := (a + b) * 0.5 + perp * bulge
	var out: Array = []
	for i in range(1, n):
		var t := float(i) / float(n)
		var p1 := a.lerp(ctrl, t)
		var p2 := ctrl.lerp(b, t)
		out.append(p1.lerp(p2, t))
	return out


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	var total := SPECS.size() * 3
	if _i >= total:
		if not _composed:
			_composed = true
			_compose()
		return true

	var ci := _i / 3
	var vi := _i % 3
	if not _pending:
		for k in _cells.size():
			_cells[k].visible = (k == ci)
		var cell: Node3D = _cells[ci]
		var pivot: Node3D = _pivots[ci]
		cell.position = Vector3.ZERO
		pivot.rotation_degrees = Vector3.ZERO if vi != 2 else PIVOT_ROT

		var box := _cell_aabb(cell, "")
		var target := box.get_center()
		var b := Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(45), 0)) if vi == 2 else Basis.IDENTITY
		var view := get_root().get_size()
		var aspect := float(view.x) / maxf(float(view.y), 1.0)
		var need := _fit_size(box, b, aspect) * 1.52
		if vi == 1:
			var head := _cell_aabb(cell, "Blade")
			target = head.get_center()
			need = maxf(head.size.y, head.size.x / aspect) * 1.55
		_cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, 3))
		_cam.size = need
		_lname.text = String(SPECS[ci]["name"])
		_lnote.text = String(SPECS[ci]["note"])
		var s := need * 0.0011
		_lname.pixel_size = s
		_lnote.pixel_size = s
		_lrow.pixel_size = s
		_lname.position = Vector3(-need * 0.45, -need * 0.385, -1.0)
		_lnote.position = Vector3(-need * 0.45, -need * 0.43, -1.0)
		_lrow.text = ["整体剪影", "刃部特写", "实机俯角 55°"][vi]
		_lrow.position = Vector3(-need * 0.45, need * 0.455, -1.0)
		_pending = true
		return false

	var path := "%s/axe_blade_%d_%d.png" % [OUT_DIR, ci, vi]
	get_root().get_texture().get_image().save_png(path)
	_pending = false
	_i += 1
	return false


func _cell_aabb(n: Node3D, only: String) -> AABB:
	var box := AABB()
	var first := true
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		if only != "" and mi.name != only:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _fit_size(box: AABB, b: Basis, aspect: float) -> float:
	var half := box.size * 0.5
	var up := 0.0
	var right := 0.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var v := b.inverse() * Vector3(half.x * sx, half.y * sy, half.z * sz)
				right = maxf(right, absf(v.x))
				up = maxf(up, absf(v.y))
	return maxf(up * 2.0, right * 2.0 / maxf(aspect, 0.01))


# ---------------- 几何 ----------------

func _build_axe(parent: Node3D, idx: int) -> void:
	var root := Node3D.new()
	root.name = "Axe"
	parent.add_child(root)
	var prof: Array = _profiles[idx]

	var ymin := 9.0
	var ymax := -9.0
	for p in prof:
		ymin = minf(ymin, (p as Vector2).y)
		ymax = maxf(ymax, (p as Vector2).y)

	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.020
	cyl.bottom_radius = 0.024
	cyl.height = (ymax - 0.006) - HANDLE_BOT
	cyl.radial_segments = 10
	handle.mesh = cyl
	handle.material_override = _mat["wood"]
	handle.position = Vector3(0, ((ymax - 0.006) + HANDLE_BOT) * 0.5, 0)
	handle.scale = Vector3(1.1, 1.0, 0.88)
	root.add_child(handle)

	for i in 4:
		var w := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.0225
		tm.outer_radius = 0.029
		tm.rings = 10
		tm.ring_segments = 5
		w.mesh = tm
		w.material_override = _mat["rope"]
		w.position = Vector3(0, -0.14 + 0.068 * i, 0)
		w.rotation_degrees = Vector3(90, 0, 0)
		root.add_child(w)

	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	blade.mesh = _blade_mesh(prof)
	blade.material_override = _mat["iron"]
	root.add_child(blade)

	var shim := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.030, 0.016, 0.030)
	shim.mesh = sm
	shim.material_override = _mat["iron_dark"]
	shim.position = Vector3(0, ymax - 0.002, 0)
	root.add_child(shim)

	if idx > 0:
		_beam(root, Vector3(-0.026, 0.512, 0), Vector3(-0.092, 0.544, 0), 0.020, 0.026)
		_beam(root, Vector3(-0.092, 0.544, 0), Vector3(-0.110, 0.592, 0), 0.015, 0.019)


## 剖面挤出 + 倒角：外轮廓 0 厚，往里 78% 是厚脸颊
func _blade_mesh(profile: Array) -> ArrayMesh:
	var pts: Array[Vector2] = []
	for p in profile:
		pts.append(p as Vector2)
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		pts.reverse()

	var n := pts.size()
	var cx := 0.0
	var cy := 0.0
	for p in pts:
		cx += p.x
		cy += p.y
	var c := Vector2(cx / n, cy / n)
	var max_x := 0.0
	for p in pts:
		max_x = maxf(max_x, p.x)

	const INSET := 0.78
	var rim: Array[Vector3] = []
	var cf: Array[Vector3] = []
	var cb: Array[Vector3] = []
	for p in pts:
		var q := c + (p - c) * INSET
		var t := lerpf(0.020, 0.0026, clampf(p.x / maxf(max_x, 0.001), 0.0, 1.0)) * 0.5
		rim.append(Vector3(p.x, p.y, 0.0))
		cf.append(Vector3(q.x, q.y, t))
		cb.append(Vector3(q.x, q.y, -t))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cF := Vector3(c.x, c.y, 0.009)
	var cB := Vector3(c.x, c.y, -0.009)
	for i in n:
		var j := (i + 1) % n
		st.add_vertex(rim[i]); st.add_vertex(cf[j]); st.add_vertex(cf[i])
		st.add_vertex(rim[i]); st.add_vertex(rim[j]); st.add_vertex(cf[j])
		st.add_vertex(rim[i]); st.add_vertex(cb[i]); st.add_vertex(cb[j])
		st.add_vertex(rim[i]); st.add_vertex(cb[j]); st.add_vertex(rim[j])
		st.add_vertex(cF); st.add_vertex(cf[i]); st.add_vertex(cf[j])
		st.add_vertex(cB); st.add_vertex(cb[j]); st.add_vertex(cb[i])
	st.generate_normals()
	return st.commit()


func _beam(parent: Node3D, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var d := b - a
	bm.size = Vector3(w, h, d.length())
	mi.mesh = bm
	mi.material_override = _mat["iron_dark"]
	mi.position = (a + b) * 0.5
	var dir := d.normalized()
	if dir.length_squared() > 0.001:
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		mi.basis = Basis.looking_at(dir, up)
	parent.add_child(mi)


func _build_materials() -> void:
	var base := KitArt.build()
	_mat["iron"] = _obj(base["iron_rust"], Color(1, 1, 1), 7.0)
	_mat["iron_dark"] = _obj(base["iron_rust"], Color(0.58, 0.56, 0.55), 7.0)
	_mat["wood"] = _obj(base["wood_dry"], Color(1.0, 0.96, 0.9), 5.0)
	_mat["rope"] = _obj(base["cloth_rot"], Color(0.85, 0.8, 0.72), 14.0)


func _obj(src: Material, tint: Color, tri: float) -> StandardMaterial3D:
	var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = tint
	m.uv1_world_triplanar = false
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * tri
	return m


# ---------------- 拼图 ----------------

func _compose() -> void:
	var cell := 720
	var cols := SPECS.size()
	var img := Image.create(cell * cols, cell * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.06))
	for ci in cols:
		for vi in 3:
			var p := ProjectSettings.globalize_path("%s/axe_blade_%d_%d.png" % [OUT_DIR, ci, vi])
			var im := Image.load_from_file(p)
			if im == null:
				continue
			var side: int = mini(im.get_width(), im.get_height())
			im = im.get_region(Rect2i((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side))
			im.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
			if im.get_format() != Image.FORMAT_RGBA8:
				im.convert(Image.FORMAT_RGBA8)
			var x := ci * cell
			var y := vi * cell
			img.blit_rect(im, Rect2i(0, 0, cell, cell), Vector2i(x, y))
			for k in cell:
				img.set_pixel(x, y + k, Color(0.24, 0.24, 0.24))
				img.set_pixel(x + k, y, Color(0.24, 0.24, 0.24))
	img.save_png(ProjectSettings.globalize_path("%s/sheet_axe_blade.png" % OUT_DIR))
	print("sheet done")
