extends SceneTree

# 连弩上色方案对比（只读）：同一把蒸汽朋克弩，四套配色，俯角 55° 出图
# 用法: godot --path . --script res://tools/tint_xbow.gd

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const TSCN := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"
const OUT_DIR := "res://docs/19_武器模型/review"
const FONT := "res://assets/fonts/NotoSansSC-Regular.ttf"

const VARIANTS := [
	{"name": "0 原色", "tint": Color(1, 1, 1), "metal": 0.15, "rough": 0.82, "gem": false},
	{"name": "A 旧化冷钢", "tint": Color(0.80, 0.82, 0.86), "metal": 0.05, "rough": 0.94, "gem": false},
	{"name": "B 铁锈暖", "tint": Color(1.00, 0.78, 0.62), "metal": 0.08, "rough": 0.90, "gem": false},
	{"name": "C 烬纹暗红", "tint": Color(0.62, 0.56, 0.56), "metal": 0.10, "rough": 0.88, "gem": true},
]

var _root: Node3D
var _cam: Camera3D
var _label: Label3D
var _inst: Node3D
var _parts: Array[MeshInstance3D] = []
var _gem_idx := -1
var _frame := 0
var _i := 0
var _pending := false


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
	for m: Node in _inst.find_children("*", "MeshInstance3D", true, false):
		_parts.append(m as MeshInstance3D)

	# 找出红色占比最高的部件 = 宝石
	var best := -1.0
	var best_i := -1
	for i in _parts.size():
		var mat := _parts[i].material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			continue
		var img: Image = mat.albedo_texture.get_image()
		if img == null:
			continue
		img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var red := 0
		for y in 32:
			for x in 32:
				var c := img.get_pixel(x, y)
				if c.r > 0.25 and c.r > c.g * 1.6 and c.r > c.b * 1.6:
					red += 1
		var frac := float(red) / 1024.0
		print("part %d 红色占比 %.3f" % [i, frac])
		if frac > best:
			best = frac
			best_i = i
	if best > 0.02:
		_gem_idx = best_i
	print("宝石件 = ", _gem_idx, " (%.3f)" % best)

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
	if _i >= VARIANTS.size():
		return true
	var v: Dictionary = VARIANTS[_i]
	if not _pending:
		for i in _parts.size():
			var mat := (_parts[i].material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			mat.albedo_color = v["tint"]
			mat.metallic = v["metal"]
			mat.roughness = v["rough"]
			if bool(v["gem"]) and i == _gem_idx:
				mat.emission_enabled = true
				mat.emission = Color(0.55, 0.10, 0.08)
				mat.emission_energy_multiplier = 2.2
			_parts[i].material_override = mat
		var box := AABB()
		var first := true
		for mi in _parts:
			var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		var c := box.get_center()
		if _i == 0:
			print("aabb=", box, " cam_target=", c)
		var b := Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(45), 0))
		_cam.global_transform = Transform3D(b, c + b * Vector3(0, 0, 3))
		_cam.size = 0.95
		_label.text = String(v["name"])
		_label.pixel_size = 0.95 * 0.0011
		_label.position = Vector3(-0.43, -0.44, -1.0)
		_pending = true
		return false
	get_root().get_texture().get_image().save_png("%s/tint_%d.png" % [OUT_DIR, _i])
	print("saved ", v["name"])
	_pending = false
	_i += 1
	return false
