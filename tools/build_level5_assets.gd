extends SceneTree

# 第5关「沉没大教堂」环境资产：程序化低模 → 导出 GLB → 同帧渲染等距预览
# 用法: godot --path . --resolution 900x900 --script res://tools/build_level5_assets.gd -- <key>
#   key ∈ nave | altar | cage | choir
# 约定: 模型底部中心为原点(+Y 向上)，正面朝 +X，单位米

const OUT_ROOT := "res://art/environments/"

const MATS := {
	"stone": {"color": Color(0.71, 0.70, 0.65), "rough": 0.82, "metal": 0.0, "alpha": 1.0},
	"stone_dark": {"color": Color(0.41, 0.41, 0.42), "rough": 0.70, "metal": 0.05, "alpha": 1.0},
	"stone_wet": {"color": Color(0.46, 0.47, 0.44), "rough": 0.55, "metal": 0.05, "alpha": 1.0},
	"stone_deep": {"color": Color(0.17, 0.17, 0.18), "rough": 0.85, "metal": 0.0, "alpha": 1.0},
	"wood": {"color": Color(0.19, 0.15, 0.11), "rough": 0.90, "metal": 0.0, "alpha": 1.0},
	"iron": {"color": Color(0.28, 0.27, 0.26), "rough": 0.62, "metal": 0.75, "alpha": 1.0},
	"water": {"color": Color(0.34, 0.39, 0.38), "rough": 0.16, "metal": 0.0, "alpha": 1.0},
	"wax": {"color": Color(0.74, 0.69, 0.57), "rough": 0.45, "metal": 0.0, "alpha": 1.0},
	"gauze": {"color": Color(0.74, 0.72, 0.66), "rough": 0.88, "metal": 0.0, "alpha": 0.34},
}

var _asset := "nave"
var _surf := {}
var _root: Node3D
var _vp: SubViewport
var _pending_setup := false
var _frame_n := 0


# ---------------------------------------------------------------- mesh plumbing

func _st(key: String) -> SurfaceTool:
	if not _surf.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surf[key] = s
	return _surf[key]


func _hash01(p: Vector3) -> float:
	var h := sin(p.dot(Vector3(12.9898, 78.233, 37.719)) * 1.7) * 43758.5453
	return h - floor(h)


## 顶点色当作 albedo 的乘法调制：随机斑驳 + 贴近地面偏湿绿、上半偏干
func _tint(p: Vector3, amt: float, wet := true) -> Color:
	var n := _hash01(p)
	var v := 1.0 + (n - 0.5) * amt
	if not wet:
		return Color(v, v, v)
	var damp := clampf(1.0 - p.y / 2.4, 0.0, 1.0)
	return Color(v * (1.0 - 0.14 * damp), v * (1.0 - 0.03 * damp), v * (1.0 - 0.20 * damp))


func _tri(key: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv: Vector2, col: Color) -> void:
	var s := _st(key)
	var pts := [a, b, c]
	for i in 3:
		s.set_color(col)
		s.set_normal(n)
		s.set_uv(uv + Vector2(float(i) * 0.13, float(i) * 0.07))
		s.add_vertex(pts[i])


func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	var uv := Vector2(a.x + a.z, a.y) * 0.35
	_tri(key, a, b, c, n, uv, col)
	_tri(key, a, c, d, n, uv, col)


