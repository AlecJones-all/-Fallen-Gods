extends SceneTree
## 第4关新模型核对：运行时 GLTFDocument 载入，正交取景渲染目录图。
## 用法: godot --path . --script res://tools/_l4_model_check.gd -- [宽] [高]

const MODELS := [
	"res://art/environments/白洗礼拜堂/主教祭坛-游戏.glb",
	"res://art/environments/白洗礼拜堂/双心跳祭龛-游戏.glb",
	"res://art/environments/白洗礼拜堂/记忆焚烧台-游戏.glb",
	"res://art/environments/白洗礼拜堂/唱诗班楼阳台-游戏.glb",
	"res://art/environments/白洗礼拜堂/悬挂圣徒铁笼-游戏.glb",
	"res://art/environments/白洗礼拜堂/沉没大教堂中殿-v2.glb",
	"res://art/environments/白洗礼拜堂/大理石台座.glb",
]
const OUT := "res://art/previews/l4_models"

var _size := Vector2i(400, 400)
var _index := 0
var _frame := 0
var _framed := false
var _holder: Node3D
var _camera: Camera3D
var _name := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_size = Vector2i(int(args[0]), int(args[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_size(_size)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#e8e4da")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#cfd6dd")
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	get_root().add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, 40, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	get_root().add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.7
	fill.light_color = Color("#c3d3e2")
	get_root().add_child(fill)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	get_root().add_child(_camera)
	_load_next()


func _process(_delta: float) -> bool:
	_frame += 1
	if _holder == null:
		return false
	if not _framed:
		_framed = true
		_frame_object()
		return false
	if _frame < 14:
		if _frame == 2:
			DisplayServer.window_set_size(_size)
		return false
	var path := "%s/%s.png" % [OUT, _name]
	var err := get_root().get_texture().get_image().save_png(path)
	print("SHOT ", _name, " -> ", error_string(err))
	_holder.queue_free()
	_holder = null
	_index += 1
	_frame = 0
	_framed = false
	_load_next()
	return false


func _load_next() -> void:
	if _index >= MODELS.size():
		print("L4 MODEL CHECK DONE")
		quit()
		return
	var src: String = MODELS[_index]
	_name = src.get_file().get_basename()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(src), state) != OK:
		push_error("load failed: " + src)
		_index += 1
		_load_next()
		return
	_holder = Node3D.new()
	_holder.name = _name
	get_root().add_child(_holder)
	var inst := doc.generate_scene(state) as Node3D
	_holder.add_child(inst)


func _frame_object() -> void:
	var box := _aabb(_holder)
	var center := box.get_center()
	var extent: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	_camera.size = box.size.length() * 1.12
	var dir := Vector3(1.0, 0.62, 1.35).normalized()
	_camera.position = center + dir * maxf(extent * 3.0, 1.0)
	_camera.look_at(center, Vector3.UP)
	_camera.near = 0.05
	_camera.far = maxf(extent * 12.0, 5.0)
	print("MODEL %-18s size=(%.2f, %.2f, %.2f) min_y=%.3f ortho=%.2f" % [_name, box.size.x, box.size.y, box.size.z, box.position.y, _camera.size])


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		mesh.force_update_transform()
		var local := mesh.global_transform * mesh.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out
