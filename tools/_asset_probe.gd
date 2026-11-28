extends SceneTree
# 资产完整性探测：加载每个 FBX，报告 网格/骨架/动画片段(名称+时长+轨道数)
# 用法: godot --headless --path . --script res://tools/_asset_probe.gd

const ROOTS := [
	"res://assets/anim_src/",
	"res://assets/anim_src/bulky-knight/source/",
	"res://assets/anim_src/jack-of-blades/source/",
	"res://assets/anim_src/medieval-knight-sculpture-game-ready/source/",
	"res://assets/anim_src/realtime-grass/source/",
	"res://assets/anim_src/stone-pack/source/",
	"res://assets/anim_src/fantasy-sky-background/source/",
	"res://assets/characters/rogue_knight/",
]

func _init() -> void:
	print("=== ASSET PROBE BEGIN ===")
	for d in ROOTS:
		var files := DirAccess.get_files_at(d)
		if files.is_empty():
			print("[MISS] dir %s" % d)
			continue
		for f in files:
			if f.to_lower().ends_with(".fbx") or f.to_lower().ends_with(".glb") or f.to_lower().ends_with(".gltf"):
				_probe(d + f)
	print("=== ASSET PROBE END ===")
	quit()

func _probe(path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var ps: PackedScene = null
	ps = load(path) as PackedScene
	if ps == null:
		print("[FAIL ] %s | 加载失败(非场景或导入损坏)" % path)
		return
	var inst: Node = ps.instantiate()
	var meshes: Array[String] = []
	var skels: Array[String] = []
	var aps: Array[AnimationPlayer] = []
	_walk(inst, meshes, skels, aps)
	var parts: Array[String] = []
	parts.append("%-46s" % path.get_file())
	parts.append("mesh=%d" % meshes.size())
	parts.append("skel=%d" % skels.size())
	if skels.size() > 0:
		var sk := _find_skel(inst)
		if sk != null:
			parts.append("bones=%d" % sk.get_bone_count())
	if aps.is_empty():
		parts.append("ANIM=NONE")
	else:
		for ap in aps:
			var names := ap.get_animation_list()
			for n in names:
				var a: Animation = ap.get_animation(n)
				parts.append("anim{%s %.2fs %dtr}" % [n, a.length, a.get_track_count()])
	var st := "OK   "
	for m in meshes:
		if m.to_lower().contains("fail") or m.is_empty():
			st = "WARN "
	print("[%s] %s  (%dms)" % [st, " ".join(parts), Time.get_ticks_msec() - t0])
	inst.free()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _walk(n: Node, meshes: Array[String], skels: Array[String], aps: Array[AnimationPlayer]) -> void:
	if n is MeshInstance3D:
		meshes.append(n.name)
	if n is Skeleton3D:
		skels.append(n.name)
	if n is AnimationPlayer:
		aps.append(n)
	for c in n.get_children():
		_walk(c, meshes, skels, aps)
