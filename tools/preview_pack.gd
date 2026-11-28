extends SceneTree

# 动作包预览图：每段取 3 帧（起手/中点/收势）拼成一条横带
# 用法: godot --path . --resolution 360x520 --script res://tools/preview_pack.gd
# 产出: dist/anim_pack_v1/preview/<clip>.png + _overview.png

const RIG := "res://scenes/player/rogue_knight_v2.tscn"
const PACK := "res://dist/anim_pack_v1/rogue_knight_anims.tres"
const OUT_DIR := "res://dist/anim_pack_v1/preview/"
const W := 360
const H := 520
const PICK := ["roll", "attack_blade", "aim_walk", "charge_hold_blade", "charge_hold_axe", "attack_axe",
	"attack_axe_heavy", "attack_axe_leap", "equip_shared", "reload_xbow", "hit_head"]
const PHASES := [0.18, 0.5, 0.82]
const WAIT := 6
## 贴地类片段单独取景：翻滚会把髋部压到 0.13m，用站姿取景会出画
const LOW_CLIPS := ["roll", "attack_axe_leap"]

var _ap: AnimationPlayer
var _job := 0
var _ph := 0
var _armed := false
var _wait := 0
var _strips: Array[String] = []
var _strip: Image
var _imgs: Array[Image] = []
var _cam: Camera3D


func _frame_for(clip: String) -> void:
	if _cam == null:
		return
	if LOW_CLIPS.has(clip):
		_cam.transform = Transform3D(Basis(), Vector3(3.4, 1.5, 4.9)).looking_at(
			Vector3(0.0, 0.75, 0.0), Vector3.UP)
	else:
		_cam.transform = Transform3D(Basis(), Vector3(4.2, 2.5, 6.3)).looking_at(
			Vector3(0.0, 1.95, 0.0), Vector3.UP)


func _initialize() -> void:
	var scene := Node3D.new()
	get_root().add_child(scene)
	var inst: Node3D = (load(RIG) as PackedScene).instantiate()
	scene.add_child(inst)
	_ap = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_ap.remove_animation_library("")
	_ap.add_animation_library("", load(PACK))
	_ap.pause()
	_ap.seek(0.0, true)

	var cam := Camera3D.new()
	cam.fov = 32.0
	scene.add_child(cam)
	_cam = cam
	_frame_for("")
	cam.current = true

	var l1 := DirectionalLight3D.new()
	scene.add_child(l1)
	l1.rotation_degrees = Vector3(-38, -52, 0)
	l1.light_energy = 2.3
	var l2 := DirectionalLight3D.new()
	scene.add_child(l2)
	l2.rotation_degrees = Vector3(-12, 148, 0)
	l2.light_energy = 1.0

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.26, 0.27, 0.3)
	ground.material_override = gm
	scene.add_child(ground)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 1.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	scene.add_child(we)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_start_job()


func _start_job() -> void:
	if _job >= PICK.size():
		_finish()
		return
	var clip: String = PICK[_job]
	if not _ap.has_animation(clip):
		_job += 1
		_start_job()
		return
	_frame_for(clip)
	_ap.play(clip)
	_ap.pause()
	_ph = 0
	_wait = 0
	_armed = false
	_imgs = []


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < WAIT:
		return false
	_wait = 0
	var clip: String = PICK[_job]
	# 先 seek 定格，等一帧让骨骼真的更新，再截图（否则截到的是上一帧姿势）
	if not _armed:
		_ap.seek(_ap.get_animation(clip).length * PHASES[_ph], true)
		_armed = true
		return false
	_imgs.append(get_root().get_texture().get_image())
	_armed = false
	_ph += 1
	if _ph < PHASES.size():
		return false
	_save_strip(clip)
	_job += 1
	_start_job()
	return false


func _save_strip(clip: String) -> void:
	if _imgs.size() != PHASES.size():
		return
	var strip := Image.create(W * PHASES.size(), H, false, _imgs[0].get_format())
	for i in _imgs.size():
		var im: Image = _imgs[i]
		if im.get_width() != W or im.get_height() != H:
			im.resize(W, H, Image.INTERPOLATE_BILINEAR)
		strip.blit_rect(im, Rect2i(0, 0, W, H), Vector2i(i * W, 0))
	var path := OUT_DIR + clip + ".png"
	strip.save_png(path)
	_strips.append(path)
	print("  strip ", path)


func _finish() -> void:
	# 总览：把各条横带竖向拼（缩到 45%）
	if _strips.is_empty():
		quit(1)
		return
	var first := Image.load_from_file(ProjectSettings.globalize_path(_strips[0]))
	var sw := int(first.get_width() * 0.5)
	var sh := int(first.get_height() * 0.5)
	var sheet := Image.create(sw, sh * _strips.size(), false, first.get_format())
	for i in _strips.size():
		var im := Image.load_from_file(ProjectSettings.globalize_path(_strips[i]))
		im.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, sw, sh), Vector2i(0, i * sh))
	sheet.save_png(OUT_DIR + "_overview.png")
	print("saved ", _strips.size(), " strips + _overview.png")
	quit(0)
	return
