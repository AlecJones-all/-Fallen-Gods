extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")
const CAMERA_SCENE := preload("res://scenes/camera/camera_rig.tscn")

var _player: CharacterBody3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set("_aim_point", Vector3(10.0, 0.0, 0.0))
	if not _movement_test():
		return
	if not await _buffer_test():
		return
	_player.call("_end_swing")
	_player.set("_attack_left", 0.0)
	if not await _dash_physics_test():
		return
	if not await _melee_test():
		return
	if not await _multi_target_swing_test():
		return
	if not await _projectile_test():
		return
	if not await _telegraph_geometry_test():
		return
	if not await _enemy_timing_test():
		return
	if not await _boss_timing_test():
		return
	if not await _feedback_test():
		return
	for voice: AudioStreamPlayer3D in get_tree().get_nodes_in_group(&"audio_voices_3d"):
		voice.stop()
		voice.stream = null
		voice.queue_free()
	for voice: AudioStreamPlayer in Audio.get_children():
		voice.stop()
		voice.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
	# Stopped audio playbacks retire on mixer ticks, not scene frames.
	var mix_cycle := AudioServer.get_time_since_last_mix() + AudioServer.get_time_to_next_mix()
	await _wait_wall_msec(int(ceil(mix_cycle * 2000.0)))
	print("FEEL OK")
	get_tree().quit(0)


func _movement_test() -> bool:
	for hz: int in [30, 60, 144]:
		var step := 1.0 / float(hz)
		_player.velocity = Vector3.ZERO
		Input.action_press("move_right")
		for frame in int(ceil(0.1 / step)):
			_player.call("_update_velocity", step)
		if not _check(is_equal_approx(_player.velocity.x, 5.5), "movement did not reach full speed at %d Hz" % hz):
			return false
		Input.action_release("move_right")
		for frame in int(ceil(0.08 / step)):
			_player.call("_update_velocity", step)
		if not _check(_player.velocity.is_zero_approx(), "release did not stop at %d Hz" % hz):
			return false
		_player.velocity = Vector3(5.5, 0.0, 0.0)
		Input.action_press("move_left")
		for frame in int(ceil(0.08 / step)):
			_player.call("_update_velocity", step)
		if not _check(_player.velocity.x < 0.0, "reverse input did not change direction at %d Hz" % hz):
			return false
		for frame in int(ceil(0.1 / step)):
			_player.call("_update_velocity", step)
		if not _check(is_equal_approx(_player.velocity.x, -5.5), "reverse turn too slow at %d Hz" % hz):
			return false
		Input.action_release("move_left")
		_player.velocity = Vector3.ZERO
		_player.set("_cooldown_left", 0.0)
		_player.set("_dash_left", 0.0)
		_press("dash")
		var distance := 0.0
		for frame in int(ceil(0.5 / step)):
			_player.call("_update_dash", step)
			_player.call("_update_velocity", step)
			distance += Vector3(_player.velocity.x, 0.0, _player.velocity.z).length() * step
		if not _check(absf(distance - 2.56) < 0.26, "dash drift at %d Hz: %.3f" % [hz, distance]):
			return false
		if not _check(_player.velocity.is_zero_approx(), "dash kept sliding after release"):
			return false
	return true


