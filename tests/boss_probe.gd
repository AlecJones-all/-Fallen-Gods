extends Node

## Headless M3 probe: elite affixes, boss spawn/phases/HP bar, boss room clear
## and the final-floor victory route. Run with:
##   godot --headless --path . res://tests/boss_probe.tscn

const MAIN_SCENE := "res://scenes/main.tscn"
const VICTORY_SCENE := "res://scenes/ui/victory.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const DUNGEON_GROUP := &"dungeon"
const PLAYER_GROUP := &"player"
const BOSS_GROUP := &"boss"
const FLOOR_STEP := Vector3(0.0, 0.05, 0.0)
const BOSS_FLOOR := 3
const EXPECTED_FINAL_FLOOR := 9
const BOSS_MIN_HP := 500.0

var _tree: SceneTree
var _dungeon: Node
var _player: Node3D
var _boss_bar: Control


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

	var hud := _tree.current_scene.get_node_or_null(^"HUD")
	if hud != null:
		_boss_bar = hud.find_child("BossBar", true, false) as Control
	if _boss_bar == null:
		_fail("HUD BossBar missing")
		return

	if not _audio_manifest_test():
		return
	if not await _affix_test():
		return
	if not await _boss_floor_test(BOSS_FLOOR):
		return
	if not await _victory_test():
		return

	if not is_equal_approx(Engine.time_scale, 1.0):
		_fail("hit-stop left engine time scale at %.3f" % Engine.time_scale)
		return

	print("BOSS OK")
	_tree.quit(0)


func _audio_manifest_test() -> bool:
	if AudioServer.get_bus_index(&"SFX") == -1:
		return _fail_bool("SFX audio bus missing")
	var missing: PackedStringArray = Audio.verify_events()
	if not missing.is_empty():
		return _fail_bool("audio files failed to load: %s" % ", ".join(missing))
	return true


func _affix_test() -> bool:
	var packed := load(ENEMY_SCENE) as PackedScene
	if packed == null:
		return _fail_bool("enemy scene missing")
	var dummy := packed.instantiate() as Node3D
	if dummy == null:
		return _fail_bool("enemy scene root is not 3D")
	if not dummy.has_method(&"apply_affix"):
		return _fail_bool("enemy cannot take an affix")

	dummy.call(&"configure", &"grunt", 1, _player.global_position + Vector3(2.0, 0.0, 0.0))
	dummy.call(&"apply_affix", &"shielded")
	_tree.current_scene.add_child(dummy)
	# Freeze the dummy so its AI cannot move or hit the player mid-check.
	dummy.set_physics_process(false)
	await _tree.process_frame
	await _tree.process_frame

	if String(dummy.call(&"get_affix")) != "shielded":
		return _fail_bool("enemy did not report the shielded affix")
	if float(dummy.call(&"get_max_hp")) < 60.0:
		return _fail_bool("shielded hp multiplier not applied")

	var before := float(dummy.call(&"get_current_hp"))
	dummy.call(&"take_damage", 10.0)
	var drop := before - float(dummy.call(&"get_current_hp"))
	if absf(drop - 5.5) > 0.6:
		return _fail_bool("shielded did not reduce damage (%.2f)" % drop)

	dummy.call(&"take_damage", 9999.0)
	await _tree.create_timer(0.4).timeout
	return true


