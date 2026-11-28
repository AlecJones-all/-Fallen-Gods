extends SceneTree

func _init() -> void:
	for p in ["res://assets/anim_src/bulky-knight/source/Big Night For Sketchfab.fbx",
			"res://assets/anim_src/jack-of-blades/source/Jack_Of_Blades.fbx"]:
		print("--- ", p.get_file())
		var ps: PackedScene = load(p)
		var n: Node = ps.instantiate()
		_dump(n, 0)
		n.free()
	quit()

func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = n.mesh
		if m != null:
			var aabb: AABB = m.get_aabb()
			extra = "  size=%.2f,%.2f,%.2f surf=%d" % [aabb.size.x, aabb.size.y, aabb.size.z, m.get_surface_count()]
	print("  ".repeat(d), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_dump(c, d + 1)
