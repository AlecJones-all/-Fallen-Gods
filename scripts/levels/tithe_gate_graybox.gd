extends Node3D

## 什一税道·税卡灰盒：读 data/levels/tithe_gate.json（布局）+ data/kit/tithe_gate_kit.json（模块规格）。
## 所有构件都由模块 id 摆出来，脚本里不再写死尺寸——尺寸改动只改 kit。
## 约定：原点在村口道西南角地面，+x 沿路前进，z 越大越靠近相机。

const SPEC_PATH := "res://data/levels/tithe_gate.json"
const KIT_PATH := "res://data/kit/tithe_gate_kit.json"
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const KIT_ART := preload("res://scripts/art/kit_art.gd")
const FLOOR_THICKNESS := 0.5
const CELL := 2.0
## 场地整体绕 Y 轴转 135°，让本地 +x 对齐相机前方（yaw 45° 的水平朝向）。
## 这样按 W 就是沿路往前走，而不是横着穿路。
const WORLD_YAW_DEG := 135.0

var _spec: Dictionary = {}
var _kit: Dictionary = {}
var _materials: Dictionary = {}
var _geometry: Node3D
var _world: Node3D
var _enemies_root: Node3D
var _triggered: Dictionary = {}
var _alive: int = 0
var _zone_rects: Array[Rect2] = []
var _spawn := Vector3(2.0, 0.05, 0.0)
var _placed: int = 0


func _ready() -> void:
	_spec = _load_json(SPEC_PATH)
	_kit = _load_json(KIT_PATH)
	if _spec.is_empty() or _kit.is_empty():
		return

	_make_materials()
	_world = get_node_or_null("World") as Node3D
	if _world != null:
		_world.rotation.y = deg_to_rad(WORLD_YAW_DEG)
	_geometry = get_node_or_null("World/Geometry") as Node3D
	if _geometry == null:
		_geometry = Node3D.new()
		_geometry.name = "Geometry"
		add_child(_geometry)

	_read_zones()
	var wall_only := _off("wallonly")
	_build_outside_ground()
	if not wall_only:
		_build_floors()
	_build_walls()
	if wall_only:
		for k: Vector2i in _wall_heights:
			print("  wall block x=%d z=%d h=%.1f" % [k.x, k.y, float(_wall_heights[k])])
	if not wall_only:
		_build_boundary_strip()
	_build_wall_attachments()
	if not wall_only:
		_build_outside_ruins()
		_build_road()
		_build_road_detail()
		_build_gate()
		_build_fences()
		_build_booth()
		_build_props()
		_build_exit_marker()
		_build_portal()
	_place_player()
	_apply_camera()
	# 调试开关：带参数 nofight 时不刷怪，便于拍干净的构图
	if not OS.get_cmdline_user_args().has("nofight"):
		_build_encounters()
	_tone_actor()
	_tune_hud()
	# 调试开关：带参数 flat 时跳过光照与后期，只看材质
	if not OS.get_cmdline_user_args().has("flat"):
		_setup_mood()
		_setup_atmosphere()
		_setup_post()

	print("[TitheGate] 灰盒完成：%d 个模块实例，%d 种模块" % [_placed, (_kit.get("modules", []) as Array).size()])


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("TitheGateGraybox: 无法解析 %s" % path)
		return {}
	return parsed


## 批 4：机位 / 光 / 空气 / 远景 / 角色色调，全部集中在下面几段，方便回退。

const GATE_PITCH := -35.0
const GATE_ORTHO := 11.0
const CANDLE_XS: Array[float] = [4.0, 9.0, 18.0, 26.0, 34.0, 42.0]
const CANDLE_BASE := 1.70

var _candles: Array[OmniLight3D] = []
var _clock: float = 0.0
var _exiting: bool = false


func _process(delta: float) -> void:
	# 烛火是画面里唯一会动的东西：两个不同周期的正弦叠加，避免机械感
	if _candles.is_empty():
		return
	_clock += delta
	for i: int in _candles.size():
		var phase := float(i) * 1.7
		var flicker := 0.88 + 0.12 * sin(_clock * 7.3 + phase) + 0.05 * sin(_clock * 17.1 + phase * 2.0)
		_candles[i].light_energy = CANDLE_BASE * flicker


## 只调本场景的俯角。-50° 的遮挡带 2.52m 小于墙离路缘的 3.0m，走位尺寸不变。
func _apply_camera() -> void:
	var rig := get_node_or_null("CameraRig") as Node3D
	if rig == null:
		return
	rig.rotation_degrees = Vector3(GATE_PITCH, 45.0, 0.0)
	var cam := rig.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.size = GATE_ORTHO


func _setup_mood() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.60, 0.68, 0.86)
		sun.light_energy = 1.50
		sun.rotation_degrees = Vector3(-50.0, 236.0, 0.0)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 70.0

	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.065, 0.055, 0.052)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.115, 0.090)
	env.ambient_light_energy = 0.260
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.72

	# 接触阴影：没有这一层，所有东西都像贴在地上的贴纸
	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 2.4
	env.ssao_power = 1.5

	env.glow_enabled = false
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 2.0

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.098, 0.086, 0.084)
	env.fog_density = 0.0125
	env.fog_sky_affect = 0.0
	# 高度雾：贴地更浓，远处发白，把场景关成一只盒子
	if env.get("fog_height") != null:
		env.set("fog_height", 1.4)
		env.set("fog_height_density", 1.0)

	_place_candles()


func _place_candles() -> void:
	if _world == null:
		return
	_candles.clear()
	for x: float in CANDLE_XS:
		var lamp := OmniLight3D.new()
		lamp.name = "Candle_%d" % int(x)
		lamp.light_color = Color(1.0, 0.58, 0.24)
		lamp.light_energy = CANDLE_BASE
		lamp.omni_range = 5.4
		lamp.omni_attenuation = 1.8
		lamp.shadow_enabled = false
		lamp.position = Vector3(x, 1.45, 4.2)
		_world.add_child(lamp)
		_candles.append(lamp)


