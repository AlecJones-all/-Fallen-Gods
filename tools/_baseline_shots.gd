extends SceneTree

# P1 兼容基线：用场景自己的机位（-50°），按指定窗口尺寸出 4 张图。
# 用法：godot --path . --script res://tools/_baseline_shots.gd -- 1600 900
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

const SHOTS := [
	{ "file": "1_open", "x": 7.0, "z": 0.0, "hud": true },
	{ "file": "2_gate", "x": 10.6, "z": 0.0, "hud": false },
	{ "file": "3_yard", "x": 25.6, "z": 0.0, "hud": false },
	{ "file": "4_vista", "x": 34.0, "z": -1.5, "hud": false },
	{ "file": "5_exit", "x": 44.0, "z": 0.0, "hud": false },
]
const SETTLE_FRAMES := 20
const CYCLE := 18

var _m: Node
var _rig: Node3D
var _player: Node3D
var _world: Node3D
var _f := 0
var _tag := ""
var _want := Vector2i(1600, 900)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_want = Vector2i(int(args[0]), int(args[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	_world = _m.get_node_or_null("World") as Node3D


func _process(_d: float) -> bool:
	_f += 1
	if _f <= SETTLE_FRAMES:
		if _f == 2 or _f == 8:
			DisplayServer.window_set_size(_want)
		if _f == SETTLE_FRAMES:
			var view := get_root().get_visible_rect().size
			_tag = "%dx%d" % [int(view.x), int(view.y)]
			print("BASELINE window=", DisplayServer.window_get_size(), " visible=", view, " tag=", _tag)
		return false

	var local := (_f - SETTLE_FRAMES) % CYCLE
	var index := int((float(_f - SETTLE_FRAMES) / float(CYCLE)))
	if index >= SHOTS.size():
		print("BASELINE DONE ", _tag)
		return true

	var shot: Dictionary = SHOTS[index]
	if local == 2:
		var hud := _m.get_node_or_null("HUD")
		if hud != null:
			hud.set("visible", bool(shot["hud"]))
		var at := Vector3(float(shot["x"]), 0.05, float(shot["z"]))
		if _player != null:
			_player.position = at
		if _rig != null and _world != null:
			_rig.global_position = _world.transform * Vector3(at.x, 1.0, at.z)
	if local == 14:
		var path := "res://docs/baseline/%s_%s.png" % [_tag, String(shot["file"])]
		get_root().get_texture().get_image().save_png(path)
		print("saved ", path)
	return false