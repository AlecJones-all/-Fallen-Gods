extends Node

## Headless display probe: stretch setup, aspect-aware camera framing and the
## settings panel resolution picker. Run with:
##   godot --headless --path . res://tests/display_probe.tscn

const CAMERA_SCENE := "res://scenes/camera/camera_rig.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_panel.tscn"
const DESIGN_SIZE := Vector2i(1280, 720)
const MIN_WINDOW := Vector2i(960, 540)
const FIT_TOLERANCE := 0.01


var _tree: SceneTree


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_tree = get_tree()
	reparent(_tree.root)
	_tree.current_scene = null

	if not _check_stretch():
		return
	if not _check_fit_math():
		return
	if not await _check_camera():
		return
	if not await _check_settings_ui():
		return

	print("DISPLAY OK")
	_tree.quit(0)


func _check_stretch() -> bool:
	var mode := String(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var aspect := String(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	if mode != "canvas_items":
		return _fail_bool("stretch mode is %s, expected canvas_items" % mode)
	if aspect != "expand":
		return _fail_bool("stretch aspect is %s, expected expand" % aspect)
	if width != DESIGN_SIZE.x or height != DESIGN_SIZE.y:
		return _fail_bool("design size is %dx%d, expected %dx%d" % [width, height,
			DESIGN_SIZE.x, DESIGN_SIZE.y])
	return true


func _check_fit_math() -> bool:
	var base := 12.0
	var design := 16.0 / 9.0
	var cases := {
		"16:9": [design, 12.0],
		"16:10": [16.0 / 10.0, 13.3333],
		"4:3": [4.0 / 3.0, 16.0],
		"21:9": [21.0 / 9.0, 12.0],
		"9:16": [9.0 / 16.0, 18.0],
	}
	for label in cases:
		var aspect: float = cases[label][0]
		var expected: float = cases[label][1]
		var actual := CameraRig.fitted_ortho_size(base, aspect, design, 1.5)
		if absf(actual - expected) > FIT_TOLERANCE:
			return _fail_bool("fit %s -> %.3f, expected %.3f" % [label, actual, expected])
	if not is_equal_approx(CameraRig.fitted_ortho_size(base, 0.0, design, 1.5), base):
		return _fail_bool("degenerate aspect did not fall back to the base size")
	return true


func _check_camera() -> bool:
	var packed := load(CAMERA_SCENE) as PackedScene
	if packed == null:
		return _fail_bool("camera scene missing")
	var rig := packed.instantiate() as CameraRig
	if rig == null:
		return _fail_bool("camera rig root is not CameraRig")
	_tree.root.add_child(rig)
	await _tree.process_frame
	await _tree.process_frame

	var camera := rig.get_node_or_null(^"Camera3D") as Camera3D
	if camera == null:
		return _fail_bool("camera node missing")
	var view := _tree.root.get_visible_rect().size
	if view.y <= 0.0:
		return _fail_bool("viewport has no height")

	var tuning := _tree.root.get_node_or_null(^"Tuning")
	var base := float(tuning.call(&"value", "camera", "ortho_size", 12.0)) if tuning != null else 12.0
	var design_aspect := float(tuning.call(&"value", "camera", "fit_aspect", 16.0 / 9.0)) \
		if tuning != null else 16.0 / 9.0
	var fit_max := float(tuning.call(&"value", "camera", "fit_max", 1.5)) if tuning != null else 1.5
	var expected := CameraRig.fitted_ortho_size(base, view.x / view.y, design_aspect, fit_max)
	if absf(camera.size - expected) > FIT_TOLERANCE:
		return _fail_bool("camera size %.3f, expected %.3f at aspect %.3f"
			% [camera.size, expected, view.x / view.y])
	return true


func _check_settings_ui() -> bool:
	var settings := _tree.root.get_node_or_null(^"Settings")
	if settings == null:
		return _fail_bool("Settings autoload missing")
	for method in ["get_window_size", "set_window_size", "available_resolutions"]:
		if not settings.has_method(method):
			return _fail_bool("Settings has no %s()" % method)

	var current: Variant = settings.call(&"get_window_size")
	if not current is Vector2i:
		return _fail_bool("window size is not a Vector2i")
	if current.x < MIN_WINDOW.x or current.y < MIN_WINDOW.y:
		return _fail_bool("window size %s is below the minimum" % str(current))

	var options: Variant = settings.call(&"available_resolutions")
	if not options is Array or (options as Array).is_empty():
		return _fail_bool("no resolutions offered")
	if not (options as Array).has(current):
		return _fail_bool("current window size missing from the resolution list")

	var panel := (load(SETTINGS_SCENE) as PackedScene).instantiate()
	_tree.root.add_child(panel)
	await _tree.process_frame
	var picker := panel.find_child("Resolution", true, false) as OptionButton
	if picker == null:
		return _fail_bool("settings panel has no resolution picker")
	if picker.item_count != (options as Array).size():
		return _fail_bool("resolution picker has %d items, expected %d"
			% [picker.item_count, (options as Array).size()])
	if picker.disabled != bool(settings.get(&"fullscreen")):
		return _fail_bool("resolution picker enabled state does not match fullscreen")
	var hint := panel.find_child("ResolutionHint", true, false) as Label
	if hint == null:
		return _fail_bool("settings panel has no fullscreen hint")
	if hint.visible != picker.disabled:
		return _fail_bool("fullscreen hint visibility does not match the picker state")
	panel.call(&"close")
	return true


func _fail_bool(message: String) -> bool:
	print("DISPLAY FAIL: ", message)
	_tree.quit(1)
	return false