## 飘灰：只在下落时被烛光照亮才看得见，所以速度压得很慢。
func _setup_atmosphere() -> void:
	if _world == null:
		return
	var ash := GPUParticles3D.new()
	ash.name = "Ash"
	ash.amount = 600
	ash.lifetime = 16.0
	ash.preprocess = 8.0
	ash.fixed_fps = 30
	ash.visibility_aabb = AABB(Vector3(-28.0, -6.0, -12.0), Vector3(56.0, 22.0, 24.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(28.0, 2.5, 8.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 22.0
	process.gravity = Vector3(0.18, -0.30, 0.06)
	process.initial_velocity_min = 0.10
	process.initial_velocity_max = 0.38
	process.scale_min = 0.5
	process.scale_max = 1.6
	process.color = Color(0.60, 0.57, 0.52, 0.55)
	ash.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.055)
	var flake := StandardMaterial3D.new()
	flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.vertex_color_use_as_albedo = true
	flake.albedo_color = Color(0.66, 0.62, 0.56, 0.55)
	quad.material = flake
	ash.draw_pass_1 = quad
	ash.position = Vector3(24.0, 7.0, 0.0)
	_world.add_child(ash)


## 角色压暗降饱和：不动模型，只改表面材质的反照率并关掉自发光（绿色眼睛）。
func _tone_actor() -> void:
	var player := get_node_or_null("World/Player")
	if player == null:
		return
	var tint := 0.60
	for node: Node in player.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.name == "AimMarker":
			continue
		for i: int in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i)
			if not (source is BaseMaterial3D):
				continue
			var mat := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
			var c := mat.albedo_color
			mat.albedo_color = Color(clampf(c.r * tint, 0.0, 1.0), clampf(c.g * tint, 0.0, 1.0), clampf(c.b * tint, 0.0, 1.0), c.a)
			mat.emission_enabled = false
			mi.set_surface_override_material(i, mat)


## 敌人压暗降饱和：只改 Body 的反照率，保留眼睛/预警圈的不发光可读性。
func _tone_enemy(enemy: Node3D) -> void:
	for node: Node in enemy.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var source: Material = mi.material_override
		if source == null:
			source = mi.get_active_material(0)
		if not (source is StandardMaterial3D):
			continue
		var mat := source as StandardMaterial3D
		if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			continue
		if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var c := mat.albedo_color
		var gray := (c.r + c.g + c.b) / 3.0
		var toned := Color(
			clampf(lerpf(c.r, gray, 0.55) * 0.55, 0.0, 1.0),
			clampf(lerpf(c.g, gray, 0.55) * 0.55, 0.0, 1.0),
			clampf(lerpf(c.b, gray, 0.55) * 0.55, 0.0, 1.0),
			c.a)
		mat.albedo_color = toned
		mat.emission_enabled = false
		if mi.name == "Body":
			enemy.set("_base_albedo", toned)


## P2 兼容：税卡是剧情节点，不是地牢楼层；隐藏新版 HUD 的楼层/目标块。
func _tune_hud() -> void:
	var hud := get_node_or_null("HUD")
	if hud == null:
		return
	var floor_anchor := hud.get_node_or_null("FloorAnchor") as CanvasItem
	if floor_anchor != null:
		floor_anchor.visible = false


## 全屏油画后期：暗角 / 颗粒 / 暗部提暖 / 边缘柔化 / 色阶化 / 轻微色差
func _setup_post() -> void:
	var layer := CanvasLayer.new()
	layer.name = "OilGrade"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.name = "Grade"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/art/oil_grade.gdshader")
	rect.material = material
	layer.add_child(rect)
	add_child(layer)


## 走完整条税道 → 进地牢。用 Router 的淡入淡出，不硬切。
func _build_portal() -> void:
	var at := _landmark("exit")
	if at.is_empty():
		return
	var pos: Array = at["pos"]
	var area := Area3D.new()
	area.name = "ExitPortal"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.6, 2.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.3, 0.0)
	area.add_child(shape)
	area.position = Vector3(float(pos[0]), 0.0, float(pos[2]))
	area.body_entered.connect(_on_exit_entered)
	(_world if _world != null else self).add_child(area)


