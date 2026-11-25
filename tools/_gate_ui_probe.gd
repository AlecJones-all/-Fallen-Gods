extends SceneTree

# P2 兼容检查：税卡场景 HUD / 暂停菜单 / 楼层块隐藏。
# 用法：godot --path . --resolution 1600x900 --script res://tools/_gate_ui_probe.gd
const SCENE := "res://scenes/levels/tithe_gate_graybox.tscn"

var _m: Node
var _f := 0
var _tag := ""


func _initialize() -> void:
	var view := get_root().get_visible_rect().size
	_tag = "%dx%d" % [int(view.x), int(view.y)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	_m = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_m)


func _process(_d: float) -> bool:
	_f += 1
	var hud := _m.get_node_or_null("HUD")
	var pm := _m.get_node_or_null("PauseMenu")
	var floor_anchor := hud.get_node_or_null("FloorAnchor") if hud != null else null
	if _f == 20:
		print("NODES hud=", hud != null, " pause=", pm != null,
			" floor_anchor=", floor_anchor != null,
			" floor_visible=", (floor_anchor as CanvasItem).visible if floor_anchor != null else "?")
		if pm != null:
			pm.call("open")
	if _f == 30:
		var visible := bool(pm.visible) if pm != null else false
		print("OPEN paused=", paused, " visible=", visible)
		get_root().get_texture().get_image().save_png("res://docs/baseline/ui_pause_%s.png" % _tag)
	if _f == 40:
		if pm != null:
			pm.call("close")
	if _f == 50:
		var visible := bool(pm.visible) if pm != null else true
		var floor_ok := floor_anchor != null and not (floor_anchor as CanvasItem).visible
		var ok := pm != null and not paused and not visible and floor_ok
		print("CLOSE paused=", paused, " visible=", visible, " floor_hidden=", floor_ok)
		print("UI ", "OK" if ok else "FAIL")
		return true
	return false