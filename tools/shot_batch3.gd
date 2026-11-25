extends SceneTree

# 批 3 验收图：拱下铁链 / 院内吊笼 / 交互提示
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _rig: Node3D
var _cam: Camera3D
var _player: Node3D
var _world: Node3D
var _f := 0
var _stage := 0


func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	if _rig != null:
		_cam = _rig.get_node_or_null("Camera3D") as Camera3D
		_rig.set_physics_process(false)
	_world = _m.get_node_or_null("World") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D


func _process(_d: float) -> bool:
	_f += 1
	if _stage > 2:
		return true
	if _f == 5:
		match _stage:
			0:
				_aim(10.4, 10.0, -44.0)
			1:
				_aim(26.2, 12.5, -42.0)
			2:
				_aim(12.6, 9.5, -48.0)
				var area: Area3D = _m.get_node_or_null("World/Interactables/Interact_ledger") as Area3D
				if area != null:
					area.call("_start_reading")
		return false
	if _f == 16:
		var names := ["08_道具_拱下铁链.png", "08_道具_院中吊笼.png", "08_道具_交互提示.png"]
		if OS.get_cmdline_user_args().has("flat"):
			names = ["08f_拱下铁链.png", "08f_院中吊笼.png", "08f_交互提示.png"]
		get_root().get_texture().get_image().save_png("res://docs/" + names[_stage])
		print("saved ", names[_stage])
		_stage += 1
		_f = 4
		return false
	return false


func _aim(x: float, size: float, pitch: float) -> void:
	if _player != null:
		_player.position = Vector3(x, 0.05, 0.0)
	if _rig != null and _world != null:
		_rig.rotation_degrees = Vector3(pitch, 45.0, 0.0)
		_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
	if _cam != null:
		_cam.size = size
