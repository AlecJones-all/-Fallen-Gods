extends SceneTree
# 贴图检查：临时撤掉油画光照与后期，用平光照亮，只看材质。
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"
var _f := 0
var _m: Node
var _rig: Node3D
var _cam: Camera3D
var _player: Node3D
var _world: Node3D

func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	_rig = _m.get_node_or_null("CameraRig") as Node3D
	if _rig != null:
		_cam = _rig.get_node_or_null("Camera3D") as Camera3D
		_rig.set_physics_process(false)
	_world = _m.get_node_or_null("World") as Node3D
	_player = _m.get_node_or_null("World/Player") as Node3D
	var hud := _m.get_node_or_null("HUD")
	if hud != null:
		hud.set("visible", false)
	var grade := _m.get_node_or_null("OilGrade")
	if grade != null:
		grade.queue_free()
	var sun := _m.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 1.9
		sun.light_color = Color(1, 1, 1)
		sun.rotation_degrees = Vector3(-50, 30, 0)
	var we := _m.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_energy = 0.9
		we.environment.fog_enabled = false
		we.environment.glow_enabled = false

func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		var x := 8.0
		if _player != null:
			_player.position = Vector3(x, 0.05, 0.0)
		if _rig != null and _world != null:
			_rig.rotation_degrees = Vector3(-55.0, 45.0, 0.0)
			_rig.global_position = _world.transform * Vector3(x, 1.0, 0.0)
		if _cam != null:
			_cam.size = 9.5
		return false
	if _f == 14:
		get_root().get_texture().get_image().save_png("res://docs/07_贴图检查.png")
		print("saved 07_贴图检查.png")
		return true
	return false
