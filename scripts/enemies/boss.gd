extends CharacterBody3D

## Floor boss. Chases the player, slams a telegraphed AoE ring and fires radial
## volleys. Two hp thresholds (66% / 33%) push it into faster phases. All numbers
## live in enemies.boss; the scene file stays a bare CharacterBody3D root.

signal died(boss: Node)
signal health_changed(current: float, maximum: float)
signal phase_changed(phase: int)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

const GROUP_PLAYER: StringName = &"player"
const GROUP_ENEMIES: StringName = &"enemies"
const GROUP_BOSS: StringName = &"boss"
const GROUP_PROJECTILE_ROOT: StringName = &"projectile_root"

const PLAYER_POLL_SEC: float = 0.3
const ACCELERATION: float = 14.0
const FRICTION: float = 20.0
const FLAT_EPSILON: float = 0.0001

const FLASH_SEC: float = 0.1
const FLASH_COLOR: Color = Color.WHITE
const FLASH_ENERGY: float = 2.6
const WINDUP_COLOR: Color = Color(1.0, 0.4, 0.15)
const WINDUP_ENERGY: float = 2.0
const AURA_ENERGY: float = 0.5
const PHASE_COLORS: Array[Color] = [
	Color(0.34, 0.20, 0.44),
	Color(0.58, 0.18, 0.32),
	Color(0.90, 0.28, 0.12),
]

const TELEGRAPH_COLOR: Color = Color(1.0, 0.3, 0.12, 0.28)
const TELEGRAPH_Y: float = 0.04
const TELEGRAPH_SEGMENTS: int = 96
const TELEGRAPH_BOUNDARY_WIDTH: float = 0.055
const VOLLEY_LINE_WIDTH: float = 0.055

const DAMAGE_NUMBER_COLOR: Color = Color(1.0, 0.72, 0.3)
const DAMAGE_NUMBER_SCALE: float = 1.5

const PROJECTILE_LIFETIME: float = 3.0
const VOLLEY_DAMAGE_MULT: float = 0.75
const MUZZLE_OFFSET: float = 1.1
const PLAYER_TORSO_HEIGHT: float = 0.9

const EYE_HEIGHT_FACTOR: float = 0.78
const EYE_ENERGY: float = 2.2

const DEATH_SEC: float = 0.32
const DEATH_SCALE: float = 0.04

const SPIKES: int = 6

enum State { CHASE, SLAM, VOLLEY }

var _floor_number: int = 1
var _spawn_position: Vector3 = Vector3.ZERO
var _configured: bool = false

var _display_name: String = "BOSS"
var _max_hp: float = 900.0
var _current_hp: float = 900.0
var _dead: bool = false
var _phase: int = 1
var _speed: float = 2.5
var _damage: float = 16.0
var _radius: float = 1.0
var _height: float = 2.8
var _knockback_resist: float = 0.95

var _slam_range: float = 3.6
var _slam_radius: float = 3.6
var _slam_windup: float = 0.65
var _slam_cooldown: float = 2.4
var _volley_interval: float = 4.4
var _volley_windup_sec: float = 0.45
var _volley_count: int = 10
var _projectile_speed: float = 11.0
var _phase_two_ratio: float = 0.66
var _phase_three_ratio: float = 0.33
var _slam_origin: Vector3 = Vector3.ZERO
var _volley_origin: Vector3 = Vector3.ZERO
var _volley_directions: Array[Vector3] = []
var _windup_target: Node3D

var _gravity: float = 9.8
var _state: State = State.CHASE
var _slam_cd_left: float = 0.0
var _slam_windup_left: float = 0.0
var _volley_left: float = 0.0
var _volley_windup_left: float = 0.0
var _flash_left: float = 0.0

var _player: Node3D
var _player_poll: float = 0.0

var _collision: CollisionShape3D
var _model: Node3D
var _body_mesh: MeshInstance3D
var _body_material: StandardMaterial3D
var _facing: Node3D
var _eye: MeshInstance3D
var _eye_material: StandardMaterial3D
var _aura_material: StandardMaterial3D
var _telegraph: Node3D
var _telegraph_boundary: MeshInstance3D
var _telegraph_fill: MeshInstance3D
var _volley_telegraph: Node3D
var _volley_boundary: MeshInstance3D
var _volley_fill: MeshInstance3D


