extends SceneTree

# Reproducible visual and performance review for Whitewash Chapel.
# Examples:
#   godot --path . --script res://tools/chapel_review.gd -- graybox 1280 720
#   godot --path . --script res://tools/chapel_review.gd -- final 2560 1080
# Use Godot's --write-movie with the final command to emit a normal-speed review clip.

const SCENE := "res://scenes/levels/whitewash_chapel.tscn"
const OUTPUT_DIR := "res://art/previews/whitewash_chapel"
const SETTLE_FRAMES := 20
const WALK_SECONDS := 12.0
const WALK_TIMEOUT_SECONDS := 30.0
const WALK_TOLERANCE := 0.22
const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back"]

var _phase := "final"
var _size := Vector2i(1280, 720)
var _scene: Node
var _world: Node3D
var _player: Node3D
var _rig: Node3D
var _camera: Camera3D
var _frame := 0
var _shot_index := 0
var _shot_frames := 0
var _walk_started := false
var _walk_elapsed := 0.0
var _walk_point := 0
var _frame_ms: Array[float] = []
var _walk_positions: Array[Vector3] = []
var _worst_position := Vector3.ZERO
var _worst_frame_ms := 0.0
var _last_walk_tick_usec := 0
var _tag := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_phase = args[0].to_lower()
	if args.size() >= 3:
		_size = Vector2i(int(args[1]), int(args[2]))
	if _phase != "graybox" and _phase != "final":
		push_error("phase must be graybox or final")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("missing " + SCENE)
		quit(2)
		return
	_scene = packed.instantiate()
	# The scene exposes its draft state before it enters the tree.
	_scene.set("graybox", _phase == "graybox")
	get_root().add_child(_scene)
	_world = _scene.get_node_or_null("World") as Node3D
	_player = _scene.get_node_or_null("Player") as Node3D
	_rig = _scene.get_node_or_null("CameraRig") as Node3D
	if _rig != null:
		_camera = _rig.get_node_or_null("Camera3D") as Camera3D
		_rig.set_physics_process(false)
	DisplayServer.window_set_size(_size)


func _process(delta: float) -> bool:
	_frame += 1
	if _frame <= SETTLE_FRAMES:
		if _frame == 3:
			DisplayServer.window_set_size(_size)
		return false
	if _tag.is_empty():
		var visible := get_root().get_visible_rect().size
		_tag = "%dx%d" % [int(visible.x), int(visible.y)]
		print("CHAPEL REVIEW phase=", _phase, " requested=", _size, " visible=", _tag)
	return _capture_or_walk(delta)


func _capture_or_walk(delta: float) -> bool:
	var shots := _shots()
	if _shot_index < shots.size():
		_shot_frames += 1
		if _shot_frames == 1:
			_apply_shot(shots[_shot_index])
		elif _shot_frames == 18:
			_save_shot(String(shots[_shot_index]["name"]))
			_shot_index += 1
			_shot_frames = 0
		return false
	if not _walk_started:
		_walk_started = true
		_player.position = Vector3(-5.0, 0.0, 0.0)
		_sync_camera()
		_last_walk_tick_usec = Time.get_ticks_usec()
	return _walk(delta)


func _shots() -> Array[Dictionary]:
	if _phase == "graybox":
		return [
			{"name": "entrance", "position": Vector3(-5.0, 0.0, 0.0)},
			{"name": "altar", "position": Vector3(2.6, 0.0, 0.0)},
		]
	return [
		{"name": "entrance", "position": Vector3(-5.0, 0.0, 0.0)},
		{"name": "altar", "position": Vector3(2.6, 0.0, 0.0)},
		{"name": "shrine", "position": Vector3(5.4, 0.0, -1.8)},
	]


func _apply_shot(shot: Dictionary) -> void:
	if _player != null:
		_player.position = shot["position"] as Vector3
	_sync_camera()


func _sync_camera() -> void:
	if _rig != null and _player != null:
		_rig.global_position = _player.global_position + Vector3(0.0, 1.0, 0.0)


func _save_shot(name: String) -> void:
	var path := "%s/%s_%s_%s.png" % [OUTPUT_DIR, _phase, _tag, name]
	var result := get_root().get_texture().get_image().save_png(path)
	if result != OK:
		push_error("failed to save " + path + ": " + str(result))
	else:
		print("CHAPEL SAVED ", path)


