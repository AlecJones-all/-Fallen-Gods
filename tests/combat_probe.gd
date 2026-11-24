extends Node

## Headless combat probe: boots a run, clears a room, exercises both weapons,
## invulnerability, healing and the floor portal. Run with:
##   godot --headless --path . res://tests/combat_probe.tscn

const MAIN_SCENE := "res://scenes/main.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const DUNGEON_GROUP := &"dungeon"
const PLAYER_GROUP := &"player"
const ENEMY_GROUP := &"enemies"
const DAMAGE_NUMBER_GROUP := &"damage_numbers"
const FX_TRANSIENT_GROUP := &"fx_transient"
const FLOOR_STEP := Vector3(0.0, 0.05, 0.0)

var _tree: SceneTree
var _dungeon: Node
var _player: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_tree = get_tree()
	reparent(_tree.root)
	_tree.current_scene = null

	var router: Node = _tree.root.get_node_or_null(^"Router")
	if router == null or not router.has_method(&"goto"):
		_fail("Router autoload missing")
		return
	router.call(&"goto", MAIN_SCENE)
	await _tree.create_timer(1.0).timeout

	if _tree.current_scene == null or _tree.current_scene.scene_file_path != MAIN_SCENE:
		_fail("main scene not current")
		return

	_dungeon = _tree.get_first_node_in_group(DUNGEON_GROUP)
	_player = _tree.get_first_node_in_group(PLAYER_GROUP) as Node3D
	if _dungeon == null:
		_fail("dungeon missing")
		return
	if _player == null:
		_fail("player missing")
		return

	if int(_dungeon.call(&"get_floor_number")) != 1:
		_fail("dungeon did not start on floor 1")
		return
	if not _audio_manifest_test():
		return
	var ok: bool = await _room_test()
	if ok:
		ok = await _weapon_test()
	if ok:
		ok = await _invuln_test()
	if ok:
		ok = await _exit_test()
	if not ok:
		return

	if not is_equal_approx(Engine.time_scale, 1.0):
		_fail("hit-stop left engine time scale at %.3f" % Engine.time_scale)
		return

	print("COMBAT OK")
	_tree.quit(0)


func _audio_manifest_test() -> bool:
	if AudioServer.get_bus_index(&"SFX") == -1:
		return _fail_bool("SFX audio bus missing")
	var missing: PackedStringArray = Audio.verify_events()
	if not missing.is_empty():
		return _fail_bool("audio files failed to load: %s" % ", ".join(missing))
	return true


func _room_test() -> bool:
	var start_index := int(_dungeon.call(&"get_start_room_index"))
	var exit_index := int(_dungeon.call(&"get_exit_room_index"))
	if start_index == exit_index:
		return _fail_bool("start and exit share a room")

	var index := _pick_room(start_index, exit_index)
	if index < 0:
		return _fail_bool("no combat room available")

	_enter_room(index)
	await _tree.create_timer(0.4).timeout
	var enemies := _live_enemies()
	if enemies.is_empty():
		return _fail_bool("room %d spawned no enemies" % index)

	# Leave the player idle for a moment: melee chasers and shooters must engage.
	var hp_before := float(_player.call(&"get_current_hp"))
	await _tree.create_timer(2.2).timeout
	if float(_player.call(&"get_current_hp")) >= hp_before:
		return _fail_bool("enemies never damaged the idle player")

	_kill(_live_enemies())
	await _tree.create_timer(0.6).timeout
	if not bool(_dungeon.call(&"is_room_cleared", index)):
		return _fail_bool("room %d was not cleared" % index)
	return true


