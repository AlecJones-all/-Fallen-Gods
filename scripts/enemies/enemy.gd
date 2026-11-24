extends CharacterBody3D

## Graybox enemy. Values and visuals are generated from data/tuning.json at
## runtime, so scenes/enemies/enemy.tscn stays a bare CharacterBody3D root.

signal died(enemy: Node)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

const GROUP_ENEMIES: StringName = &"enemies"
const GROUP_PLAYER: StringName = &"player"
const GROUP_PROJECTILE_ROOT: StringName = &"projectile_root"

const KIND_GRUNT: StringName = &"grunt"
const KIND_SHOOTER: StringName = &"shooter"
const KIND_BRUTE: StringName = &"brute"

const PLAYER_POLL_SEC: float = 0.3
const ACCELERATION: float = 20.0
const FRICTION: float = 25.0

const SEPARATION_RADIUS: float = 1.2
const SEPARATION_NEIGHBOURS: int = 5
const SEPARATION_WEIGHT: float = 0.4

const FLAT_EPSILON: float = 0.0001
const FLASH_SEC: float = 0.1
const FLASH_COLOR: Color = Color.WHITE
const FLASH_ENERGY: float = 2.6
const WINDUP_COLOR: Color = Color(1.0, 0.95, 0.25)
const WINDUP_ENERGY: float = 1.6
const AFFIX_AURA_ENERGY: float = 0.4

const TELEGRAPH_COLOR: Color = Color(1.0, 0.82, 0.2, 0.28)
const TELEGRAPH_Y: float = 0.03
const TELEGRAPH_SEGMENTS: int = 48
const TELEGRAPH_BOUNDARY_WIDTH: float = 0.045
const AIM_LINE_WIDTH: float = 0.045

const DAMAGE_NUMBER_COLOR: Color = Color(1.0, 0.86, 0.45)

const ATTACK_REACH_SLACK: float = 1.25
const STRAFE_FACTOR: float = 0.4
const STRAFE_FLIP_SEC: float = 2.0
const FIRE_RANGE_FACTOR: float = 1.35
const PROJECTILE_LIFETIME: float = 2.0
const PROJECTILE_MUZZLE_OFFSET: float = 0.6
const PLAYER_TORSO_HEIGHT: float = 0.9

const EYE_HEIGHT_FACTOR: float = 0.8
const EYE_ENERGY: float = 1.6

const DEATH_SEC: float = 0.18
const DEATH_SCALE: float = 0.05

enum State { MOVE, WINDUP, RECOVER }

var _kind: StringName = KIND_GRUNT
var _floor_number: int = 1
var _spawn_position: Vector3 = Vector3.ZERO
var _configured: bool = false

var _max_hp: float = 46.0
var _current_hp: float = 46.0
var _dead: bool = false
var _speed: float = 3.2
var _damage: float = 10.0
var _radius: float = 0.45
var _height: float = 1.7
var _knockback_resist: float = 0.0

var _affix: StringName = &""
var _affix_data: Dictionary = {}
var _damage_taken_mult: float = 1.0

var _attack_range: float = 1.8
var _attack_arc_deg: float = 110.0
var _windup_sec: float = 0.45
var _aim_lock_sec: float = 0.1
var _attack_cooldown: float = 1.1
var _preferred_range: float = 8.0
var _min_range: float = 4.5
var _fire_interval: float = 1.7
var _projectile_speed: float = 13.0
var _attack_origin: Vector3 = Vector3.ZERO
var _attack_direction: Vector3 = Vector3.FORWARD
var _aim_locked: bool = false
var _windup_target: Node3D

var _gravity: float = 9.8
var _state: State = State.MOVE
var _cooldown_left: float = 0.0
var _windup_left: float = 0.0
var _fire_left: float = 0.0
var _flash_left: float = 0.0
var _strafe_left: float = STRAFE_FLIP_SEC
var _strafe_sign: float = 1.0

var _player: Node3D
var _player_poll: float = 0.0

var _collision: CollisionShape3D
var _model: Node3D
var _body_mesh: MeshInstance3D
var _facing: Node3D
var _eye: MeshInstance3D
var _eye_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _body_color: Color = Color(0.70, 0.22, 0.20)
var _telegraph: Node3D
var _telegraph_boundary: MeshInstance3D
var _telegraph_fill: MeshInstance3D
var _aim_telegraph: Node3D
var _aim_boundary: MeshInstance3D
var _aim_fill: MeshInstance3D


func configure(kind: StringName, floor_number: int, spawn_position: Vector3) -> void:
	_kind = kind
	_floor_number = maxi(floor_number, 1)
	_spawn_position = spawn_position
	_configured = true

	# Late configure (already inside the tree) still applies immediately.
	if is_node_ready():
		global_position = _spawn_position
		_read_tuning()
		_current_hp = _max_hp
		_apply_geometry()


func apply_affix(affix: StringName) -> void:
	if String(affix).is_empty():
		return
	_affix = affix
	var affixes: Dictionary = Tuning.section("enemies").get("affixes", {})
	_affix_data = affixes.get(String(affix), {})
	if _affix_data.is_empty():
		return

	if is_node_ready():
		_read_tuning()
		_current_hp = _max_hp
		_apply_geometry()
		_update_appearance()


func get_affix() -> StringName:
	return _affix


func get_kind() -> StringName:
	return _kind


func get_current_hp() -> float:
	return _current_hp


func get_max_hp() -> float:
	return _max_hp


func is_dead() -> bool:
	return _dead


func take_damage(amount: float, knockback_dir: Vector3 = Vector3.ZERO, knockback_force: float = 6.0) -> void:
	if _dead or amount <= 0.0:
		return

	var applied := amount * _damage_taken_mult
	_current_hp = maxf(_current_hp - applied, 0.0)
	_flash_left = FLASH_SEC
	Juice.damage_number(global_position + Vector3.UP * _height * 0.9, applied,
		DAMAGE_NUMBER_COLOR)
	Juice.hitstop_hit()
	Juice.hit_shake()
	Audio.play_at(&"enemy_hit", global_position + Vector3.UP * _height * 0.6)

	var flat := Vector3(knockback_dir.x, 0.0, knockback_dir.z)
	if flat.length_squared() > FLAT_EPSILON:
		velocity += flat.normalized() * knockback_force * (1.0 - _knockback_resist)

	if _current_hp <= 0.0:
		_die()


func _ready() -> void:
	add_to_group(GROUP_ENEMIES)
	if not _configured:
		_kind = KIND_GRUNT
		_floor_number = 1
		_spawn_position = global_position

	global_position = _spawn_position
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_read_tuning()
	_current_hp = _max_hp
	_build_visuals()
	_apply_geometry()


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_tick_timers(delta)
	_poll_player(delta)

	var target: Node3D = _player if _is_usable_player(_player) else null
	var cancelled := _state == State.WINDUP and (
		not _is_usable_player(_windup_target) or target != _windup_target)
	if cancelled:
		_cancel_windup()
	var desired := Vector3.ZERO
	if target != null and not cancelled:
		var was_winding_up := _state == State.WINDUP
		if not was_winding_up:
			_face(target.global_position)
		desired = _decide(delta, target)
		if _state != State.WINDUP and not was_winding_up:
			desired += _separation() * SEPARATION_WEIGHT
		if desired.length_squared() > 1.0:
			desired = desired.normalized()

	_drive(desired, delta)
	if _state == State.WINDUP:
		look_at(global_position + _attack_direction, Vector3.UP)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	_update_appearance()