func _on_exit_entered(body: Node3D) -> void:
	if _exiting or not body.is_in_group(&"player"):
		return
	_exiting = true
	var router := get_node_or_null("/root/Router")
	if router != null and router.has_method(&"goto"):
		router.call(&"goto", "res://scenes/main.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _module(id: String) -> Dictionary:
	for entry: Variant in _kit.get("modules", []):
		var module: Dictionary = entry as Dictionary
		if String(module.get("id", "")) == id:
			return module
	push_error("TitheGateGraybox: kit 里没有模块 %s" % id)
	return {}


func _make_materials() -> void:
	# 3A：程序化贴图 + 世界三平面映射，方块不用展 UV
	_materials = KIT_ART.build()
	# 关卡里用到的别名，映射到同一套材质
	_materials["stone_light"] = _materials["pave"]
	_materials["road_approach"] = _materials["dirt"]
	_materials["road_gate"] = _materials["pave"]
	# 院子地面单独压暗，避免开阔区比开场亮一截
	var yard_floor := (_materials["stone_crack"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	yard_floor.albedo_color = Color(0.55, 0.51, 0.46)
	_materials["yard"] = yard_floor
	_materials["road_yard"] = yard_floor
	# 墙体整体压暗，消掉等距俯视下的一圈亮白墙顶
	var wall := (_materials["plaster"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	wall.albedo_color = Color(0.60, 0.58, 0.55)
	_materials["plaster"] = wall
	_materials["stone"] = wall
	# 墙顶压条：深色，压住墙顶的一道亮边
	var coping := (_materials["iron_rust"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	coping.albedo_color = Color(0.28, 0.27, 0.25)
	_materials["coping"] = coping
	# 壁柱：比白灰墙暗一档的石头。材质槽固定 7 个，只能走代码里的别名
	var pillar := (_materials["stone_crack"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	pillar.albedo_color = Color(0.34, 0.32, 0.29)
	_materials["pillar"] = pillar


func _solid_material(color: Color, metallic: float = 0.0, roughness: float = 0.85) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _read_zones() -> void:
	_zone_rects.clear()
	for entry: Variant in _spec.get("zones", []):
		var zone: Dictionary = entry as Dictionary
		var origin: Array = zone["origin"]
		var size: Array = zone["size"]
		_zone_rects.append(Rect2(float(origin[0]), float(origin[2]), float(size[0]), float(size[2])))
	for entry: Variant in _spec.get("landmarks", []):
		var lm: Dictionary = entry as Dictionary
		if String(lm.get("id", "")) == "spawn":
			var pos: Array = lm["pos"]
			_spawn = Vector3(float(pos[0]), float(pos[1]) + 0.05, float(pos[2]))


func _bounds() -> Rect2:
	var bounds := _zone_rects[0]
	for rect: Rect2 in _zone_rects:
		bounds = bounds.merge(rect)
	return bounds


# ---------------------------------------------------------------- 地面

## 墙外的荒野地面：没有它，整座关卡看起来像悬在黑底上的一只白盒子。
func _build_outside_ground() -> void:
	var ground: Material = _material_of("mud")
	_add_block(Vector3(24.0, -0.05, 0.0), Vector3(140.0, 0.06, 100.0), ground, false)


func _build_floors() -> void:
	var tile := _module("ground_tile")
	var part: Dictionary = (tile.get("parts", []) as Array)[0]
	var tile_size := _vec3(part["size"])
	var zone_ids: Array[String] = ["dirt", "pave", "yard"]

	# 一个网格 + 三个材质，全部地砖共用
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = tile_size
	var zone_materials: Array[Material] = []
	for id: String in zone_ids:
		zone_materials.append(_materials[id] if _materials.has(id) else _materials["stone"])

	for i: int in _zone_rects.size():
		var rect := _zone_rects[i]
		var material: Material = zone_materials[i] if i < zone_materials.size() else zone_materials[0]

		# 碰撞用一整块看不见的板，省掉几百个碰撞体
		_add_collider(
			Vector3(rect.position.x + rect.size.x * 0.5, -FLOOR_THICKNESS * 0.5, rect.position.y + rect.size.y * 0.5),
			Vector3(rect.size.x, FLOOR_THICKNESS, rect.size.y)
		)

		var cols := int(round(rect.size.x / CELL))
		var rows := int(round(rect.size.y / CELL))
		for cx: int in cols:
			for cz: int in rows:
				var instance := MeshInstance3D.new()
				instance.mesh = tile_mesh
				instance.material_override = material
				instance.position = Vector3(
					rect.position.x + (float(cx) + 0.5) * CELL,
					float(part["offset"][1]),
					rect.position.y + (float(cz) + 0.5) * CELL
				)
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_geometry.add_child(instance)


# ---------------------------------------------------------------- 墙

## 墙不再"一条 2m 素板铺到底"：每 6m 一段，段内 2m 板同高，接缝上立壁柱。
## 高度必须可复现——截图对比和回归都靠它，所以用固定种子按"块"取值。
const PILLAR_SPACING := 6.0
const WALL_SEED := 20261125
## 墙洞：落在区间里的那块 2m 板整块换成开洞版（下沿 1.12m、上沿 2.50m）。
## 洞口的碰撞不能省：看得见外面的荒野，但走不出去。
const WINDOW_SPANS: Array[Vector2] = [Vector2(20.0, 22.0), Vector2(34.0, 36.0)]

## 逐段验收开关（命令行）：nowallvar（关墙身高差）/ nopillar / nowindow / noattach。
## 只用于出"这一步改了什么"的对比图，跑测试时不带。
var _cli_args: PackedStringArray = OS.get_cmdline_user_args()

var _wall_heights: Dictionary = {}


func _off(name: String) -> bool:
	return _cli_args.has(name)


func _build_walls() -> void:
	var bounds := _bounds()
	var end_x := bounds.position.x + bounds.size.x
	var inside: Dictionary = {}
	for rect: Rect2 in _zone_rects:
		var i0 := int(round((rect.position.x - bounds.position.x) / CELL))
		var i1 := int(round((rect.position.x + rect.size.x - bounds.position.x) / CELL))
		var j0 := int(round((rect.position.y - bounds.position.y) / CELL))
		var j1 := int(round((rect.position.y + rect.size.y - bounds.position.y) / CELL))
		for i: int in range(i0, i1):
			for j: int in range(j0, j1):
				inside[Vector2i(i, j)] = true

	# 把并集的外边界按 2m 单元找出来，再合并成连续墙段
	var h_lines: Dictionary = {}
	var v_lines: Dictionary = {}
	for key: Vector2i in inside:
		if not inside.has(key + Vector2i(0, -1)):
			_h_add(h_lines, key.y, key.x)
		if not inside.has(key + Vector2i(0, 1)):
			_h_add(h_lines, key.y + 1, key.x)
		if not inside.has(key + Vector2i(-1, 0)):
			_v_add(v_lines, key.x, key.y)
		if not inside.has(key + Vector2i(1, 0)):
			_v_add(v_lines, key.x + 1, key.y)

	# 贴着路的侧墙（横线）：墙身高差 + 窗洞 + 壁柱都只做在这里
	for line: int in h_lines:
		var z := bounds.position.y + float(line) * CELL
		var inward := -1.0 if z > 0.0 else 1.0
		for run: Vector2i in _merge(h_lines[line]):
			var x0 := bounds.position.x + float(run.x) * CELL
			var x1 := bounds.position.x + float(run.y + 1) * CELL
			for x: float in _steps(x0, x1, CELL):
				var center := Vector3(x + CELL * 0.5, 0.0, z)
				if _is_spawn_open(center) or _is_breach(center):
					# 不砌墙，但补一块看不见的碰撞：边界一个像素都不变
					_add_collider(center + Vector3(0.0, 1.5, 0.0), Vector3(CELL, 3.0, 0.4), 0.0)
					continue
				if _is_window(center):
					_place_module("wall_window", center, 0.0)
					_add_collider(center + Vector3(0.0, 1.5, 0.0), Vector3(CELL, 3.0, 0.4), 0.0)
				else:
					_place_wall_panel(center, 0.0, _wall_height_at(center))
				_try_wall_pillar(center, inward)
	for line: int in v_lines:
		var x := bounds.position.x + float(line) * CELL
		for run: Vector2i in _merge(v_lines[line]):
			var z0 := bounds.position.y + float(run.x) * CELL
			var z1 := bounds.position.y + float(run.y + 1) * CELL
			for z: float in _steps(z0, z1, CELL):
				var center := Vector3(x, 0.0, z + CELL * 0.5)
				# 出口断口：尽头的墙开一个 8m 口子看远景，碰撞用隐形墙兜住
				if absf(x - end_x) < 0.01 and center.z > -4.0 and center.z < 4.0:
					_add_collider(center + Vector3(0.0, 1.5, 0.0), Vector3(0.4, 3.0, CELL), 0.0)
					continue
				if _is_spawn_open(center):
					_add_collider(center + Vector3(0.0, 1.5, 0.0), Vector3(0.4, 3.0, CELL), 0.0)
					continue
				_place_wall_panel(center, 90.0, _wall_height_at(center))
	_build_wall_corners()


## 每 6m 一段：同一段内的 2m 板同高，段与段之间才台阶式落差。
## 塌段（低于 2.7m）不再补压顶——墙顶露出白灰，深色压条断开，
## 这是这台相机唯一能看见的"墙身高差"（墙面本身与视线平行，零像素）。
func _wall_height_at(center: Vector3) -> float:
	if _off("nowallvar"):
		return 3.0
	var block := Vector2i(floori(center.x / PILLAR_SPACING), floori(center.z / PILLAR_SPACING))
	if _wall_heights.has(block):
		return float(_wall_heights[block])
	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED + block.x * 7919 + block.y * 104729
	var roll := rng.randf()
	var height := 3.0
	if roll < 0.26:
		height = rng.randf_range(1.95, 2.35)
	elif roll < 0.62:
		height = rng.randf_range(2.45, 2.80)
	else:
		height = rng.randf_range(2.90, 3.00)
	height = snappedf(height, 0.1)
	_wall_heights[block] = height
	return height


## 一块墙板：墙基固定，墙身按段高伸缩，压顶永远压在最上面。
## 尺寸仍从 kit 的 wall_panel 读——只有"总高"是代码给的变量。
func _place_wall_panel(center: Vector3, yaw_deg: float, height: float) -> void:
	var parts: Array = _module("wall_panel").get("parts", [])
	if parts.size() < 3:
		return
	var base := _vec3((parts[0] as Dictionary)["size"])
	var coping := _vec3((parts[2] as Dictionary)["size"])
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var body_h := maxf(height - base.y - coping.y, 0.5)
	var body := Vector3(base.x, body_h, base.z)
	var body_at := Vector3(0.0, base.y + body_h * 0.5, 0.0)

	_add_wall_box(center, base, Vector3(0.0, base.y * 0.5, 0.0), basis, _materials["stone_crack"])
	_add_wall_box(center, body, body_at, basis, _materials["plaster"])
	_add_collider(center + basis * body_at, body, 0.0, basis)
	# 塌段不压顶：墙顶直接露出白灰，深色压条在这里断开——断墙的读法全靠这一下
	if height >= 2.7:
		_add_wall_box(center, coping, Vector3(0.0, height - coping.y * 0.5, 0.0), basis, _materials["coping"])
	elif height < 2.4:
		_add_wall_debris(center, yaw_deg)
	_placed += 1


## 塌段墙根堆碎石：相机与路平行，墙在平面上只有 0.4m 一条，只有把墙脚堆到 1.6m 深，
## "墙"才在画面上有厚度。这一段同时也是最暗的一块——长廊靠它断开。
func _add_wall_debris(center: Vector3, yaw_deg: float) -> void:
	if absf(yaw_deg) > 0.01:
		return
	var inward := -1.0 if center.z > 0.0 else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED + int(round(center.x * 10.0)) * 37 + int(round(center.z * 10.0)) * 11
	for i: int in 4:
		var w := rng.randf_range(0.6, 1.05)
		var d := rng.randf_range(0.5, 1.15)
		var h := rng.randf_range(0.32, 0.9)
		var at := center + Vector3(
			rng.randf_range(-0.62, 0.62),
			h * 0.5,
			inward * (0.2 + d * 0.5 - 0.06))
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, h, d)
		block.mesh = box
		block.material_override = _materials["stone_crack"]
		block.position = at
		block.rotation = Vector3(0.0, rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.1))
		_geometry.add_child(block)


func _add_wall_box(origin: Vector3, size: Vector3, offset: Vector3, basis: Basis, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.transform = Transform3D(basis, origin + basis * offset)
	_geometry.add_child(instance)


## 壁柱站在两段墙的接缝上、贴墙内侧，永远比两侧墙高一截（2.6~3.2）。
## 它同时收掉卡口两侧被切断的墙口——那两道生硬截面以前是用 KayKit 断柱糊的。
func _try_wall_pillar(center: Vector3, inward: float) -> void:
	if _off("nopillar"):
		return
	var joint := center.x - CELL * 0.5
	if absf(fmod(joint, PILLAR_SPACING)) > 0.01:
		return
	_place_wall_pillar(joint, center.z, inward, center)


func _place_wall_pillar(x: float, z: float, inward: float, near: Vector3 = Vector3.ZERO) -> void:
	var parts: Array = _module("wall_pillar").get("parts", [])
	if parts.size() < 3:
		return
	var plinth := _vec3((parts[0] as Dictionary)["size"])
	var shaft := _vec3((parts[1] as Dictionary)["size"])
	var cap := _vec3((parts[2] as Dictionary)["size"])

	var rng := RandomNumberGenerator.new()
	rng.seed = WALL_SEED + int(round(x * 10.0)) * 131 + int(round(z * 10.0)) * 17
	var tallest := 0.0
	if near != Vector3.ZERO:
		tallest = maxf(_wall_height_at(near), _wall_height_at(near + Vector3(CELL, 0.0, 0.0)))
		tallest = maxf(tallest, _wall_height_at(near - Vector3(CELL, 0.0, 0.0)))
	var height := clampf(tallest + rng.randf_range(0.06, 0.26), 2.6, 3.2)

	var origin := Vector3(x, 0.0, z + inward * 0.425)
	var basis := Basis()
	var shaft_h := maxf(height - plinth.y - cap.y, 0.6)
	_add_wall_box(origin, plinth, Vector3(0.0, plinth.y * 0.5, 0.0), basis, _materials["pillar"])
	_add_wall_box(origin, Vector3(shaft.x, shaft_h, shaft.z),
		Vector3(0.0, plinth.y + shaft_h * 0.5, 0.0), basis, _materials["pillar"])
	# 柱帽用浅石：它正好压在深色墙顶压条上，一格亮、一格暗，6m 的节奏才读得出来
	_add_wall_box(origin, cap, Vector3(0.0, height - cap.y * 0.5, 0.0), basis, _materials["stone_crack"])
	_placed += 1


## 墙走到头的地方（院子加宽处、出口断口）补柱子，否则墙角是一个悬空的 0.4m 断面。
func _build_wall_corners() -> void:
	if _off("nopillar"):
		return
	for entry: Array in [[24.0, -7.0, 1.0], [24.0, 7.0, -1.0], [48.0, -9.0, 1.0], [48.0, 9.0, -1.0]]:
		_place_wall_pillar(float(entry[0]), float(entry[1]), float(entry[2]))


## 只有贴着路的侧墙才留窗：区间内的 2m 板整块给 `wall_window`。
func _is_window(center: Vector3) -> bool:
	if _off("nowindow"):
		return false
	if absf(center.z) < 4.0:
		return false
	for span: Vector2 in WINDOW_SPANS:
		if center.x > span.x + 0.01 and center.x < span.y - 0.01:
			return true
	return false


## 出生点区间开墙：这一段的围墙拆掉，边界改用隐形碰撞 + 0.6m 矮石带。
## 其他分区的墙一律不动。
const OPEN_X := 12.0


func _is_spawn_open(center: Vector3) -> bool:
	return center.x < OPEN_X - 0.01


## 两处塌口：只开在院子远墙，位置避开税亭与出口
const BREACH_XS: Array[Vector2] = [Vector2(30.0, 33.0), Vector2(39.0, 41.0)]


func _is_breach(center: Vector3) -> bool:
	if center.z > -8.0:
		return false
	for span: Vector2 in BREACH_XS:
		if center.x > span.x and center.x < span.y:
			return true
	return false


## 界外废墟：KayKit 的几何 + 我们自己的材质。
## 正交相机可见范围只有 12/sin40 ≈ 18.7m 深 × 23m 宽，所以这些必须压在这条带子里。
const RUIN_PLAN := [
	# 模型, 位置(本地), yaw, 缩放, 材质
	["pillar", Vector3(10.5, 0.0, -9.2), 12.0, 1.0, "stone_crack"],
	["pillar", Vector3(2.0, 0.0, 9.7), -26.0, 1.05, "stone_crack"],
	["column", Vector3(7.6, 0.0, -9.6), 0.0, 1.0, "stone_crack"],
	["column", Vector3(14.2, 0.0, 9.0), 35.0, 0.95, "stone_crack"],
	["rubble_large", Vector3(4.6, 0.0, -12.2), 22.0, 0.7, "stone_crack"],
	["rubble_half", Vector3(-2.2, 0.0, 11.2), -42.0, 0.9, "stone_crack"],
	["rubble_half", Vector3(16.5, 0.0, -11.0), 64.0, 0.8, "stone_crack"],
	["crates_stacked", Vector3(1.4, 0.0, 8.5), 18.0, 0.85, "wood_dry"],
	["barrel_large", Vector3(15.4, 0.0, -8.5), 0.0, 0.9, "wood_dry"],
	["column", Vector3(19.5, 0.0, 7.6), 8.0, 1.0, "stone_crack"],
	["rubble_half", Vector3(21.0, 0.0, -8.2), 33.0, 0.7, "stone_crack"],
	["pillar", Vector3(23.5, 0.0, 8.4), -12.0, 0.9, "stone_crack"],
	["rubble_large", Vector3(9.0, 0.0, 13.0), -18.0, 0.55, "stone_crack"],
	["rubble_large", Vector3(14.0, 0.0, -13.5), 41.0, 0.6, "stone_crack"],
]


func _build_outside_ruins() -> void:
	for entry: Array in RUIN_PLAN:
		_add_ruin(String(entry[0]), entry[1] as Vector3, float(entry[2]), float(entry[3]), String(entry[4]))


## KayKit 用的是色阶图集，直接上会卡通；统一换成我们的三平面石头/木头。
func _override_material(node: Node, material: Material) -> void:
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 拆墙之后，边界要"看得见"：沿原墙线撒碎石。
## 间距、朝向、尺寸全部随机，并且混入真实石头模型，避免"一条整齐的白虚线"。
func _build_boundary_strip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	var flat: Material = _material_of("yard")
	_scatter_edge(Vector3(0.0, 0.0, -7.0), Vector3(OPEN_X, 0.0, -7.0), flat, rng)
	_scatter_edge(Vector3(0.0, 0.0, 7.0), Vector3(OPEN_X, 0.0, 7.0), flat, rng)
	_scatter_edge(Vector3(0.0, 0.0, -7.0), Vector3(0.0, 0.0, 7.0), flat, rng)
	# 被切断的墙口由 _build_walls 的壁柱收口（高度跟墙走），这里只留一段斜靠的柱头
	_add_ruin("column", Vector3(OPEN_X + 1.6, 0.0, 6.2), 22.0, 0.9, "stone_crack")


# ---------------------------------------------------------------- 墙上附着物

## 墙面本来是"一块干净的灰板"：铁环、火把、旗是三种不同高度的竖向打断，
## 让墙有使用痕迹。位置避开壁柱接缝和窗洞，撞上了就跳过。
const WALL_RING_XS: Array[float] = [13.0, 17.0, 21.0, 25.0, 29.0, 33.0, 37.0, 41.0, 45.0]
## 火把：每 6m 一支、左右交错——同侧每 6m 会连成一条虚线，交错才是"人随手钉的"
const WALL_TORCHES: Array = [
	[15.0, 7.0], [27.0, -9.0], [33.0, 9.0], [45.0, -9.0],
]
const WALL_BANNERS: Array = [
	[23.0, -7.0], [28.5, -9.0],
]


func _build_wall_attachments() -> void:
	if _off("noattach"):
		return
	for x: float in WALL_RING_XS:
		var z := 7.0 if x < 24.0 else 9.0
		for side: float in [-1.0, 1.0]:
			var at := Vector3(x, 0.0, side * z)
			if _is_window(at) or absf(fmod(x, PILLAR_SPACING)) < 0.6:
				continue
			_place_wall_fixture("wall_ring", Vector3(x, 1.05, side * (z - 0.21)), side)
	for entry: Array in WALL_TORCHES:
		var x := float(entry[0])
		var z := float(entry[1])
		var inward := -1.0 if z > 0.0 else 1.0
		var at := Vector3(x, 0.0, z + inward * 0.2)
		if _is_window(at) or _is_breach(at):
			continue
		_place_wall_fixture("wall_torch", at, -inward)
		# 火把本体在墙上读不出来，能读出来的是它打在墙根的光斑
		_add_torch_light(Vector3(x, 2.12, z + inward * 0.44), 0.9, 4.2)
	for entry: Array in WALL_BANNERS:
		var x := float(entry[0])
		var z := float(entry[1])
		var inward := -1.0 if z > 0.0 else 1.0
		if _is_window(Vector3(x, 0.0, z)):
			continue
		# 旗横挑出墙面：布面正对相机，才不是又一条看不见的竖线
		_place_module("wall_banner", Vector3(x, 0.0, z + inward * 0.9), -90.0 * inward)


## 墙面构件统一朝路：模块本地 +z 要指向路心，所以 yaw 由"墙在路的哪一侧"决定。
## side = +1 是近侧墙（z>0，路在它 -z 方向），-1 是远侧墙。
func _place_wall_fixture(id: String, at: Vector3, side: float) -> void:
	_place_module(id, at, 180.0 if side > 0.0 else 0.0)


## 沿一条线撒石头。靠近卡口的一端更碎更矮，读作"被人踩平了"。
func _scatter_edge(a: Vector3, b: Vector3, flat: Material, rng: RandomNumberGenerator) -> void:
	var edge := b - a
	var length := edge.length()
	if length < 0.1:
		return
	var dir := edge / length
	var side := Vector3(-dir.z, 0.0, dir.x)
	var t := 0.0
	while t < length:
		t += rng.randf_range(0.5, 1.2)
		if t >= length:
			break
		var wear := clampf(minf(t, length - t) / 2.5, 0.25, 1.0)
		var center := a + dir * t + side * rng.randf_range(-0.26, 0.26)
		for i: int in rng.randi_range(1, 3):
			var w := rng.randf_range(0.28, 0.82) * (0.7 + wear * 0.5)
			var h := rng.randf_range(0.10, 0.40) * wear
			var d := rng.randf_range(0.24, 0.58)
			var at := center + side * rng.randf_range(-0.30, 0.30) + dir * rng.randf_range(-0.32, 0.32)
			var block := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(w, h, d)
			block.mesh = box
			block.material_override = flat
			block.position = at + Vector3(0.0, h * 0.45, 0.0)
			block.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0.0, TAU), rng.randf_range(-0.09, 0.09))
			_geometry.add_child(block)
		if rng.randf() < 0.22:
			_add_ruin("rubble_half", center + side * rng.randf_range(-0.18, 0.18),
				rng.randf_range(0.0, 360.0), rng.randf_range(0.15, 0.27), "yard")


## 放一个 KayKit 几何，并把它的色阶图集换成我们的三平面材质。
func _add_ruin(model: String, at: Vector3, yaw: float, scale: float, material: String) -> void:
	var path := "res://assets/kit/kaykit/%s.gltf" % model
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	node.position = at
	node.rotation_degrees = Vector3(0.0, yaw, 0.0)
	node.scale = Vector3.ONE * scale
	_override_material(node, _material_of(material))
	(_world if _world != null else self).add_child(node)


func _steps(from: float, to: float, step: float) -> Array[float]:
	var out: Array[float] = []
	var value := from
	while value < to - 0.0001:
		out.append(value)
		value += step
	return out


func _h_add(table: Dictionary, line: int, index: int) -> void:
	if not table.has(line):
		table[line] = []
	(table[line] as Array).append(index)


func _v_add(table: Dictionary, line: int, index: int) -> void:
	_h_add(table, line, index)


func _merge(indices: Array) -> Array[Vector2i]:
	var sorted := indices.duplicate()
	sorted.sort()
	var runs: Array[Vector2i] = []
	var begin := int(sorted[0])
	var last := begin
	for i: int in range(1, sorted.size()):
		var value := int(sorted[i])
		if value == last + 1:
			last = value
			continue
		runs.append(Vector2i(begin, last))
		begin = value
		last = value
	runs.append(Vector2i(begin, last))
	return runs


func _build_road() -> void:
	var road_half := float((_spec["scene"] as Dictionary).get("road_width", 8.0)) * 0.5
	var ids: Array[String] = ["road_approach", "road_gate", "road_yard"]
	for i: int in _zone_rects.size():
		var rect := _zone_rects[i]
		var material: Material = _materials[ids[i]] if i < ids.size() else _materials["stone_light"]
		var center := Vector3(rect.position.x + rect.size.x * 0.5, 0.03, 0.0)
		_add_block(center, Vector3(rect.size.x, 0.03, road_half * 2.0), material, false)


## 车辙 + 碎石补丁：8m 宽的路面不再是一块干净的灰板。
func _build_road_detail() -> void:
	var mud: Material = _material_of("mud")
	var stone: Material = _material_of("yard")
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	# 两道车辙：到门洞前收窄、穿过去维持窄距。原来两条平行线穿过 4m 卡口，像画上去的
	for side: float in [-1.0, 1.0]:
		_rut_strip(Vector3(0.5, 0.058, side * 1.85), Vector3(9.4, 0.058, side * 1.85), mud)
		_rut_strip(Vector3(9.4, 0.058, side * 1.85), Vector3(12.6, 0.058, side * 1.25), mud)
		_rut_strip(Vector3(12.6, 0.058, side * 1.25), Vector3(47.5, 0.058, side * 1.25), mud)
	# 路缘的碎石补丁：随机大小、随机朝向
	for i: int in 26:
		var x := rng.randf_range(0.5, 47.5)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z := side * rng.randf_range(3.0, 3.95)
		var w := rng.randf_range(0.45, 1.15)
		var d := rng.randf_range(0.35, 0.9)
		var patch := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w, 0.02, d)
		patch.mesh = box
		patch.material_override = stone
		patch.position = Vector3(x, 0.056, z)
		patch.rotation.y = rng.randf_range(0.0, TAU)
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_geometry.add_child(patch)


## 一段车辙：按两点连成一条贴着路面的窄带，转角处不再是硬折线。
func _rut_strip(a: Vector3, b: Vector3, material: Material) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.02, 0.5)
	instance.mesh = box
	instance.material_override = material
	instance.position = (a + b) * 0.5
	instance.rotation.y = atan2(-(b.z - a.z), b.x - a.x)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geometry.add_child(instance)


# ---------------------------------------------------------------- 构件

func _build_gate() -> void:
	var at := _landmark("gate_arch")
	if at.is_empty():
		return
	var pos: Array = at["pos"]
	# 门梁宽度沿模块本地 +x，摆到路上要转 90°，让它横跨 z
	_place_module("gate_arch", Vector3(float(pos[0]), 0.0, float(pos[2])), 90.0)
	# 门槛石：门洞下一道被踩亮的石条。没有它，门梁像直接插在土里
	_add_block(Vector3(float(pos[0]), 0.085, 0.0), Vector3(1.0, 0.11, 2.9), _material_of("pave"), false)


func _build_fences() -> void:
	var gx := 12.0
	var at := _landmark("gate_arch")
	if not at.is_empty():
		gx = float((at["pos"] as Array)[0])
	# 8m 路收成 4m：两侧各两段直栅栏 + 一段斜插，卡口后再收回
	for side: float in [-1.0, 1.0]:
		_place_module("fence_stake", Vector3(gx - 5.0, 0.0, side * 4.0), 0.0)
		_place_module("fence_stake", Vector3(gx - 3.0, 0.0, side * 4.0), 0.0)
		# 斜段长 2.83m，用两块 2m 模块错开铺，视觉上连成一线。
		# 模块长边是本地 +x，所以 yaw 要把 +x 转到 (b-a) 方向：atan2(-dz, dx)
		var a := Vector3(gx - 2.0, 0.0, side * 4.0)
		var b := Vector3(gx, 0.0, side * 2.0)
		var yaw := rad_to_deg(atan2(-(b.z - a.z), b.x - a.x))
		_place_module("fence_stake", a.lerp(b, 0.25), yaw)
		_place_module("fence_stake", a.lerp(b, 0.75), yaw)
	for side: float in [-1.0, 1.0]:
		_place_module("fence_stake", Vector3(gx + 3.0, 0.0, side * 2.0), 0.0)
		_place_module("fence_stake", Vector3(gx + 5.0, 0.0, side * 2.0), 0.0)


func _build_booth() -> void:
	var at := _landmark("toll_booth")
	if at.is_empty():
		return
	var pos: Array = at["pos"]
	# 开口要朝来路（本地 -x），否则沿路看过去只能看到亭子的侧墙
	_place_module("booth_half", Vector3(float(pos[0]), 0.0, float(pos[2])), -90.0)


func _build_props() -> void:
	# 生活件（原有）
	_place_module("cart_hand", Vector3(32.0, 0.0, -6.0))
	for point: Vector3 in [Vector3(35.2, 0.0, -6.2), Vector3(36.1, 0.0, -5.6), Vector3(35.4, 0.0, -4.9)]:
		_place_module("barrel_oil", point)
	for point: Vector3 in [Vector3(30.6, 0.0, 2.4), Vector3(31.4, 0.0, 2.1), Vector3(31.0, 0.6, 2.3)]:
		_place_module("sack_grain", point)
	_place_module("scale_toll", Vector3(8.0, 0.0, -3.0))
	_place_module("stretcher", Vector3(5.5, 0.0, 5.4))
	for x: float in [4.0, 9.0, 18.0, 26.0, 34.0, 42.0]:
		_place_module("lantern_hook", Vector3(x, 0.0, 4.2))

	# 恐怖件：吊笼（横臂朝路）、铁链（挂在拱下）、十字桩、账册板、碎石骨堆、血渍
	_place_module("cage_hanging", Vector3(29.5, 0.0, -3.6), -90.0)
	for z: float in [-1.05, 1.05]:
		_place_module("chain_hang", Vector3(12.0, 0.0, z))
	# 等距镜头下"朝路"的面正好侧对相机，十字桩与账册都要转向来路才读得出形状
	_place_module("cross_stake", Vector3(9.2, 0.0, -5.4), 78.0)
	_place_module("cross_stake", Vector3(21.0, 0.0, -4.6), 104.0)
	_place_module("ledger_board", Vector3(13.4, 0.0, -3.0), -90.0)
	_place_module("rubble_pile", Vector3(18.6, 0.0, -4.4), 24.0)
	_place_module("rubble_pile", Vector3(33.2, 0.0, 3.5), -40.0)
	for spot: Vector3 in [Vector3(11.3, 0.0, 0.8), Vector3(29.5, 0.0, -2.2), Vector3(16.6, 0.0, -2.4)]:
		_place_module("blood_decal", spot, 15.0)

	# 卡口两侧墙脚：堆点货、塌下来的石头，别让墙是一条光板
	_place_module("rubble_pile", Vector3(14.6, 0.0, 6.3), 12.0)
	_place_module("rubble_pile", Vector3(20.4, 0.0, -6.4), -26.0)
	_place_module("barrel_oil", Vector3(22.4, 0.0, 6.5))
	_place_module("sack_grain", Vector3(19.6, 0.0, -6.6))
	_place_module("sack_grain", Vector3(18.9, 0.0, -6.2))
	# 村口道：开场三件太少了，铺成"排队被拦下过"的现场
	for spot: Vector3 in [Vector3(1.7, 0.0, -5.0), Vector3(1.7, 0.0, 5.0)]:
		_place_module("torch_post", spot, 0.0 if spot.z < 0.0 else 180.0)
		_add_torch_light(spot + Vector3(0.0, 2.55, 0.0))
	_place_module("milestone", Vector3(3.4, 0.0, -4.4))
	_place_module("milestone", Vector3(9.8, 0.0, 4.5), 180.0)
	for point: Vector3 in [Vector3(4.6, 0.0, 4.6), Vector3(5.3, 0.0, 5.1)]:
		_place_module("barrel_oil", point)
	for point: Vector3 in [Vector3(6.5, 0.0, 4.7), Vector3(7.0, 0.0, 4.2)]:
		_place_module("sack_grain", point)
	_place_module("cart_hand", Vector3(9.9, 0.0, 5.8), 25.0)
	_place_module("rubble_pile", Vector3(7.6, 0.0, -4.8), 16.0)
	_place_module("rubble_pile", Vector3(11.4, 0.0, 5.4), -30.0)

	# 税亭内装：书桌 + 两张凳子 + 一盏油灯（桌在柜台后，玩家从路上看进来）
	_place_module("desk_clerk", Vector3(16.6, 0.0, -5.0), -90.0)
	_place_module("stool", Vector3(15.9, 0.0, -5.6), 0.0)
	_place_module("stool", Vector3(15.9, 0.0, -4.4), 0.0)
	_add_torch_light(Vector3(16.2, 1.3, -5.0))

	# 栅栏背后（z 4~7 的三角区）：被丢下的货 + 第二座吊笼
	_place_module("barrel_oil", Vector3(15.4, 0.0, 4.6))
	_place_module("sack_grain", Vector3(16.4, 0.0, 5.2))
	_place_module("sack_grain", Vector3(16.9, 0.0, 4.7))
	_place_module("cage_hanging", Vector3(14.6, 0.0, 6.3), 90.0)

	# 院子两侧：不规则间距的杂物，别让墙根空着
	_place_module("rubble_pile", Vector3(26.4, 0.0, -6.9), 34.0)
	_place_module("barrel_oil", Vector3(28.2, 0.0, 6.7))
	_place_module("barrel_oil", Vector3(28.9, 0.0, 6.2))
	_place_module("sack_grain", Vector3(31.4, 0.0, -6.6))
	_place_module("rubble_pile", Vector3(37.2, 0.0, 7.4), -52.0)
	_place_module("barrel_oil", Vector3(39.8, 0.0, -7.2))
	_place_module("sack_grain", Vector3(42.6, 0.0, 7.0))
	_place_module("sack_grain", Vector3(43.1, 0.0, 6.5))

	# 收储院收尾（x 40–48）：原来这段完全空白
	_place_module("cart_hand", Vector3(41.2, 0.0, -5.8), -18.0)
	_place_module("barrel_oil", Vector3(43.6, 0.0, 5.9))
	_place_module("barrel_oil", Vector3(44.3, 0.0, 5.4))
	_place_module("sack_grain", Vector3(47.0, 0.0, -5.0))
	_place_module("sack_grain", Vector3(46.4, 0.0, -5.6))
	_place_module("rubble_pile", Vector3(45.2, 0.0, 6.6), -40.0)
	# 竖向：两面教会挂旗，界面上第一次有"高"
	_place_module("banner_seat", Vector3(40.4, 0.0, -6.4), 90.0)
	_place_module("banner_seat", Vector3(44.6, 0.0, 6.6), -90.0)
	# 远侧补光：原来 6 盏灯全在 z=+4.2，院子左半边是死黑
	for x: float in [28.0, 36.0, 44.0]:
		_add_torch_light(Vector3(x, 1.45, -5.2))
	_build_interactions()


## 三个交互点：税册 / 秤 / 空笼。只在必经路径上给提示，按 E 读一行。
func _build_interactions() -> void:
	var script: Script = load("res://scripts/levels/interactable.gd")
	if script == null:
		return
	var root := Node3D.new()
	root.name = "Interactables"
	(_world if _world != null else self).add_child(root)
	for entry: Variant in _spec.get("interactables", []):
		var data: Dictionary = entry as Dictionary
		var at: Array = data.get("at", [0.0, 0.0, 0.0])
		var node := Area3D.new()
		node.name = "Interact_%s" % String(data.get("id", "x"))
		node.set_script(script)
		node.set("title", String(data.get("label", "查看")))
		node.set("body", String(data.get("prompt", "")))
		node.set("label_height", float(data.get("label_height", 2.2)))
		node.position = Vector3(float(at[0]), 0.0, float(at[2]))
		root.add_child(node)


## 火把的实际光源：挂在火把头上，并接进闪烁列表。
func _add_torch_light(at: Vector3, energy: float = 1.5, reach: float = 5.5) -> void:
	if _world == null:
		return
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.56, 0.22)
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.7
	lamp.shadow_enabled = false
	lamp.position = at
	_world.add_child(lamp)
	_candles.append(lamp)


func _build_exit_marker() -> void:
	var at := _landmark("exit")
	if at.is_empty():
		return
	var pos: Array = at["pos"]
	var base := Vector3(float(pos[0]), 0.06, float(pos[2]))
	_add_block(base, Vector3(2.8, 0.12, 2.8), _material_of("stone_crack"), true)
	_add_block(base + Vector3(0.0, 0.10, 0.0), Vector3(1.5, 0.06, 1.5),
		_solid_material(Color(0.85, 0.50, 0.22), 0.0, 0.55), false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.62, 0.28)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	lamp.omni_attenuation = 1.6
	lamp.position = base + Vector3(0.0, 1.2, 0.0)
	_geometry.add_child(lamp)


func _landmark(id: String) -> Dictionary:
	for entry: Variant in _spec.get("landmarks", []):
		var lm: Dictionary = entry as Dictionary
		if String(lm.get("id", "")) == id:
			return lm
	return {}


# ---------------------------------------------------------------- 模块摆放

## 按 kit 规格摆一个模块：parts 逐个建网格，碰撞按模块的 collision 策略。
func _place_module(id: String, origin: Vector3, yaw_deg: float = 0.0) -> void:
	var module := _module(id)
	if module.is_empty():
		return
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var parts: Array = module.get("parts", [])
	var collided := false

	for entry: Variant in parts:
		var part: Dictionary = entry as Dictionary
		var size := _vec3(part["size"])
		var offset: Array = part.get("offset", [0.0, 0.0, 0.0])
		var center := origin + basis * Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
		var material := _material_of(String(part.get("material", "stone")))
		var part_basis := _part_basis(part)

		var wants_collider := String(module.get("collision", "none")) == "parts" and bool(part.get("collide", false))

		# 允许"只碰撞不显示"的件：吊笼这类有内部空腔的东西，需要一个整块碰撞体
		if bool(part.get("visible", true)):
			var instance := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = size
			instance.mesh = box
			instance.material_override = material
			instance.transform = Transform3D(basis * part_basis, center)
			_geometry.add_child(instance)

		if wants_collider:
			_add_collider(center, size, 0.0, basis * part_basis)
			collided = true

	if String(module.get("collision", "none")) == "hull_85" and not collided:
		var size := _vec3(module["size"]) * 0.85
		var center := origin + basis * Vector3(0.0, float((module["size"] as Array)[1]) * 0.5, 0.0)
		_add_collider(center, size, deg_to_rad(yaw_deg))
	_placed += 1


## Godot 4 不支持 Vector3(Array)，这里统一转一次。
func _vec3(values: Array) -> Vector3:
	if values.size() < 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


## 零件可以带 rot: [x, y, z]（度），用于拱券这类需要倾斜的件。
func _part_basis(part: Dictionary) -> Basis:
	var values: Variant = part.get("rot", null)
	if values is Array and (values as Array).size() >= 3:
		var a: Array = values
		return Basis.from_euler(Vector3(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])), deg_to_rad(float(a[2]))))
	return Basis()


