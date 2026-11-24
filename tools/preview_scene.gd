extends SceneTree

# 通用预览：加载指定场景并渲染
# 用法: godot --path . --resolution WxH --script res://tools/preview_scene.gd -- <scene> <out.png> [yaw] [dist] [clip] [time]
var _out := "res://_prev.png"
var _scene_path := "res://scenes/player/rogue_knight_v2.tscn"
var _yaw := 0.0
var _dist := 5.0
var _clip := ""
var _time := 0.0
var _f := 0
var _ap: AnimationPlayer


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_scene_path = a[0]
	if a.size() >= 2:
		_out = "res://" + a[1]
	if a.size() >= 3:
		_yaw = float(a[2])
	if a.size() >= 4:
		_dist = float(a[3])
	if a.size() >= 5:
		_clip = a[4]
	if a.size() >= 6:
		_time = float(a[5])

	var scene := Node3D.new()
	get_root().add_child(scene)
	var ps: PackedScene = load(_scene_path)
	if ps == null:
		print("LOAD FAIL ", _scene_path)
		quit()
		return
	var inst: Node3D = ps.instantiate()
	scene.add_child(inst)

	_ap = inst.find_child("AnimationPlayer", true, false)
	if _ap and _clip != "":
		_ap.play(_clip)
		_ap.seek(_time, true)
		_ap.pause()
		print("playing ", _clip, " @ ", _time)

	var cam := Camera3D.new()
	cam.fov = 30.0
	scene.add_child(cam)
	var center := Vector3(0, 1.1, 0)
	var dir := Vector3(sin(deg_to_rad(_yaw)), 0.08, cos(deg_to_rad(_yaw))).normalized()
	cam.transform = Transform3D(Basis(), center + dir * _dist).looking_at(center, Vector3.UP)
	cam.current = true

	var l1 := DirectionalLight3D.new()
	scene.add_child(l1)
	l1.rotation_degrees = Vector3(-35, -50, 0)
	l1.light_energy = 2.2
	var l2 := DirectionalLight3D.new()
	scene.add_child(l2)
	l2.rotation_degrees = Vector3(-10, 150, 0)
	l2.light_energy = 1.0

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.32, 0.36)
	ground.material_override = gm
	scene.add_child(ground)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.95)
	e.ambient_light_energy = 1.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	scene.add_child(we)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 10:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
