extends SceneTree

# 墙体改造逐段验收：同一机位拍"卡口"与"院子"，按 tag 存到 docs/wall/<tag>_*.png
# 用法：godot --path . --resolution 1600x900 --script res://tools/shot_wall.gd -- <tag> nofight
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

const SHOTS := [
	{ "name": "gate", "x": 10.6, "z": 0.0, "size": 0.0 },
	{ "name": "yard", "x": 25.6, "z": 0.0, "size": 0.0 },
	{ "name": "detail", "x": 19.0, "z": 0.0, "size": 6.5 },
]

var _m: Node
var _rig: Node3D
var _player: Node3D
var _world: Node3D
var _tag := "wall"
var _f := 0
var _i := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_tag = String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/wall"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	_world = _m.get_node_or_null("World") as Node3D
	var hud := _m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", false)


func _process(_d: float) -> bool:
	_f += 1
	if _i >= SHOTS.size():
		return true
	var shot: Dictionary = SHOTS[_i]
	if _f == 8:
		var at := Vector3(float(shot["x"]), 0.05, float(shot["z"]))
		if _player != null:
			_player.position = at
		if _rig != null and _world != null:
			_rig.global_position = _world.transform * Vector3(at.x, 1.0, at.z)
		var cam: Camera3D = null
		if _rig != null:
			cam = _rig.get_node_or_null("Camera3D") as Camera3D
		if cam != null and float(shot["size"]) > 0.0:
			cam.size = float(shot["size"])
		return false
	if _f == 22:
		var path := "res://docs/wall/%s_%s.png" % [_tag, String(shot["name"])]
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
		_i += 1
		_f = 4
		return false
	return false
