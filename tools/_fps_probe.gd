extends SceneTree

# P3 性能基线：院子遭遇场景跑 10s，统计平均/最低 FPS。
# 用法：godot --path . --resolution 1600x900 --script res://tools/_fps_probe.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0
var _t := 0.0
var _samples: Array[float] = []


func _initialize() -> void:
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)
	var vite := get_root().get_visible_rect().size
	print("FPS viewport=", vite, " window=", DisplayServer.window_get_size())


func _process(d: float) -> bool:
	_f += 1
	_t += d
	if _f == 2:
		var player := _m.get_node_or_null("World/Player") as Node3D
		var world := _m.get_node_or_null("World") as Node3D
		var rig := _m.get_node_or_null("CameraRig") as Node3D
		if player != null:
			player.position = Vector3(26.0, 0.05, 0.0)
		if rig != null and world != null:
			rig.global_position = world.transform * Vector3(26.0, 1.0, 0.0)
	if _t > 2.0:
		_samples.append(Engine.get_frames_per_second())
	if _t > 12.0:
		var total := 0.0
		var minv := 999.0
		for s: float in _samples:
			total += s
			minv = minf(minv, s)
		print("FPS avg=%.1f min=%.1f samples=%d" % [
			total / float(maxi(_samples.size(), 1)), minv, _samples.size()])
		return true
	return false