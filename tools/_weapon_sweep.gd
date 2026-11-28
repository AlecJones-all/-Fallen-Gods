extends SceneTree

# 连弩滚转扫描：只改内存里的节点旋转，不写盘。
# 用法: godot --path . --script res://tools/_weapon_sweep.gd

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const OUT_DIR := "res://docs/19_武器模型/review"
const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

var _root: Node3D
var _cam: Camera3D
var _label: Label3D
var _ap: AnimationPlayer
var _xbow: Node3D
var _axe: Node3D
var _frame := 0
var _i := 0
var _pending := false
var _saved: Array[String] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(_root)
	_ap = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_xbow = _root.find_child("Crossbow", true, false) as Node3D
	_axe = _root.find_child("Axe", true, false) as Node3D

	for m: Node in _root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var in_weapon := false
		var p := mi.get_parent()
		while p != null:
			if p.name == "Crossbow" or p.name == "Axe":
				in_weapon = true
				break
			p = p.get_parent()
		mi.visible = true if in_weapon else (mi.name != "Cube_009")

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.current = true
	get_root().add_child(_cam)

	_label = Label3D.new()
	_label.font = load(FONT)
	_label.font_size = 40
	_label.modulate = Color(0.96, 0.93, 0.86)
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
		_ap.play("idle")
		_ap.seek(0.6, true)
		_ap.pause()
	if _frame >= 8:
		var rolls := [0.0, 90.0, 180.0, 270.0]
		if _i < rolls.size():
			if not _pending:
				_xbow.visible = true
				_axe.visible = false
				_xbow.rotation_degrees = Vector3(0, 0, rolls[_i])
				var c := _world_aabb(_xbow).get_center()
				var b := Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(30), 0))
				_cam.global_transform = Transform3D(b, c + b * Vector3(0, 0, 3))
				_cam.size = 0.62
				_label.text = "弩滚转 %d°" % int(rolls[_i])
				_label.pixel_size = 0.62 * 0.00105
				_label.position = Vector3(-0.29, 0.27, -0.5)
				_pending = true
				return false
			var path := "%s/sweep_xbow_%d.png" % [OUT_DIR, int(rolls[_i])]
			get_root().get_texture().get_image().save_png(path)
			_saved.append(path)
			_pending = false
			_i += 1
			return false
		if _i == rolls.size():
			_sheet()
			_i += 1
			return true
	return false


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


func _sheet() -> void:
	var cell := 800
	var img := Image.create(cell * 4, cell, false, Image.FORMAT_RGBA8)
	for i in 4:
		var im := Image.load_from_file(ProjectSettings.globalize_path("%s/sweep_xbow_%d.png" % [OUT_DIR, [0, 90, 180, 270][i]]))
		if im == null:
			continue
		var side: int = mini(im.get_width(), im.get_height())
		im = im.get_region(Rect2i((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side))
		im.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		img.blit_rect(im, Rect2i(0, 0, cell, cell), Vector2i(i * cell, 0))
	img.save_png(ProjectSettings.globalize_path("%s/sheet_sweep_xbow.png" % OUT_DIR))
	print("sweep sheet done")
