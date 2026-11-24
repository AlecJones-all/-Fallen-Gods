extends SceneTree

# 数值校验：输出各骨骼全局位置随时间变化，检查脚是否踩地、步幅是否合理
var _skel: Skeleton3D
var _ap: AnimationPlayer


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/player/rogue_knight_rigged.tscn")
	var model: Node3D = ps.instantiate()
	get_root().add_child(model)
	_skel = model.find_child("Skeleton3D", true, false)
	_ap = model.find_child("AnimationPlayer", true, false)


func _process(_d: float) -> bool:
	for clip in ["idle", "walk", "run", "attack"]:
		var a: Animation = _ap.get_animation(clip)
		if a == null:
			print(clip, " MISSING")
			continue
		var n := 24
		var min_y := {"foot.L": 1e9, "foot.R": 1e9, "toe.L": 1e9, "toe.R": 1e9}
		var zr := {"foot.L": [1e9, -1e9], "foot.R": [1e9, -1e9]}
		var hipy := [1e9, -1e9]
		for i in n:
			var t: float = a.length * float(i) / float(n)
			_ap.play(clip)
			_ap.seek(t, true)
			for b in ["foot.L", "foot.R", "toe.L", "toe.R"]:
				var p := _skel.get_bone_global_pose(_skel.find_bone(b)).origin
				min_y[b] = min(min_y[b], p.y)
				if zr.has(b):
					zr[b][0] = min(zr[b][0], p.z)
					zr[b][1] = max(zr[b][1], p.z)
			var hp := _skel.get_bone_global_pose(_skel.find_bone("hips")).origin
			hipy[0] = min(hipy[0], hp.y)
			hipy[1] = max(hipy[1], hp.y)
		print("=== ", clip, " len=", a.length, " loop=", a.loop_mode)
		print("   脚最低 y: foot.L=", snappedf(min_y["foot.L"], 0.001), " foot.R=", snappedf(min_y["foot.R"], 0.001),
			" toe.L=", snappedf(min_y["toe.L"], 0.001), " toe.R=", snappedf(min_y["toe.R"], 0.001))
		print("   步幅 z: foot.L=[", snappedf(zr["foot.L"][0], 0.01), ",", snappedf(zr["foot.L"][1], 0.01), "]",
			" foot.R=[", snappedf(zr["foot.R"][0], 0.01), ",", snappedf(zr["foot.R"][1], 0.01), "]")
		print("   hips y 范围=[", snappedf(hipy[0], 0.01), ",", snappedf(hipy[1], 0.01), "]")
	print("--- 关键骨静止位置 ---")
	for b in ["hips", "chest", "head", "hand.L", "hand.R", "foot.L", "weapon_sword"]:
		var i := _skel.find_bone(b)
		print("  ", b, " rest_global=", _skel.get_bone_global_rest(i).origin.snapped(Vector3.ONE * 0.01))
		return true
	return false
