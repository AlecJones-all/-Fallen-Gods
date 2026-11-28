extends SceneTree

# 围绕弩口轴滚转扫描：找出"弩臂平面水平"的角度
# 用法: godot --path . --script res://tools/roll_sweep.gd

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const TSCN := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"
const OUT_DIR := "res://docs/19_武器模型/review"
const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

var _root: Node3D
var _cam: Camera3D
var _label: Label3D
var _inst: Node3D
var _model: Node3D
var _frame := 0
var _i := 0
var _pending := false
var _rolls := [0.0, 90.0, 180.0, 270.0]


func _initialize() -> void:
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
	_inst = (load(TSCN) as PackedScene).instantiate() as Node3D
	pivot.add_child(_inst)
	_model = _inst.get_node("Model")

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
	_cam.far = 200
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)

	_label = Label3D.new()
	_label.font = load(FONT)
	_label.font_size = 40
	_label.modulate = Color(0.96, 0.93, 0.86)
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cam.add_child(_label)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 6:
		return false
	if _i >= _rolls.size():
		return true
	if not _pending:
		_model.rotation_degrees = Vector3(0, 0, _rolls[_i])
		var c := _inst.global_transform * Vector3.ZERO
		var b := Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(45), 0))
		_cam.global_transform = Transform3D(b, c + b * Vector3(0, 0, 3))
		_cam.size = 1.05
		_label.text = "roll %d°" % int(_rolls[_i])
		_label.pixel_size = 1.05 * 0.0011
		_label.position = Vector3(-0.48, -0.46, -1.0)
		_pending = true
		return false
	get_root().get_texture().get_image().save_png("%s/roll_%d.png" % [OUT_DIR, int(_rolls[_i])])
	print("saved ", _rolls[_i])
	_pending = false
	_i += 1
	return false
