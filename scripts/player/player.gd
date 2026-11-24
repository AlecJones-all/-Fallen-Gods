extends CharacterBody3D

signal hp_changed(current: float, maximum: float)
signal dash_state_changed(remaining: float, total: float)
signal aim_point_changed(point: Vector3)
signal weapon_changed(index: int, label: String)
signal damaged_from(source_position: Vector3)
signal died

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

const GROUND_Y: float = 0.0
const AIM_MARKER_Y: float = 0.02
const AIM_EPSILON: float = 0.0001

# Layer bits: world = 1 (bit 0), player = 2 (bit 1).
const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2

const WEAPON_BLADE: int = 0
const WEAPON_CROSSBOW: int = 1
const WEAPON_COUNT: int = 2
const WEAPON_LABELS: Array[String] = ["长剑", "连弩"]

const SWING_SEC: float = 0.16
const MELEE_REACH_SLACK: float = 0.9
const MUZZLE_FORWARD: float = 0.9
const MUZZLE_HEIGHT: float = 0.9
const HIT_FLASH_TINT: Color = Color(1.0, 0.25, 0.2)
const GHOST_INTERVAL: float = 0.045
const HURT_NUMBER_COLOR: Color = Color(1.0, 0.42, 0.35)

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _facing: Node3D = $FacingWedge
@onready var _aim_marker: MeshInstance3D = $AimMarker
@onready var _swing_pivot: Node3D = $FacingWedge/SwingPivot
@onready var _blade_mesh: MeshInstance3D = $FacingWedge/SwingPivot/Blade

var _max_hp: float = 100.0
var _current_hp: float = 100.0
var _dead: bool = false
var _invuln_sec: float = 0.6
var _hit_flash_sec: float = 0.18
var _invuln_left: float = 0.0
var _flash_left: float = 0.0
var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color(0.8, 0.8, 0.82)

var _move_speed: float = 5.5
var _sprint_multiplier: float = 1.6
var _acceleration: float = 40.0
var _friction: float = 30.0
var _dash_speed: float = 16.0
var _dash_time: float = 0.16
var _dash_cooldown: float = 1.0
var _radius: float = 0.45
var _height: float = 1.8
var _gravity: float = 9.8

var _dash_left: float = 0.0
var _dash_dir: Vector3 = Vector3.FORWARD
var _cooldown_left: float = 0.0
var _reported_cooldown: float = 0.0
var _ghost_left: float = 0.0

var _weapon_index: int = WEAPON_BLADE
var _attack_left: float = 0.0
var _swing_left: float = 0.0

var _blade_damage: float = 26.0
var _blade_cooldown: float = 0.42
var _blade_range: float = 2.7
var _blade_arc_deg: float = 110.0
var _blade_knockback: float = 7.0
var _bolt_damage: float = 16.0
var _bolt_cooldown: float = 0.26
var _bolt_speed: float = 26.0
var _bolt_lifetime: float = 1.2

var _aim_point: Vector3 = Vector3.ZERO
var _has_aim: bool = false
var _last_move_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	# Movement only collides with the world; enemies and shots never block it.
	collision_layer = LAYER_PLAYER
	collision_mask = LAYER_WORLD
	_read_tuning()
	_apply_geometry()
	_setup_hit_flash()
	_current_hp = _max_hp
	_emit_initial_state.call_deferred()


