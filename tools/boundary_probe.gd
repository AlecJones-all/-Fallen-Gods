extends SceneTree
# 边界探针：拆墙后，隐形碰撞必须仍在原墙线上。直接查碰撞体的覆盖，不靠走动。
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0
var _boxes: Array = []

func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 4:
		return false
	var geo: Node3D = _m.get_node_or_null("World/Geometry") as Node3D
	if geo == null:
		print("BOUNDARY FAIL 无 Geometry")
		return true
	for c: Node in geo.get_children():
		if c is StaticBody3D:
			var body := c as StaticBody3D
			var shape := body.get_child(0) as CollisionShape3D
			if shape == null or not (shape.shape is BoxShape3D):
				continue
			var box := shape.shape as BoxShape3D
			_boxes.append({ "pos": body.position, "size": box.size })

	var checks := [
		{ "name": "x=0 封口线", "axis": "x", "line": 0.0, "from": -7.0, "to": 7.0 },
		{ "name": "z=-7 左石带", "axis": "z", "line": -7.0, "from": 0.0, "to": 12.0 },
		{ "name": "z=+7 右石带", "axis": "z", "line": 7.0, "from": 0.0, "to": 12.0 },
	]
	for chk: Dictionary in checks:
		var line := float(chk["line"])
		var a := float(chk["from"])
		var b := float(chk["to"])
		var step := 2.0
		var total := 0
		var hit := 0
		var t := a + step * 0.5
		while t < b:
			total += 1
			if _covered(String(chk["axis"]), line, t):
				hit += 1
			t += step
		print("BOUNDARY %s  覆盖 %d/%d" % [chk["name"], hit, total])
		if hit < total:
			print("BOUNDARY FAIL %s 有缺口" % chk["name"])
	print("BOUNDARY DONE  碰撞体 %d 个" % _boxes.size())
	return true

func _covered(axis: String, line: float, t: float) -> bool:
	for b: Dictionary in _boxes:
		var p: Vector3 = b["pos"]
		var s: Vector3 = b["size"]
		# axis 指"这条线沿哪个轴恒定"：x 表示 x=line 的竖线（沿 z 铺），z 表示 z=line 的横线（沿 x 铺）
		var across := p.x if axis == "x" else p.z
		var across_half := (s.x if axis == "x" else s.z) * 0.5 + 0.06
		var along := p.z if axis == "x" else p.x
		var along_half := (s.z if axis == "x" else s.x) * 0.5 + 0.06
		if absf(across - line) > across_half:
			continue
		if absf(along - t) > along_half:
			continue
		return true
	return false
