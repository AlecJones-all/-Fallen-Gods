extends SceneTree

# 武器审查出图（只读，不改场景）
# 用法: godot --path . --resolution 900x900 --script res://tools/_weapon_review.gd
# 产物: docs/19_武器模型/review/*.png + 两张拼图

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const OUT_DIR := "res://docs/19_武器模型/review"
const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

var _root: Node3D
var _cam: Camera3D
var _label: Label3D
var _ap: AnimationPlayer
var _char_meshes: Array[Node] = []
var _xbow: Node3D
var _axe: Node3D

var _frame := 0
var _i := 0
var _pending := false
var _shots: Array = []
var _saved: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(_root)

	_ap = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_xbow = _root.find_child("Crossbow", true, false) as Node3D
	_axe = _root.find_child("Axe", true, false) as Node3D

	# 角色网格全部藏起来当"人台"，只留骨骼驱动挂点
	for m: Node in _root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.name == "Cube_009":  # 剑是蒙皮件，单独处理
			_char_meshes.append(mi)
			continue
		var p := mi.get_parent()
		var in_weapon := false
		while p != null:
			if p.name == "Crossbow" or p.name == "Axe":
				in_weapon = true
				break
			p = p.get_parent()
		if not in_weapon:
			_char_meshes.append(mi)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.current = true
	get_root().add_child(_cam)

	_label = Label3D.new()
	_label.font = load(FONT)
	_label.font_size = 40
	_label.pixel_size = 0.0016
	_label.modulate = Color(0.96, 0.93, 0.86)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.no_depth_test = true
	_label.render_priority = 10
	_cam.add_child(_label)

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
		[Vector3(-30, -35, 0), 2.6, Color(1, 1, 1)],
		[Vector3(-10, 140, 0), 1.2, Color(1, 1, 1)],
		[Vector3(-160, 200, 0), 1.4, Color(0.92, 0.95, 1.0)],
	]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_energy = l[1]
		dl.light_color = l[2]
		get_root().add_child(dl)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		_prepare_pose()
	if _frame == 6:
		_shots = _build_shots()
	if _frame >= 10 and _i < _shots.size():
		if not _pending:
			_apply(_shots[_i])
			_pending = true
			return false
		_save(_shots[_i])
		_pending = false
		_i += 1
		return false
	if _i >= _shots.size() and _saved.size() == _shots.size() and _shots.size() > 0 and not _composed:
		_composed = true
		_compose()
		return true
	return false


var _composed := false


func _prepare_pose() -> void:
	if _ap != null and _ap.has_animation("idle"):
		_ap.play("idle")
		_ap.seek(0.6, true)
		_ap.pause()
	if _xbow != null:
		_xbow.visible = true
	if _axe != null:
		_axe.visible = true


func _build_shots() -> Array:
	var shots := []
	# 武器自身坐标系下的三个正交视角：判断几何与剪影（local = true）
	for spec in [
		["xbow", _xbow, 0.62],
		["axe", _axe, 1.04],
	]:
		var nm: String = spec[0]
		var node: Node3D = spec[1]
		var size: float = spec[2]
		var c := _world_aabb(node).get_center()
		shots.append({"name": nm + "_front", "weapon": node, "target": c, "yaw": 0.0, "pitch": -8.0, "size": size, "local": true, "cap": "武器正前"})
		shots.append({"name": nm + "_side", "weapon": node, "target": c, "yaw": 90.0, "pitch": 0.0, "size": size, "local": true, "cap": "武器正侧（剪影）"})
		shots.append({"name": nm + "_top", "weapon": node, "target": c, "yaw": 0.0, "pitch": -89.0, "size": size, "local": true, "cap": "武器俯视"})
		shots.append({"name": nm + "_wgame", "weapon": node, "target": c, "yaw": 45.0, "pitch": -55.0, "size": size, "local": false, "cap": "实机俯角 55° 看它"})
	# 实机读图：真实 ortho 12
	var chest := _root.global_position + Vector3(0, 1.0, 0)
	shots.append({"name": "game_xbow", "weapon": null, "target": chest, "yaw": 45.0, "pitch": -55.0, "size": 12.0, "local": false, "cap": "实机视角（ortho 12）· 弩"})
	shots.append({"name": "game_axe", "weapon": null, "target": chest, "yaw": 45.0, "pitch": -55.0, "size": 12.0, "local": false, "cap": "实机视角（ortho 12）· 斧"})
	# 手部接触特写
	shots.append({"name": "hand_xbow", "weapon": _xbow, "target": _world_aabb(_xbow).get_center(), "yaw": 30.0, "pitch": -30.0, "size": 0.62, "local": false, "cap": "握持特写 · 弩"})
	shots.append({"name": "hand_axe", "weapon": _axe, "target": _world_aabb(_axe).get_center(), "yaw": 30.0, "pitch": -30.0, "size": 0.62, "local": false, "cap": "握持特写 · 斧"})
	return shots