func _buffer_test() -> bool:
	_player.set("_cooldown_left", 0.04)
	_player.set("_dash_left", 0.0)
	_press("dash")
	_player.call("_update_dash", 0.02)
	if not _check(float(_player.get("_dash_left")) == 0.0, "dash fired before cooldown"):
		return false
	_player.call("_update_dash", 0.02)
	if not _check(float(_player.get("_dash_left")) > 0.0, "buffered dash was lost"):
		return false
	_player.set("_dash_left", 0.0)
	_player.set("_cooldown_left", 0.0)
	_player.call("_update_dash", 0.01)
	if not _check(float(_player.get("_dash_left")) == 0.0, "dash buffer executed twice"):
		return false
	_player.set("_attack_left", 0.04)
	_press("attack")
	_player.call("_update_attack", 0.02)
	if not _check(float(_player.get("_attack_left")) < 0.04, "attack fired before cooldown"):
		return false
	_player.call("_update_attack", 0.02)
	if not _check(float(_player.get("_attack_left")) > 0.0, "buffered attack was lost"):
		return false
	_player.set("_attack_left", 0.0)
	_player.call("_update_attack", 0.01)
	if not _check(float(_player.get("_attack_left")) == 0.0, "attack buffer executed twice"):
		return false
	_player.call("_end_swing")
	_player.set("_dash_left", 0.04)
	_press("attack")
	_player.call("_update_attack", 0.01)
	if not _check(float(_player.get("_attack_left")) == 0.0, "sword attacked during dash"):
		return false
	_player.call("_update_dash", 0.04)
	_player.call("_update_attack", 0.001)
	if not _check(float(_player.get("_attack_left")) > 0.0, "dash ending swallowed a buffered attack"):
		return false
	_player.call("_end_swing")
	_player.set("_attack_left", 0.0)
	Engine.time_scale = 0.08
	_press("attack")
	_player.call("_update_attack", 0.001)
	if not _check(float(_player.get("_attack_left")) > 0.0, "hit-stop swallowed an attack press"):
		return false
	_player.call("_end_swing")
	_player.set("_attack_left", 0.0)
	_press("attack")
	var expires := int(_player.get("_attack_buffer_until_msec"))
	while Time.get_ticks_msec() <= expires:
		await get_tree().process_frame
	_player.call("_update_attack", 0.001)
	Engine.time_scale = 1.0
	if not _check(float(_player.get("_attack_left")) == 0.0, "buffer expiry followed slowed game time"):
		return false
	_press("dash")
	_press("attack")
	get_tree().paused = true
	get_tree().paused = false
	if not _check(int(_player.get("_attack_buffer_until_msec")) == 0, "pause retained a buffered attack"):
		return false
	_player.call("_update_dash", 0.01)
	return _check(float(_player.get("_dash_left")) == 0.0, "pause retained a buffered dash")


func _dash_physics_test() -> bool:
	_wall(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	_player.velocity = Vector3.ZERO
	_player.set("_cooldown_left", 0.0)
	_player.set("_dash_left", 0.0)
	await _sync_physics()
	_player.set_physics_process(true)
	_press("dash")
	await get_tree().create_timer(0.5).timeout
	_player.set_physics_process(false)
	var distance := Vector2(_player.global_position.x, _player.global_position.z).length()
	if not _check(absf(distance - 2.56) < 0.26, "actual physics dash drift: %.3f" % distance):
		return false
	if not _check(Vector2(_player.velocity.x, _player.velocity.z).is_zero_approx(), "actual physics dash did not stop"):
		return false
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set("_cooldown_left", 0.0)
	_player.set("_dash_left", 0.0)
	await _sync_physics()
	return true


func _melee_test() -> bool:
	var dummy := _dummy(&"brute", Vector3(2.0, 0.0, 0.0))
	await _sync_physics()
	var before := float(dummy.call("get_current_hp"))
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.034)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "sword damaged during startup"):
		return false
	_player.set("_aim_point", Vector3(-10.0, 0.0, 0.0))
	_player.call("_face_aim")
	var facing := _player.get_node("FacingWedge") as Node3D
	if not _check((-facing.global_basis.z).dot(Vector3.RIGHT) > 0.99, "sword direction changed during swing"):
		return false
	_player.call("_update_swing", 0.016)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "sword hit before reaching target"):
		return false
	_player.call("_update_swing", 0.035)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 26.0), "sword sweep missed its target"):
		return false
	_player.call("_update_swing", 0.1)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 26.0), "one swing damaged a target twice"):
		return false
	_player.call("_end_swing")
	before = float(dummy.call("get_current_hp"))
	_player.set("_cooldown_left", 0.0)
	_player.call("_begin_swing", Vector3.RIGHT)
	_press("dash")
	_player.call("_update_dash", 0.001)
	_player.call("_update_swing", 0.2)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "cancelled startup still dealt damage"):
		return false
	_player.set("_dash_left", 0.0)
	_player.set("_cooldown_left", 0.0)
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.05)
	_press("dash")
	_player.call("_update_dash", 0.001)
	if not _check(float(_player.get("_dash_left")) == 0.0, "dash cancelled the active blade"):
		return false
	_player.call("_update_swing", 0.08)
	_player.call("_update_dash", 0.001)
	if not _check(float(_player.get("_dash_left")) > 0.0 and float(_player.get("_attack_left")) == 0.0, "dash did not cancel recovery"):
		return false
	_player.set("_dash_left", 0.0)
	_player.set("_cooldown_left", 0.0)
	var wall := _wall(Vector3(1.0, 1.0, 0.0), Vector3(0.05, 3.0, 3.0))
	await _sync_physics()
	before = float(dummy.call("get_current_hp"))
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.13)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "sword hit through a wall"):
		return false
	wall.queue_free()
	dummy.global_position = Vector3(3.65, 0.0, 0.0)
	await _sync_physics()
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.13)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "sword extended beyond target volume"):
		return false
	dummy.global_position = Vector3(3.4, 0.0, 0.0)
	await _sync_physics()
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.13)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 26.0), "sword ignored target volume at its tip"):
		return false
	before = float(dummy.call("get_current_hp"))
	dummy.global_position = Vector3(-2.0, 0.0, 0.0)
	await _sync_physics()
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.13)
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "sword damaged behind its arc"):
		return false
	dummy.queue_free()
	await _sync_physics()
	for hz: int in [30, 60, 144]:
		dummy = _dummy(&"brute", Vector3(2.0, 0.0, 0.0))
		await _sync_physics()
		before = float(dummy.call("get_current_hp"))
		_player.call("_begin_swing", Vector3.RIGHT)
		var step := 1.0 / float(hz)
		for frame in int(ceil(0.45 / step)):
			_player.call("_update_swing", step)
		if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 26.0), "sword sweep changed damage at %d Hz" % hz):
			return false
		dummy.queue_free()
		await _sync_physics()
	_player.call("_end_swing")
	_player.set("_aim_point", Vector3(10.0, 0.0, 0.0))
	return true


