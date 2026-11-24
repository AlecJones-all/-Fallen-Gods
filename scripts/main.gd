extends Node3D

const GAMEPLAY_FLOOR: int = 1

@onready var _player: CharacterBody3D = $Player
@onready var _room := $GrayboxRoom

var _elapsed_sec: float = 0.0
var _alive: bool = true


func _ready() -> void:
	_player.global_position = _room.get_spawn_position() + Vector3(0.0, 0.05, 0.0)
	_player.connect(&"died", _on_player_died)


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
		"floor": GAMEPLAY_FLOOR,
	})
