extends SceneTree

# 用法: godot --path . --script res://tools/preview_rig.gd -- <out.png> [clip] [time] [yaw_deg] [dist]
var _out := "res://.tmp_rig.png"
var _clip := ""
var _time := 0.0
var _yaw := 0.0
var _dist := 3.2
var _frames := 0
var _ap: AnimationPlayer


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_out = "res://" + a[0]
	if a.size() >= 2:
		_clip = a[1]
	if a.size() >= 3:
		_time = float(a[2])
	if a.size() >= 4:
		_yaw = float(a[3])
	if a.size() >= 5:
		_dist = float(a[4])

	var scene := Node3D.new()
	get_root().add_child(scene)
	var ps: PackedScene = load("res://scenes/player/rogue_knight_rigged.tscn")
	if ps == null:
		print("LOAD_FAIL")
		quit()
		return
	var model: Node3D = ps.instantiate()
	scene.add_child(model)

	_ap = model.find_child("AnimationPlayer", true, false)
	if _ap and _clip != "":
		_ap.play(_clip)
		_ap.seek(_time, true)
		_ap.pause()

	var cam := Camera3D.new()
	cam.fov = 30.0
	scene.add_child(cam)
	var center := Vector3(0, 1.05, 0)
	var dir := Vector3(sin(deg_to_rad(_yaw)), 0.06, cos(deg_to_rad(_yaw))).normalized()
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
	_frames += 1
	if _frames == 8:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out, " clip=", _clip, " t=", _time, " yaw=", _yaw)
		return true
	return false