func configure(floor_number: int, spawn_position: Vector3) -> void:
	_floor_number = maxi(floor_number, 1)
	_spawn_position = spawn_position
	_configured = true

	if is_node_ready():
		global_position = _spawn_position
		_read_tuning()
		_current_hp = _max_hp
		_apply_geometry()
		health_changed.emit(_current_hp, _max_hp)


func get_display_name() -> String:
	return _display_name


func get_current_hp() -> float:
	return _current_hp


func get_max_hp() -> float:
	return _max_hp


func get_phase() -> int:
	return _phase


func is_dead() -> bool:
	return _dead


func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO, knockback_force: float = 6.0) -> void:
	if _dead or amount <= 0.0:
		return

	_current_hp = maxf(_current_hp - amount, 0.0)
	_flash_left = FLASH_SEC
	Juice.damage_number(global_position + Vector3.UP * _height * 0.85, amount,
		DAMAGE_NUMBER_COLOR, DAMAGE_NUMBER_SCALE)
	Juice.hitstop_hit()
	Juice.hit_shake()
	Audio.play_at(&"enemy_hit", global_position + Vector3.UP * _height * 0.6)
	health_changed.emit(_current_hp, _max_hp)

	var flat := Vector3(knockback_dir.x, 0.0, knockback_dir.z)
	if flat.length_squared() > FLAT_EPSILON:
		velocity += flat.normalized() * knockback_force * (1.0 - _knockback_resist)

	if _current_hp <= 0.0:
		_die()
		return
	_check_phase()


