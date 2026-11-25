extends Node

## 场景规格探针：把 data/levels/tithe_gate.json 当作契约来验，规格不成立就不许进灰盒。
## 运行：godot --headless --path . res://tests/spec_probe.tscn

const SPEC_PATH := "res://data/levels/tithe_gate.json"
const KIT_PATH := "res://data/kit/tithe_gate_kit.json"
const KNOWN_SCENES: Array[String] = [
	"burned_village", "market", "chapel", "cathedral", "north", "court", "core", "hearth",
]
const KNOWN_SIDES: Array[String] = ["near", "far", "both", "center"]
const REQUIRED_ROOT: Array[String] = ["scene", "materials", "zones", "landmarks", "items"]
const SNAKE_CASE := "^[a-z][a-z0-9_]*$"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var text := FileAccess.get_file_as_string(SPEC_PATH)
	if text.is_empty():
		_fail_run("无法读取 %s" % SPEC_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail_run("JSON 解析失败 %s" % SPEC_PATH)
		return
	var spec: Dictionary = parsed

	print("== 结构 ==")
	for key: String in REQUIRED_ROOT:
		_check(spec.has(key), "根字段存在: %s" % key)
	if _failed > 0:
		_finish()
		return

	var scene: Dictionary = spec["scene"]
	var limits: Dictionary = scene.get("limits", {})
	var grid := float(scene.get("grid", 2.0))
	var road_width := float(scene.get("road_width", 8.0))
	var wall_max := float(limits.get("wall_height_max", 3.0))
	var frame_max := float(limits.get("open_frame_height_max", 4.5))
	var near_max := float(limits.get("near_side_solid_max", 1.2))
	var corridor_min := float(limits.get("corridor_min", 4.0))
	var slot_max := int(limits.get("material_slots_max", 4))
	var length_max := float(limits.get("scene_length_max", 60.0))
	var p0_max := int(limits.get("p0_module_max", 16))
	var p0_mesh_max := int(limits.get("p0_mesh_max", 11))

	print("== 材质槽 ==")
	var slots: Array = spec["materials"]
	var slot_names: Array[String] = []
	for entry: Variant in slots:
		slot_names.append(String((entry as Dictionary).get("slot", "")))
	_check(slots.size() <= slot_max, "材质槽 %d 个 <= 上限 %d" % [slots.size(), slot_max])
	_check(slots.size() > 0, "至少一个材质槽")

	print("== 平面与构图 ==")
	var comp: Dictionary = scene.get("composition", {})
	var pitch := deg_to_rad(float((scene.get("camera", {}) as Dictionary).get("pitch_deg", -55.0)))
	var shadow_expected := wall_max / tan(absf(pitch))
	var shadow_spec := float(comp.get("occlusion_shadow_m", 0.0))
	_check(absf(shadow_expected - shadow_spec) < 0.05, "视线遮挡带 %.2fm 与 %.0f°/tan 一致" % [shadow_spec, absf(rad_to_deg(pitch))])
	var screen_w := float(comp.get("screen_width_m", 21.33))

	var zones: Array = spec["zones"]
	_check(zones.size() >= 3, "分区数 %d >= 3" % zones.size())
	var total_len := 0.0
	var cursor := 0.0
	var apparent: Dictionary = {}
	for i: int in zones.size():
		var zone: Dictionary = zones[i]
		var origin: Array = zone["origin"]
		var size: Array = zone["size"]
		var w := float(size[0])
		var d := float(size[2])
		var ox := float(origin[0])
		_check(is_multiple(w, grid) and is_multiple(d, grid), "%s 尺寸 %.1fx%.1f 对齐 %.1fm 网格" % [zone["id"], w, d, grid])
		_check(is_equal_approx(ox, cursor), "%s 起点 x=%.1f 与上一区接上" % [zone["id"], ox])
		# 侧墙沿 +x 铺、视线也沿 +x，因此不遮挡路面；真正会被遮的是墙外侧。
		# 这里只保证墙离路缘留出贴墙走位的余量。
		var clearance := (d - road_width) * 0.5
		_check(clearance >= 1.2, "%s 墙离路缘 %.1fm >= 1.2m（贴墙走位余量）" % [zone["id"], clearance])
		apparent[String(zone["id"])] = (w + d) / sqrt(2.0)
		cursor = ox + w
		total_len = cursor
	_check(total_len <= length_max, "总长 %.1fm <= %.1fm" % [total_len, length_max])

	var app_gate := float(apparent.get("gate", 0.0))
	var app_approach := float(apparent.get("approach", 0.0))
	var app_yard := float(apparent.get("yard", 0.0))
	_check(app_approach < screen_w, "村口屏幕宽 %.1fm < 屏幕 %.1fm（两侧墙在画内）" % [app_approach, screen_w])
	_check(app_yard > screen_w, "收储院屏幕宽 %.1fm > 屏幕 %.1fm（墙出画，开阔）" % [app_yard, screen_w])

	var landmarks: Array = spec["landmarks"]
	var gate_ok := false
	var spawn_ok := false
	var exit_ok := false
	var booth_ok := false
	var spawn_x := -1.0
	var gate_x := -1.0
	for entry: Variant in landmarks:
		var lm: Dictionary = entry as Dictionary
		var pos: Array = lm["pos"]
		var px := float(pos[0])
		var pz := float(pos[2])
		_check(px >= 0.0 and px <= total_len, "%s 在场地 x 范围内 (%.1f)" % [lm["id"], px])
		_check(absf(pz) <= 9.0, "%s 在场地 z 范围内 (%.1f)" % [lm["id"], pz])
		if String(lm["id"]) == "gate_arch":
			var opening: Array = lm.get("opening", [0.0, 0.0])
			gate_ok = float(opening[0]) >= corridor_min
			gate_x = px
			_check(gate_ok, "卡口净宽 %.1fm >= %.1fm" % [float(opening[0]), corridor_min])
		elif String(lm["id"]) == "spawn":
			spawn_x = px
			spawn_ok = px <= 10.0
		elif String(lm["id"]) == "exit":
			exit_ok = px >= total_len - 4.0
		elif String(lm["id"]) == "toll_booth":
			booth_ok = pz < 0.0 and String(lm.get("open_side", "")) == "+z"
	_check(gate_ok, "存在唯一卡口")
	_check(spawn_ok, "出生点在场地起点 10m 内")
	_check(exit_ok, "出口在场地末端 4m 内")
	_check(booth_ok, "税亭在远侧(z<0) 且朝路开窗(+z)，不挡相机")
	# 相机可见进深约 7.3m（ortho 12 半高 6 / sin55°），门梁必须在出生点视野内
	_check(gate_x - spawn_x <= 7.0, "出生点到卡口 %.1fm <= 7.0m（一眼能看到门梁）" % (gate_x - spawn_x))

	print("== 物品 ==")
	var items: Array = spec["items"]
	var seen: Dictionary = {}
	var prop_count := 0
	var p0_count := 0
	var p0_meshes: Dictionary = {}
	var regex := RegEx.create_from_string(SNAKE_CASE)
	for entry: Variant in items:
		var item: Dictionary = entry as Dictionary
		var id := String(item.get("id", ""))
		var category := String(item.get("category", ""))
		var priority := String(item.get("priority", "p1"))
		var occlusion := String(item.get("occlusion", "none"))
		var side := String(item.get("side", "center"))
		var size: Array = item.get("size", [0.0, 0.0, 0.0])
		var reuse: Array = item.get("reuse", [])
		var mats: Array = item.get("materials", [])
		var mesh_value: Variant = item.get("mesh", "")
		var mesh := "" if mesh_value == null else String(mesh_value)

		_check(not seen.has(id), "id 唯一: %s" % id)
		seen[id] = true
		_check(regex.search(id) != null, "id 命名 snake_case: %s" % id)
		_check(KNOWN_SIDES.has(side), "%s 侧别合法: %s" % [id, side])
		if category != "atmosphere":
			_check(not mesh.is_empty(), "%s 指定了 mesh" % id)
			if priority == "p0":
				p0_meshes[mesh] = true

		if category == "prop":
			prop_count += 1
		if priority == "p0":
			p0_count += 1

		var h := float(size[1])
		if occlusion == "solid" and category != "ground":
			_check(h <= wall_max, "%s 实体高 %.1fm <= %.1fm（不挡视线）" % [id, h, wall_max])
		elif occlusion == "open_frame":
			_check(h <= frame_max, "%s 框架高 %.1fm <= %.1fm" % [id, h, frame_max])
		if side == "near" and (occlusion == "solid" or occlusion == "open_frame"):
			_check(h <= near_max, "%s 位于近侧(+z) 且高 %.1fm <= %.1fm" % [id, h, near_max])

		if category != "atmosphere":
			_check(reuse.size() >= 2, "%s 复用去向 %d 个 >= 2" % [id, reuse.size()])
			for target: Variant in reuse:
				_check(KNOWN_SCENES.has(String(target)), "%s 的去向 %s 在已知场景表内" % [id, target])
			for slot: Variant in mats:
				_check(slot_names.has(String(slot)), "%s 引用的材质槽 %s 存在" % [id, slot])

	_check(prop_count >= 12, "道具 %d 件 >= 12" % prop_count)
	_check(p0_count <= p0_max, "P0 模块 %d 个 <= %d" % [p0_count, p0_max])
	_check(p0_meshes.size() <= p0_mesh_max, "P0 唯一网格 %d 个 <= %d（材质变体不重复建模）" % [p0_meshes.size(), p0_mesh_max])

	print("== 遭遇与交互 ==")
	var zone_by_id: Dictionary = {}
	for entry: Variant in zones:
		var z: Dictionary = entry as Dictionary
		zone_by_id[String(z["id"])] = z
	for entry: Variant in spec.get("encounters", []):
		var enc: Dictionary = entry as Dictionary
		var trigger: Dictionary = enc.get("trigger", {})
		var id := String(enc.get("id", ""))
		_check(String(trigger.get("type", "")) == "area", "%s 用 Area3D 触发而非坐标阈值" % id)
		_check(bool(trigger.get("once", false)), "%s 只触发一次" % id)

		var kinds: Array = enc.get("enemies", [])
		var spawns: Array = enc.get("spawns", [])
		_check(spawns.size() == kinds.size(), "%s 站位 %d 个与敌人 %d 个一致" % [id, spawns.size(), kinds.size()])

		var zone: Dictionary = zone_by_id.get(String(enc.get("zone", "")), {})
		var zr := Rect2()
		if not zone.is_empty():
			var zo: Array = zone["origin"]
			var zs: Array = zone["size"]
			zr = Rect2(float(zo[0]), float(zo[2]), float(zs[0]), float(zs[2]))
		for point: Variant in spawns:
			var pair: Array = point
			var sx := float(pair[0])
			var sz := float(pair[1])
			_check(zr.has_point(Vector2(sx, sz)), "%s 站位 (%.1f,%.1f) 在分区内" % [id, sx, sz])
			_check(absf(sz) <= road_width * 0.5 + 0.5, "%s 站位 (%.1f,%.1f) 在路面上" % [id, sx, sz])

	for entry: Variant in spec.get("interactables", []):
		var inter: Dictionary = entry as Dictionary
		_check(bool(inter.get("on_required_path", false)), "交互 %s 压在必经路径上" % inter.get("id", ""))

	print("== 变体 ==")
	var variants: Array = spec.get("dressing_variants", [])
	_check(variants.size() >= 3, "换装变体 %d 组 >= 3" % variants.size())
	for entry: Variant in variants:
		var variant: Dictionary = entry as Dictionary
		_check(not String(variant.get("id", "")).is_empty(), "变体 id 非空: %s" % variant.get("name", ""))

	_check_kit(items, slot_names, grid)

	_finish()


## 模块规格与关卡数据必须一一对上：kit 多一个（没用到）或关卡引用了一个不存在的模块，都算错。
func _check_kit(items: Array, slot_names: Array[String], grid: float) -> void:
	print("== 模块规格 ==")
	var text := FileAccess.get_file_as_string(KIT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_check(false, "kit 可解析: %s" % KIT_PATH)
		return
	var kit: Dictionary = parsed
	var modules: Array = kit.get("modules", [])
	_check(not modules.is_empty(), "kit 模块数 %d" % modules.size())

	var by_id: Dictionary = {}
	var regex := RegEx.create_from_string(SNAKE_CASE)
	for entry: Variant in modules:
		var module: Dictionary = entry as Dictionary
		var id := String(module.get("id", ""))
		_check(not by_id.has(id), "kit id 唯一: %s" % id)
		by_id[id] = module
		_check(regex.search(id) != null, "kit id 命名 snake_case: %s" % id)

		var size: Array = module.get("size", [0.0, 0.0, 0.0])
		var box_w := float(size[0])
		var box_h := float(size[1])
		var box_d := float(size[2])
		_check(["parts", "hull_85", "none"].has(String(module.get("collision", ""))), "%s 碰撞策略合法" % id)
		_check(["tile", "object"].has(String(module.get("snap", ""))), "%s 吸附类型合法" % id)

		var parts: Array = module.get("parts", [])
		_check(not parts.is_empty(), "%s 至少一个 part" % id)
		for part_entry: Variant in parts:
			var part: Dictionary = part_entry as Dictionary
			var psize := Vector3(float(part["size"][0]), float(part["size"][1]), float(part["size"][2]))
			var offset: Array = part.get("offset", [0.0, 0.0, 0.0])
			var p := Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
			# 原点是底部中心：x/z 关于 0 对称，y 从 0 往上；地面瓦片允许向下探 0.15
			_check(
				absf(p.x) + psize.x * 0.5 <= box_w * 0.5 + 0.05
				and absf(p.z) + psize.z * 0.5 <= box_d * 0.5 + 0.05
				and p.y - psize.y * 0.5 >= -0.15
				and p.y + psize.y * 0.5 <= box_h + 0.05,
				"%s 的 part %.2fx%.2fx%.2f 未越出模块包络" % [id, psize.x, psize.y, psize.z]
			)
			var part_slot := String(part.get("material", ""))
			_check(slot_names.has(part_slot) or part_slot == "glow", "%s part 材质 %s 存在" % [id, part_slot])

		if String(module.get("snap", "")) == "tile":
			_check(is_multiple(box_w, grid), "%s 可拼接件宽 %.1f 对齐 %.1fm 网格" % [id, box_w, grid])

	# P0 的每个网格都必须在 kit 里，且尺寸一致（P1 允许到阶段 5 再做）
	var referenced: Dictionary = {}
	for entry: Variant in items:
		var item: Dictionary = entry as Dictionary
		var mesh_value: Variant = item.get("mesh", "")
		var mesh := "" if mesh_value == null else String(mesh_value)
		if mesh.is_empty():
			continue
		if by_id.has(mesh):
			referenced[mesh] = true
		var priority := String(item.get("priority", "p1"))
		if not by_id.has(mesh):
			if priority == "p0":
				_check(false, "%s（P0）引用的模块 %s 在 kit 里" % [item.get("id", ""), mesh])
			continue
		var module: Dictionary = by_id[mesh]
		var isize: Array = item.get("size", [0.0, 0.0, 0.0])
		var msize: Array = module.get("size", [0.0, 0.0, 0.0])
		var same := true
		for axis: int in 3:
			if absf(float(isize[axis]) - float(msize[axis])) > 0.101:
				same = false
		_check(same, "%s 与模块 %s 尺寸一致" % [item.get("id", ""), mesh])

	# 反向：kit 里不该有没人用的模块
	for id: String in by_id:
		_check(referenced.has(id), "模块 %s 被关卡引用" % id)


func _finish() -> void:
	if _failed == 0:
		print("SPEC OK  %d/%d" % [_passed, _passed])
		get_tree().quit(0)
	else:
		print("SPEC FAIL  %d passed, %d failed" % [_passed, _failed])
		get_tree().quit(1)


func _fail_run(message: String) -> void:
	print("SPEC FAIL  ", message)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  ok   ", message)
	else:
		_failed += 1
		print("  FAIL ", message)


func is_multiple(value: float, step: float) -> bool:
	if is_zero_approx(value):
		return true
	var ratio := value / step
	return is_equal_approx(ratio, roundf(ratio))