func _multi_target_swing_test() -> bool:
	for hz: int in [30, 60, 144]:
		var front := _dummy(&"grunt", Vector3(2.0, 0.0, 0.0))
		var edge := _dummy(&"grunt", Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(50.0)) * 2.5)
		await _sync_physics()
		_player.call("_begin_swing", Vector3.RIGHT)
		var step := 1.0 / float(hz)
		for frame in int(ceil(0.125 / step)):
			_player.call("_update_swing", step)
		if not _check(is_equal_approx(float(front.call("get_current_hp")), 20.0) and is_equal_approx(float(edge.call("get_current_hp")), 20.0), "swing missed a second or late target at %d Hz" % hz):
			return false
		var blade := _player.get_node("FacingWedge/SwingPivot") as Node3D
		if not _check(blade.visible, "last sword contact was hidden before rendering at %d Hz" % hz):
			return false
		_player.call("_update_swing", 0.001)
		if not _check(blade.visible, "another physics tick hid the last contact before rendering"):
			return false
		await get_tree().process_frame
		await get_tree().process_frame
		_player.call("_update_swing", 0.001)
		if not _check(not blade.visible, "sword remained visible throughout recovery"):
			return false
		front.queue_free()
		edge.queue_free()
		_player.call("_end_swing")
		await _sync_physics()
	return true