const BOX_FACES := [
	[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
	[Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)],
	[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
	[Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)],
	[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
	[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
]


func _box_world(key: String, xf: Transform3D, size: Vector3, amt := 0.16, wet := true) -> void:
	var h := size * 0.5
	for f in BOX_FACES:
		var lp: Array = []
		for k in 4:
			lp.append((f[k] as Vector3) * h)
		var wp: Array = []
		for k in 4:
			wp.append(xf * (lp[k] as Vector3))
		var e1: Vector3 = (wp[1] as Vector3) - (wp[0] as Vector3)
		var e2: Vector3 = (wp[2] as Vector3) - (wp[1] as Vector3)
		var fn := e1.cross(e2).normalized()
		var mid: Vector3 = ((wp[0] as Vector3) + (wp[2] as Vector3)) * 0.5
		var out_dir := (mid - xf.origin)
		if out_dir.length() > 0.0001 and fn.dot(out_dir) < 0.0:
			fn = -fn
		_quad(key, wp[0], wp[1], wp[2], wp[3], fn, _tint(mid, amt, wet))


func _box(key: String, center: Vector3, size: Vector3, amt := 0.16, wet := true) -> void:
	_box_world(key, Transform3D(Basis(), center), size, amt, wet)


func _lbox(key: String, xf: Transform3D, c: Vector3, s: Vector3) -> void:
	_box_world(key, xf * Transform3D(Basis(), c), s)


## 局部平面里的斜梁：p0/p1 用局部 (u,v,w) 坐标，wf=面内厚度，df=出平面厚度
func _lbeam(key: String, xf: Transform3D, p0: Vector3, p1: Vector3, wf: float, df: float, amt := 0.12) -> void:
	var dir := p1 - p0
	var L := dir.length()
	if L < 0.0005:
		return
	var ang := atan2(dir.y, dir.x)
	var t := Transform3D(Basis(Vector3(0, 0, 1), ang), (p0 + p1) * 0.5)
	_box_world(key, xf * t, Vector3(L, wf, df), amt)


## 世界空间斜梁（截面近似圆，用于铁笼肋与锁链）
func _beam(key: String, a: Vector3, b: Vector3, wf: float, df: float, amt := 0.16) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 0.0005:
		return
	var d3 := dir / L
	var ref := Vector3(0, 0, 1) if absf(d3.z) < 0.9 else Vector3(1, 0, 0)
	var u := d3.cross(ref).normalized()
	var vv := u.cross(d3).normalized()
	_box_world(key, Transform3D(Basis(d3, vv, u), (a + b) * 0.5), Vector3(L, wf, df), amt)


func _cyl(key: String, a: Vector3, b: Vector3, r0: float, r1: float, sides := 8, amt := 0.14) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 0.0005:
		return
	var d3 := dir / L
	var ref := Vector3(0, 1, 0) if absf(d3.y) < 0.9 else Vector3(1, 0, 0)
	var u := ref.cross(d3).normalized()
	var vv := d3.cross(u).normalized()
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var d0 := u * cos(a0) + vv * sin(a0)
		var d1 := u * cos(a1) + vv * sin(a1)
		var p0 := a + d0 * r0
		var p1 := a + d1 * r0
		var p2 := b + d1 * r1
		var p3 := b + d0 * r1
		var fn := (p1 - p0).cross(p2 - p1).normalized()
		_quad(key, p0, p1, p2, p3, fn, _tint((p0 + p2) * 0.5, amt))
	if r0 > 0.0005:
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var q0 := a + (u * cos(a0) + vv * sin(a0)) * r0
			var q1 := a + (u * cos(a1) + vv * sin(a1)) * r0
			_tri(key, a, q0, q1, -d3, Vector2.ZERO, _tint(a, amt))
	if r1 > 0.0005:
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var q0 := b + (u * cos(a0) + vv * sin(a0)) * r1
			var q1 := b + (u * cos(a1) + vv * sin(a1)) * r1
			_tri(key, b, q1, q0, d3, Vector2.ZERO, _tint(b, amt))


func _frame(u: Vector3, v: Vector3, origin: Vector3) -> Transform3D:
	var uu := u.normalized()
	var vv := (v - uu * uu.dot(v)).normalized()
	var ww := uu.cross(vv)
	return Transform3D(Basis(uu, vv, ww), origin)


# ---------------------------------------------------------------- arch helpers

## 等边尖拱：返回跨中相对拱脚的升起高度（u 以跨中为 0）
func _lancet(u: float, span: float) -> float:
	var half := span * 0.5
	if absf(u) >= half:
		return 0.0
	var R := span
	if u <= 0.0:
		var d := u - half
		return sqrt(maxf(R * R - d * d, 0.0))
	var d2 := u + half
	return sqrt(maxf(R * R - d2 * d2, 0.0))


## 在局部平面里造一段带尖拱洞口的墙板：panel_w 为墙板全宽，open_w 为洞口宽
func _arch_wall(key: String, xf: Transform3D, panel_w: float, open_w: float, sill: float,
		top: float, thickness: float, ring: bool, slices := 16) -> void:
	var apex := sill + _lancet(0.0, open_w)
	# 窗台以下
	if sill > 0.001:
		_lbox(key, xf, Vector3(0, sill * 0.5, 0), Vector3(panel_w, sill, thickness))
	# 两侧墙垛
	var jamb := (panel_w - open_w) * 0.5
	if jamb > 0.01:
		var hst := top - sill
		_lbox(key, xf, Vector3(-(open_w + jamb) * 0.5, sill + hst * 0.5, 0), Vector3(jamb, hst, thickness))
		_lbox(key, xf, Vector3((open_w + jamb) * 0.5, sill + hst * 0.5, 0), Vector3(jamb, hst, thickness))
	# 拱腹填充（砌到拱线以上）
	if top > apex:
		var step := open_w / float(slices)
		for i in slices:
			var u0 := -open_w * 0.5 + float(i) * step
			var u1 := u0 + step
			var hh := maxf(_lancet(u0, open_w), _lancet(u1, open_w))
			if apex - hh > 0.02:
				_lbox(key, xf, Vector3((u0 + u1) * 0.5, (hh + apex) * 0.5, 0),
						Vector3(step, apex - hh, thickness))
		_lbox(key, xf, Vector3(0, (apex + top) * 0.5, 0), Vector3(panel_w, top - apex, thickness))
	# 券石环（略凸出墙面）
	if ring:
		var seg := 20
		for i in seg:
			var t0 := float(i) / float(seg)
			var t1 := float(i + 1) / float(seg)
			var uu0 := lerpf(-open_w * 0.5, open_w * 0.5, t0)
			var uu1 := lerpf(-open_w * 0.5, open_w * 0.5, t1)
			var p0 := Vector3(uu0, sill + _lancet(uu0, open_w), 0)
			var p1 := Vector3(uu1, sill + _lancet(uu1, open_w), 0)
			_lbeam(key, xf, p0, p1, 0.15, thickness * 1.10, 0.10)


# ---------------------------------------------------------------- 1. 中殿

func _build_nave() -> void:
	var L := 12.0
	var W := 9.6
	var wall_h := 7.2
	var col_h := 5.3
	var bays := 3
	var bay := L / float(bays)
	var ax := W * 0.5 - 0.55

	# 地面：分块石板
	_box("stone_wet", Vector3(0, -0.25, L * 0.5), Vector3(W, 0.5, L))
	var tile := 1.55
	for ix in int(W / tile):
		for iz in int(L / tile):
			var tx := -W * 0.5 + tile * (float(ix) + 0.5)
			var tz := tile * (float(iz) + 0.5)
			_box("stone_wet", Vector3(tx, 0.005, tz), Vector3(tile - 0.06, 0.05, tile - 0.06), 0.22)
	# 积水
	for i in 6:
		var px := lerpf(-W * 0.42, W * 0.42, _hash01(Vector3(float(i), 1.7, 5.1)))
		var pz := lerpf(1.4, L - 1.4, _hash01(Vector3(float(i), 8.2, 2.3)))
		var sx := 1.7 + _hash01(Vector3(float(i), 3.3, 7.7)) * 2.0
		var sz := 1.6 + _hash01(Vector3(float(i), 6.1, 1.9)) * 2.4
		_box("water", Vector3(px, 0.042, pz), Vector3(sx, 0.012, sz), 0.02, false)

	# -X 侧墙：三开间，每间一扇尖拱窗
	var wall_xf := _frame(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-W * 0.5 + 0.42, 0, 0))
	for b in bays:
		var zc := bay * (float(b) + 0.5)
		_arch_wall("stone", wall_xf * Transform3D(Basis(), Vector3(zc, 0, 0)),
				bay, bay * 0.46, 3.1, wall_h, 0.84, true)
	_lbox("stone", wall_xf, Vector3(0, 0.34, L * 0.5), Vector3(1.10, 0.68, L))
	_lbox("stone", wall_xf, Vector3(0, wall_h - 0.16, L * 0.5), Vector3(1.22, 0.32, L))
	for b in bays + 1:
		var z := bay * float(b)
		_lbox("stone", wall_xf, Vector3(0, (wall_h - 0.4) * 0.5, z),
				Vector3(1.62, wall_h - 0.4, 0.80))

	# +X 侧开敞拱廊：束柱 + 尖拱（中间一柱断裂）
	for b in bays + 1:
		var z := bay * float(b)
		var broken := b == 1
		var h := 2.1 if broken else col_h
		_cyl("stone", Vector3(ax, 0.0, z), Vector3(ax, h, z), 0.34, 0.30, 8)
		for k in 4:
			var ang := TAU * float(k) / 4.0 + PI * 0.25
			var off := Vector3(cos(ang), 0, sin(ang)) * 0.30
			_cyl("stone", Vector3(ax, 0.0, z) + off, Vector3(ax, h, z) + off, 0.13, 0.12, 6)
		_box("stone", Vector3(ax, 0.16, z), Vector3(0.96, 0.32, 0.96), 0.12)
		if broken:
			_box("stone", Vector3(ax, h + 0.04, z), Vector3(0.58, 0.10, 0.58), 0.22)
		else:
			_box("stone", Vector3(ax, h - 0.16, z), Vector3(0.92, 0.32, 0.92), 0.12)

	var arc_xf := _frame(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(ax, 0, 0))
	var arch_span := bay * 0.94
	for b in bays:
		var zc := bay * (float(b) + 0.5)
		for i in 16:
			var t0 := float(i) / 16.0
			var t1 := float(i + 1) / 16.0
			var u0 := lerpf(-arch_span * 0.5, arch_span * 0.5, t0)
			var u1 := lerpf(-arch_span * 0.5, arch_span * 0.5, t1)
			if b == 1 and i > 12:
				continue
			_lbeam("stone", arc_xf, Vector3(zc + u0, col_h + _lancet(u0, arch_span) * 0.46, 0),
					Vector3(zc + u1, col_h + _lancet(u1, arch_span) * 0.46, 0), 0.34, 0.56, 0.12)
	# 拱廊拱脚线脚
	_lbox("stone", arc_xf, Vector3(L * 0.5, col_h + 0.06, 0), Vector3(L, 0.20, 0.78))

	# 碎石
	for i in 12:
		var t := float(i) / 12.0
		var px := lerpf(-W * 0.40, W * 0.42, _hash01(Vector3(t * 7.0, 3.1, 1.7)))
		var pz := lerpf(0.8, L - 0.8, _hash01(Vector3(t * 3.3, 9.2, 5.5)))
		var s := 0.22 + _hash01(Vector3(px, pz, 1.0)) * 0.32
		_box("stone", Vector3(px, s * 0.32 + 0.02, pz), Vector3(s * 1.5, s, s * 1.2), 0.24)


# ---------------------------------------------------------------- 2. 主教祭坛

func _build_altar() -> void:
	# 只在正面(+X)探出的两级台阶
	_box("stone_dark", Vector3(0.30, 0.075, 0), Vector3(2.50, 0.15, 1.30), 0.20)
	_box("stone_dark", Vector3(0.15, 0.225, 0), Vector3(2.42, 0.15, 1.24), 0.20)
	# 台座
	_box("stone_dark", Vector3(0.0, 0.57, 0), Vector3(2.16, 0.54, 1.16), 0.22)
	# 台座正面凹龛（三条，无字）
	for i in 3:
		_box("stone_deep", Vector3(1.070, 0.57, -0.34 + float(i) * 0.34), Vector3(0.015, 0.28, 0.20), 0.08)
	# 收分线脚 + 台面石板（出檐）
	_box("stone_dark", Vector3(0.0, 0.89, 0), Vector3(2.30, 0.10, 1.24), 0.16)
	_box("stone_dark", Vector3(0.0, 1.02, 0), Vector3(2.44, 0.16, 1.30), 0.18)
	_box("stone_dark", Vector3(0.0, 1.105, 0), Vector3(2.34, 0.03, 1.20), 0.10)
	# 角部小柱（贴着台座）
	for cx in [-1.07, 1.07]:
		for cz in [-0.57, 0.57]:
			_box("stone_dark", Vector3(cx, 0.57, cz), Vector3(0.15, 0.56, 0.15), 0.10)
			_box("stone_dark", Vector3(cx, 1.115, cz), Vector3(0.20, 0.09, 0.20), 0.08)
			_box("stone_dark", Vector3(cx, 0.30, cz), Vector3(0.21, 0.10, 0.21), 0.08)
	# 磕损的边角
	_box("stone_deep", Vector3(-1.20, 1.10, 0.62), Vector3(0.10, 0.05, 0.10), 0.10)
	_box("stone_deep", Vector3(1.16, 1.10, -0.60), Vector3(0.12, 0.04, 0.08), 0.10)
	# 台面刻槽（凹入的暗线）
	for i in 4:
		_box("stone_deep", Vector3(0.0, 1.123, -0.30 + float(i) * 0.20), Vector3(1.70, 0.008, 0.024), 0.05)
	_box("stone_deep", Vector3(0.0, 1.123, 0.0), Vector3(0.024, 0.008, 0.90), 0.05)
	# 蜡泪：从台面边缘垂下
	for z in [-0.48, -0.30, -0.09, 0.13, 0.32, 0.50]:
		var len_v := 0.10 + _hash01(Vector3(z, 1.3, 2.0)) * 0.20
		var thick := 0.014 + _hash01(Vector3(z, 4.0, 1.0)) * 0.014
		_beam("wax", Vector3(1.222, 0.94, z), Vector3(1.222, 0.94 - len_v, z), thick, thick, 0.10)
		_box("wax", Vector3(1.214, 0.935, z), Vector3(0.034, 0.036, thick * 1.7), 0.10)
	# 台阶上的凝蜡
	_box("wax", Vector3(1.30, 0.012, 0.24), Vector3(0.20, 0.02, 0.14), 0.10, false)


# ---------------------------------------------------------------- 3. 铁笼

func _build_cage() -> void:
	var half := 0.75
	var body_h := 2.0
	var ring_h := 2.80
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half),
			Vector3(half, 0, half), Vector3(-half, 0, half)]
	# 底框
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		_beam("iron", a, b, 0.085, 0.085, 0.10)
		_beam("iron", a + Vector3(0, 0.075, 0), b + Vector3(0, 0.075, 0), 0.05, 0.05, 0.10)
	for i in 4:
		var t := -half + 0.375 * float(i)
		_beam("iron", Vector3(-half, 0.03, t), Vector3(half, 0.03, t), 0.04, 0.05, 0.08)
	# 竖条
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		_cyl("iron", a, a + Vector3(0, body_h, 0), 0.045, 0.045, 6)
		for i in range(1, 4):
			var p: Vector3 = a.lerp(b, float(i) / 4.0)
			_cyl("iron", p, p + Vector3(0, body_h, 0), 0.032, 0.032, 6)
	# 横箍
	for h in [0.62, 1.32, body_h]:
		for k in 4:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 4]
			_beam("iron", a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.06, 0.06, 0.08)
	# 笼门（+X 面）
	var dc := Vector3(half, 0, 0)
	_beam("iron", dc + Vector3(0, 0.06, -0.30), dc + Vector3(0, 0.06, 0.30), 0.07, 0.07, 0.08)
	_beam("iron", dc + Vector3(0, body_h - 0.06, -0.30), dc + Vector3(0, body_h - 0.06, 0.30), 0.07, 0.07, 0.08)
	for i in 3:
		var z := -0.15 + float(i) * 0.15
		_cyl("iron", dc + Vector3(0, 0.06, z), dc + Vector3(0, body_h - 0.06, z), 0.028, 0.028, 6)
	for h in [0.45, 1.10, 1.70]:
		_beam("iron", dc + Vector3(0.02, h, -0.30), dc + Vector3(0.02, h, 0.30), 0.05, 0.05, 0.08)
	_box("iron", Vector3(half + 0.05, 1.05, 0.06), Vector3(0.10, 0.30, 0.07), 0.10)
	_cyl("iron", Vector3(half + 0.03, 1.22, 0.06), Vector3(half + 0.20, 1.22, 0.10), 0.022, 0.022, 6)
	# 穹顶：8 根肋（角部 + 边中）向顶点收拢，两圈环箍
	var apex := Vector3(0, ring_h, 0)
	var dome_base := []
	for k in 4:
		dome_base.append(corners[k])
		dome_base.append((corners[k] + corners[(k + 1) % 4]) * 0.5)
	for bp in dome_base:
		var p0: Vector3 = bp
		var seg := 5
		for i in seg:
			var t0 := float(i) / float(seg)
			var t1 := float(i + 1) / float(seg)
			var c0 := p0.lerp(apex, t0) + Vector3(0, sin(t0 * PI) * 0.10, 0)
			var c1 := p0.lerp(apex, t1) + Vector3(0, sin(t1 * PI) * 0.10, 0)
			_beam("iron", c0, c1, 0.040, 0.040, 0.08)
	for frac in [0.38, 0.72]:
		for k in 8:
			var p0: Vector3 = dome_base[k]
			var p1: Vector3 = dome_base[(k + 1) % 8]
			var a0 := p0.lerp(apex, frac) + Vector3(0, sin(frac * PI) * 0.10, 0)
			var a1 := p1.lerp(apex, frac) + Vector3(0, sin(frac * PI) * 0.10, 0)
			_beam("iron", a0, a1, 0.030, 0.030, 0.08)
	# 顶部吊环 + 吊钩 + 锁链
	_cyl("iron", Vector3(0, ring_h, 0), Vector3(0, ring_h + 0.18, 0), 0.075, 0.055, 8)
	var hy := ring_h + 0.32
	for k in 8:
		var a0 := TAU * float(k) / 8.0
		var a1 := TAU * float(k + 1) / 8.0
		_beam("iron", Vector3(cos(a0) * 0.14, hy + sin(a0) * 0.14, 0),
				Vector3(cos(a1) * 0.14, hy + sin(a1) * 0.14, 0), 0.045, 0.045, 0.08)
	var ly := hy + 0.14
	for i in 6:
		var c := Vector3(0, ly + 0.17 * float(i) + 0.09, 0)
		var rot := Basis(Vector3(0, 1, 0), PI * 0.5 * float(i % 2))
		for k in 6:
			var a0 := TAU * float(k) / 6.0
			var a1 := TAU * float(k + 1) / 6.0
			var p0 := c + rot * Vector3(cos(a0) * 0.075, sin(a0) * 0.115, 0)
			var p1 := c + rot * Vector3(cos(a1) * 0.075, sin(a1) * 0.115, 0)
			_beam("iron", p0, p1, 0.032, 0.032, 0.06)
	# 外侧纱幔：从穹顶下垂
	_hang_veil(Vector3(0.05, 2.55, 0.80), Vector3(0.02, 0.75, 0.88), Vector3(0.32, 0, 0))
	_hang_veil(Vector3(0.80, 2.35, -0.10), Vector3(0.88, 1.05, -0.05), Vector3(0, 0, 0.26))


