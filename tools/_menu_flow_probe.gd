extends Node

# P4 全链路验收：菜单→税卡→出口→地牢；死亡重开按 payload 回税卡/地牢。
# 用法：godot --headless --path . res://tools/_menu_flow_probe.tscn
const GATE := "res://scenes/levels/tithe_gate_graybox.tscn"
const MAIN := "res://scenes/main.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const GO := "res://scenes/ui/game_over.tscn"

var _ok := true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null
	var menu := (load(MENU) as PackedScene).instantiate()
	tree.root.add_child(menu)
	tree.current_scene = menu
	await tree.process_frame
	await tree.process_frame

	var start := menu.find_child("Start", true, false) as Button
	if start == null:
		_fail("start button missing")
		return
	start.emit_signal("pressed")
	await tree.create_timer(1.5).timeout

	var router: Node = tree.root.get_node_or_null(^"Router")
	var path := _path(tree)
	var payload: Dictionary = router.get(&"last_payload")
	print("MENU_START current=", path, " payload=", payload)
	if path != GATE:
		_ok = false
	if String(payload.get("restart_scene", "")) != GATE:
		_ok = false

	var player := tree.get_first_node_in_group(&"player") as Node3D
	if player == null:
		_fail("player missing")
		return
	player.position = Vector3(46.0, 0.05, 0.0)
	await tree.create_timer(5.0).timeout

	path = _path(tree)
	payload = router.get(&"last_payload")
	print("GATE_EXIT current=", path, " payload=", payload)
	if path != MAIN:
		_ok = false
	if not payload.is_empty():
		_ok = false

	router.call(&"goto", GO, { "restart_scene": GATE, "elapsed_sec": 1, "floor": 1 })
	await tree.create_timer(1.2).timeout
	var go := tree.current_scene
	if go == null or go.scene_file_path != GO:
		_fail("game_over not current")
		return
	var restart := go.find_child("Restart", true, false) as Button
	if restart == null:
		_fail("restart button missing")
		return
	restart.emit_signal("pressed")
	await tree.create_timer(1.5).timeout
	path = _path(tree)
	print("RESTART_GATE current=", path)
	if path != GATE:
		_ok = false

	router.call(&"goto", GO, { "elapsed_sec": 1, "floor": 1 })
	await tree.create_timer(1.2).timeout
	go = tree.current_scene
	if go == null or go.scene_file_path != GO:
		_fail("game_over not current 2")
		return
	restart = go.find_child("Restart", true, false) as Button
	if restart == null:
		_fail("restart button missing 2")
		return
	restart.emit_signal("pressed")
	await tree.create_timer(1.5).timeout
	path = _path(tree)
	print("RESTART_MAIN current=", path)
	if path != MAIN:
		_ok = false

	print("MENU FLOW ", "OK" if _ok else "FAIL")
	tree.quit(0 if _ok else 1)


func _path(tree: SceneTree) -> String:
	return tree.current_scene.scene_file_path if tree.current_scene != null else "<null>"


func _fail(message: String) -> void:
	print("MENU FLOW FAIL: ", message)
	get_tree().quit(1)