func _projectile_test() -> bool:
	var dummy := _dummy(&"grunt", Vector3(4.0, 0.0, 0.56))
	await _sync_physics()
	var before := float(dummy.call("get_current_hp"))
	var shot := _shot(Vector3(0.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(6.0, 0.9, 0.0))
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 16.0), "sphere sweep missed a grazing hit"):
		return false
	shot.call("sweep_to", Vector3(6.0, 0.9, 0.0))
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before - 16.0), "spent projectile damaged twice"):
		return false
	dummy.global_position.z = 0.7
	await _sync_physics()
	before = float(dummy.call("get_current_hp"))
	shot = _shot(Vector3(0.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(6.0, 0.9, 0.0))
	if not _check(not shot.is_queued_for_deletion() and is_equal_approx(float(dummy.call("get_current_hp")), before), "sphere sweep hit outside its radius"):
		return false
	shot.queue_free()
	dummy.global_position = Vector3(-4.0, 0.0, 0.0)
	dummy.velocity = Vector3.ZERO
	await _sync_physics()
	shot = _shot(Vector3(-8.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(-2.0, 0.9, 0.0))
	if not _check(dummy.velocity.x > 0.0, "bolt knockback followed world coordinates instead of flight direction"):
		return false
	before = float(dummy.call("get_current_hp"))
	dummy.global_position = Vector3(4.0, 0.0, 0.0)
	var wall := _wall(Vector3(2.0, 1.0, 0.0), Vector3(0.04, 3.0, 3.0))
	await _sync_physics()
	shot = _shot(Vector3(0.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(20.0, 0.9, 0.0))
	if not _check(shot.is_queued_for_deletion() and shot.global_position.x < 2.0, "high-speed shot passed through a thin wall"):
		return false
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "projectile damaged a target behind a wall"):
		return false
	shot = _shot(Vector3(2.0, 0.9, 0.0), false)
	shot.call("sweep_to", shot.global_position)
	if not _check(shot.is_queued_for_deletion(), "initial overlap with world was ignored"):
		return false
	wall.global_position.x = 0.5
	await _sync_physics()
	_player.call("_do_ranged", Vector3.RIGHT)
	for node in get_children():
		if node is Area3D and not node.is_queued_for_deletion():
			return _check(false, "muzzle spawned a live projectile beyond a nearby wall")
	await _sync_physics()
	if not _check(is_equal_approx(float(dummy.call("get_current_hp")), before), "muzzle spawned beyond a nearby wall"):
		return false
	wall.queue_free()
	dummy.queue_free()
	await _sync_physics()
	before = float(_player.call("get_current_hp"))
	shot = _shot(Vector3(-3.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(3.0, 0.9, 0.0))
	if not _check(not shot.is_queued_for_deletion(), "friendly shot hit the player"):
		return false
	shot.queue_free()
	shot = _shot(Vector3(-3.0, 0.9, 0.0), true)
	shot.call("sweep_to", Vector3(3.0, 0.9, 0.0))
	if not _check(is_equal_approx(float(_player.call("get_current_hp")), before - 16.0), "hostile shot missed the player"):
		return false
	await _sync_physics()
	return true


func _telegraph_geometry_test() -> bool:
	_player.global_position = Vector3(1.5, 0.0, 0.0)
	var enemy := _dummy(&"grunt", Vector3.ZERO)
	enemy.call("_begin_windup", _player)
	var boundary := enemy.get_node("WindupTelegraph/Boundary") as MeshInstance3D
	var fill := enemy.get_node("WindupTelegraph/Fill") as MeshInstance3D
	if not _check(is_equal_approx(_mesh_radius(boundary), 2.25) and not fill.visible, "melee warning did not start with its full boundary"):
		return false
	var origin := boundary.global_position
	enemy.global_position = Vector3(0.4, 0.0, 0.0)
	enemy.call("_advance_windup", 0.2, _player)
	if not _check(is_equal_approx(_mesh_radius(boundary), 2.25) and boundary.global_position.is_equal_approx(origin), "melee warning boundary drifted or grew"):
		return false
	if not _check(fill.visible and _mesh_radius(fill) > 0.0 and _mesh_radius(fill) < 2.25, "melee countdown fill did not advance inside its boundary"):
		return false
	enemy.queue_free()
	var boss := _boss(Vector3.ZERO)
	boss.call("_start_slam", _player)
	boundary = boss.get_node("SlamTelegraph/Boundary") as MeshInstance3D
	fill = boss.get_node("SlamTelegraph/Fill") as MeshInstance3D
	if not _check(is_equal_approx(_mesh_radius(boundary), 3.6) and not fill.visible, "slam warning did not start with its full boundary"):
		return false
	origin = boundary.global_position
	boss.global_position = Vector3(0.4, 0.0, 0.0)
	boss.call("_decide", 0.3, _player)
	if not _check(is_equal_approx(_mesh_radius(boundary), 3.6) and boundary.global_position.is_equal_approx(origin), "slam warning boundary drifted or grew"):
		return false
	if not _check(fill.visible and _mesh_radius(fill) > 0.0 and _mesh_radius(fill) < 3.6, "slam countdown fill did not advance inside its boundary"):
		return false
	boss.queue_free()
	await _sync_physics()
	return true


func _mesh_radius(part: MeshInstance3D) -> float:
	var vertices: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var radius := 0.0
	for vertex in vertices:
		var point := part.global_basis * vertex
		radius = maxf(radius, Vector2(point.x, point.z).length())
	return radius


func _enemy_timing_test() -> bool:
	_player.global_position = Vector3(1.5, 0.0, 0.0)
	_player.set("_invuln_left", 0.0)
	var before := float(_player.call("get_current_hp"))
	var enemy := _dummy(&"grunt", Vector3.ZERO)
	enemy.set_physics_process(true)
	await get_tree().create_timer(0.37).timeout
	if not _check(_visible_warning(enemy), "melee windup showed no danger area"):
		return false
	_player.global_position = Vector3(-1.5, 0.0, 0.0)
	await get_tree().create_timer(0.15).timeout
	if not _check(is_equal_approx(float(_player.call("get_current_hp")), before), "melee kept tracking into its blind side"):
		return false
	enemy.queue_free()
	await _sync_physics()
	_player.global_position = Vector3(1.5, 0.0, 0.0)
	_player.set("_invuln_left", 0.0)
	enemy = _dummy(&"grunt", Vector3.ZERO)
	enemy.set_physics_process(true)
	await get_tree().create_timer(0.55).timeout
	if not _check(float(_player.call("get_current_hp")) < before, "melee never hit inside its telegraph"):
		return false
	enemy.queue_free()
	await _sync_physics()
	_player.global_position = Vector3.ZERO
	enemy = _dummy(&"shooter", Vector3(-6.0, 0.0, 0.0))
	enemy.set_physics_process(true)
	await get_tree().create_timer(0.12).timeout
	if not _check(_shots().is_empty() and _visible_warning(enemy), "shooter fired without a windup"):
		return false
	await get_tree().create_timer(0.11).timeout
	_player.global_position = Vector3(0.0, 0.0, 3.0)
	await get_tree().create_timer(0.14).timeout
	var shots := _shots()
	if not _check(shots.size() == 1, "shooter did not fire once after its warning"):
		return false
	var direction: Vector3 = shots[0].call("get_direction")
	if not _check(direction.dot(Vector3.RIGHT) > 0.99, "shooter changed aim in the locked window"):
		return false
	enemy.queue_free()
	_clear_shots()
	await _sync_physics()
	_player.global_position = Vector3.ZERO
	enemy = _dummy(&"shooter", Vector3(-6.0, 0.0, 0.0))
	enemy.set_physics_process(true)
	await get_tree().create_timer(0.12).timeout
	enemy.call("take_damage", 9999.0)
	if not _check(not _visible_warning(enemy), "dead shooter left its warning behind"):
		return false
	await get_tree().create_timer(0.3).timeout
	if not _check(_shots().is_empty(), "dead shooter completed a queued attack"):
		return false
	return true


func _boss_timing_test() -> bool:
	_player.global_position = Vector3(5.0, 0.0, 0.0)
	var boss := _boss(Vector3.ZERO)
	boss.set("_volley_left", 0.0)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.2).timeout
	if not _check(_shots().is_empty() and _visible_warning(boss), "boss volley fired without a windup"):
		return false
	boss.call("take_damage", 316.0)
	_player.global_position = Vector3(8.0, 0.0, 3.0)
	await get_tree().create_timer(0.3).timeout
	var shots := _shots()
	if not _check(shots.size() == 10, "phase change altered the previewed volley count"):
		return false
	for index in shots.size():
		var angle := PI * 0.5 + 0.35 + TAU * float(index) / 10.0
		var expected := Vector3(sin(angle), 0.0, cos(angle))
		var actual: Vector3 = shots[index].call("get_direction")
		if not _check(actual.dot(expected) > 0.999, "volley direction differed from its locked preview"):
			return false
	boss.queue_free()
	_clear_shots()
	await _sync_physics()
	boss = _boss(Vector3.ZERO)
	_player.global_position = Vector3(3.75, 0.0, 0.0)
	_player.set("_invuln_left", 0.0)
	var before := float(_player.call("get_current_hp"))
	boss.call("_start_slam", _player)
	if not _check(_visible_warning(boss), "boss slam showed no danger area"):
		return false
	boss.set_physics_process(true)
	await get_tree().create_timer(0.7).timeout
	if not _check(is_equal_approx(float(_player.call("get_current_hp")), before), "boss slam hit outside the drawn radius"):
		return false
	boss.set_physics_process(false)
	boss.global_position = Vector3.ZERO
	_player.global_position = Vector3(3.5, 0.0, 0.0)
	_player.set("_invuln_left", 0.0)
	boss.call("_start_slam", _player)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.7).timeout
	if not _check(float(_player.call("get_current_hp")) < before, "boss slam missed inside its drawn radius"):
		return false
	boss.queue_free()
	_clear_shots()
	await _sync_physics()
	boss = _boss(Vector3.ZERO)
	_player.global_position = Vector3(5.0, 0.0, 0.0)
	boss.set("_volley_left", 0.0)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.1).timeout
	_player.set("_dead", true)
	await _sync_physics()
	if not _check(not _visible_warning(boss), "boss kept warning after losing its target"):
		return false
	boss.queue_free()
	_player.set("_dead", false)
	_clear_shots()
	await _sync_physics()
	return true