func _hang_veil(top: Vector3, bottom: Vector3, side: Vector3) -> void:
	var nrm := (top - bottom).cross(side).normalized()
	var rows := 4
	for r in rows:
		var t0 := float(r) / float(rows)
		var t1 := float(r + 1) / float(rows)
		var a0 := top.lerp(bottom, t0)
		var a1 := top.lerp(bottom, t1)
		var w0 := sin(t0 * PI) * 0.05
		var w1 := sin(t1 * PI) * 0.05
		_quad("gauze", a0 - side + nrm * w0, a0 + side + nrm * w0,
				a1 + side + nrm * w1, a1 - side + nrm * w1, nrm, Color(1, 1, 1))


# ---------------------------------------------------------------- 4. 唱诗班楼上层

func _build_choir() -> void:
	var W := 2.6
	var L := 6.4
	var deck := 0.38
	var front_x := W * 0.5 - 0.14
	var back_x := -W * 0.5 + 0.14
	_box("stone", Vector3(0, deck * 0.5, 0), Vector3(W, deck, L), 0.16)
	_box("stone", Vector3(0, -0.02, 0), Vector3(W * 0.94, 0.10, L * 0.98), 0.14)
	for i in 5:
		_box("stone", Vector3(0, -0.10, -L * 0.42 + float(i) * L * 0.21), Vector3(W * 0.92, 0.14, 0.16), 0.12)
	# 前侧栏杆
	var rail_top := deck + 1.04
	_box("stone", Vector3(front_x, deck + 0.07, 0), Vector3(0.30, 0.14, L), 0.14)
	_box("stone", Vector3(front_x, rail_top, 0), Vector3(0.36, 0.16, L), 0.14)
	var n := 9
	var pitch := L / float(n)
	for i in n + 1:
		var z := -L * 0.5 + pitch * float(i)
		_cyl("stone", Vector3(front_x, deck + 0.14, z), Vector3(front_x, rail_top - 0.08, z), 0.075, 0.065, 6)
		_box("stone", Vector3(front_x, deck + 0.17, z), Vector3(0.20, 0.08, 0.20), 0.10)
	# 栏板小尖拱
	var rail_xf := _frame(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(front_x, 0, 0))
	for i in n:
		var zc := -L * 0.5 + pitch * (float(i) + 0.5)
		var span := pitch * 0.88
		var base := deck + 0.24
		for k in 5:
			var t0 := float(k) / 5.0
			var t1 := float(k + 1) / 5.0
			var u0 := lerpf(-span * 0.5, span * 0.5, t0)
			var u1 := lerpf(-span * 0.5, span * 0.5, t1)
			_lbeam("stone", rail_xf, Vector3(zc + u0, base + _lancet(u0, span) * 0.82, 0),
					Vector3(zc + u1, base + _lancet(u1, span) * 0.82, 0), 0.09, 0.24, 0.08)
	# 后端拱壁：三个尖拱开口
	var wall_h := 4.30
	var wall_xf := _frame(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(back_x, 0, 0))
	var bay := L / 3.0
	for b in 3:
		var zc := -L * 0.5 + bay * (float(b) + 0.5)
		_arch_wall("stone", wall_xf * Transform3D(Basis(), Vector3(zc, deck, 0)),
				bay, bay * 0.66, 1.90, wall_h, 0.52, true)
	_box("stone", Vector3(back_x, deck + 0.30, 0), Vector3(0.72, 0.60, L), 0.14)
	_box("stone", Vector3(back_x, wall_h - 0.12, 0), Vector3(0.80, 0.24, L), 0.14)
	# 端头收边
	for s in [-1.0, 1.0]:
		var z: float = s * (L * 0.5 - 0.11)
		_box("stone", Vector3(0, deck + 0.07, z), Vector3(W, 0.14, 0.26), 0.14)
		_box("stone", Vector3(front_x - 0.04, rail_top, z), Vector3(0.40, 0.34, 0.34), 0.14)
	# 木质唱诗席：两段连续长凳，靠背断续，右段凳面断裂
	var seat_x := back_x + 0.88
	for seg in 2:
		var z0 := -L * 0.40 + float(seg) * L * 0.42
		var seg_len := L * 0.34
		var zc := z0 + seg_len * 0.5
		_box("wood", Vector3(seat_x, deck + 0.46, zc), Vector3(0.60, 0.09, seg_len), 0.18)
		_box("wood", Vector3(seat_x + 0.12, deck + 0.40, zc), Vector3(0.10, 0.16, seg_len), 0.16)
		# 靠背只保留中段，两端塌掉
		_box("wood", Vector3(seat_x - 0.26, deck + 0.76, zc), Vector3(0.10, 0.62, seg_len * 0.72), 0.18)
		_box("wood", Vector3(seat_x - 0.26, deck + 1.10, zc), Vector3(0.15, 0.09, seg_len * 0.78), 0.16)
		# 扶手（分隔座位）
		for k in 3:
			var zz := z0 + seg_len * (float(k) / 2.0)
			_box("wood", Vector3(seat_x - 0.04, deck + 0.62, zz), Vector3(0.58, 0.34, 0.07), 0.16)
	# 断裂的一小截凳面斜置在地上
	_box("wood", Vector3(seat_x + 0.30, deck + 0.52, -L * 0.02), Vector3(0.50, 0.08, 0.34), 0.22)
	_box("wood", Vector3(seat_x + 0.44, deck + 0.60, -L * 0.02), Vector3(0.10, 0.20, 0.34), 0.22)