func _weapon_test() -> bool:
	var packed := load(ENEMY_SCENE) as PackedScene
	if packed == null:
		return _fail_bool("enemy scene missing")
	var dummy := packed.instantiate() as Node3D
	if dummy == null:
		return _fail_bool("enemy scene root is not 3D")
	if not dummy.has_method(&"configure"):
		return _fail_bool("enemy scene cannot be configured")

	var origin := _player.global_position
	dummy.call(&"configure", &"grunt", 1, origin + Vector3(2.0, 0.0, 0.0))
	if _tree.current_scene == null:
		return _fail_bool("no current scene for the dummy")
	_tree.current_scene.add_child(dummy)
	# Freeze the dummy so its AI cannot body the player during the hp checks.
	dummy.set_physics_process(false)
	await _tree.process_frame
	await _tree.process_frame

	var hp_before := float(dummy.call(&"get_current_hp"))
	var hit_audio_before := Audio.play_count(&"enemy_hit")
	_player.call(&"_do_melee", Vector3(1.0, 0.0, 0.0))
	await _tree.process_frame
	await _tree.process_frame
	if not is_instance_valid(dummy):
		return _fail_bool("melee destroyed the dummy before the hp check")
	if float(dummy.call(&"get_current_hp")) >= hp_before:
		return _fail_bool("melee attack did not damage the dummy")
	if _tree.get_nodes_in_group(DAMAGE_NUMBER_GROUP).is_empty():
		return _fail_bool("melee hit spawned no damage number")
	if Audio.play_count(&"enemy_hit") <= hit_audio_before:
		return _fail_bool("melee hit played no audio")

	dummy.global_position = origin + Vector3(4.0, 0.0, 0.0)
	await _tree.process_frame
	_player.call(&"select_weapon", 1)
	await _tree.process_frame
	if int(_player.call(&"get_weapon_index")) != 1:
		return _fail_bool("select_weapon(1) did not switch to the crossbow")

	var ranged_before := float(dummy.call(&"get_current_hp"))
	var shot_audio_before := Audio.play_count(&"crossbow_fire")
	_player.call(&"_do_ranged", Vector3(1.0, 0.0, 0.0))
	await _tree.create_timer(0.5).timeout
	if Audio.play_count(&"crossbow_fire") <= shot_audio_before:
		return _fail_bool("crossbow shot played no audio")
	if is_instance_valid(dummy):
		var ranged_after := float(dummy.call(&"get_current_hp"))
		if ranged_after >= ranged_before:
			return _fail_bool("ranged attack did not damage the dummy")

	var die_audio_before := Audio.play_count(&"enemy_die")
	_kill([dummy])
	if Audio.play_count(&"enemy_die") <= die_audio_before:
		return _fail_bool("enemy death played no audio")
	if _tree.get_nodes_in_group(FX_TRANSIENT_GROUP).is_empty():
		return _fail_bool("enemy death spawned no fx shards")
	await _tree.create_timer(0.4).timeout
	return true


func _invuln_test() -> bool:
	var before := float(_player.call(&"get_current_hp"))
	_player.call(&"take_damage", 7.0)
	var after_first := float(_player.call(&"get_current_hp"))
	_player.call(&"take_damage", 7.0)
	var after_second := float(_player.call(&"get_current_hp"))
	if after_first >= before:
		return _fail_bool("first hit did not damage the player")
	if not is_equal_approx(after_first, after_second):
		return _fail_bool("invulnerability did not block the second hit")

	await _tree.create_timer(0.7).timeout
	var before_heal := float(_player.call(&"get_current_hp"))
	_player.call(&"heal", 5.0)
	if float(_player.call(&"get_current_hp")) <= before_heal:
		return _fail_bool("heal did not restore hp")
	return true


func _exit_test() -> bool:
	var exit_index := int(_dungeon.call(&"get_exit_room_index"))
	_enter_room(exit_index)
	await _tree.create_timer(0.5).timeout

	var exit_point: Vector3 = _dungeon.call(&"get_exit_position")
	# Step off the disc first: clearing the room while standing on it starts the
	# descent timer and rebuilds the floor before the cleared check below.
	_player.global_position = exit_point + Vector3(2.5, 0.05, 0.0)
	await _tree.create_timer(0.05).timeout
	_kill(_live_enemies())
	await _tree.create_timer(0.8).timeout
	if not bool(_dungeon.call(&"is_room_cleared", exit_index)):
		return _fail_bool("exit room %d was not cleared" % exit_index)

	_player.global_position = exit_point + Vector3(2.5, 0.05, 0.0)
	await _tree.create_timer(0.25).timeout
	_player.global_position = exit_point + FLOOR_STEP
	await _tree.create_timer(1.6).timeout

	if int(_dungeon.call(&"get_floor_number")) != 2:
		return _fail_bool("portal did not advance to floor 2")
	var spawn: Vector3 = _dungeon.call(&"get_spawn_position")
	if _player.global_position.distance_to(spawn) > 1.5:
		return _fail_bool("player was not placed at the floor 2 spawn")
	return true


func _pick_room(start_index: int, exit_index: int) -> int:
	var count := int(_dungeon.call(&"get_room_count"))
	for index in count:
		if index != start_index and index != exit_index:
			return index
	return -1


func _enter_room(index: int) -> void:
	var center: Vector3 = _dungeon.call(&"get_room_center", index)
	if _player != null:
		_player.global_position = center + FLOOR_STEP


func _live_enemies() -> Array[Node]:
	var alive: Array[Node] = []
	for node in _tree.get_nodes_in_group(ENEMY_GROUP):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive.append(node)
	return alive


func _kill(enemies: Array) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method(&"take_damage"):
			enemy.call(&"take_damage", 9999.0)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	print("COMBAT FAIL: ", message)
	if _tree != null:
		_tree.quit(1)
	else:
		get_tree().quit(1)