func _feedback_test() -> bool:
	await _wait_feedback_idle()
	var rig: CameraRig = CAMERA_SCENE.instantiate()
	add_child(rig)
	rig.set_process(false)
	rig.set_physics_process(false)
	_player.global_position = Vector3.ZERO
	_player.set("_aim_point", Vector3(10.0, 0.0, 0.0))
	_player.set("_dash_left", 0.0)
	var profiles: Dictionary = Tuning.section("fx")["impacts"]
	var swing_audio := Audio.play_count(&"sword_swing")
	var hit_audio := Audio.play_count(&"enemy_hit")
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.13)
	_player.call("_end_swing")
	if not _check(Audio.play_count(&"sword_swing") == swing_audio + 1 and Audio.play_count(&"enemy_hit") == hit_audio, "empty swing mixed in a hit sound"):
		return false
	if not _check(int(Juice.get("_stop_until_msec")) == 0 and float(rig.get("_shake_left")) == 0.0 and get_tree().get_nodes_in_group(&"hit_sparks").is_empty(), "empty swing produced impact feedback"):
		return false

	var front := _dummy(&"grunt", Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(-30.0)) * 2.0)
	var edge := _dummy(&"grunt", Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(50.0)) * 2.5)
	await _sync_physics()
	var numbers_before := get_tree().get_nodes_in_group(&"damage_numbers").size()
	_player.call("_begin_swing", Vector3.RIGHT)
	_player.call("_update_swing", 0.06)
	if not _check(is_equal_approx(float(front.call("get_current_hp")), 20.0), "first sword contact produced no damage"):
		return false
	var stop_until := int(Juice.get("_stop_until_msec"))
	var budget_until := int(Juice.get("_impact_until_msec"))
	if not _check(stop_until > 0 and float(rig.get("_shake_strength")) == float(profiles["melee"]["shake"]), "sword contact produced no melee impact"):
		return false
	await _wait_wall_msec(5)
	_player.call("_update_swing", 0.07)
	_player.call("_end_swing")
	if not _check(is_equal_approx(float(edge.call("get_current_hp")), 20.0) and Audio.play_count(&"enemy_hit") > hit_audio, "late sword contact lost damage or hit audio"):
		return false
	if not _check(int(Juice.get("_stop_until_msec")) == stop_until and int(Juice.get("_impact_until_msec")) == budget_until, "multi-target sword refreshed the global impact budget"):
		return false
	var sparks := get_tree().get_nodes_in_group(&"hit_sparks")
	if not _check(sparks.size() == 2 and get_tree().get_nodes_in_group(&"damage_numbers").size() == numbers_before + 2, "merged impact swallowed a target's local feedback"):
		return false
	var melee_size := (sparks[0] as MeshInstance3D).mesh.get_aabb().size.length()
	var melee_material := (sparks[0] as MeshInstance3D).material_override as StandardMaterial3D
	if not _check(melee_material.albedo_color.is_equal_approx(Juice.SPARK_MELEE_COLOR), "melee contact used the wrong spark color"):
		return false
	front.queue_free()
	edge.queue_free()
	await _wait_feedback_idle()
	rig.call("_update_shake", 1.0)
	if not await _timed_multi_target_feedback_test(rig):
		return false
	await _wait_feedback_idle()
	rig.call("_update_shake", 1.0)

	var target := _dummy(&"grunt", Vector3(4.0, 0.0, 0.0))
	await _sync_physics()
	var bolt_audio := Audio.play_count(&"bolt_hit")
	hit_audio = Audio.play_count(&"enemy_hit")
	var shot := _shot(Vector3(0.0, 0.9, 0.0), false)
	shot.call("sweep_to", Vector3(6.0, 0.9, 0.0))
	if not _check(is_equal_approx(float(target.call("get_current_hp")), 30.0) and Audio.play_count(&"bolt_hit") == bolt_audio + 1 and Audio.play_count(&"enemy_hit") == hit_audio, "ranged impact did not use its own hit sound"):
		return false
	if not _check(int(Juice.get("_impact_priority")) == int(profiles["ranged"]["priority"]) and float(rig.get("_shake_strength")) == float(profiles["ranged"]["shake"]), "ranged impact used melee feedback strength"):
		return false
	sparks = get_tree().get_nodes_in_group(&"hit_sparks")
	if not _check(sparks.size() == 1, "ranged contact produced no spark"):
		return false
	var ranged_spark := sparks[0] as MeshInstance3D
	var ranged_material := ranged_spark.material_override as StandardMaterial3D
	if not _check(ranged_spark.mesh.get_aabb().size.length() < melee_size and ranged_material.albedo_color.is_equal_approx(Juice.SPARK_RANGED_COLOR), "ranged spark was not smaller and distinct"):
		return false
	if not _check(ranged_spark.global_position.is_equal_approx(Vector3(3.55, 1.02, 0.0)), "spark was not placed on the contacted side of the target"):
		return false

	target.call("take_damage", 9999.0, Vector3.RIGHT, 6.0, true)
	stop_until = int(Juice.get("_stop_until_msec"))
	budget_until = int(Juice.get("_impact_until_msec"))
	if not _check(int(Juice.get("_impact_priority")) == int(profiles["kill"]["priority"]) and float(rig.get("_shake_strength")) == float(profiles["kill"]["shake"]), "kill did not upgrade a light hit"):
		return false
	await _wait_wall_msec(5)
	target = _dummy(&"grunt", Vector3(4.0, 0.0, 2.0))
	target.call("take_damage", 9999.0)
	if not _check(int(Juice.get("_stop_until_msec")) == stop_until and int(Juice.get("_impact_until_msec")) == budget_until, "nearby kills repeatedly extended hit-stop"):
		return false
	_player.set("_invuln_left", 0.0)
	var hp_before := float(_player.call("get_current_hp"))
	_player.call("take_damage", 7.0, Vector3.LEFT)
	if not _check(float(_player.call("get_current_hp")) == hp_before - 7.0 and int(Juice.get("_impact_priority")) == int(profiles["hurt"]["priority"]) and float(rig.get("_shake_strength")) == float(profiles["hurt"]["shake"]), "player damage lost its stronger feedback"):
		return false
	stop_until = int(Juice.get("_stop_until_msec"))
	budget_until = int(Juice.get("_impact_until_msec"))
	await _wait_wall_msec(5)
	Juice.impact(&"ranged")
	if not _check(int(Juice.get("_stop_until_msec")) == stop_until and int(Juice.get("_impact_until_msec")) == budget_until and float(rig.get("_shake_strength")) == float(profiles["hurt"]["shake"]), "light hit refreshed or weakened player-hurt feedback"):
		return false
	var boss := _boss(Vector3(8.0, 0.0, 0.0))
	boss.call("take_damage", 999999.0)
	if not _check(int(Juice.get("_impact_priority")) == int(profiles["boss_kill"]["priority"]) and float(rig.get("_shake_strength")) == float(profiles["boss_kill"]["shake"]), "boss kill lost its strongest feedback"):
		return false
	await _wait_feedback_idle()
	if not _check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop did not recover on the wall clock"):
		return false
	if not _camera_feedback_test(rig):
		return false
	await _wait_feedback_idle()
	Juice.impact(&"melee")
	get_tree().paused = true
	await _wait_feedback_idle()
	if not _check(is_equal_approx(Engine.time_scale, 1.0), "pause prevented hit-stop recovery"):
		return false
	get_tree().paused = false
	Engine.time_scale = 0.08
	Juice.hit_spark(Vector3.UP)
	await _wait_wall_msec(120)
	if not _check(get_tree().get_nodes_in_group(&"hit_sparks").is_empty(), "hit sparks lingered during slow motion"):
		return false
	Engine.time_scale = 1.0
	rig.queue_free()
	await _sync_physics()
	return true