func _walk(delta: float) -> bool:
	_walk_elapsed += delta
	_drive_player()
	var now_usec := Time.get_ticks_usec()
	var elapsed_ms := float(now_usec - _last_walk_tick_usec) / 1000.0
	_last_walk_tick_usec = now_usec
	_frame_ms.append(elapsed_ms)
	if _player != null:
		_walk_positions.append(_player.global_position)
		if elapsed_ms > _worst_frame_ms:
			_worst_frame_ms = elapsed_ms
			_worst_position = _player.global_position
	if _walk_point < _walk_route().size() and _walk_elapsed < WALK_TIMEOUT_SECONDS:
		return false
	_release_movement()
	_write_performance()
	if _walk_point == _walk_route().size():
		print("CHAPEL REVIEW DONE ", _phase, " ", _tag)
		quit()
	else:
		push_error("CHAPEL REVIEW route incomplete: %d/%d waypoints" % [_walk_point, _walk_route().size()])
		quit(2)
	return true


func _walk_route() -> Array[Vector3]:
	# Main aisle, both walls, shrine, and a return along the opposite wall.
	return [
		Vector3(-1.5, 0.0, 0.0),
		Vector3(2.6, 0.0, 0.0),
		Vector3(0.9, 0.0, 0.0),
		Vector3(0.9, 0.0, -4.45),
		Vector3(4.5, 0.0, -4.45),
		Vector3(0.9, 0.0, -4.45),
		Vector3(0.9, 0.0, 0.0),
		Vector3(5.95, 0.0, 0.0),
		Vector3(5.95, 0.0, -1.75),
		Vector3(5.95, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 3.98),
		Vector3(1.0, 0.0, 0.0),
		Vector3(-5.0, 0.0, 0.0),
	]


func _drive_player() -> void:
	if _player == null or _walk_point >= _walk_route().size():
		return
	var target := _walk_route()[_walk_point]
	var offset := target - _player.global_position
	offset.y = 0.0
	if offset.length() <= WALK_TOLERANCE:
		_walk_point += 1
		_release_movement()
		return
	var camera_forward := Vector3.FORWARD
	var camera_right := Vector3.RIGHT
	if _camera != null:
		camera_forward = -_camera.global_basis.z
		camera_forward.y = 0.0
		camera_forward = camera_forward.normalized()
		camera_right = _camera.global_basis.x
		camera_right.y = 0.0
		camera_right = camera_right.normalized()
	var direction := offset.normalized()
	_set_action(&"move_forward", maxf(direction.dot(camera_forward), 0.0))
	_set_action(&"move_back", maxf(-direction.dot(camera_forward), 0.0))
	_set_action(&"move_right", maxf(direction.dot(camera_right), 0.0))
	_set_action(&"move_left", maxf(-direction.dot(camera_right), 0.0))
	_sync_camera()


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_movement() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _write_performance() -> void:
	if _frame_ms.is_empty():
		return
	var sum := 0.0
	var worst := 0.0
	for frame_ms in _frame_ms:
		sum += frame_ms
		worst = maxf(worst, frame_ms)
	var average := sum / float(_frame_ms.size())
	var csv_path := ProjectSettings.globalize_path("%s/%s_%s_walk.csv" % [OUTPUT_DIR, _phase, _tag])
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	csv.store_line("frame,ms")
	for index in _frame_ms.size():
		csv.store_line("%d,%.3f" % [index + 1, _frame_ms[index]])
	var summary_path := ProjectSettings.globalize_path("%s/%s_%s_walk.txt" % [OUTPUT_DIR, _phase, _tag])
	var summary := FileAccess.open(summary_path, FileAccess.WRITE)
	summary.store_line("phase=%s" % _phase)
	summary.store_line("visible=%s" % _tag)
	summary.store_line("route=main_aisle,north_aisle,shrine,south_aisle,return")
	summary.store_line("frames=%d" % _frame_ms.size())
	summary.store_line("average_ms=%.3f" % average)
	summary.store_line("worst_ms=%.3f" % worst)
	summary.store_line("worst_position=(%.2f,%.2f,%.2f)" % [_worst_position.x, _worst_position.y, _worst_position.z])
	summary.store_line("waypoints_reached=%d/%d" % [_walk_point, _walk_route().size()])
