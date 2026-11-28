extends SceneTree
## 第 4 关体量走查：单机位、单帧，按给定分辨率出图。
##
## 用法:
##   godot --path . --script res://tools/chapel_scale_review.gd -- 1280 720 16x9
##   godot --path . --script res://tools/chapel_scale_review.gd -- 1680 720 21x9
## 第三个参数只用于文件名；可再跟一个整数字段作为玩家 Z 坐标（默认 5.5）。

const SCENE := "res://scenes/levels/whitewash_chapel.tscn"
const OUT := "res://art/previews/whitewash_chapel"

var _size := Vector2i(1280, 720)
var _tag := "16x9"
var _player_z := 5.5
var _ortho := 0.0
var _frame := 0
var _scene: Node
var _rig: Node3D
var _player: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_size = Vector2i(int(args[0]), int(args[1]))
	if args.size() >= 3:
		_tag = args[2]
	if args.size() >= 4:
		_player_z = float(args[3])
	if args.size() >= 5:
		_ortho = float(args[4])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_size(_size)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("missing " + SCENE)
		quit(2)
		return
	_scene = packed.instantiate()
	get_root().add_child(_scene)
	_rig = _scene.get_node_or_null("CameraRig") as Node3D
	_player = _scene.get_node_or_null("Player") as Node3D
	if _rig != null:
		_rig.set_physics_process(false)
	if _player != null:
		_player.global_position = Vector3(1.8, 0.06, _player_z)
		for node in _player.find_children("*", "MeshInstance3D", true, false):
			if node.name == "AimMarker":
				node.visible = false


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		DisplayServer.window_set_size(_size)
		return false
	if _frame == 4:
		if _rig != null:
			_rig.rotation_degrees = Vector3(-44, 8, 0)
			if _ortho > 0.0:
				_rig.set("_base_ortho_size", _ortho)
				_rig.call("_update_projection")
		if _rig != null and _player != null:
			_rig.global_position = _player.global_position + Vector3(0.0, 1.0, 0.0)
			if _rig.has_method("snap_to_target"):
				_rig.call("snap_to_target")
		return false
	if _frame < 26:
		return false
	var view := get_root().get_visible_rect().size
	var cam: Camera3D = _rig.get_node_or_null("Camera3D") if _rig != null else null
	if cam != null:
		print("CAM ortho=", cam.projection == Camera3D.PROJECTION_ORTHOGONAL, " size=", cam.size,
			" pos=", cam.global_position, " rot=", cam.global_rotation_degrees, " keep=", cam.keep_aspect)
	var path := "%s/planA_%s_%dx%d.png" % [OUT, _tag, int(view.x), int(view.y)]
	var err := get_root().get_texture().get_image().save_png(path)
	print("SCALE REVIEW ", path, " -> ", error_string(err), " view=", view)
	quit()
	return true
