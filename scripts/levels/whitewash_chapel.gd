extends Node3D
## 第 4 关：白洗礼拜堂（42 m × 37.6 m 三进式大厅）
##
## 前庭（+12.6 ~ +18）→ 中殿 + 双侧廊（−12.6 ~ +12.6）→ 后殿圣坛（−19.6 ~ −12.6）。
## 英雄道具走运行时 GLB：`art/environments/白洗礼拜堂/` 下的新模型。
## 后殿右墙开一道侧门，进门即返回关卡页（本关终点）。

@export var graybox := false

const Glb := preload("res://scripts/art/glb_scene.gd")
const NAVE_WALL := preload("res://assets/environment/chapel_nave_module.glb")
const PAVEMENT := preload("res://assets/materials/chapel_pavement.gdshader")
const STONE := preload("res://assets/materials/stone_crack_albedo.png")
const PLASTER := preload("res://assets/materials/plaster_albedo.png")
const WOOD := preload("res://assets/materials/wood_dry_albedo.png")

const MODEL_DIR := "res://art/environments/白洗礼拜堂/"
const MODEL_ALTAR := MODEL_DIR + "主教祭坛-游戏.glb"
const MODEL_SHRINE := MODEL_DIR + "双心跳祭龛-游戏.glb"
const MODEL_BRAZIER := MODEL_DIR + "记忆焚烧台-游戏.glb"
const MODEL_LOFT := MODEL_DIR + "唱诗班楼阳台-游戏.glb"
const MODEL_CAGE := MODEL_DIR + "悬挂圣徒铁笼-游戏.glb"
const MODEL_ARCADE := MODEL_DIR + "沉没大教堂中殿-v2.glb"
const MODEL_PLINTH := MODEL_DIR + "大理石台座.glb"

const HALF_W := 21.0
const Z_FRONT := 18.0
const Z_BACK := -19.6
const Z_NARTHEX := 12.6
const Z_CHANCEL := -12.6
const NARTHEX_HALF := 10.0
const APSE_HALF := 14.0
const COLONNADE_X := 16.5
const BAY := 8.4
const ORTHO := 17.0

var palette := {}
var shapes := {}
var batches := {}
var _brazier_light: OmniLight3D
var _altar_light: OmniLight3D
var _clock := 0.0


func _ready() -> void:
	var rig := get_node_or_null("CameraRig")
	if rig != null:
		rig.set("ortho_override", ORTHO)
		rig.rotation_degrees = Vector3(-38, 16, 0)

	var round_mesh := CylinderMesh.new()
	round_mesh.radial_segments = 24
	round_mesh.rings = 1
	round_mesh.height = 1.0
	var jewel := SphereMesh.new()
	jewel.radial_segments = 16
	jewel.rings = 6
	shapes = {"box": BoxMesh.new(), "round": round_mesh, "jewel": jewel}
	_make_material("chalk", "#c9bfa8")
	_make_material("edge", "#e4d9bb")
	_make_material("slate", "#424b50")
	_make_material("apse", "#4b4740")
	_make_material("oak", "#4f352e")
	_make_material("bronze", "#aa8451", 0.52)
	_make_material("velvet", "#622b37")
	_make_material("lead", "#343c41", 0.35)
	_make_material("amber", "#e1a25c", 0.18, 0.48)
	_make_material("blue", "#507887", 0.10, 0.33)
	_make_material("ruby", "#a74e49", 0.10, 0.42)

	_floor()
	_outer_shell()
	_narthex()
	_colonnades()
	_chancel()
	if not graybox:
		_benches()
		_votives()
		_hero_props()
	_lights()
	_exit_gate()
	_flush_batches()


func _process(delta: float) -> void:
	_clock += delta
	if _brazier_light != null:
		_brazier_light.light_energy = 1.55 + sin(_clock * 7.3) * 0.12 + sin(_clock * 3.1) * 0.08
	if _altar_light != null:
		_altar_light.light_energy = 3.4 + sin(_clock * 1.7) * 0.16


func _make_material(key: String, color: String, metal := 0.0, glow := 0.0) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.metallic = metal
	mat.roughness = 0.76 - metal * 0.35
	if key in ["chalk", "oak"]:
		mat.albedo_texture = PLASTER if key == "chalk" else WOOD
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * 0.45
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(color)
		mat.emission_energy_multiplier = glow
	palette[key] = mat


func _piece(kind: String, finish: String, at: Vector3, size: Vector3, angle := 0.0) -> void:
	var key := kind + "/" + finish
	if not batches.has(key):
		batches[key] = []
	batches[key].append(Transform3D(Basis(Vector3.BACK, angle).scaled_local(size), at))


