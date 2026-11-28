extends SceneTree

# 实战取景：用 player.tscn（真实组合），切到连弩，出一张实机比例 + 一张近景
const PLAYER := "res://scenes/player/player.tscn"
const OUT := "res://docs/19_武器模型/review"

var _frame := 0
var _i := 0
var _pending := false
var _cam: Camera3D
var _p: Node3D
var _shots := [["w1", 0.9], ["w2", 2.2], ["game12", 12.0]]


func _initialize() -> void:
	_p = (load(PLAYER) as PackedScene).instantiate() as Node3D
	get_root().add_child(_p)

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
	for l in [[Vector3(-30, -35, 0), 2.6, Color(1, 1, 1)], [Vector3(-10, 140, 0), 1.2, Color(1, 1, 1)], [Vector3(-160, 200, 0), 1.4, Color(0.92, 0.95, 1.0)]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_energy = l[1]
		dl.light_color = l[2]
		get_root().add_child(dl)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		var ap: AnimationPlayer = _p.find_child("AnimationPlayer", true, false) as AnimationPlayer
		ap.play("idle")
		ap.seek(0.6, true)
		ap.pause()
		# 走游戏自己的切换逻辑，保证剑/弩互斥
		if _p.has_method("select_weapon"):
			_p.select_weapon(1)
		var sw2: Node3D = _p.find_child("Cube_009", true, false) as Node3D
		var xb2: Node3D = _p.find_child("Crossbow", true, false) as Node3D
		print("剑可见=", sw2.visible if sw2 != null else "?", " 弩可见=", xb2.visible if xb2 != null else "?")
	if _frame < 8:
		return false
	if _i >= _shots.size():
		return true
	if not _pending:
		var s: Array = _shots[_i]
		var b := Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(45), 0))
		var xbn: Node3D = _p.find_child("Crossbow", true, false) as Node3D
		var box := AABB()
		var first := true
		for m: Node in xbn.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		var target := box.get_center() if not first else _p.global_position + Vector3(0, 1.0, 0)
		if String(s[0]) == "game12":
			target = _p.global_position + Vector3(0, 1.0, 0)
		_cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, 3))
		_cam.size = float(s[1])
		_pending = true
		return false
	get_root().get_texture().get_image().save_png("%s/player_xbow_%s.png" % [OUT, _shots[_i][0]])
	print("saved ", _shots[_i][0])
	_pending = false
	_i += 1
	return false