# ---------------------------------------------------------------- export + preview

func _build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys := _surf.keys()
	keys.sort()
	for key in keys:
		var s: SurfaceTool = _surf[key]
		var arr := s.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _make_mat(key))
	return mesh


func _make_mat(key: String) -> StandardMaterial3D:
	var d: Dictionary = MATS[key]
	var m := StandardMaterial3D.new()
	var c: Color = d["color"]
	m.albedo_color = Color(c.r, c.g, c.b, d["alpha"])
	m.roughness = d["rough"]
	m.metallic = d["metal"]
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	if float(d["alpha"]) < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _name_cn() -> String:
	match _asset:
		"nave":
			return "沉没大教堂中殿"
		"altar":
			return "主教祭坛"
		"cage":
			return "悬挂圣徒铁笼"
		"choir":
			return "唱诗班楼上层"
	return _asset


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_asset = a[0]
	_vp = SubViewport.new()
	_vp.size = Vector2i(900, 900)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_vp)
	_root = Node3D.new()
	_root.name = _name_cn()
	_vp.add_child(_root)

	match _asset:
		"nave":
			_build_nave()
		"altar":
			_build_altar()
		"cage":
			_build_cage()
		"choir":
			_build_choir()
		_:
			print("unknown asset ", _asset)
			quit(1)
			return

	var mesh := _build_mesh()
	var mi := MeshInstance3D.new()
	mi.name = _asset + "_mesh"
	mi.mesh = mesh
	_root.add_child(mi)

	var tr := 0
	for i in mesh.get_surface_count():
		tr += int(mesh.surface_get_array_len(i) / 3.0)
	print("ASSET ", _asset, " surfaces=", mesh.get_surface_count(), " tris≈", tr)

	var dir := OUT_ROOT + _name_cn() + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(_root, state)
	if err != OK:
		print("APPEND FAIL ", err)
		quit(1)
		return
	err = doc.write_to_filesystem(state, dir + _name_cn() + ".glb")
	print("GLB err=", err, " -> ", dir + _name_cn() + ".glb")

	# 与游戏相机同口径：yaw 45° / pitch -55°、正交投影
	_pending_setup = true


