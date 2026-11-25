extends SceneTree

# P3 调光诊断：同机位对比雾参数/后期/SSAO/glow，输出明度统计与截图。
# 用法：godot --path . --script res://tools/_tune_probe.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

const VARIANTS := [
	{ "name": "base" },
	{ "name": "fog_b", "fog_set": { "color": [0.16, 0.135, 0.125], "density": 0.009, "height": 1.4, "hd": 0.6 } },
	{ "name": "fog_d", "fog_set": { "color": [0.145, 0.122, 0.113], "density": 0.009, "height": 1.4, "hd": 0.5 } },
	{ "name": "fog_e", "fog_set": { "color": [0.135, 0.113, 0.105], "density": 0.010, "height": 1.4, "hd": 0.6 } },
	{ "name": "fog_f", "fog_set": { "color": [0.16, 0.135, 0.125], "density": 0.010, "height": 1.4, "hd": 0.2 } },
	{ "name": "fog_b_exp18", "fog_set": { "color": [0.16, 0.135, 0.125], "density": 0.009, "height": 1.4, "hd": 0.6 },
		"env_set": { "tonemap_exposure": 1.8 } },
]

var _m: Node
var _oil: CanvasLayer
var _env: Environment
var _f := 0
var _i := 0
var _stage := 0
var _px := 7.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_px = float(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	var we := _m.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we != null else null


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_oil = _m.get_node_or_null("OilGrade") as CanvasLayer
		var player := _m.get_node_or_null("World/Player") as Node3D
		var world := _m.get_node_or_null("World") as Node3D
		var rig := _m.get_node_or_null("CameraRig") as Node3D
		if player != null:
			player.position = Vector3(_px, 0.05, 0.0)
		if rig != null and world != null:
			rig.global_position = world.transform * Vector3(_px, 1.0, 0.0)
		print("OIL layer=", _oil != null, " x=", _px)
	if _f < 20:
		return false
	if _i >= VARIANTS.size():
		print("TUNE DONE")
		return true
	if _stage == 0:
		_apply(VARIANTS[_i])
		_stage = 1
		return false
	if _stage == 1:
		_stage = 2
		return false
	if _stage == 2:
		var v: Dictionary = VARIANTS[_i]
		var img := get_root().get_texture().get_image()
		img.save_png("res://docs/baseline/tune_%s.png" % String(v["name"]))
		_stats(String(v["name"]), img)
		_reset()
		_i += 1
		_stage = 0
	return false


func _apply(v: Dictionary) -> void:
	_reset()
	if _oil != null and v.has("post"):
		_oil.visible = bool(v["post"])
	if v.has("post_set"):
		var mat := _post_mat()
		if mat != null:
			var ps: Dictionary = v["post_set"]
			for key: String in ps:
				mat.set_shader_parameter(key, ps[key])
	if _env == null:
		return
	if v.has("fog"):
		_env.fog_enabled = bool(v["fog"])
	if v.has("fog_set"):
		var fs: Dictionary = v["fog_set"]
		var c: Array = fs["color"]
		_env.fog_enabled = true
		_env.fog_light_color = Color(float(c[0]), float(c[1]), float(c[2]))
		_env.fog_density = float(fs["density"])
		_env.set("fog_height", float(fs["height"]))
		_env.set("fog_height_density", float(fs["hd"]))
	if v.has("env_set"):
		var es: Dictionary = v["env_set"]
		for key: String in es:
			_env.set(key, es[key])


func _post_mat() -> ShaderMaterial:
	if _oil == null:
		return null
	var rect := _oil.get_node_or_null("Grade") as ColorRect
	if rect == null:
		return null
	return rect.material as ShaderMaterial


func _reset() -> void:
	if _oil != null:
		_oil.visible = true
		var mat := _post_mat()
		if mat != null:
			mat.set_shader_parameter("vignette_strength", 0.42)
			mat.set_shader_parameter("vignette_start", 0.30)
			mat.set_shader_parameter("contrast_boost", 1.12)
			mat.set_shader_parameter("posterize_mix", 0.22)
			mat.set_shader_parameter("warm_lift", 0.26)
			mat.set_shader_parameter("shadow_tint", Color(0.19, 0.14, 0.10))
	if _env == null:
		return
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.16, 0.135, 0.125)
	_env.fog_density = 0.009
	_env.set("fog_height", 1.4)
	_env.set("fog_height_density", 0.6)
	_env.tonemap_exposure = 2.0
	_env.ambient_light_energy = 0.260
	_env.ssao_enabled = true
	_env.glow_enabled = true


func _stats(name: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var step := 2
	var total := 0
	var dark := 0
	var bright := 0
	var sum := 0.0
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			var c := img.get_pixel(x, y)
			var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			sum += l
			total += 1
			if l < 0.25:
				dark += 1
			if l > 0.70:
				bright += 1
	print("%s mean=%.3f dark=%.1f%% bright=%.1f%%" % [
		name, sum / float(total),
		100.0 * float(dark) / float(total),
		100.0 * float(bright) / float(total)])