func _ready() -> void:
	add_to_group(GROUP_ENEMIES)
	add_to_group(GROUP_BOSS)
	if not _configured:
		_floor_number = 1
		_spawn_position = global_position

	global_position = _spawn_position
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_read_tuning()
	_current_hp = _max_hp
	_build_visuals()
	_apply_geometry()

	_volley_left = _volley_interval * 0.6
	health_changed.emit(_current_hp, _max_hp)
	phase_changed.emit(_phase)
	Audio.play_at(&"boss_roar", global_position + Vector3.UP * _height * 0.5)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_tick_timers(delta)
	_poll_player(delta)

	var target: Node3D = _player if _is_usable_player(_player) else null
	var cancelled := _state != State.CHASE and (
		not _is_usable_player(_windup_target) or target != _windup_target)
	if cancelled:
		_cancel_windup()
	var desired := Vector3.ZERO
	if target != null and not cancelled:
		if _state != State.VOLLEY:
			_face(target.global_position)
		desired = _decide(delta, target)

	_drive(desired, delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	_update_appearance()


func _read_tuning() -> void:
	var block: Dictionary = Tuning.section("enemies").get("boss", {})
	var scaling: Dictionary = Tuning.section("enemies").get("scaling", {})
	var floor_steps := float(_floor_number - 1)
	var hp_scale := 1.0 + float(scaling.get("hp_per_floor", 0.16)) * floor_steps
	var damage_scale := 1.0 + float(scaling.get("damage_per_floor", 0.10)) * floor_steps

	_display_name = String(block.get("name", "BOSS"))
	_max_hp = float(block.get("hp", 900.0)) * hp_scale
	_damage = float(block.get("damage", 16.0)) * damage_scale
	_speed = float(block.get("speed", 2.5))
	_radius = float(block.get("radius", 1.0))
	_height = float(block.get("height", 2.8))
	_knockback_resist = float(block.get("knockback_resist", 0.95))

	_slam_range = float(block.get("slam_range", 3.6))
	_slam_radius = float(block.get("slam_radius", 3.6))
	_slam_windup = float(block.get("slam_windup", 0.65))
	_slam_cooldown = float(block.get("slam_cooldown", 2.4))
	_volley_interval = float(block.get("volley_interval", 4.4))
	_volley_windup_sec = maxf(float(block.get("volley_windup_sec", 0.45)), 0.01)
	_volley_count = maxi(int(block.get("volley_count", 10)), 1)
	_projectile_speed = float(block.get("projectile_speed", 11.0))
	_phase_two_ratio = clampf(float(block.get("phase_two", 0.66)), 0.05, 0.95)
	_phase_three_ratio = clampf(float(block.get("phase_three", 0.33)), 0.05, 0.95)


func _build_visuals() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	_collision.shape = CapsuleShape3D.new()
	add_child(_collision)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.7
	_body_material.metallic = 0.0

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = CapsuleMesh.new()
	_body_mesh.material_override = _body_material
	_model.add_child(_body_mesh)

	var spike_mesh := BoxMesh.new()
	spike_mesh.size = Vector3(0.2, 0.95, 0.2)
	for i: int in SPIKES:
		var angle := TAU * float(i) / float(SPIKES)
		var spike := MeshInstance3D.new()
		spike.name = "Spike%d" % i
		spike.mesh = spike_mesh
		spike.material_override = _body_material
		spike.position = Vector3(sin(angle) * _radius * 0.72, _height * 0.8, cos(angle) * _radius * 0.72)
		spike.rotation = Vector3(0.0, angle, 0.0)
		_model.add_child(spike)

	_facing = Node3D.new()
	_facing.name = "FacingLobe"
	_model.add_child(_facing)

	_eye_material = StandardMaterial3D.new()
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.emission_enabled = true
	_eye_material.emission_energy_multiplier = EYE_ENERGY

	_eye = MeshInstance3D.new()
	_eye.name = "Eye"
	_eye.mesh = BoxMesh.new()
	_eye.material_override = _eye_material
	_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_facing.add_child(_eye)

	_aura_material = StandardMaterial3D.new()
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.emission_enabled = true
	_aura_material.emission_energy_multiplier = 1.4
	_aura_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var aura_mesh := TorusMesh.new()
	aura_mesh.inner_radius = _radius * 1.05
	aura_mesh.outer_radius = _radius * 1.25
	aura_mesh.rings = 32
	aura_mesh.ring_segments = 12

	var aura := MeshInstance3D.new()
	aura.name = "Aura"
	aura.mesh = aura_mesh
	aura.material_override = _aura_material
	aura.position = Vector3(0.0, 0.08, 0.0)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(aura)

	_build_telegraph()


func _build_telegraph() -> void:
	_telegraph = Node3D.new()
	_telegraph.name = "SlamTelegraph"
	_telegraph.top_level = true
	_telegraph.visible = false
	add_child(_telegraph)
	_telegraph_boundary = _telegraph_part(_telegraph, "Boundary", Color(TELEGRAPH_COLOR, 0.9))
	_telegraph_fill = _telegraph_part(_telegraph, "Fill", TELEGRAPH_COLOR)
	_telegraph_fill.position.y = 0.002

	_volley_telegraph = Node3D.new()
	_volley_telegraph.name = "VolleyTelegraph"
	_volley_telegraph.top_level = true
	_volley_telegraph.visible = false
	add_child(_volley_telegraph)
	_volley_boundary = _telegraph_part(_volley_telegraph, "Boundary", Color(1.0, 0.55, 0.18, 0.9))
	_volley_fill = _telegraph_part(_volley_telegraph, "Fill", Color(1.0, 0.55, 0.18, 0.5))
	_volley_fill.position.y = 0.002


func _telegraph_part(parent: Node3D, part_name: String, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var part := MeshInstance3D.new()
	part.name = part_name
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


func _circle_mesh(radius: float, boundary: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var inner_radius := maxf(radius - TELEGRAPH_BOUNDARY_WIDTH, 0.0)
	for i: int in TELEGRAPH_SEGMENTS:
		var angle_a := TAU * float(i) / float(TELEGRAPH_SEGMENTS)
		var angle_b := TAU * float(i + 1) / float(TELEGRAPH_SEGMENTS)
		var direction_a := Vector3(sin(angle_a), 0.0, cos(angle_a))
		var direction_b := Vector3(sin(angle_b), 0.0, cos(angle_b))
		var a := direction_a * radius
		var b := direction_b * radius
		if boundary:
			var inner_a := direction_a * inner_radius
			var inner_b := direction_b * inner_radius
			vertices.append_array(PackedVector3Array([inner_a, a, b, inner_a, b, inner_b]))
		else:
			vertices.append_array(PackedVector3Array([Vector3.ZERO, a, b]))
	return _ground_mesh(vertices)


func _volley_mesh(length: float, width: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for direction: Vector3 in _volley_directions:
		var side := direction.cross(Vector3.UP) * width * 0.5
		var end := direction * length
		vertices.append_array(PackedVector3Array([-side, side, end + side, -side, end + side, end - side]))
	return _ground_mesh(vertices)


func _ground_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_geometry() -> void:
	var capsule_height := maxf(_height, _radius * 2.0)
	var center_y := _height * 0.5

	var shape := _collision.shape as CapsuleShape3D
	shape.radius = _radius
	shape.height = capsule_height
	_collision.position = Vector3(0.0, center_y, 0.0)

	var capsule := _body_mesh.mesh as CapsuleMesh
	capsule.radius = _radius
	capsule.height = capsule_height
	_body_mesh.position = Vector3(0.0, center_y, 0.0)

	_facing.position = Vector3(0.0, _height * EYE_HEIGHT_FACTOR, 0.0)

	var eye_mesh := _eye.mesh as BoxMesh
	eye_mesh.size = Vector3(_radius * 0.62, _radius * 0.42, _radius * 0.32)
	_eye.position = Vector3(0.0, 0.0, -_radius * 0.84)

	_apply_phase_look()


func _apply_phase_look() -> void:
	var color := _phase_color()
	_body_material.albedo_color = color
	_eye_material.albedo_color = color.lightened(0.5)
	_eye_material.emission = color.lightened(0.4)
	_aura_material.albedo_color = Color(color.lightened(0.3), 0.55)
	_aura_material.emission = color.lightened(0.3)


func _phase_color() -> Color:
	return PHASE_COLORS[clampi(_phase - 1, 0, PHASE_COLORS.size() - 1)]


func _tick_timers(delta: float) -> void:
	_slam_cd_left = maxf(_slam_cd_left - delta, 0.0)
	_volley_left = maxf(_volley_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)


func _poll_player(delta: float) -> void:
	_player_poll -= delta
	if _player_poll > 0.0:
		return
	_player_poll = PLAYER_POLL_SEC
	if not _is_usable_player(_player):
		_player = get_tree().get_first_node_in_group(GROUP_PLAYER) as Node3D


func _is_usable_player(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	return true


func _face(target_position: Vector3) -> void:
	var flat := target_position - global_position
	flat.y = 0.0
	if flat.length_squared() < FLAT_EPSILON:
		return
	look_at(global_position + flat, Vector3.UP)


func _decide(delta: float, target: Node3D) -> Vector3:
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	var direction := to_player / distance if distance > FLAT_EPSILON else Vector3.ZERO

	if _state == State.SLAM:
		_slam_windup_left = maxf(_slam_windup_left - delta, 0.0)
		_update_slam_telegraph()
		if _slam_windup_left <= 0.0:
			_resolve_slam(target)
		return Vector3.ZERO
	if _state == State.VOLLEY:
		_volley_windup_left = maxf(_volley_windup_left - delta, 0.0)
		_update_volley_telegraph()
		if _volley_windup_left <= 0.0:
			_fire_volley()
		return Vector3.ZERO

	_try_volley(target, direction)
	if _state == State.VOLLEY:
		return Vector3.ZERO

	if distance <= _slam_range and _slam_cd_left <= 0.0:
		_start_slam(target)
		return Vector3.ZERO

	return direction if distance > _slam_range * 0.7 else Vector3.ZERO


func _start_slam(target: Node3D) -> void:
	_state = State.SLAM
	_slam_windup_left = _slam_windup
	_windup_target = target
	_slam_origin = global_position
	velocity.x = 0.0
	velocity.z = 0.0
	_show_telegraph()


func _resolve_slam(target: Node3D) -> void:
	_state = State.CHASE
	_slam_cd_left = _slam_cooldown * _phase_slam_cooldown_mult()
	_windup_target = null
	_hide_telegraph()
	Audio.play_at(&"boss_slam", _slam_origin)
	Juice.shake(0.4, 0.25)

	if not _is_usable_player(target) or not target.has_method(&"take_damage"):
		return
	var flat := target.global_position - _slam_origin
	flat.y = 0.0
	if flat.length_squared() <= _slam_radius * _slam_radius:
		target.call(&"take_damage", _damage, _slam_origin)


func _show_telegraph() -> void:
	_hide_volley_telegraph()
	_telegraph.global_transform = Transform3D(Basis.IDENTITY, _slam_origin + Vector3.UP * TELEGRAPH_Y)
	_telegraph_boundary.mesh = _circle_mesh(_slam_radius, true)
	_telegraph_fill.mesh = _circle_mesh(1.0, false)
	_telegraph.visible = true
	_update_slam_telegraph()


func _update_slam_telegraph() -> void:
	var progress := clampf(1.0 - _slam_windup_left / maxf(_slam_windup, 0.01), 0.0, 1.0)
	var fill_radius := _slam_radius * progress
	_telegraph_fill.visible = progress > 0.0
	_telegraph_fill.scale = Vector3(fill_radius, 1.0, fill_radius)


func _hide_telegraph() -> void:
	if _telegraph != null:
		_telegraph.visible = false


func _try_volley(target: Node3D, direction: Vector3) -> void:
	if _state != State.CHASE or _volley_left > 0.0 or direction.length_squared() < FLAT_EPSILON:
		return
	if not _is_usable_player(target) or not _has_line_of_sight(target):
		return
	_state = State.VOLLEY
	_volley_windup_left = _volley_windup_sec
	_windup_target = target
	_volley_origin = global_position
	velocity.x = 0.0
	velocity.z = 0.0
	_volley_directions.clear()
	var extra := 2 if _phase >= 2 else 0
	extra += 2 if _phase >= 3 else 0
	var count := maxi(_volley_count + extra, 1)
	var base_angle := atan2(direction.x, direction.z)
	var spin := 0.35 * float(_phase)
	for i: int in count:
		var angle := base_angle + spin + TAU * float(i) / float(count)
		_volley_directions.append(Vector3(sin(angle), 0.0, cos(angle)))
	_show_volley_telegraph()


func _show_volley_telegraph() -> void:
	_hide_telegraph()
	_volley_telegraph.global_transform = Transform3D(Basis.IDENTITY, _volley_origin + Vector3.UP * TELEGRAPH_Y)
	var length := maxf(_projectile_speed * 0.65, _slam_radius * 1.6)
	_volley_boundary.mesh = _volley_mesh(length, VOLLEY_LINE_WIDTH)
	_volley_fill.mesh = _volley_mesh(length, VOLLEY_LINE_WIDTH * 3.0)
	_volley_telegraph.visible = true
	_update_volley_telegraph()


func _update_volley_telegraph() -> void:
	var progress := clampf(1.0 - _volley_windup_left / _volley_windup_sec, 0.0, 1.0)
	_volley_fill.visible = progress > 0.0
	_volley_fill.scale = Vector3(progress, 1.0, progress)


func _hide_volley_telegraph() -> void:
	if _volley_telegraph != null:
		_volley_telegraph.visible = false


func _cancel_windup() -> void:
	_state = State.CHASE
	_slam_windup_left = 0.0
	_volley_windup_left = 0.0
	_windup_target = null
	_volley_directions.clear()
	_hide_telegraph()
	_hide_volley_telegraph()


func _fire_volley() -> void:
	_state = State.CHASE
	_volley_left = _volley_interval * _phase_volley_interval_mult()
	_windup_target = null
	_hide_volley_telegraph()
	for direction: Vector3 in _volley_directions:
		_spawn_projectile(direction, _volley_origin)
	_volley_directions.clear()
	Audio.play_at(&"boss_volley", _volley_origin + Vector3.UP * _height * 0.6)
	Juice.shake(0.12, 0.12)


func _spawn_projectile(direction: Vector3, source_origin: Vector3) -> void:
	var shot := PROJECTILE_SCENE.instantiate()
	if shot == null:
		return
	var shot_node := shot as Node3D
	if shot_node == null or not shot.has_method(&"configure") or not shot.has_method(&"sweep_to"):
		shot.queue_free()
		return

	shot.call(&"configure", direction, _projectile_speed, _damage * VOLLEY_DAMAGE_MULT,
		true, PROJECTILE_LIFETIME)
	var parent := get_tree().get_first_node_in_group(GROUP_PROJECTILE_ROOT)
	if parent == null:
		parent = get_parent()
	if parent == null:
		shot.queue_free()
		return

	parent.add_child(shot)
	var source := source_origin + Vector3.UP * _height * 0.55
	shot_node.global_position = source
	shot.call(&"sweep_to", source + direction * MUZZLE_OFFSET)


func _has_line_of_sight(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * _height * EYE_HEIGHT_FACTOR
	var to := target.global_position + Vector3.UP * PLAYER_TORSO_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _drive(desired: Vector3, delta: float) -> void:
	var target := Vector3.ZERO
	if desired.length_squared() > FLAT_EPSILON:
		target = desired.normalized() * _speed * _phase_speed_mult()

	var rate := ACCELERATION if target.length_squared() > FLAT_EPSILON else FRICTION
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)


func _phase_speed_mult() -> float:
	match _phase:
		2:
			return 1.2
		3:
			return 1.35
	return 1.0


func _phase_slam_cooldown_mult() -> float:
	match _phase:
		2:
			return 0.85
		3:
			return 0.65
	return 1.0


func _phase_volley_interval_mult() -> float:
	match _phase:
		2:
			return 0.9
		3:
			return 0.7
	return 1.0


func _check_phase() -> void:
	var ratio := _current_hp / maxf(_max_hp, 0.001)
	var next_phase := _phase
	if ratio <= _phase_three_ratio:
		next_phase = 3
	elif ratio <= _phase_two_ratio:
		next_phase = 2

	while _phase < next_phase:
		_phase += 1
		phase_changed.emit(_phase)
		Audio.play_at(&"boss_phase", global_position)
		Juice.kill_shake()
		_volley_left = minf(_volley_left, 0.6)
		_apply_phase_look()


func _update_appearance() -> void:
	if _body_material == null:
		return

	if _flash_left > 0.0:
		_set_tint(FLASH_COLOR, FLASH_ENERGY)
	elif _state == State.SLAM or _state == State.VOLLEY:
		_set_tint(WINDUP_COLOR, WINDUP_ENERGY)
	else:
		_set_tint(_phase_color().lightened(0.15), AURA_ENERGY)


func _set_tint(color: Color, energy: float) -> void:
	_body_material.emission_enabled = true
	_body_material.emission = color
	_body_material.emission_energy_multiplier = energy


func _die() -> void:
	_dead = true
	_state = State.CHASE
	velocity = Vector3.ZERO
	set_physics_process(false)
	_cancel_windup()
	if _collision != null:
		_collision.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)

	var burst_center := global_position + Vector3.UP * _height * 0.5
	Juice.death_burst(burst_center, _phase_color())
	Juice.death_burst(burst_center + Vector3(0.6, 0.4, 0.0), _phase_color().lightened(0.2))
	Juice.death_burst(burst_center + Vector3(-0.5, -0.3, 0.4), _phase_color().lightened(0.2))
	Juice.hitstop_kill()
	Juice.kill_shake()
	Audio.play_at(&"boss_die", burst_center)
	health_changed.emit(0.0, _max_hp)
	died.emit(self)

	if _model == null:
		queue_free()
		return

	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ONE * DEATH_SCALE, DEATH_SEC)
	tween.tween_callback(queue_free)