func _setup_render() -> void:
	var mi: MeshInstance3D = _root.get_child(0)
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.1
	cam.far = 300.0
	var aabb := mi.get_aabb()
	var center := aabb.get_center()
	var cb := Basis.from_euler(Vector3(deg_to_rad(-45.0), deg_to_rad(45.0), 0.0))
	var inv := cb.inverse()
	var hx := 0.0
	var hy := 0.0
	for ci in 8:
		var corner := aabb.position + Vector3(
			aabb.size.x * float(ci & 1), aabb.size.y * float((ci >> 1) & 1), aabb.size.z * float((ci >> 2) & 1))
		var rel := inv * (corner - center)
		hx = maxf(hx, absf(rel.x))
		hy = maxf(hy, absf(rel.y))
	cam.size = 2.0 * maxf(hx, hy) * 1.08
	cam.transform = Transform3D(cb, center + cb.z * 60.0)
	cam.current = true

	var l1 := DirectionalLight3D.new()
	_root.add_child(l1)
	l1.transform = Transform3D(Basis(), Vector3(5.5, 7.0, 6.0)).looking_at(Vector3.ZERO, Vector3.UP)
	l1.light_energy = 2.2
	var l2 := DirectionalLight3D.new()
	_root.add_child(l2)
	l2.transform = Transform3D(Basis(), Vector3(-6.0, 2.4, -5.0)).looking_at(Vector3.ZERO, Vector3.UP)
	l2.light_energy = 0.45
	l2.light_color = Color(0.70, 0.79, 0.95)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.169, 0.184, 0.224)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.80, 0.84, 0.94)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 0.55
	e.ssao_intensity = 1.4
	we.environment = e
	_root.add_child(we)


func _process(_d: float) -> bool:
	_frame_n += 1
	if _frame_n == 2 and _pending_setup:
		_pending_setup = false
		_setup_render()
		return false
	if _frame_n == 12:
		var p := OUT_ROOT + _name_cn() + "/模型预览.png"
		_vp.get_texture().get_image().save_png(p)
		print("PREVIEW ", p)
		return true
	return false