func _flush_batches() -> void:
	for key: String in batches:
		var parts := key.split("/")
		var transforms: Array = batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = shapes[parts[0]]
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
		var inst := MultiMeshInstance3D.new()
		inst.name = key.replace("/", "_")
		inst.multimesh = multi
		inst.material_override = palette[parts[1]]
		add_child(inst)


func _solid(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	body.position = at
	add_child(body)


func _floor() -> void:
	var pavement := MeshInstance3D.new()
	var surface := PlaneMesh.new()
	surface.size = Vector2(46, 42)
	pavement.mesh = surface
	var mat := ShaderMaterial.new()
	mat.shader = PAVEMENT
	mat.set_shader_parameter("worn_stone", STONE)
	mat.set_shader_parameter("graybox", graybox)
	pavement.material_override = mat
	add_child(pavement)
	_solid(Vector3(0, -0.25, 0), Vector3(46, 0.5, 42))
	# 地面薄板分区：中央走道、两侧廊道、前庭
	_piece("box", "slate", Vector3(0, 0.04, 0), Vector3(9.0, 0.06, 25.0))
	for side in [-1.0, 1.0]:
		_piece("box", "slate", Vector3(side * 19.0, 0.04, 0), Vector3(3.8, 0.06, 25.0))
	_piece("box", "slate", Vector3(0, 0.04, 15.3), Vector3(7.0, 0.06, 5.4))


func _outer_shell() -> void:
	# 分层叠放：基座 0–0.48 / 墙身 0.48–3.48 / 压顶 3.48–3.62，段间不留重叠。
	var wall_len := Z_NARTHEX - Z_BACK
	var wall_mid := (Z_NARTHEX + Z_BACK) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * HALF_W
		_piece("box", "slate", Vector3(x, 0.24, wall_mid), Vector3(0.90, 0.48, wall_len))
		_piece("box", "chalk", Vector3(x, 1.98, wall_mid), Vector3(0.72, 3.00, wall_len))
		_piece("box", "edge", Vector3(x, 3.55, wall_mid), Vector3(0.90, 0.14, wall_len))
		_solid(Vector3(x, 1.75, wall_mid), Vector3(0.90, 3.50, wall_len))
		for i in 8:
			var z: float = Z_NARTHEX - 1.6 - i * 4.2
			_piece("box", "chalk", Vector3(x - side * 0.42, 1.98, z), Vector3(0.62, 3.00, 0.90))
			if i < 7:
				_piece("box", "lead", Vector3(x - side * 0.40, 2.35, z + 2.1), Vector3(0.06, 1.50, 1.40))
				_piece("box", "blue", Vector3(x - side * 0.455, 2.35, z + 2.1), Vector3(0.02, 1.34, 1.24))
	# 横向隔墙：在柱廊处断开，避免与柱廊模块端头共面。
	var inner_edge := COLONNADE_X - 0.70
	var outer_edge := COLONNADE_X + 0.70
	for side in [-1.0, 1.0]:
		_cross_wall(side, Z_NARTHEX, NARTHEX_HALF, inner_edge, outer_edge)
		_cross_wall(side, Z_CHANCEL, APSE_HALF, inner_edge, outer_edge)
	# 后殿两侧墙（右墙开侧门）
	var apse_len := Z_CHANCEL - Z_BACK
	var apse_mid := (Z_CHANCEL + Z_BACK) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * APSE_HALF
		if side > 0.0:
			# z 从 −19.6 到 −17.7 与 −15.3 到 −12.6，中间 2.4 m 门洞
			var near_len := Z_CHANCEL - (-15.3)
			_piece("box", "slate", Vector3(x, 0.24, (-15.3 + Z_CHANCEL) * 0.5), Vector3(0.80, 0.48, near_len))
			_piece("box", "chalk", Vector3(x, 1.98, (-15.3 + Z_CHANCEL) * 0.5), Vector3(0.64, 3.00, near_len))
			_piece("box", "edge", Vector3(x, 3.55, (-15.3 + Z_CHANCEL) * 0.5), Vector3(0.80, 0.14, near_len))
			_solid(Vector3(x, 1.75, (-15.3 + Z_CHANCEL) * 0.5), Vector3(0.80, 3.50, near_len))
			var far_len := -17.7 - Z_BACK
			_piece("box", "slate", Vector3(x, 0.24, (-17.7 + Z_BACK) * 0.5), Vector3(0.80, 0.48, far_len))
			_piece("box", "chalk", Vector3(x, 1.98, (-17.7 + Z_BACK) * 0.5), Vector3(0.64, 3.00, far_len))
			_piece("box", "edge", Vector3(x, 3.55, (-17.7 + Z_BACK) * 0.5), Vector3(0.80, 0.14, far_len))
			_solid(Vector3(x, 1.75, (-17.7 + Z_BACK) * 0.5), Vector3(0.80, 3.50, far_len))
			# 门楣与两扇半开的木门
			_piece("box", "chalk", Vector3(x, 2.50, -16.5), Vector3(0.64, 0.60, 2.40))
			_solid(Vector3(x, 3.0, -16.5), Vector3(0.80, 1.00, 2.40))
			_piece("box", "oak", Vector3(x - side * 0.55, 1.15, -17.45), Vector3(0.12, 2.20, 1.10))
			_piece("box", "oak", Vector3(x - side * 0.55, 1.15, -15.55), Vector3(0.12, 2.20, 1.10))
		else:
			_piece("box", "slate", Vector3(x, 0.24, apse_mid), Vector3(0.80, 0.48, apse_len))
			_piece("box", "chalk", Vector3(x, 1.98, apse_mid), Vector3(0.64, 3.00, apse_len))
			_piece("box", "edge", Vector3(x, 3.55, apse_mid), Vector3(0.80, 0.14, apse_len))
			_solid(Vector3(x, 1.75, apse_mid), Vector3(0.80, 3.50, apse_len))
	# 后殿端墙
	_piece("box", "slate", Vector3(0, 0.24, Z_BACK), Vector3(APSE_HALF * 2.0, 0.48, 0.90))
	_piece("box", "apse", Vector3(0, 2.84, Z_BACK), Vector3(APSE_HALF * 2.0, 4.72, 0.72))
	_solid(Vector3(0, 2.60, Z_BACK), Vector3(APSE_HALF * 2.0, 5.20, 0.90))
	# 侧门外的短通道
	_piece("box", "slate", Vector3(14.0 + 1.6, 0.11, -16.5), Vector3(3.2, 0.22, 2.6))
	_piece("box", "chalk", Vector3(14.0 + 3.2, 1.98, -16.5), Vector3(0.64, 3.00, 2.6))
	_piece("box", "chalk", Vector3(14.0 + 1.6, 1.98, -17.8), Vector3(3.2, 3.00, 0.5))
	_solid(Vector3(14.0 + 1.6, 1.75, -17.8), Vector3(3.2, 3.50, 0.5))
	_piece("box", "chalk", Vector3(14.0 + 1.6, 1.98, -15.2), Vector3(3.2, 3.00, 0.5))
	_solid(Vector3(14.0 + 1.6, 1.75, -15.2), Vector3(3.2, 3.50, 0.5))


func _cross_wall(side: float, z: float, from_x: float, inner_edge: float, outer_edge: float) -> void:
	# 横向隔墙拆成柱廊两侧两段，柱廊自身补上中间的口子。
	for span_pair in [[from_x, inner_edge], [outer_edge, HALF_W]]:
		var a: float = span_pair[0]
		var b: float = span_pair[1]
		var span: float = b - a
		if span <= 0.01:
			continue
		var x: float = side * (a + span * 0.5)
		_piece("box", "slate", Vector3(x, 0.24, z), Vector3(span, 0.48, 0.90))
		_piece("box", "chalk", Vector3(x, 1.98, z), Vector3(span, 3.00, 0.72))
		_piece("box", "edge", Vector3(x, 3.55, z), Vector3(span, 0.14, 0.90))
		_solid(Vector3(x, 1.75, z), Vector3(span, 3.50, 0.90))


func _narthex() -> void:
	# 前庭层高更低：基座 0–0.40 / 墙身 0.40–2.70 / 压顶 2.70–2.82。
	var depth := Z_FRONT - Z_NARTHEX
	var mid := (Z_FRONT + Z_NARTHEX) * 0.5
	for side in [-1.0, 1.0]:
		var x: float = side * NARTHEX_HALF
		_piece("box", "slate", Vector3(x, 0.20, mid), Vector3(0.80, 0.40, depth))
		_piece("box", "chalk", Vector3(x, 1.55, mid), Vector3(0.62, 2.30, depth))
		_piece("box", "edge", Vector3(x, 2.76, mid), Vector3(0.78, 0.12, depth))
		_solid(Vector3(x, 1.40, mid), Vector3(0.80, 2.80, depth))
	var door_half := 1.6
	var wing: float = NARTHEX_HALF - door_half
	for side in [-1.0, 1.0]:
		var x: float = side * (door_half + wing * 0.5)
		_piece("box", "slate", Vector3(x, 0.20, Z_FRONT), Vector3(wing, 0.40, 0.80))
		_piece("box", "chalk", Vector3(x, 1.55, Z_FRONT), Vector3(wing, 2.30, 0.62))
		_piece("box", "edge", Vector3(x, 2.76, Z_FRONT), Vector3(wing, 0.12, 0.78))
		_solid(Vector3(x, 1.40, Z_FRONT), Vector3(wing, 2.80, 0.90))
		_piece("box", "oak", Vector3(side * door_half * 0.5, 1.15, Z_FRONT - 0.10), Vector3(door_half, 2.20, 0.12))
		_piece("box", "bronze", Vector3(side * door_half * 0.92, 1.05, Z_FRONT - 0.19), Vector3(0.08, 0.50, 0.08))
	_piece("box", "chalk", Vector3(0, 2.48, Z_FRONT), Vector3(door_half * 2.0, 0.50, 0.62))
	_piece("box", "edge", Vector3(0, 2.82, Z_FRONT), Vector3(door_half * 2.0 + 0.40, 0.16, 0.78))
	_solid(Vector3(0, 2.50, Z_FRONT), Vector3(door_half * 2.0, 0.90, 0.90))
	for x: float in [-7.2, 7.2]:
		_piece("box", "oak", Vector3(x, 0.44, 15.4), Vector3(3.40, 0.14, 0.60))
		_piece("box", "oak", Vector3(x, 0.72, 15.68), Vector3(3.40, 0.50, 0.12))
		_piece("box", "bronze", Vector3(x, 1.00, 15.68), Vector3(3.40, 0.06, 0.14))
		_solid(Vector3(x, 0.45, 15.4), Vector3(3.40, 0.90, 0.70))


func _colonnades() -> void:
	# 每侧 3 段两开间模块，沿 Z 铺满中殿。
	for side in [-1.0, 1.0]:
		for i in 3:
			var centre: float = -BAY + i * BAY
			var wall := NAVE_WALL.instantiate() as Node3D
			wall.rotation.y = 0.0
			wall.position = Vector3(side * COLONNADE_X, 0, centre)
			add_child(wall)
			for panel in wall.find_children("*", "MeshInstance3D", true, false):
				var mesh := panel as MeshInstance3D
				var original := mesh.get_active_material(0) as StandardMaterial3D
				if original and original.resource_name == "Aged pale limestone":
					mesh.material_override = palette["chalk"]
			# 接缝壁柱：盖住模块雕饰层在接缝处 20 cm 的重叠
			for seam in [-BAY * 0.5, BAY * 0.5]:
				_piece("box", "chalk", Vector3(side * COLONNADE_X, 3.0, centre + seam), Vector3(1.30, 6.00, 1.30))
				_piece("box", "edge", Vector3(side * COLONNADE_X, 6.05, centre + seam), Vector3(1.50, 0.16, 1.50))
				_solid(Vector3(side * COLONNADE_X, 1.0, centre + seam), Vector3(1.45, 2.0, 1.45))


func _chancel() -> void:
	# 四段拱廊墙拼成后殿整面墙，自带石台当高台地面。
	for x: float in [-6.75, -2.25, 2.25, 6.75]:
		Glb.place(self, MODEL_ARCADE, Vector3(x, 0.0, Z_BACK), 0.0, 0.56)
	_solid(Vector3(0, 0.16, -16.24), Vector3(17.9, 0.32, 6.72))
	# 台前一级踏步：主踏步 0–0.22，压边 0.22–0.32
	_piece("box", "slate", Vector3(0, 0.11, -12.10), Vector3(18.4, 0.22, 1.20))
	_piece("box", "edge", Vector3(0, 0.27, -12.70), Vector3(18.2, 0.10, 0.16))


func _benches() -> void:
	# 6 排、3.6 m 排距、9 m 长：中央留 10 m 宽，靠柱廊再留 1.9 m 走位。
	for z: float in [9.0, 5.4, 1.8, -1.8, -5.4, -9.0]:
		for side in [-1.0, 1.0]:
			var x: float = side * 9.5
			_piece("box", "oak", Vector3(x, 0.44, z), Vector3(9.00, 0.14, 0.62))
			_piece("box", "oak", Vector3(x, 0.74, z + 0.26), Vector3(9.00, 0.52, 0.10))
			_piece("box", "bronze", Vector3(x, 1.03, z + 0.26), Vector3(9.00, 0.06, 0.14))
			for end: float in [-4.20, 4.20]:
				_piece("box", "oak", Vector3(x + end, 0.22, z), Vector3(0.18, 0.44, 0.62))
			_solid(Vector3(x, 0.50, z), Vector3(9.00, 1.00, 0.72))


func _votives() -> void:
	for x: float in [-19.2, 19.2]:
		for z: float in [-9.6, -4.8, 0.0, 4.8, 9.6]:
			_piece("round", "slate", Vector3(x, 0.12, z), Vector3(0.7, 0.24, 0.7))
			_piece("round", "bronze", Vector3(x, 0.62, z), Vector3(0.14, 0.86, 0.14))
			_piece("round", "lead", Vector3(x, 1.08, z), Vector3(0.78, 0.1, 0.78))
			for i in 5:
				var a := TAU * i / 5.0
				var stem := Vector3(x + cos(a) * 0.24, 1.24, z + sin(a) * 0.24)
				_piece("round", "edge", stem, Vector3(0.07, 0.2, 0.07))
				_piece("jewel", "amber", stem + Vector3.UP * 0.14, Vector3(0.05, 0.11, 0.05))
			var light := OmniLight3D.new()
			light.position = Vector3(x, 1.75, z)
			light.light_color = Color("#ffc183")
			light.light_energy = 0.95
			light.omni_range = 4.8
			add_child(light)


func _hero_props() -> void:
	Glb.place(self, MODEL_BRAZIER, Vector3(0, 0, 0.0), 0.0, 1.0)
	Glb.place(self, MODEL_ALTAR, Vector3(0, 0.34, -15.4), 90.0, 1.5)
	for side in [-1.0, 1.0]:
		Glb.place(self, MODEL_PLINTH, Vector3(side * 3.9, 0.62, -16.0), 0.0, 1.15)
	var shrine := Node3D.new()
	shrine.name = "Shrine"
	shrine.position = Vector3(0, 0.34, -17.7)
	add_child(shrine)
	var model := Glb.load_node(MODEL_SHRINE)
	if model != null:
		shrine.add_child(model)
	var heartbeat := Node3D.new()
	heartbeat.name = "Heartbeat"
	heartbeat.set_script(load("res://双心跳祭龛.gd"))
	var upper := OmniLight3D.new()
	upper.name = "UpperHeartbeatLight"
	upper.position = Vector3(0, 1.42, 0.55)
	upper.light_color = Color(0.72, 0.84, 1, 1)
	upper.omni_range = 1.1
	var lower := OmniLight3D.new()
	lower.name = "LowerHeartbeatLight"
	lower.position = Vector3(0, 0.72, 0.55)
	lower.light_color = Color(1, 0.66, 0.50, 1)
	lower.omni_range = 1.1
	heartbeat.add_child(upper)
	heartbeat.add_child(lower)
	shrine.add_child(heartbeat)
	var cage := Glb.place(self, MODEL_CAGE, Vector3(0, 1.9, -3.0), 0.0, 1.0)
	if cage != null:
		cage.name = "HangingCage"
	Glb.place(self, MODEL_LOFT, Vector3(0, 5.45, -18.4), 90.0, 1.0)


func _lights() -> void:
	var altar := OmniLight3D.new()
	altar.name = "AltarLantern"
	altar.position = Vector3(0, 3.6, -15.4)
	altar.light_color = Color("#ffb877")
	altar.light_energy = 3.4
	altar.omni_range = 13.0
	add_child(altar)
	_altar_light = altar

	var brazier := OmniLight3D.new()
	brazier.name = "BrazierLight"
	brazier.position = Vector3(0, 1.5, 0.0)
	brazier.light_color = Color("#ff9b52")
	brazier.light_energy = 1.55
	brazier.omni_range = 7.0
	add_child(brazier)
	_brazier_light = brazier

	var narthex := OmniLight3D.new()
	narthex.position = Vector3(0, 2.6, 15.4)
	narthex.light_color = Color("#c9d7e8")
	narthex.light_energy = 1.2
	narthex.omni_range = 7.5
	add_child(narthex)

	for side in [-1.0, 1.0]:
		var apse := OmniLight3D.new()
		apse.position = Vector3(side * 7.5, 3.2, -17.0)
		apse.light_color = Color("#ffc98f")
		apse.light_energy = 1.8
		apse.omni_range = 8.5
		add_child(apse)


func _exit_gate() -> void:
	var gate := Area3D.new()
	gate.name = "ExitGate"
	gate.position = Vector3(15.6, 1.0, -16.5)
	gate.collision_layer = 0
	gate.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.2)
	shape.shape = box
	gate.add_child(shape)
	gate.set_script(preload("res://scripts/levels/exit_gate.gd"))
	add_child(gate)
