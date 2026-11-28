extends SceneTree

# 临时：主角候选对比。第二参数 dim=1 时用项目里的低照度布光。
# 用法: godot --path . --resolution 1560x900 --script res://tools/_lead_check.gd -- out.png [dim]

const CAST := [
	{"path": "res://assets/characters/rogue_knight/Rogue Knight.fbx", "name": "现用 · Rogue Knight"},
	{"path": "res://assets/anim_src/Vanguard By T. Choonyung.fbx", "name": "Vanguard"},
	{"path": "res://assets/anim_src/Peasant Girl.fbx", "name": "Peasant Girl"},
]

const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"
const CELL_X := 2.20
const TARGET_HEIGHT := 1.80

var _frames := 0
var _out := "res://.tmp_lead.png"
var _dim := false
var _models: Array[Node3D] = []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_out = "res://" + a[0]
	if a.size() >= 2:
		_dim = a[1] == "dim"

	var scene := Node3D.new()
	get_root().add_child(scene)

	for i in CAST.size():
		var c: Dictionary = CAST[i]
		var cell := Node3D.new()
		scene.add_child(cell)
		cell.position = Vector3((float(i) - 1.0) * CELL_X, 0.0, 0.0)
		var model: Node3D = (load(String(c["path"])) as PackedScene).instantiate()
		cell.add_child(model)
		_models.append(model)

		var label := Label3D.new()
		label.text = String(c["name"])
		label.font = load(FONT)
		label.font_size = 36
		label.pixel_size = 0.0030
		label.modulate = Color(1.0, 0.93, 0.82) if not _dim else Color(0.78, 0.70, 0.60)
		label.outline_size = 0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector3(0.0, -0.20, 0.5)
		cell.add_child(label)

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = 26.0
	cam.transform = Transform3D(Basis(), Vector3(0.0, 1.02, 7.2)).looking_at(Vector3(0.0, 1.02, 0.0), Vector3.UP)
	cam.current = true

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if _dim:
		# 近似 09_ 场景：冷主光 + 极低暖环境光 + 一盏烛火点光
		_add_light(scene, Vector3(-46, -28, 0), 1.55, Color(0.72, 0.80, 1.0))
		_add_light(scene, Vector3(-10, 160, 0), 0.20, Color(1.0, 0.86, 0.70))
		var lamp := OmniLight3D.new()
		lamp.light_energy = 1.1
		lamp.omni_range = 4.2
		lamp.light_color = Color(1.0, 0.62, 0.30)
		lamp.position = Vector3(0.9, 0.7, 1.1)
		scene.add_child(lamp)
		env.background_color = Color(0.045, 0.038, 0.032)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.28, 0.22, 0.17)
		env.ambient_light_energy = 0.26
		env.glow_enabled = true
		env.glow_intensity = 0.35
	else:
		_add_light(scene, Vector3(-28, -30, 0), 2.9, Color.WHITE)
		_add_light(scene, Vector3(-6, 135, 0), 1.15, Color.WHITE)
		_add_light(scene, Vector3(-14, 200, 0), 1.55, Color.WHITE)
		env.background_color = Color(0.098, 0.093, 0.086)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.72, 0.74, 0.80)
		env.ambient_light_energy = 1.0
	we.environment = env
	scene.add_child(we)


func _add_light(parent: Node3D, rot: Vector3, energy: float, color: Color) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_energy = energy
	l.light_color = color
	parent.add_child(l)


func _local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 3:
		for model in _models:
			var box := _local_aabb(model)
			if box.size.y <= 0.0:
				continue
			var s := TARGET_HEIGHT / box.size.y
			model.scale = Vector3.ONE * s
			var c := box.get_center()
			model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	if _frames == 13:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out, " dim=", _dim)
		return true
	return false