func _timed_multi_target_feedback_test(rig: CameraRig) -> bool:
	var front := _dummy(&"grunt", Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(-55.0)) * 2.5)
	var edge := _dummy(&"grunt", Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(55.0)) * 2.7)
	front.call("take_damage", 26.0)
	await _wait_feedback_idle()
	rig.call("_update_shake", 1.0)
	await _sync_physics()
	_player.call("_begin_swing", Vector3.RIGHT)
	var previous := Time.get_ticks_usec()
	var deadline := previous + 1000000
	var kill_at: int = 0
	var budget_until: int = 0
	var edge_hit_at: int = 0
	while is_equal_approx(float(edge.call("get_current_hp")), 46.0) and Time.get_ticks_usec() < deadline:
		var time_scale := Engine.time_scale
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var numbers_before := get_tree().get_nodes_in_group(&"damage_numbers").size()
		var sparks_before := get_tree().get_nodes_in_group(&"hit_sparks").size()
		var hit_audio := Audio.play_count(&"enemy_hit")
		_player.call("_update_swing", float(now - previous) * time_scale / 1000000.0)
		previous = now
		if kill_at == 0 and bool(front.call("is_dead")):
			kill_at = Time.get_ticks_usec()
			budget_until = int(Juice.get("_impact_until_msec"))
		if not is_equal_approx(float(edge.call("get_current_hp")), 46.0):
			edge_hit_at = Time.get_ticks_usec()
			if not _check(get_tree().get_nodes_in_group(&"damage_numbers").size() == numbers_before + 1 and get_tree().get_nodes_in_group(&"hit_sparks").size() == sparks_before + 1 and Audio.play_count(&"enemy_hit") == hit_audio + 1, "timed late contact lost its local feedback"):
				return false
	if not _check(kill_at > 0 and edge_hit_at - kill_at >= 100000, "timed sword contacts did not cross the old 100 ms budget"):
		return false
	if not _check(is_equal_approx(float(edge.call("get_current_hp")), 20.0), "timed sword missed its late target"):
		return false
	if not _check(int(Juice.get("_impact_until_msec")) == budget_until and int(Juice.get("_stop_until_msec")) == 0 and is_equal_approx(Engine.time_scale, 1.0), "timed late contact restarted global impact after a kill"):
		return false
	var kill_profile: Dictionary = Tuning.section("fx")["impacts"]["kill"]
	if not _check(int(Juice.get("_impact_priority")) == int(kill_profile["priority"]) and is_equal_approx(float(rig.get("_shake_strength")), float(kill_profile["shake"])), "timed late contact replaced kill feedback"):
		return false
	_player.call("_end_swing")
	if is_instance_valid(front):
		front.queue_free()
	edge.queue_free()
	await _wait_wall_msec(int(ceil(float(Tuning.value("fx", "spark_sec")) * 1000.0)))
	await _sync_physics()
	return true