func _boss_floor_test(boss_floor: int) -> bool:
	_dungeon.call(&"build_floor", boss_floor)
	await _tree.create_timer(0.3).timeout

	if not bool(_dungeon.call(&"is_boss_floor", boss_floor)):
		return _fail_bool("floor %d is not flagged as a boss floor" % boss_floor)
	if bool(_dungeon.call(&"is_boss_floor", 1)):
		return _fail_bool("floor 1 was flagged as a boss floor")

	var exit_index := int(_dungeon.call(&"get_exit_room_index"))
	var center: Vector3 = _dungeon.call(&"get_room_center", exit_index)
	# Stand inside the room but off the portal disc.
	_player.global_position = center + Vector3(3.0, 0.05, 0.0)
	await _tree.create_timer(0.6).timeout

	var boss := _tree.get_first_node_in_group(BOSS_GROUP) as Node3D
	if boss == null:
		return _fail_bool("boss did not spawn on floor %d" % boss_floor)
	if not boss.has_method(&"get_phase"):
		return _fail_bool("boss does not report a phase")

	var max_hp := float(boss.call(&"get_max_hp"))
	if max_hp < BOSS_MIN_HP:
		return _fail_bool("boss hp looks unscaled (%.1f)" % max_hp)
	if String(boss.call(&"get_display_name")).is_empty():
		return _fail_bool("boss has no display name")
	if Audio.play_count(&"boss_roar") <= 0:
		return _fail_bool("boss spawn played no roar")

	await _tree.create_timer(0.4).timeout
	if not _boss_bar.visible:
		return _fail_bool("boss health bar is not visible")
	if String(_boss_bar.get(&"label_text")) != String(boss.call(&"get_display_name")):
		return _fail_bool("boss health bar shows the wrong name")

	var phase_audio_before := Audio.play_count(&"boss_phase")
	boss.call(&"take_damage", max_hp * 0.35 + 1.0)
	if int(boss.call(&"get_phase")) != 2:
		return _fail_bool("phase 1 -> 2 transition missed")
	boss.call(&"take_damage", max_hp * 0.32 + 1.0)
	if int(boss.call(&"get_phase")) != 3:
		return _fail_bool("phase 2 -> 3 transition missed")
	if Audio.play_count(&"boss_phase") <= phase_audio_before:
		return _fail_bool("phase change played no audio")
	if not _boss_bar.visible:
		return _fail_bool("boss health bar vanished mid-fight")

	var die_audio_before := Audio.play_count(&"boss_die")
	boss.call(&"take_damage", max_hp * 2.0)
	await _tree.create_timer(0.7).timeout
	if Audio.play_count(&"boss_die") <= die_audio_before:
		return _fail_bool("boss death played no audio")
	if not bool(_dungeon.call(&"is_room_cleared", exit_index)):
		return _fail_bool("boss death did not clear the exit room")

	await _tree.create_timer(0.4).timeout
	if _boss_bar.visible:
		return _fail_bool("boss health bar still visible after the kill")
	if _tree.get_first_node_in_group(BOSS_GROUP) != null:
		return _fail_bool("boss node survived its death")

	var exit_point: Vector3 = _dungeon.call(&"get_exit_position")
	_player.global_position = exit_point + Vector3(2.5, 0.05, 0.0)
	await _tree.create_timer(0.25).timeout
	_player.global_position = exit_point + FLOOR_STEP
	await _tree.create_timer(1.6).timeout

	if int(_dungeon.call(&"get_floor_number")) != boss_floor + 1:
		return _fail_bool("portal did not advance past the boss floor")
	return true


func _victory_test() -> bool:
	var final_floor := int(_dungeon.call(&"get_final_boss_floor"))
	if final_floor != EXPECTED_FINAL_FLOOR:
		return _fail_bool("final boss floor is %d, expected %d" % [final_floor, EXPECTED_FINAL_FLOOR])

	_dungeon.call(&"build_floor", final_floor)
	await _tree.create_timer(0.3).timeout
	if not bool(_dungeon.call(&"is_final_boss_floor", final_floor)):
		return _fail_bool("floor %d is not flagged as the final boss floor" % final_floor)

	var exit_index := int(_dungeon.call(&"get_exit_room_index"))
	var center: Vector3 = _dungeon.call(&"get_room_center", exit_index)
	_player.global_position = center + Vector3(3.0, 0.05, 0.0)
	await _tree.create_timer(0.6).timeout

	var boss := _tree.get_first_node_in_group(BOSS_GROUP)
	if boss == null:
		return _fail_bool("final boss did not spawn")
	if not boss.has_method(&"take_damage"):
		return _fail_bool("final boss cannot take damage")
	boss.call(&"take_damage", 999999.0)
	await _tree.create_timer(0.7).timeout

	var exit_point: Vector3 = _dungeon.call(&"get_exit_position")
	_player.global_position = exit_point + FLOOR_STEP
	await _tree.create_timer(2.2).timeout

	var path := "<null>"
	if _tree.current_scene != null:
		path = _tree.current_scene.scene_file_path
	if path != VICTORY_SCENE:
		return _fail_bool("victory scene not reached (%s)" % path)

	var payload: Dictionary = Router.last_payload
	if int(payload.get("floor", 0)) != final_floor:
		return _fail_bool("victory payload missing the final floor")
	if Audio.play_count(&"victory") <= 0:
		return _fail_bool("victory screen played no stinger")
	# Let the one-shot stinger finish before the engine shuts down.
	await _tree.create_timer(1.2).timeout
	return true


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	print("BOSS FAIL: ", message)
	if _tree != null:
		_tree.quit(1)
	else:
		get_tree().quit(1)
