extends CanvasLayer

signal transition_started(path: String)
signal scene_changed(path: String)

const LAYER := 128
const FADE_IN_TIME := 0.25
const FADE_OUT_TIME := 0.2

var last_payload: Dictionary = {}
var is_transitioning: bool = false

var _overlay: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Cover the initial scene before revealing it so the first frames never flash.
	_fade_overlay(0.0, FADE_IN_TIME).tween_callback(_set_mouse_blocking.bind(false))


func goto(scene_path: String, payload: Dictionary = {}) -> void:
	if is_transitioning or scene_path.is_empty():
		return
	is_transitioning = true
	last_payload = payload
	transition_started.emit(scene_path)
	_set_mouse_blocking(true)
	await _fade_overlay(1.0, FADE_OUT_TIME).finished
	_set_mouse_blocking(false)
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await _fade_overlay(0.0, FADE_IN_TIME).finished
	is_transitioning = false
	scene_changed.emit(scene_path)


func _set_mouse_blocking(block: bool) -> void:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if block else Control.MOUSE_FILTER_IGNORE


func _fade_overlay(target_alpha: float, duration: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# Explicit PROCESS so the fade survives a paused tree regardless of node inheritance.
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_overlay, "color:a", target_alpha, duration)
	return _tween
