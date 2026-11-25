extends Node3D

## F1 规格预览：读 data/levels/tithe_gate.json，把三区、路面、卡口、地标画成线框。
## 开启时临时隐藏 Dungeon 的网格，让你在空场里单独审视规格；再按一次恢复。

const SPEC_PATH := "res://data/levels/tithe_gate.json"
const ZONE_COLOR := Color(0.95, 0.68, 0.25)
const ROAD_COLOR := Color(0.78, 0.80, 0.86)
const MARK_COLOR := Color(0.35, 0.82, 0.70)
const GATE_COLOR := Color(0.90, 0.38, 0.34)
const LABEL_HEIGHT := 3.0
const LABEL_RATIO := 0.0005

var _root: Node3D
var _dungeon: Node3D
var _shown: bool = false
var _labels: Array[Label3D] = []


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "SpecRoot"
	add_child(_root)
	_build()
	_root.visible = false
	var parent := get_parent()
	if parent != null:
		_dungeon = parent.get_node_or_null("Dungeon") as Node3D
	print("[SpecOverlay] 已装载，按 F1 查看规格线框")


func _process(_delta: float) -> void:
	if not _shown or _labels.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 正交缩放下按相机尺寸等比放大，保证任何 zoom 下线框标签都是同一屏上字号。
	var size := cam.size * LABEL_RATIO
	for label: Label3D in _labels:
		label.pixel_size = size


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F1:
			toggle()


func toggle() -> bool:
	_shown = not _shown
	_root.visible = _shown
	if _dungeon != null:
		_dungeon.visible = not _shown
	print("[SpecOverlay] ", "开启规格预览" if _shown else "关闭规格预览")
	return _shown


func is_shown() -> bool:
	return _shown


func _build() -> void:
	var text := FileAccess.get_file_as_string(SPEC_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SpecOverlay: 无法解析 %s" % SPEC_PATH)
		return
	var spec: Dictionary = parsed

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var zones: Array = spec.get("zones", [])
	for entry: Variant in zones:
		var zone: Dictionary = entry as Dictionary
		var origin: Array = zone["origin"]
		var size: Array = zone["size"]
		var o := Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
		var s := Vector3(float(size[0]), maxf(float(size[1]), 2.0), float(size[2]))
		_add_box(mesh, o, s, ZONE_COLOR)
		_add_label(String(zone.get("name", "")), o + Vector3(1.5, LABEL_HEIGHT, 0.5), ZONE_COLOR)

	var scene: Dictionary = spec["scene"]
	var road := float(scene.get("road_width", 8.0)) * 0.5
	var total := 0.0
	for entry: Variant in zones:
		var zone: Dictionary = entry as Dictionary
		var origin: Array = zone["origin"]
		var size: Array = zone["size"]
		total = maxf(total, float(origin[0]) + float(size[0]))
	for z: float in [-road, road]:
		_add_line(mesh, Vector3(0.0, 0.05, z), Vector3(total, 0.05, z), ROAD_COLOR)

	var landmarks: Array = spec.get("landmarks", [])
	for entry: Variant in landmarks:
		var lm: Dictionary = entry as Dictionary
		var pos: Array = lm["pos"]
		var p := Vector3(float(pos[0]), float(pos[1]) + 0.05, float(pos[2]))
		var id := String(lm["id"])
		if id == "gate_arch":
			var opening: Array = lm.get("opening", [4.0, 4.0])
			var half := float(opening[0]) * 0.5
			var h := float(opening[1])
			_add_line(mesh, Vector3(p.x, 0.0, -half), Vector3(p.x, h, -half), GATE_COLOR)
			_add_line(mesh, Vector3(p.x, 0.0, half), Vector3(p.x, h, half), GATE_COLOR)
			_add_line(mesh, Vector3(p.x, h, -half), Vector3(p.x, h, half), GATE_COLOR)
			_add_label("卡口 %.0fm" % (half * 2.0), p + Vector3(0.0, h + 0.6, 0.0), GATE_COLOR)
		elif id == "toll_booth":
			var bsize: Array = lm.get("size", [4.0, 2.6, 4.0])
			var bo := Vector3(p.x - float(bsize[0]) * 0.5, 0.0, p.z - float(bsize[2]) * 0.5)
			var bs := Vector3(float(bsize[0]), float(bsize[1]), float(bsize[2]))
			_add_box(mesh, bo, bs, MARK_COLOR)
			_add_label("税亭", bo + Vector3(bs.x * 0.5, bs.y + 0.5, bs.z * 0.5), MARK_COLOR)
		else:
			var c := MARK_COLOR if id != "exit" else GATE_COLOR
			_add_box(mesh, p - Vector3(0.4, 0.0, 0.4), Vector3(0.8, 1.6, 0.8), c)
			_add_label(id, p + Vector3(0.0, 2.0, 0.0), c)

	var encounters: Array = spec.get("encounters", [])
	for entry: Variant in encounters:
		var trigger: Dictionary = (entry as Dictionary).get("trigger", {})
		var at: Array = trigger.get("at", [0.0, 0.0, 0.0])
		var span: Array = trigger.get("span", [2.0, 0.0, 4.0])
		var to := Vector3(float(at[0]) - float(span[0]) * 0.5, 0.0, float(at[2]) - float(span[2]) * 0.5)
		var ts := Vector3(maxf(float(span[0]), 0.5), 1.2, maxf(float(span[2]), 0.5))
		_add_box(mesh, to, ts, GATE_COLOR)

	var interactables: Array = spec.get("interactables", [])
	for entry: Variant in interactables:
		var inter: Dictionary = entry as Dictionary
		var at: Array = inter.get("at", [0.0, 0.0, 0.0])
		var p := Vector3(float(at[0]), 0.15, float(at[2]))
		_add_line(mesh, p + Vector3(-0.5, 0.0, -0.5), p + Vector3(0.5, 1.2, 0.5), MARK_COLOR)
		_add_line(mesh, p + Vector3(-0.5, 0.0, 0.5), p + Vector3(0.5, 1.2, -0.5), MARK_COLOR)
		_add_label(String(inter.get("id", "")), p + Vector3(0.0, 1.8, 0.0), MARK_COLOR)

	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false

	var instance := MeshInstance3D.new()
	instance.name = "SpecLines"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(instance)


func _add_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)


func _add_box(mesh: ImmediateMesh, origin: Vector3, size: Vector3, color: Color) -> void:
	var p0 := origin
	var p1 := origin + Vector3(size.x, 0.0, 0.0)
	var p2 := origin + Vector3(size.x, 0.0, size.z)
	var p3 := origin + Vector3(0.0, 0.0, size.z)
	var top := Vector3(0.0, size.y, 0.0)
	for corner: Vector3 in [p0, p1, p2, p3]:
		_add_line(mesh, corner, corner + top, color)
	_add_line(mesh, p0 + top, p1 + top, color)
	_add_line(mesh, p1 + top, p2 + top, color)
	_add_line(mesh, p2 + top, p3 + top, color)
	_add_line(mesh, p3 + top, p0 + top, color)


func _add_label(text: String, at: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.outline_modulate = Color(0.04, 0.04, 0.05, 0.9)
	_root.add_child(label)
	_labels.append(label)
