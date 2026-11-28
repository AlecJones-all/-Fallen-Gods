extends SceneTree
## 运行时 GLB 探测：不依赖编辑器导入，直接用 GLTFDocument 读取并报告包围盒。
## 用法: godot --path . --script res://tools/_glb_probe.gd

const FILES := [
	"res://双心跳祭龛-游戏.glb",
	"res://主教祭坛-游戏.glb",
	"res://记忆焚烧台-游戏.glb",
	"res://唱诗班楼阳台-游戏.glb",
	"res://悬挂圣徒铁笼-游戏.glb",
	"res://沉没大教堂中殿-v2.glb",
	"res://大理石台座.glb",
]


func _init() -> void:
	for path in FILES:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var t0 := Time.get_ticks_msec()
		var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
		if err != OK:
			print("FAIL ", path, " err=", err)
			continue
		var scene := doc.generate_scene(state)
		var box := _aabb(scene)
		print("OK %-26s %5dms size=(%.3f, %.3f, %.3f) min_y=%.3f meshes=%d"
			% [path.get_file(), Time.get_ticks_msec() - t0, box.size.x, box.size.y, box.size.z,
			box.position.y, scene.find_children("*", "MeshInstance3D", true, false).size()])
		scene.free()
	quit()


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local := mesh.transform * mesh.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out
