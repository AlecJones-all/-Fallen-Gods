class_name ChapelRitual
extends Node3D

## The reusable hero-prop set for node 04.  It intentionally uses primitive
## meshes: the room can be iterated before bespoke GLBs are commissioned.

@export var graybox := false

const ALTAR := Vector3(3.7, 0.0, -2.0)
const SHRINE := Vector3(6.6, 0.0, -3.4)
const RITUAL_DURATION := 4.0

var _time := 0.0
var _ritual_time := -1.0
var _started := false
var _memory_glow: StandardMaterial3D
var _flame_glow: StandardMaterial3D
var _heart_a: StandardMaterial3D
var _heart_b: StandardMaterial3D
var _fire_light: OmniLight3D
var _cinders: Array[MeshInstance3D] = []
var _memory_shard: MeshInstance3D
var _memory_start := Vector3.ZERO
var _memory_end := Vector3.ZERO


func _ready() -> void:
	_build_altar()
	_build_burning_station()
	_build_oil_apparatus()
	_build_shrine()
	_add_blockers()


func _process(delta: float) -> void:
	_time += delta
	_update_light()
	_update_shrine()
	_update_ritual(delta)


func _material(color: Color, roughness := 0.8, metallic := 0.0, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	if emission.a > 0.0:
		result.emission_enabled = true
		result.emission = emission
		result.emission_energy_multiplier = 1.0
	return result


func _box(name_: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = center
	add_child(node)
	return node


func _cylinder(name_: String, center: Vector3, radius: float, height: float, material: Material, sides := 16) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	node.mesh = mesh
	node.material_override = material
	node.position = center
	add_child(node)
	return node


func _sphere(name_: String, center: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.material_override = material
	node.position = center
	add_child(node)
	return node


func _build_altar() -> void:
	var dark_stone := _material(Color("34333a"), 0.9)
	var pale_stone := _material(Color("bbb1a0"), 0.86)
	var carved_stone := _material(Color("ded4bd"), 0.78)
	_box("AltarStepLower", ALTAR + Vector3(0.0, 0.18, 0.0), Vector3(3.8, 0.36, 2.35), dark_stone)
	_box("AltarStepUpper", ALTAR + Vector3(0.0, 0.43, 0.0), Vector3(3.22, 0.22, 1.82), pale_stone)
	_box("AltarPlinth", ALTAR + Vector3(0.0, 0.83, 0.0), Vector3(2.72, 0.62, 1.42), dark_stone)
	_box("AltarSlab", ALTAR + Vector3(0.0, 1.22, 0.0), Vector3(3.02, 0.18, 1.66), carved_stone)
	if graybox:
		return
	for x in [-1.12, 1.12]:
		for z in [-0.55, 0.55]:
			_cylinder("AltarCorner", ALTAR + Vector3(x, 1.48, z), 0.12, 0.42, carved_stone)
	# A shallow, deliberately abstract ritual groove.
	var groove := _material(Color("765d4d"), 0.68, 0.1)
	_cylinder("AltarRitualGroove", ALTAR + Vector3(0.0, 1.325, 0.0), 0.58, 0.025, groove, 32)
	_cylinder("AltarRitualCenter", ALTAR + Vector3(0.0, 1.34, 0.0), 0.34, 0.028, dark_stone, 32)


func _build_burning_station() -> void:
	var iron := _material(Color("1f2025"), 0.4, 0.78)
	var soot := _material(Color("121014"), 0.96)
	var brass := _material(Color("9d7850"), 0.38, 0.7)
	var ember := _material(Color("ff7b36"), 0.5, 0.05, Color("ff4b16"))
	var station := ALTAR + Vector3(-0.52, 1.43, 0.05)
	_cylinder("MemoryBrazierFoot", station + Vector3(0.0, 0.12, 0.0), 0.16, 0.24, iron)
	_cylinder("MemoryBrazierStem", station + Vector3(0.0, 0.35, 0.0), 0.065, 0.3, brass)
	_cylinder("MemoryBrazierBowl", station + Vector3(0.0, 0.55, 0.0), 0.28, 0.13, iron, 24)
	_cylinder("MemoryAsh", station + Vector3(0.0, 0.625, 0.0), 0.21, 0.018, soot, 24)
	if graybox:
		return
	_memory_glow = _material(Color("ffe8b7"), 0.35, 0.0, Color("ffb868"))
	_memory_glow.emission_energy_multiplier = 0.32
	_memory_start = ALTAR + Vector3(0.64, 1.51, 0.05)
	_memory_end = station + Vector3(0.02, 0.68, 0.0)
	_memory_shard = _box("MemoryShard", _memory_start, Vector3(0.22, 0.025, 0.13), _memory_glow)
	_flame_glow = _material(Color("ff9a42"), 0.55, 0.0, Color("ff531c"))
	_flame_glow.emission_energy_multiplier = 1.2
	var flame := _sphere("LowRitualFlame", station + Vector3(0.0, 0.76, 0.0), 0.105, _flame_glow)
	flame.scale = Vector3(0.7, 1.5, 0.7)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "RitualFireLight"
	_fire_light.position = station + Vector3(0.0, 0.9, 0.0)
	_fire_light.light_color = Color("ff9a54")
	_fire_light.light_energy = 0.72
	_fire_light.omni_range = 4.8
	# No shadow: the flame already breath-flickers, and a shadow map redrawn from that
	# energy made the floorboards around the altar pump with it.
	_fire_light.shadow_enabled = false
	add_child(_fire_light)
	# The shallow tray makes the memory object legible from the isometric view.
	_cylinder("MemoryTray", ALTAR + Vector3(0.64, 1.43, 0.05), 0.30, 0.05, brass, 24)
	_cylinder("MemoryTrayInset", ALTAR + Vector3(0.64, 1.465, 0.05), 0.235, 0.012, soot, 24)
	for offset in [Vector3(-0.08, 0.0, 0.05), Vector3(0.08, 0.0, -0.04), Vector3(0.12, 0.0, 0.09)]:
		var cinder := _sphere("MemoryCinder", ALTAR + Vector3(0.64, 1.49, 0.05) + offset, 0.032, ember)
		_cinders.append(cinder)


func _build_oil_apparatus() -> void:
	if graybox:
		return
	var white_metal := _material(Color("b3a58d"), 0.45, 0.6)
	var oil := _material(Color("9d5c21"), 0.3, 0.1, Color("6a2e12"))
	oil.emission_energy_multiplier = 0.16
	var iron := _material(Color("292b2d"), 0.52, 0.74)
	var base := ALTAR + Vector3(-1.46, 1.46, -0.38)
	_cylinder("HolyOilReservoir", base + Vector3(0.0, 0.2, 0.0), 0.19, 0.4, white_metal)
	_cylinder("HolyOilGlass", base + Vector3(0.0, 0.42, 0.0), 0.12, 0.12, oil)
	_cylinder("HolyOilNeck", base + Vector3(0.0, 0.54, 0.0), 0.045, 0.16, white_metal)
	_box("HolyOilPipeX", base + Vector3(0.42, 0.57, 0.0), Vector3(0.78, 0.055, 0.055), iron)
	_box("HolyOilPipeZ", base + Vector3(0.80, 0.42, 0.18), Vector3(0.055, 0.055, 0.40), iron)
	_cylinder("HolyOilCatchBasin", base + Vector3(0.80, 0.32, 0.38), 0.18, 0.055, white_metal, 24)


func _build_shrine() -> void:
	var white_stone := _material(Color("d6d0c3"), 0.86)
	var deep_stone := _material(Color("4a4542"), 0.9)
	_box("HeartbeatShrineBase", SHRINE + Vector3(0.0, 0.25, 0.0), Vector3(2.05, 0.5, 0.74), white_stone)
	_box("HeartbeatShrineBack", SHRINE + Vector3(0.0, 1.38, -0.25), Vector3(1.92, 1.82, 0.28), white_stone)
	if graybox:
		return
	for x in [-0.62, 0.62]:
		_cylinder("HeartbeatShrinePillar", SHRINE + Vector3(x, 1.30, 0.12), 0.14, 1.6, white_stone)
	# A sealed, pointed white-stone reliquary. The inner black panel is recessed so
	# the red light reads as a fault in stone rather than a pair of staring eyes.
	_box("HeartbeatShrineDarkCavity", SHRINE + Vector3(0.0, 1.34, 0.075), Vector3(1.10, 1.28, 0.055), deep_stone)
	var roof_left := _box("HeartbeatShrineRoofLeft", SHRINE + Vector3(-0.36, 2.28, -0.05), Vector3(1.18, 0.24, 0.52), white_stone)
	roof_left.rotation.z = deg_to_rad(35.0)
	var roof_right := _box("HeartbeatShrineRoofRight", SHRINE + Vector3(0.36, 2.28, -0.05), Vector3(1.18, 0.24, 0.52), white_stone)
	roof_right.rotation.z = deg_to_rad(-35.0)
	_box("HeartbeatShrineCrown", SHRINE + Vector3(0.0, 2.56, -0.05), Vector3(0.26, 0.34, 0.52), white_stone)
	_heart_a = _material(Color("d56c55"), 0.55, 0.0, Color("db4939"))
	_heart_b = _material(Color("d8955d"), 0.55, 0.0, Color("db6d36"))
	_heart_a.emission_energy_multiplier = 0.35
	_heart_b.emission_energy_multiplier = 0.22
	_add_crack("HeartbeatCrackA0", SHRINE + Vector3(-0.18, 1.72, 0.115), Vector3(0.03, 0.44, 0.018), -12.0, _heart_a)
	_add_crack("HeartbeatCrackA1", SHRINE + Vector3(-0.06, 1.37, 0.115), Vector3(0.03, 0.30, 0.018), 19.0, _heart_a)
	_add_crack("HeartbeatCrackB0", SHRINE + Vector3(0.30, 1.57, 0.116), Vector3(0.027, 0.36, 0.018), 17.0, _heart_b)
	_add_crack("HeartbeatCrackB1", SHRINE + Vector3(0.19, 1.26, 0.116), Vector3(0.027, 0.28, 0.018), -22.0, _heart_b)


func _add_crack(name_: String, center: Vector3, size: Vector3, angle: float, material: Material) -> void:
	var crack := _box(name_, center, size, material)
	crack.rotation.z = deg_to_rad(angle)


func _add_blockers() -> void:
	# The target review marker (5.4, -1.8) is deliberately left unobstructed.
	_blocker("AltarBlocker", ALTAR + Vector3(0.0, 0.72, 0.0), Vector3(3.05, 1.44, 1.70))
	_blocker("ShrineBlocker", SHRINE + Vector3(0.0, 1.15, -0.08), Vector3(1.95, 2.30, 0.62))


func _blocker(name_: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name_
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _update_light() -> void:
	# Two slow breaths instead of the old 9 Hz + 17 Hz pair: the fast term sat in the band
	# the eye reads as strobing, and it made the shadowed fire light pulse every frame.
	if _flame_glow != null:
		_flame_glow.emission_energy_multiplier = 0.95 + sin(_time * 3.2) * 0.10 + sin(_time * 1.3) * 0.04
	if _fire_light != null:
		_fire_light.light_energy = 0.66 + sin(_time * 3.2) * 0.05


func _update_shrine() -> void:
	if _heart_a != null:
		_heart_a.emission_energy_multiplier = 0.26 + pow(maxf(sin(_time * 4.3), 0.0), 5.0) * 1.05
	if _heart_b != null:
		_heart_b.emission_energy_multiplier = 0.19 + pow(maxf(sin(_time * 3.1 + 1.85), 0.0), 5.0) * 0.78


func _update_ritual(delta: float) -> void:
	if not _started:
		var player := get_tree().get_first_node_in_group(&"player") as Node3D
		if player != null and player.global_position.distance_to(ALTAR) < 3.0:
			_started = true
			_ritual_time = 0.0
	if _ritual_time < 0.0:
		return
	_ritual_time += delta
	var progress := clampf(_ritual_time / RITUAL_DURATION, 0.0, 1.0)
	if _memory_glow != null:
		_memory_glow.emission_energy_multiplier = lerpf(0.32, 2.1, sin(progress * PI))
	if _flame_glow != null:
		_flame_glow.emission_energy_multiplier += sin(progress * PI) * 0.75
	for index in _cinders.size():
		var cinder := _cinders[index]
		if is_instance_valid(cinder):
			cinder.position.y = 1.49 + minf(progress * (0.30 + index * 0.06), 0.46)
			cinder.position.x += sin(_time * 5.0 + index) * delta * 0.018
	if is_instance_valid(_memory_shard):
		_memory_shard.position = _memory_start.lerp(_memory_end, smoothstep(0.0, 0.72, progress))
		_memory_shard.position.y += sin(progress * PI) * 0.10
		_memory_shard.scale = Vector3.ONE * lerpf(1.0, 0.18, smoothstep(0.55, 1.0, progress))
	if progress >= 1.0:
		_ritual_time = -1.0