func _physics_process(delta: float) -> void:
	_update_aim()
	_update_dash(delta)
	_update_survival(delta)
	_update_attack(delta)
	_update_swing(delta)
	_update_velocity(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F1:
		take_damage(10.0)


func get_current_hp() -> float:
	return _current_hp


func get_max_hp() -> float:
	return _max_hp


func is_dead() -> bool:
	return _dead


func take_damage(amount: float, source_position: Vector3 = Vector3.INF) -> void:
	if amount <= 0.0 or _dead:
		return
	# Dash i-frames and the post-hit grace window keep the player from being stunlocked.
	if _invuln_left > 0.0 or _dash_left > 0.0:
		return
	_current_hp = clampf(_current_hp - amount, 0.0, _max_hp)
	_invuln_left = _invuln_sec
	_begin_hit_flash()
	hp_changed.emit(_current_hp, _max_hp)
	damaged_from.emit(source_position)
	Juice.damage_number(global_position + Vector3.UP * _height, amount, HURT_NUMBER_COLOR)
	Juice.hit_shake()
	Juice.hitstop_hit()
	Audio.play(&"player_hurt")
	if _current_hp > 0.0:
		return
	_dead = true
	_swing_left = 0.0
	_hide_combat_visuals()
	set_physics_process(false)
	Audio.play(&"player_death")
	died.emit()


func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	var before := _current_hp
	_current_hp = clampf(_current_hp + amount, 0.0, _max_hp)
	if _current_hp <= before:
		return
	Audio.play(&"heal")
	hp_changed.emit(_current_hp, _max_hp)


## Seconds of dash cooldown left; 0.0 means the dash is ready.
func get_dash_remaining() -> float:
	return _cooldown_left


func get_dash_total() -> float:
	return _dash_cooldown


func select_weapon(index: int) -> void:
	var wrapped := posmod(index, WEAPON_COUNT)
	if wrapped == _weapon_index:
		return
	_weapon_index = wrapped
	weapon_changed.emit(_weapon_index, get_weapon_label())


func cycle_weapon(step: int) -> void:
	select_weapon(_weapon_index + step)


func get_weapon_index() -> int:
	return _weapon_index


func get_weapon_label() -> String:
	return WEAPON_LABELS[_weapon_index]


func _read_tuning() -> void:
	_max_hp = float(Tuning.value("player", "max_hp", 100.0))
	_move_speed = float(Tuning.value("player", "move_speed", 5.5))
	_sprint_multiplier = float(Tuning.value("player", "sprint_multiplier", 1.6))
	_acceleration = float(Tuning.value("player", "acceleration", 40.0))
	_friction = float(Tuning.value("player", "friction", 30.0))
	_dash_speed = float(Tuning.value("player", "dash_speed", 16.0))
	_dash_time = float(Tuning.value("player", "dash_time", 0.16))
	_dash_cooldown = float(Tuning.value("player", "dash_cooldown", 1.0))
	_radius = float(Tuning.value("player", "radius", 0.45))
	_height = float(Tuning.value("player", "height", 1.8))
	_invuln_sec = float(Tuning.value("player", "invuln_sec", 0.6))
	_hit_flash_sec = float(Tuning.value("player", "hit_flash_sec", 0.18))
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

	var blade: Dictionary = Tuning.section("weapons").get("blade", {})
	_blade_damage = float(blade.get("damage", 26.0))
	_blade_cooldown = float(blade.get("cooldown", 0.42))
	_blade_range = float(blade.get("range", 2.7))
	_blade_arc_deg = float(blade.get("arc_deg", 110.0))
	_blade_knockback = float(blade.get("knockback", 7.0))

	var crossbow: Dictionary = Tuning.section("weapons").get("crossbow", {})
	_bolt_damage = float(crossbow.get("damage", 16.0))
	_bolt_cooldown = float(crossbow.get("cooldown", 0.26))
	_bolt_speed = float(crossbow.get("speed", 26.0))
	_bolt_lifetime = float(crossbow.get("lifetime", 1.2))


func _apply_geometry() -> void:
	# Root origin sits at the feet, so capsule and mesh are lifted by half the height.
	var capsule_height := maxf(_height, _radius * 2.0)

	var shape := _collision.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		_collision.shape = shape
	shape.radius = _radius
	shape.height = capsule_height
	_collision.position = Vector3(0.0, _height * 0.5, 0.0)

	var capsule := _body_mesh.mesh as CapsuleMesh
	if capsule == null:
		capsule = CapsuleMesh.new()
		_body_mesh.mesh = capsule
	capsule.radius = _radius
	capsule.height = capsule_height
	_body_mesh.position = Vector3(0.0, _height * 0.5, 0.0)

	_facing.position = Vector3(0.0, _height * 0.6, 0.0)


func _setup_hit_flash() -> void:
	# Own the material instance so the flash never touches the shared scene resource.
	var source := _body_mesh.material_override
	if source == null:
		source = _body_mesh.get_surface_override_material(0)
	var standard := source as StandardMaterial3D
	if standard == null:
		return
	_body_material = standard.duplicate() as StandardMaterial3D
	_base_albedo = _body_material.albedo_color
	_body_mesh.material_override = _body_material


func _emit_initial_state() -> void:
	hp_changed.emit(_current_hp, _max_hp)
	_reported_cooldown = _cooldown_left
	dash_state_changed.emit(_cooldown_left, _dash_cooldown)
	aim_point_changed.emit(_aim_point)
	weapon_changed.emit(_weapon_index, get_weapon_label())


func _update_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	if absf(normal.y) < AIM_EPSILON:
		return

	var hit_time := (GROUND_Y - origin.y) / normal.y
	if hit_time < 0.0:
		return

	var point := origin + normal * hit_time
	point.y = GROUND_Y
	_aim_marker.global_position = Vector3(point.x, AIM_MARKER_Y, point.z)

	if _has_aim and point.distance_squared_to(_aim_point) < AIM_EPSILON:
		return
	_has_aim = true
	_aim_point = point
	aim_point_changed.emit(_aim_point)
	_face_aim()


func _face_aim() -> void:
	var flat := _aim_point - _facing.global_position
	flat.y = 0.0
	if flat.length_squared() < AIM_EPSILON:
		return
	_facing.look_at(_facing.global_position + flat, Vector3.UP)


func _update_survival(delta: float) -> void:
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _body_material == null:
		return
	var intensity := _flash_left / _hit_flash_sec if _hit_flash_sec > 0.0 else 0.0
	_body_material.albedo_color = _base_albedo.lerp(HIT_FLASH_TINT, intensity)


func _begin_hit_flash() -> void:
	if _hit_flash_sec <= 0.0:
		return
	_flash_left = _hit_flash_sec
	if _body_material != null:
		_body_material.albedo_color = HIT_FLASH_TINT


func _update_attack(delta: float) -> void:
	_attack_left = maxf(_attack_left - delta, 0.0)
	if _dead:
		return

	_handle_weapon_input()
	if _attack_left > 0.0:
		return

	var aim_dir := _aim_direction()
	if _weapon_index == WEAPON_BLADE:
		if Input.is_action_just_pressed("attack"):
			_attack_left = _blade_cooldown
			_begin_swing()
			_do_melee(aim_dir)
	elif Input.is_action_pressed("attack"):
		_attack_left = _bolt_cooldown
		_do_ranged(aim_dir)


func _handle_weapon_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		select_weapon(WEAPON_BLADE)
	elif Input.is_action_just_pressed("weapon_2"):
		select_weapon(WEAPON_CROSSBOW)
	elif Input.is_action_just_pressed("weapon_next"):
		cycle_weapon(1)
	elif Input.is_action_just_pressed("weapon_prev"):
		cycle_weapon(-1)


func _aim_direction() -> Vector3:
	var dir := _aim_point - global_position
	dir.y = 0.0
	if dir.length_squared() > AIM_EPSILON:
		return dir.normalized()

	var facing := -_facing.global_basis.z
	facing.y = 0.0
	if facing.length_squared() > AIM_EPSILON:
		return facing.normalized()

	return _last_move_dir


func _do_melee(direction: Vector3) -> void:
	var aim := direction
	aim.y = 0.0
	if aim.length_squared() > AIM_EPSILON:
		aim = aim.normalized()
	var min_dot := cos(deg_to_rad(_blade_arc_deg * 0.5))
	var reach := _blade_range + MELEE_REACH_SLACK

	# Damage lands on press; the sweep mesh below is pure feedback.
	for node in get_tree().get_nodes_in_group("enemies"):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		var enemy = node
		if not enemy.has_method("take_damage"):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue

		var to_enemy := target.global_position - global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > reach:
			continue
		var dir_to_enemy := to_enemy / distance if distance > AIM_EPSILON else aim
		if aim.length_squared() > AIM_EPSILON and aim.dot(dir_to_enemy) < min_dot:
			continue
		enemy.take_damage(_blade_damage, dir_to_enemy, _blade_knockback)


func _do_ranged(direction: Vector3) -> void:
	if direction.length_squared() <= AIM_EPSILON or PROJECTILE_SCENE == null:
		return
	var dir := direction.normalized()
	var parent := _projectile_parent()
	if parent == null:
		return

	var shot = PROJECTILE_SCENE.instantiate()
	if shot == null:
		return
	shot.configure(dir, _bolt_speed, _bolt_damage, false, _bolt_lifetime)
	parent.add_child(shot)
	shot.global_position = global_position + dir * MUZZLE_FORWARD + Vector3.UP * MUZZLE_HEIGHT
	Audio.play(&"crossbow_fire")


func _projectile_parent() -> Node3D:
	var roots := get_tree().get_nodes_in_group("projectile_root")
	if not roots.is_empty():
		return roots[0] as Node3D
	return get_parent() as Node3D


func _begin_swing() -> void:
	if _swing_pivot == null:
		return
	_swing_left = SWING_SEC
	_swing_pivot.visible = true
	_swing_pivot.rotation.y = -deg_to_rad(_blade_arc_deg * 0.5)
	Audio.play(&"sword_swing")


func _update_swing(delta: float) -> void:
	if _swing_left <= 0.0:
		return
	_swing_left = maxf(_swing_left - delta, 0.0)
	var half_arc := deg_to_rad(_blade_arc_deg * 0.5)
	var progress := 1.0 - _swing_left / SWING_SEC
	if _swing_pivot != null:
		_swing_pivot.rotation.y = lerpf(-half_arc, half_arc, progress)
	if _swing_left <= 0.0 and _swing_pivot != null:
		_swing_pivot.visible = false


func _hide_combat_visuals() -> void:
	if _swing_pivot != null:
		_swing_pivot.visible = false
	if _blade_mesh != null:
		_blade_mesh.visible = false
	if _aim_marker != null:
		_aim_marker.visible = false


func _update_dash(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_dash_left = maxf(_dash_left - delta, 0.0)

	if Input.is_action_just_pressed("dash") and _dash_left <= 0.0 and _cooldown_left <= 0.0:
		_dash_dir = _pick_dash_direction()
		_dash_left = _dash_time
		_cooldown_left = _dash_cooldown
		_ghost_left = 0.0
		Audio.play(&"dash")

	if _dash_left > 0.0:
		_ghost_left -= delta
		if _ghost_left <= 0.0:
			_ghost_left = GHOST_INTERVAL
			Juice.dash_ghost(global_position + Vector3.UP * _height * 0.5, _radius, _height)
	else:
		_ghost_left = 0.0

	if _cooldown_left > 0.0:
		_reported_cooldown = _cooldown_left
		dash_state_changed.emit(_cooldown_left, _dash_cooldown)
	elif not is_zero_approx(_reported_cooldown):
		_reported_cooldown = 0.0
		dash_state_changed.emit(0.0, _dash_cooldown)


func _pick_dash_direction() -> Vector3:
	var input_dir := _read_move_input()
	if input_dir.length_squared() > AIM_EPSILON:
		return input_dir.normalized()

	var to_aim := _aim_point - global_position
	to_aim.y = 0.0
	if to_aim.length_squared() > AIM_EPSILON:
		return to_aim.normalized()

	return _last_move_dir


func _update_velocity(delta: float) -> void:
	if _dash_left > 0.0:
		velocity.x = _dash_dir.x * _dash_speed
		velocity.z = _dash_dir.z * _dash_speed
		return

	var input_dir := _read_move_input()
	if input_dir.length_squared() > AIM_EPSILON:
		_last_move_dir = input_dir.normalized()

	var speed := _move_speed
	if Input.is_action_pressed("sprint"):
		speed *= _sprint_multiplier

	var target := input_dir * speed
	var rate := _acceleration if input_dir.length_squared() > AIM_EPSILON else _friction
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)


func _read_move_input() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var camera_forward := -camera.global_basis.z
		camera_forward.y = 0.0
		if camera_forward.length_squared() > AIM_EPSILON:
			forward = camera_forward.normalized()

		var camera_right := camera.global_basis.x
		camera_right.y = 0.0
		if camera_right.length_squared() > AIM_EPSILON:
			right = camera_right.normalized()

	var direction := right * input.x - forward * input.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction
