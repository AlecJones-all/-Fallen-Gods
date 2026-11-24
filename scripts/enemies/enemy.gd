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

var _attack_range: float = 1.8
var _windup_sec: float = 0.45
var _attack_cooldown: float = 1.1
var _preferred_range: float = 8.0
var _min_range: float = 4.5
var _fire_interval: float = 1.7
var _projectile_speed: float = 13.0

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

	_current_hp = maxf(_current_hp - amount, 0.0)
	_flash_left = FLASH_SEC

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
	var desired := Vector3.ZERO
	if target != null:
		_face(target.global_position)
		desired = _decide(delta, target)
		if _state != State.WINDUP:
			desired += _separation() * SEPARATION_WEIGHT
		if desired.length_squared() > 1.0:
			desired = desired.normalized()

	_drive(desired, delta)
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
	_windup_sec = float(block.get("windup_sec", 0.45))
	_attack_cooldown = float(block.get("attack_cooldown", 1.1))
	_preferred_range = float(block.get("preferred_range", 8.0))
	_min_range = float(block.get("min_range", 4.5))
	_fire_interval = float(block.get("fire_interval", 1.7))
	_projectile_speed = float(block.get("projectile_speed", 13.0))


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
		_windup_left -= delta
		if _windup_left <= 0.0:
			_resolve_attack(target, distance)
		return Vector3.ZERO

	if _state == State.RECOVER:
		return direction if distance > _attack_range * 0.9 else Vector3.ZERO

	if distance <= _attack_range and _cooldown_left <= 0.0:
		_state = State.WINDUP
		_windup_left = _windup_sec
		return Vector3.ZERO

	return direction if distance > _attack_range * 0.9 else Vector3.ZERO


func _resolve_attack(target: Node3D, distance: float) -> void:
	_state = State.RECOVER
	_cooldown_left = _attack_cooldown
	if distance > _attack_range * ATTACK_REACH_SLACK:
		return
	if not _is_usable_player(target) or not target.has_method(&"take_damage"):
		return
	target.call(&"take_damage", _damage)


func _decide_shooter(_delta: float, target: Node3D, direction: Vector3, distance: float) -> Vector3:
	_try_fire(target, distance)

	if distance < _min_range:
		return -direction
	if distance > _preferred_range:
		return direction
	return direction.cross(Vector3.UP) * _strafe_sign * STRAFE_FACTOR


func _try_fire(target: Node3D, distance: float) -> void:
	if _fire_left > 0.0 or distance > _preferred_range * FIRE_RANGE_FACTOR:
		return
	if not _has_line_of_sight(target):
		return

	_fire_left = _fire_interval
	var to_player := target.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < FLAT_EPSILON:
		return
	_spawn_projectile(to_player.normalized())


func _has_line_of_sight(target: Node3D) -> bool:
	var from := global_position + Vector3.UP * _height * EYE_HEIGHT_FACTOR
	var to := target.global_position + Vector3.UP * PLAYER_TORSO_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _spawn_projectile(direction: Vector3) -> void:
	var shot := PROJECTILE_SCENE.instantiate()
	if shot == null or not shot.has_method(&"configure"):
		return

	shot.call(&"configure", direction, _projectile_speed, _damage, true, PROJECTILE_LIFETIME)

	var parent := get_tree().get_first_node_in_group(GROUP_PROJECTILE_ROOT)
	if parent == null:
		parent = get_parent()
	if parent == null:
		return

	parent.add_child(shot)
	var shot_node := shot as Node3D
	if shot_node != null:
		var muzzle := global_position + Vector3.UP * _height * EYE_HEIGHT_FACTOR
		muzzle += direction * PROJECTILE_MUZZLE_OFFSET
		shot_node.global_position = muzzle


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
	if _collision != null:
		_collision.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)
	died.emit(self)

	if _model == null:
		queue_free()
		return

	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ONE * DEATH_SCALE, DEATH_SEC)
	tween.tween_callback(queue_free)