func _camera_feedback_test(rig: CameraRig) -> bool:
	rig.call("_update_shake", 1.0)
	rig.add_shake(0.4, 0.25)
	rig.add_shake(0.01, 1.0)
	if not _check(is_equal_approx(float(rig.get("_shake_left")), 0.25), "weak shake extended a heavy shake"):
		return false
	Engine.time_scale = 0.08
	rig.call("_process", 0.008)
	if not _check(is_equal_approx(float(rig.get("_shake_left")), 0.15), "hit-stop stretched the shake envelope"):
		return false
	Engine.time_scale = 1.0
	rig.call("_update_shake", 0.12)
	rig.add_shake(0.18, 1.0)
	if not _check(is_equal_approx(float(rig.get("_shake_left")), 0.03) and is_equal_approx(float(rig.get("_shake_strength")), 0.4) and is_equal_approx(float(rig.get("_shake_duration")), 0.25), "weak event restarted a heavy shake's decaying tail"):
		return false
	rig.add_shake(10.0, 0.2)
	if not _check(is_equal_approx(float(rig.get("_shake_strength")), float(Tuning.value("fx", "shake_max"))), "shake exceeded its configured amplitude cap"):
		return false
	rig.call("_update_shake", 0.3)
	var camera := rig.get_node("Camera3D") as Camera3D
	if not _check(float(rig.get("_shake_left")) == 0.0 and float(rig.get("_shake_duration")) == 0.0 and camera.position.is_equal_approx(rig.get("_base_camera_position")), "shake did not clear and return the camera to its origin"):
		return false
	rig.add_shake(0.05, 0.07)
	if not _check(is_equal_approx(float(rig.get("_shake_duration")), 0.07), "new shake inherited an old longer duration"):
		return false
	rig.snap_to_target()
	return _check(float(rig.get("_shake_left")) == 0.0 and float(rig.get("_shake_strength")) == 0.0, "floor snap retained shake state")


