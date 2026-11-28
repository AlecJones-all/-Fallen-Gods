extends SceneTree

# 把烘焙好的武器挂到主角手上出图（只读）
# 用法: godot --path . --script res://tools/attach_preview.gd -- <tscn 路径> <输出前缀>

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const OUT_DIR := "res://docs/19_武器模型/review"

var _root: Node3D
var _cam: Camera3D
var _tag := "steampunk"
var _frame := 0
var _i := 0
var _pending := false
var _shots := []
var _inst: Node3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var path := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn" if a.size() < 1 else String(a[0])
	_tag = "steampunk" if a.size() < 2 else String(a[1])
	if _tag == "steampunk":
		path = "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"

	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	get_root().add_child(_root)

	var ap: AnimationPlayer = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		ap.play("idle")
		ap.seek(0.6, true)
		ap.pause()

	for nm in ["Crossbow", "Axe", "Cube_009"]:
		var n: Node3D = _root.find_child(nm, true, false) as Node3D
		if n != null:
			n.visible = false

	var pivot: Node3D = _root.find_child("XbowPivot", true, false) as Node3D
	var inst: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	pivot.add_child(inst)

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

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)

	_inst = inst


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		var c := _aabb(_inst).get_center()
		_shots = [
			["hand", c, 30.0, -30.0, 0.75],
			["game55", c, 45.0, -55.0, 0.75],
			["scale", _root.global_position + Vector3(0, 1.0, 0), 45.0, -55.0, 6.0],
		]
	if _frame < 6:
		return false
	if _i >= _shots.size():
		return true
	var s: Array = _shots[_i]
	if not _pending:
		var b := Basis.from_euler(Vector3(deg_to_rad(float(s[3])), deg_to_rad(float(s[2])), 0))
		_cam.global_transform = Transform3D(b, (s[1] as Vector3) + b * Vector3(0, 0, 3))
		_cam.size = float(s[4])
		_pending = true
		return false
	get_root().get_texture().get_image().save_png("%s/%s_%s.png" % [OUT_DIR, _tag, s[0]])
	print("saved ", s[0])
	_pending = false
	_i += 1
	return false


func _aabb(n: Node3D) -> AABB:
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
