extends Node3D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

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
	for voice: AudioStreamPlayer3D in get_tree().get_nodes_in_group(&"audio_voices_3d"):
		voice.stop()
		voice.stream = null
		voice.queue_free()
	for voice: AudioStreamPlayer in Audio.get_children():
		voice.stop()
		voice.stream = null
	await get_tree().process_frame
	await get_tree().process_frame
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