func _wait_feedback_idle() -> void:
	var deadline := maxi(int(Juice.get("_impact_until_msec")), int(Juice.get("_stop_until_msec")))
	while Time.get_ticks_msec() <= deadline:
		await get_tree().process_frame
	await get_tree().process_frame


func _wait_wall_msec(duration: int) -> void:
	var deadline := Time.get_ticks_msec() + duration
	while Time.get_ticks_msec() <= deadline:
		await get_tree().process_frame


func _boss(position: Vector3) -> CharacterBody3D:
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	boss.call("configure", 1, position)
	add_child(boss)
	boss.set_physics_process(false)
	return boss


func _shots() -> Array[Area3D]:
	var shots: Array[Area3D] = []
	for node in get_children():
		if node is Area3D and not node.is_queued_for_deletion():
			shots.append(node)
	return shots


func _clear_shots() -> void:
	for shot in _shots():
		shot.queue_free()


func _visible_warning(enemy: Node) -> bool:
	for node in enemy.find_children("*Telegraph*", "Node3D", true, false):
		var warning := node as Node3D
		if warning.is_visible_in_tree():
			return true
	return false


func _dummy(kind: StringName, position: Vector3) -> CharacterBody3D:
	var dummy: CharacterBody3D = ENEMY_SCENE.instantiate()
	dummy.call("configure", kind, 1, position)
	add_child(dummy)
	dummy.set_physics_process(false)
	return dummy


func _shot(position: Vector3, hostile: bool) -> Area3D:
	var shot: Area3D = PROJECTILE_SCENE.instantiate()
	shot.call("configure", Vector3.RIGHT, 26.0, 16.0, hostile, 1.2)
	add_child(shot)
	shot.global_position = position
	shot.set_physics_process(false)
	return shot


func _wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = position
	return wall


func _sync_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		print("FEEL FAIL: ", message)
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().quit(1)
	return condition