func _material_of(name: String) -> Material:
	if _materials.has(name):
		return _materials[name]
	return _materials["stone"]


func _add_collider(center: Vector3, size: Vector3, yaw: float = 0.0, basis_override: Variant = null) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	if basis_override is Basis:
		body.transform = Transform3D(basis_override, center)
	else:
		body.position = center
		body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_geometry.add_child(body)


func _add_block(center: Vector3, size: Vector3, material: Material, collide: bool) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = center
	_geometry.add_child(instance)
	if collide:
		_add_collider(center, size)


# ---------------------------------------------------------------- 玩家与遭遇

func _place_player() -> void:
	var player := get_node_or_null("World/Player") as Node3D
	if player == null:
		player = get_node_or_null("Player") as Node3D
	if player != null:
		player.position = _spawn
	var camera := get_node_or_null("CameraRig")
	if camera != null and camera.has_method(&"snap_to_target"):
		camera.call(&"snap_to_target")


## 按 JSON 的 encounters 建触发区（Area3D + 只触发一次），玩家越过才刷怪。
func _build_encounters() -> void:
	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	add_child(_enemies_root)

	# 远程敌人会把弹丸挂到 group "projectile_root" 下；没有就退回父节点。
	var shots := Node3D.new()
	shots.name = "Projectiles"
	shots.add_to_group(&"projectile_root")
	add_child(shots)

	for entry: Variant in _spec.get("encounters", []):
		var enc: Dictionary = entry as Dictionary
		var trigger: Dictionary = enc.get("trigger", {})
		var at: Array = trigger.get("at", [0.0, 0.0, 0.0])
		var span: Array = trigger.get("span", [2.0, 0.0, 4.0])

		var area := Area3D.new()
		area.name = "Trigger_" + String(enc.get("id", ""))
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitoring = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(float(span[0]), 0.5), 3.0, maxf(float(span[2]), 0.5))
		shape.shape = box
		area.add_child(shape)
		add_child(area)
		# 必须先入树再设 global_position，否则读到的是空变换
		area.global_position = _to_world(Vector3(float(at[0]), 1.0, float(at[2])))
		area.body_entered.connect(_on_encounter_trigger.bind(enc))


func _on_encounter_trigger(body: Node3D, enc: Dictionary) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	var id := String(enc.get("id", ""))
	if _triggered.has(id):
		return
	_triggered[id] = true

	var kinds: Array = enc.get("enemies", [])
	var spawns: Array = enc.get("spawns", [])
	for i: int in kinds.size():
		var offset := Vector3(0.0, 0.0, 0.0)
		if i < spawns.size():
			var point: Array = spawns[i]
			offset = Vector3(float(point[0]), 0.05, float(point[1]))
		var enemy := ENEMY_SCENE.instantiate() as Node3D
		if enemy == null:
			continue
		enemy.call(&"configure", StringName(kinds[i]), 1, _to_world(offset))
		_enemies_root.add_child(enemy)
		_tone_enemy(enemy)
		if enemy.has_signal(&"died"):
			enemy.connect(&"died", _on_enemy_died)
		_alive += 1
	print("[TitheGate] 遭遇 %s 触发：%d 名敌人" % [id, kinds.size()])


func _on_enemy_died(_enemy: Node) -> void:
	_alive = maxi(_alive - 1, 0)
	if _alive == 0:
		print("[TitheGate] 遭遇清除")


func _to_world(local: Vector3) -> Vector3:
	if _world == null:
		return local
	return _world.transform * local