func _read_tuning() -> void:
	var block: Dictionary = Tuning.section("enemies").get(String(_kind), {})
	var scaling: Dictionary = Tuning.section("enemies").get("scaling", {})
	var floor_steps := float(_floor_number - 1)
	var hp_scale := 1.0 + float(scaling.get("hp_per_floor", 0.16)) * floor_steps
	var damage_scale := 1.0 + float(scaling.get("damage_per_floor", 0.10)) * floor_steps

	_max_hp = float(block.get("hp", 46.0)) * hp_scale
	_damage = float(block.get("damage", 10.0)) * damage_scale
	_speed = float(block.get("speed", 3.2))
	_radius = float(block.get("radius", 0.45))
	_height = float(block.get("height", 1.7))
	_knockback_resist = float(block.get("knockback_resist", 0.0))

	_attack_range = float(block.get("attack_range", 1.8))
	_attack_arc_deg = clampf(float(block.get("attack_arc_deg", 110.0)), 1.0, 180.0)
	_windup_sec = maxf(float(block.get("windup_sec", 0.3 if _kind == KIND_SHOOTER else 0.45)), 0.01)
	_aim_lock_sec = clampf(float(block.get("aim_lock_sec", 0.1)), 0.0, _windup_sec)
	_attack_cooldown = float(block.get("attack_cooldown", 1.1))
	_preferred_range = float(block.get("preferred_range", 8.0))
	_min_range = float(block.get("min_range", 4.5))
	_fire_interval = float(block.get("fire_interval", 1.7))
	_projectile_speed = float(block.get("projectile_speed", 13.0))

	_max_hp *= float(_affix_data.get("hp_mult", 1.0))
	_damage *= float(_affix_data.get("damage_mult", 1.0))
	_speed *= float(_affix_data.get("speed_mult", 1.0))
	_damage_taken_mult = float(_affix_data.get("damage_taken_mult", 1.0))


func _build_visuals() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	_collision.shape = CapsuleShape3D.new()
	add_child(_collision)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.75
	_body_material.metallic = 0.0

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = CapsuleMesh.new()
	_body_mesh.material_override = _body_material
	_model.add_child(_body_mesh)

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

	_build_telegraph()


func _build_telegraph() -> void:
	_telegraph = Node3D.new()
	_telegraph.name = "WindupTelegraph"
	_telegraph.top_level = true
	_telegraph.visible = false
	add_child(_telegraph)
	_telegraph_boundary = _telegraph_part(_telegraph, "Boundary", Color(TELEGRAPH_COLOR, 0.9))
	_telegraph_fill = _telegraph_part(_telegraph, "Fill", TELEGRAPH_COLOR)
	_telegraph_fill.position.y = 0.002

	_aim_telegraph = Node3D.new()
	_aim_telegraph.name = "AimTelegraph"
	_aim_telegraph.top_level = true
	_aim_telegraph.visible = false
	add_child(_aim_telegraph)
	_aim_boundary = _telegraph_part(_aim_telegraph, "Boundary", Color(0.65, 0.85, 1.0, 0.9))
	_aim_fill = _telegraph_part(_aim_telegraph, "Fill", Color(0.65, 0.85, 1.0, 0.5))
	_aim_fill.position.y = 0.002


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


func _sector_point(radius: float, angle: float) -> Vector3:
	return Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius)


