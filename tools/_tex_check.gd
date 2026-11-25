extends SceneTree

# P3 调试：检查游戏实际加载的石板贴图内容。
# 用法：godot --headless --path . --script res://tools/_tex_check.gd
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/baseline"))
	for p: String in ["res://assets/materials/stone_crack_albedo.png", "res://assets/materials/stone_crack_normal.png"]:
		var tex := load(p) as Texture2D
		if tex == null:
			print("TEX FAIL ", p)
			continue
		var name := p.get_file().get_basename()
		tex.get_image().save_png("res://docs/baseline/loaded_%s.png" % name)
		print("TEX ", name, " size=", tex.get_size())
	print("TEX DONE")
	quit()