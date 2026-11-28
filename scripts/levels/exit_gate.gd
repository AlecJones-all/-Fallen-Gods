extends Area3D
## 关卡终点：玩家走进范围就回关卡页，光标停在对应关卡卡上。
## 不用输入、不依赖 HUD，撞上即触发一次。

@export var target_scene := "res://scenes/main.tscn"
@export var level_index := 3
@export var scene_title := "白洗礼拜堂"

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _fired:
		return
	if not body.is_in_group(&"player") and body.name != "Player":
		return
	_fired = true
	var payload := {"open_levels": true, "level": level_index, "name": scene_title}
	var router := get_node_or_null("/root/Router")
	if router != null and router.has_method(&"goto"):
		router.call(&"goto", target_scene, payload)
	else:
		get_tree().change_scene_to_file(target_scene)