func _sector_mesh(radius: float, boundary: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var half_angle := deg_to_rad(_attack_arc_deg) * 0.5
	var inner_radius := maxf(radius - TELEGRAPH_BOUNDARY_WIDTH, 0.0)
	for i: int in TELEGRAPH_SEGMENTS:
		var angle_a := -half_angle + 2.0 * half_angle * float(i) / float(TELEGRAPH_SEGMENTS)
		var angle_b := -half_angle + 2.0 * half_angle * float(i + 1) / float(TELEGRAPH_SEGMENTS)
		var a := _sector_point(radius, angle_a)
		var b := _sector_point(radius, angle_b)
		if boundary:
			var inner_a := _sector_point(inner_radius, angle_a)
			var inner_b := _sector_point(inner_radius, angle_b)
			vertices.append_array(PackedVector3Array([inner_a, a, b, inner_a, b, inner_b]))
		else:
			vertices.append_array(PackedVector3Array([Vector3.ZERO, a, b]))
	if boundary:
		var inset := minf(TELEGRAPH_BOUNDARY_WIDTH / maxf(radius, 0.01), half_angle)
		vertices.append_array(PackedVector3Array([
			Vector3.ZERO, _sector_point(radius, -half_angle), _sector_point(radius, -half_angle + inset),
			Vector3.ZERO, _sector_point(radius, half_angle - inset), _sector_point(radius, half_angle)]))
	return _ground_mesh(vertices)


func _aim_mesh(length: float, width: float) -> ArrayMesh:
	var half := width * 0.5
	return _ground_mesh(PackedVector3Array([
		Vector3(-half, 0.0, 0.0), Vector3(half, 0.0, 0.0), Vector3(half, 0.0, -length),
		Vector3(-half, 0.0, 0.0), Vector3(half, 0.0, -length), Vector3(-half, 0.0, -length)]))


func _ground_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_geometry() -> void:
	# Root origin sits at the feet, so capsule and mesh are lifted by half the height.
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
	eye_mesh.size = Vector3(_radius * 0.55, _radius * 0.38, _radius * 0.3)
	_eye.position = Vector3(0.0, 0.0, -_radius * 0.82)

	_body_color = _body_color_for(_kind)
	if not _affix_data.is_empty():
		_body_color = _tint_from(_affix_data.get("tint"), _body_color)
	var eye_color := _eye_color_for(_kind)
	_body_material.albedo_color = _body_color
	_eye_material.albedo_color = eye_color
	_eye_material.emission = eye_color


func _body_color_for(kind: StringName) -> Color:
	match kind:
		KIND_SHOOTER:
			return Color(0.38, 0.34, 0.66)
		KIND_BRUTE:
			return Color(0.50, 0.16, 0.14)
		_:
			return Color(0.70, 0.22, 0.20)


func _tint_from(value: Variant, fallback: Color) -> Color:
	if value is Array:
		var parts := value as Array
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return fallback


func _eye_color_for(kind: StringName) -> Color:
	match kind:
		KIND_SHOOTER:
			return Color(0.55, 0.75, 1.0)
		KIND_BRUTE:
			return Color(1.0, 0.5, 0.2)
		_:
			return Color(1.0, 0.75, 0.30)


func _tick_timers(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_fire_left = maxf(_fire_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)

	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = STRAFE_FLIP_SEC
		_strafe_sign = -_strafe_sign

	if _state == State.RECOVER and _cooldown_left <= 0.0:
		_state = State.MOVE


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

	if _kind == KIND_SHOOTER:
		return _decide_shooter(delta, target, direction, distance)
	return _decide_melee(delta, target, direction, distance)


func _decide_melee(delta: float, target: Node3D, direction: Vector3, distance: float) -> Vector3:
	if _state == State.WINDUP:
		_advance_windup(delta, target)
		if _windup_left <= 0.0:
			_resolve_attack(target)
		return Vector3.ZERO

	if _state == State.RECOVER:
		return direction if distance > _attack_range * 0.9 else Vector3.ZERO

	if distance <= _attack_range and _cooldown_left <= 0.0:
		_begin_windup(target)
		return Vector3.ZERO

	return direction if distance > _attack_range * 0.9 else Vector3.ZERO


func _begin_windup(target: Node3D) -> void:
	_state = State.WINDUP
	_windup_left = _windup_sec
	_windup_target = target
	_attack_origin = global_position
	velocity.x = 0.0
	velocity.z = 0.0
	_attack_direction = -global_basis.z
	_attack_direction.y = 0.0
	_attack_direction = _attack_direction.normalized()
	_track_windup_target(target)
	_aim_locked = _windup_left <= _aim_lock_sec + 0.000001
	_start_telegraph()


func _track_windup_target(target: Node3D) -> void:
	var flat := target.global_position - _attack_origin
	flat.y = 0.0
	if flat.length_squared() > FLAT_EPSILON:
		_attack_direction = flat.normalized()
	look_at(global_position + _attack_direction, Vector3.UP)


func _advance_windup(delta: float, target: Node3D) -> void:
	if not _aim_locked:
		_track_windup_target(target)
	_windup_left = maxf(_windup_left - delta, 0.0)
	if _windup_left <= _aim_lock_sec + 0.000001:
		_aim_locked = true
	_update_windup_telegraph()


func _start_telegraph() -> void:
	_stop_telegraph()
	if _kind == KIND_SHOOTER:
		var length := _preferred_range * FIRE_RANGE_FACTOR
		_aim_boundary.mesh = _aim_mesh(length, AIM_LINE_WIDTH)
		_aim_fill.mesh = _aim_mesh(length, AIM_LINE_WIDTH * 3.0)
		_aim_telegraph.global_position = _attack_origin + Vector3.UP * TELEGRAPH_Y
		_aim_telegraph.visible = true
	else:
		var reach := _attack_range * ATTACK_REACH_SLACK
		_telegraph_boundary.mesh = _sector_mesh(reach, true)
		_telegraph_fill.mesh = _sector_mesh(1.0, false)
		_telegraph.global_position = _attack_origin + Vector3.UP * TELEGRAPH_Y
		_telegraph.visible = true
	_update_windup_telegraph()


func _update_windup_telegraph() -> void:
	var progress := clampf(1.0 - _windup_left / _windup_sec, 0.0, 1.0)
	if _kind == KIND_SHOOTER:
		_aim_telegraph.look_at(_aim_telegraph.global_position + _attack_direction, Vector3.UP)
		_aim_fill.visible = progress > 0.0
		_aim_fill.scale = Vector3(1.0, 1.0, progress)
	else:
		_telegraph.look_at(_telegraph.global_position + _attack_direction, Vector3.UP)
		var fill_radius := _attack_range * ATTACK_REACH_SLACK * progress
		_telegraph_fill.visible = progress > 0.0
		_telegraph_fill.scale = Vector3(fill_radius, 1.0, fill_radius)


func _stop_telegraph() -> void:
	if _telegraph != null:
		_telegraph.visible = false
	if _aim_telegraph != null:
		_aim_telegraph.visible = false


func _cancel_windup() -> void:
	_state = State.MOVE
	_windup_left = 0.0
	_windup_target = null
	_aim_locked = false
	_stop_telegraph()


func _resolve_attack(target: Node3D) -> void:
	_state = State.RECOVER
	_cooldown_left = _attack_cooldown
	_windup_target = null
	_stop_telegraph()
	Audio.play_at(&"enemy_swing", _attack_origin)
	if not _is_usable_player(target) or not target.has_method(&"take_damage"):
		return
	var flat := target.global_position - _attack_origin
	flat.y = 0.0
	var reach := _attack_range * ATTACK_REACH_SLACK
	if flat.length_squared() > reach * reach:
		return
	if flat.length_squared() > 0.0:
		if _attack_direction.dot(flat.normalized()) < cos(deg_to_rad(_attack_arc_deg) * 0.5):
			return
	if not _wall_clear(_attack_origin + Vector3.UP * PLAYER_TORSO_HEIGHT,
		target.global_position + Vector3.UP * PLAYER_TORSO_HEIGHT):
		return
	target.call(&"take_damage", _damage, _attack_origin)


func _decide_shooter(delta: float, target: Node3D, direction: Vector3, distance: float) -> Vector3:
	if _state == State.WINDUP:
		_advance_windup(delta, target)
		if _windup_left <= 0.0:
			_resolve_shot(target)
		return Vector3.ZERO
	_try_fire(target, distance)
	if _state == State.WINDUP:
		return Vector3.ZERO

	if distance < _min_range:
		return -direction
	if distance > _preferred_range:
		return direction
	return direction.cross(Vector3.UP) * _strafe_sign * STRAFE_FACTOR


func _try_fire(target: Node3D, distance: float) -> void:
	if _state != State.MOVE or _fire_left > 0.0 or distance > _preferred_range * FIRE_RANGE_FACTOR:
		return
	if not _is_usable_player(target) or not _has_line_of_sight(target):
		return
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < FLAT_EPSILON:
		return
	_begin_windup(target)


func _resolve_shot(target: Node3D) -> void:
	_state = State.MOVE
	_fire_left = _fire_interval
	_windup_target = null
	_stop_telegraph()
	if _is_usable_player(target):
		_spawn_projectile(_attack_direction, _attack_origin)


func _has_line_of_sight(target: Node3D) -> bool:
	return _wall_clear(global_position + Vector3.UP * _height * EYE_HEIGHT_FACTOR,
		target.global_position + Vector3.UP * PLAYER_TORSO_HEIGHT)


func _wall_clear(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < FLAT_EPSILON:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _spawn_projectile(direction: Vector3, source_origin: Vector3) -> void:
	var shot := PROJECTILE_SCENE.instantiate()
	if shot == null:
		return
	var shot_node := shot as Node3D
	if shot_node == null or not shot.has_method(&"configure") or not shot.has_method(&"sweep_to"):
		shot.queue_free()
		return

	shot.call(&"configure", direction, _projectile_speed, _damage, true, PROJECTILE_LIFETIME)
	var parent := get_tree().get_first_node_in_group(GROUP_PROJECTILE_ROOT)
	if parent == null:
		parent = get_parent()
	if parent == null:
		shot.queue_free()
		return

	parent.add_child(shot)
	var source := source_origin + Vector3.UP * _height * EYE_HEIGHT_FACTOR
	var muzzle := source + direction * PROJECTILE_MUZZLE_OFFSET
	shot_node.global_position = source
	shot.call(&"sweep_to", muzzle)
	Audio.play_at(&"enemy_shot", muzzle)


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var counted := 0
	for node: Node in get_tree().get_nodes_in_group(GROUP_ENEMIES):
		if counted >= SEPARATION_NEIGHBOURS:
			break
		if node == self or not (node is Node3D):
			continue
		var other := node as Node3D
		if other.has_method(&"is_dead") and bool(other.call(&"is_dead")):
			continue

		var flat := global_position - other.global_position
		flat.y = 0.0
		var distance := flat.length()
		if distance < 0.001 or distance >= SEPARATION_RADIUS:
			continue
		push += flat / distance * (1.0 - distance / SEPARATION_RADIUS)
		counted += 1
	return push


func _drive(desired: Vector3, delta: float) -> void:
	var target := Vector3.ZERO
	if desired.length_squared() > FLAT_EPSILON:
		target = desired.normalized() * _speed

	var rate := ACCELERATION if target.length_squared() > FLAT_EPSILON else FRICTION
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)


func _update_appearance() -> void:
	if _body_material == null:
		return

	if _flash_left > 0.0:
		_set_tint(FLASH_COLOR, FLASH_ENERGY)
	elif _state == State.WINDUP:
		_set_tint(WINDUP_COLOR, WINDUP_ENERGY)
	elif not _affix_data.is_empty():
		_set_tint(_body_color.lightened(0.15), AFFIX_AURA_ENERGY)
	else:
		_body_material.emission_enabled = false


func _set_tint(color: Color, energy: float) -> void:
	_body_material.emission_enabled = true
	_body_material.emission = color
	_body_material.emission_energy_multiplier = energy


func _die() -> void:
	_dead = true
	_state = State.MOVE
	velocity = Vector3.ZERO
	set_physics_process(false)
	_cancel_windup()
	if _collision != null:
		_collision.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)
	Juice.death_burst(global_position + Vector3.UP * _height * 0.5, _body_color)
	Juice.hitstop_kill()
	Juice.kill_shake()
	Audio.play_at(&"enemy_die", global_position + Vector3.UP * _height * 0.5)
	died.emit(self)

	if _model == null:
		queue_free()
		return

	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ONE * DEATH_SCALE, DEATH_SEC)
	tween.tween_callback(queue_free)