func _apply(s: Dictionary) -> void:
	var show_w: Node3D = s["weapon"]
	var nm := String(s["name"])
	var keep_body := nm.begins_with("game_") or nm.begins_with("hand_")
	for m in _char_meshes:
		(m as MeshInstance3D).visible = keep_body and (m as MeshInstance3D).name != "Cube_009"
	if _xbow != null:
		_xbow.visible = (show_w == null) or (show_w == _xbow)
	if _axe != null:
		_axe.visible = (show_w == null) or (show_w == _axe)
	if show_w == null:
		if s["name"] == "game_xbow":
			_xbow.visible = true
			_axe.visible = false
		else:
			_xbow.visible = false
			_axe.visible = true

	var yaw := deg_to_rad(float(s["yaw"]))
	var pitch := deg_to_rad(float(s["pitch"]))
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	if bool(s.get("local", false)) and s["weapon"] != null:
		b = (s["weapon"] as Node3D).global_transform.basis.orthonormalized() * b
	_cam.global_transform = Transform3D(b, (s["target"] as Vector3) + b * Vector3(0, 0, 3.0))
	_cam.size = float(s["size"])
	_label.text = String(s["cap"])
	_label.pixel_size = float(s["size"]) * 0.00105
	_label.position = Vector3(-float(s["size"]) * 0.46, float(s["size"]) * 0.44, -0.5)


func _save(s: Dictionary) -> void:
	var path := "%s/%s.png" % [OUT_DIR, s["name"]]
	get_root().get_texture().get_image().save_png(path)
	_saved.append(path)
	print("saved ", path)


func _world_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _compose() -> void:
	_sheet(["xbow_front", "xbow_side", "xbow_top", "axe_front", "axe_side", "axe_top"], 3, "sheet_shape.png")
	_sheet(["game_xbow", "game_axe", "hand_xbow", "hand_axe"], 2, "sheet_game.png")
	print("compose done")


func _sheet(names: Array, cols: int, out: String) -> void:
	var cell := 900
	var rows := int(ceil(float(names.size()) / float(cols)))
	var img := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.07, 0.07))
	for i in names.size():
		var p := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, names[i]])
		var im := Image.load_from_file(p)
		if im == null:
			continue
		# 实机比例那两格：裁角色附近一块再放大，才能看清 1:1 的观感
		var crop: int = 460 if names[i].begins_with("game_") else 0
		if crop > 0:
			var cx: int = im.get_width() / 2
			var cy: int = im.get_height() / 2
			im = im.get_region(Rect2i(cx - crop / 2, cy - crop / 2, crop, crop))
		# 居中裁成正方形再缩到格子大小（渲染分辨率随窗口走，不是固定 900）
		var side: int = mini(im.get_width(), im.get_height())
		var ox: int = (im.get_width() - side) / 2
		var oy: int = (im.get_height() - side) / 2
		im = im.get_region(Rect2i(ox, oy, side, side))
		im.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		var x := (i % cols) * cell
		var y := (i / cols) * cell
		img.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, y))
		# 细边线
		for k in cell:
			img.set_pixel(x, y + k, Color(0.25, 0.25, 0.25))
			img.set_pixel(x + k, y, Color(0.25, 0.25, 0.25))
	var dst := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, out])
	img.save_png(dst)
	print("sheet ", dst)
