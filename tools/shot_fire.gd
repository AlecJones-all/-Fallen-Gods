extends SceneTree

# 开火定格：箭头在离膛 1 帧处，检查它是否紧贴枪口
const OUT := "res://docs/19_武器模型/review"

var _p: Node3D
var _world: Node3D
var _cam: Camera3D
var _frame := 0


func _initialize() -> void:
	_world = Node3D.new()
	get_root().add_child(_world)
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
	_world.add_child(_p)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.105, 0.10, 0.093)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.0
	we.environment = env
	get_root().add_child(we)
	for l in [[Vector3(-30, -35, 0), 2.6], [Vector3(-10, 140, 0), 1.3], [Vector3(-160, 200, 0), 1.4]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_energy = l[1]
		get_root().add_child(dl)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.01
	_cam.far = 100
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		_p.select_weapon(1)
		_p.set_physics_process(false)  # 空场景没有地板，别让角色掉下去
		_p.set("velocity", Vector3.ZERO)
	# 连发 3 秒（每 15 帧一发），在持续射击中定格
	if _frame >= 20 and _frame <= 200 and _frame % 15 == 0:
		_p.set("_aim_point", _p.global_position + Vector3(0, 0, -6))
		_p.call("_do_ranged", Vector3(0, 0, -1))
	if _frame == 41:
		var mz: Node3D = _p.find_child("Muzzle", true, false) as Node3D
		for n: Node in _world.find_children("Projectile*", "", true, false):
			var d: float = (n as Node3D).global_position.distance_to(mz.global_position)
			print("离膛 1 帧：箭距枪口 = %.2f m（MUZZLE_FORWARD=0.35 + 1帧位移）" % d)
		var b := Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(45), 0))
		var target: Vector3 = _p.global_position + Vector3(0, 1.1, -0.7)
		_cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, 3))
		_cam.size = 2.4
		return false
	if _frame == 200:
		get_root().get_texture().get_image().save_png("%s/hold_fire.png" % OUT)
		print("saved hold_fire")
		quit(0)
		return true
	return false
