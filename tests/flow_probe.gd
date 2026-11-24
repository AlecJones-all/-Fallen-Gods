extends Node

## Headless flow probe: boot gameplay via Router, kill the player, assert the
## game-over scene is reached with a payload. Run with:
##   godot --headless --path . res://tests/flow_probe.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null

	var router: Node = tree.root.get_node_or_null(^"Router")
	if router == null or not router.has_method(&"goto"):
		_fail("Router autoload missing")
		return
	router.call(&"goto", "res://scenes/main.tscn")
	await tree.create_timer(1.0).timeout

	if tree.current_scene == null or tree.current_scene.scene_file_path != "res://scenes/main.tscn":
		_fail("gameplay scene not current")
		return

	var player: Node = tree.get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"take_damage"):
		_fail("player missing")
		return
	player.call(&"take_damage", 9999.0)
	await tree.create_timer(1.5).timeout

	var path := "<null>"
	if tree.current_scene != null:
		path = tree.current_scene.scene_file_path
	var payload: Dictionary = router.get(&"last_payload")
	print("FLOW scene=", path, " payload=", payload)
	if path != "res://scenes/ui/game_over.tscn":
		_fail("unexpected scene %s" % path)
	elif not payload.has("elapsed_sec") or not payload.has("floor"):
		_fail("payload missing keys")
	else:
		print("FLOW OK")
		await _check_settings(tree)


func _check_settings(tree: SceneTree) -> void:
	var settings: Node = tree.root.get_node_or_null(^"Settings")
	var panel: Control = (load("res://scenes/ui/settings_panel.tscn") as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame

	var slider: HSlider = panel.find_child("Slider", true, false) as HSlider
	if settings == null or slider == null:
		_fail("settings panel or autoload missing")
		return

	var original: float = float(settings.get(&"master"))
	slider.value = 0.37
	await tree.process_frame
	if not is_equal_approx(float(settings.get(&"master")), 0.37):
		_fail("slider did not reach Settings autoload")
		return
	if not FileAccess.file_exists("user://settings.cfg"):
		_fail("settings not persisted")
		return

	settings.call(&"set_master", original)
	panel.call(&"close")
	print("SETTINGS OK")
	tree.quit(0)


func _fail(message: String) -> void:
	print("FLOW FAIL: ", message)
	get_tree().quit(1)
