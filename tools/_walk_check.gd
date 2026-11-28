extends SceneTree

# 临时：把行走动画套到新模型上，检查裙摆/护甲是否穿模。
# 用法: godot --path . --resolution 1500x820 --script res://tools/_walk_check.gd -- out.png

const CLIP := "res://assets/anim_src/Great Sword Walk.fbx"

const CASES := [
	{"model": "res://assets/anim_src/Peasant Girl.fbx", "t": 0.20, "label": "Peasant Girl · 行走 0.2s"},
	{"model": "res://assets/anim_src/Peasant Girl.fbx", "t": 0.55, "label": "Peasant Girl · 行走 0.55s"},
	{"model": "res://assets/anim_src/Vanguard By T. Choonyung.fbx", "t": 0.40, "label": "Vanguard · 行走 0.4s"},
]

const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

var _frames := 0
var _out := "res://.tmp_walk.png"
var _models: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_out = "res://" + a[0]

	var scene := Node3D.new()
	get_root().add_child(scene)

	var anim := _load_clip(CLIP, "mixamo_com")

	for i in CASES.size():
		var c: Dictionary = CASES[i]
		var cell := Node3D.new()
		scene.add_child(cell)
		cell.position = Vector3((float(i) - 1.0) * 1.85, 0.0, 0.0)
		cell.rotation_degrees.y = -32.0

		var model: Node3D = (load(String(c["model"])) as PackedScene).instantiate()
		cell.add_child(model)
		_models.append(model)

		var ap := AnimationPlayer.new()
		model.add_child(ap)
		ap.root_node = NodePath("..")
		if anim != null:
			var lib := AnimationLibrary.new()
			lib.add_animation("play", anim)
			ap.add_animation_library("", lib)
		_players.append(ap)

		var label := Label3D.new()
		label.text = String(c["label"])
		label.font = load(FONT)
		label.font_size = 30
		label.pixel_size = 0.0026
		label.modulate = Color(1.0, 0.93, 0.82)
		label.outline_size = 0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector3(0.0, -0.18, 0.5)
		cell.add_child(label)

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = 27.0
	cam.transform = Transform3D(Basis(), Vector3(0.0, 1.02, 7.0)).looking_at(Vector3(0.0, 1.00, 0.0), Vector3.UP)
	cam.current = true

	_add_light(scene, Vector3(-26, -32, 0), 2.7)
	_add_light(scene, Vector3(-6, 140, 0), 1.1)
	_add_light(scene, Vector3(-12, 205, 0), 1.5)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.095, 0.088)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.80)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	scene.add_child(we)


func _load_clip(path: String, clip_name: String) -> Animation:
	if not ResourceLoader.exists(path):
		return null
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var src: AnimationPlayer = null
	for n: Node in root.find_children("*", "AnimationPlayer", true, false):
		src = n as AnimationPlayer
		break
	if src == null:
		root.free()
		return null
	var an: Animation = src.get_animation(clip_name).duplicate()
	root.free()
	return an


func _add_light(parent: Node3D, rot: Vector3, energy: float) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_energy = energy
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
			var s := 1.80 / box.size.y
			model.scale = Vector3.ONE * s
			var c := box.get_center()
			model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	if _frames == 6:
		for i in _players.size():
			var ap := _players[i]
			if ap.has_animation("play"):
				ap.play("play")
				ap.seek(float(CASES[i]["t"]), true)
				ap.pause()
	if _frames == 15:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
