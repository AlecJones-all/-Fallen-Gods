extends Node3D

const HEAL_ON_DESCEND_FALLBACK: float = 0.15
const VICTORY_SCENE := "res://scenes/ui/victory.tscn"
const FINAL_BOSS_FLOOR_FALLBACK: int = 9

@onready var _player: CharacterBody3D = $Player
@onready var _dungeon: Node = $Dungeon
@onready var _camera: Node = get_node_or_null(^"CameraRig")

var _elapsed_sec: float = 0.0
var _alive: bool = true


func _ready() -> void:
	_dungeon.call(&"build_floor", 1)
	_player.global_position = _spawn_point()
	_player.connect(&"died", _on_player_died)
	if _dungeon.has_signal(&"floor_completed"):
		_dungeon.connect(&"floor_completed", _on_floor_completed)


func _process(delta: float) -> void:
	if _alive:
		_elapsed_sec += delta


func _on_player_died() -> void:
	if not _alive:
		return
	_alive = false
	set_process(false)
	Router.goto("res://scenes/ui/game_over.tscn", {
		"elapsed_sec": _elapsed_sec,
		"floor": _current_floor(),
	})


## The portal is freed inside its own timer callback, so touch the dungeon on the next idle.
func _on_floor_completed(next_floor: int) -> void:
	if next_floor > _final_boss_floor():
		_win()
		return
	_advance_floor.call_deferred(next_floor)


func _win() -> void:
	if not _alive:
		return
	_alive = false
	set_process(false)
	Router.goto(VICTORY_SCENE, {
		"elapsed_sec": _elapsed_sec,
		"floor": _current_floor(),
	})


func _final_boss_floor() -> int:
	return int(Tuning.value("dungeon", "final_boss_floor", FINAL_BOSS_FLOOR_FALLBACK))


func _advance_floor(next_floor: int) -> void:
	if not _alive or not is_instance_valid(_player) or not is_instance_valid(_dungeon):
		return
	var ratio := float(Tuning.value("dungeon", "heal_on_descend", HEAL_ON_DESCEND_FALLBACK))
	var max_hp := float(_player.call(&"get_max_hp"))
	_player.call(&"heal", max_hp * ratio)
	_dungeon.call(&"build_floor", next_floor)
	_player.global_position = _spawn_point()
	_snap_camera()


func _spawn_point() -> Vector3:
	var spawn: Vector3 = _dungeon.call(&"get_spawn_position")
	return spawn + Vector3(0.0, 0.05, 0.0)


func _snap_camera() -> void:
	if _camera != null and _camera.has_method(&"snap_to_target"):
		_camera.call(&"snap_to_target")


func _current_floor() -> int:
	if not is_instance_valid(_dungeon):
		return 1
	if _dungeon.has_method(&"get_floor_number"):
		return int(_dungeon.call(&"get_floor_number"))
	# Some dungeon builds expose the floor as a property instead.
	var value: Variant = _dungeon.get(&"floor_number")
	if value is float or value is int:
		return int(value)
	return 1
