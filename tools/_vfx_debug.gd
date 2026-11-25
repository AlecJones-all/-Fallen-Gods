extends SceneTree

# P3 诊断：院子触发遭遇后，逐层隐藏光源/敌人/弹道/UI，定位顶部黄斑来源。
# 用法：godot --path . --script res://tools/_vfx_debug.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0
var _stage := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		var player := _m.get_node_or_null("World/Player") as Node3D
		var world := _m.get_node_or_null("World") as Node3D
		var rig := _m.get_node_or_null("CameraRig") as Node3D
		if player != null:
			player.position = Vector3(26.0, 0.05, 0.0)
		if rig != null and world != null:
			rig.global_position = world.transform * Vector3(26.0, 1.0, 0.0)
	if _f == 120:
		_shot("vfx_base")
		_hide_lights(true)
	if _f == 140:
		_shot("vfx_nolights")
		_hide_lights(false)
		_hide_node("World/Enemies", true)
	if _f == 160:
		_shot("vfx_noenemies")
		_hide_node("World/Enemies", false)
		_hide_node("Projectiles", true)
	if _f == 180:
		_shot("vfx_noproj")
		_hide_node("Projectiles", false)
		_hide_ui(true)
	if _f == 200:
		_shot("vfx_noui")
		_hide_ui(false)
	if _f == 220:
		print("VFX DONE")
		return true
	return false


func _shot(name: String) -> void:
	get_root().get_texture().get_image().save_png("res://docs/baseline/%s.png" % name)
	print("saved ", name)


func _hide_lights(hidden: bool) -> void:
	for node: Node in _m.find_children("*", "OmniLight3D", true, false):
		(node as OmniLight3D).visible = not hidden


func _hide_node(path: String, hidden: bool) -> void:
	var node := _m.get_node_or_null(path) as CanvasItem
	if node != null:
		node.visible = not hidden


func _hide_ui(hidden: bool) -> void:
	var hud := _m.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = not hidden