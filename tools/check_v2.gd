extends SceneTree

# 逐帧驱动：每帧只做一次 seek，避免 headless 下连续 seek 卡死
const TARGET := "res://scenes/player/rogue_knight_v2.tscn"
const SAMPLES := 16

var _skel: Skeleton3D
var _ap: AnimationPlayer
var _clips: Array = []
var _ci := 0
var _si := 0
var _rows: Array = []
var _cur: Dictionary = {}


func _initialize() -> void:
	var ps: PackedScene = load(TARGET)
	var r: Node3D = ps.instantiate()
	get_root().add_child(r)
	_skel = r.find_child("Skeleton3D", true, false)
	_ap = r.find_child("AnimationPlayer", true, false)
	_clips = ["idle", "walk", "run", "strafe", "attack_blade", "fire_xbow", "aim_xbow", "hit", "death"]
	_reset_clip()


func _reset_clip() -> void:
	var clip: String = _clips[_ci]
	var a: Animation = _ap.get_animation(clip)
	_cur = {"clip": clip, "len": a.length, "mtl": 1e9, "mtr": 1e9, "both": 0,
		"hx": [], "hz": [], "q0": Quaternion.IDENTITY}
	_si = 0
	_ap.play(clip)
	_ap.seek(0.0, true)


func _process(_d: float) -> bool:
	if _ci >= _clips.size():
		_report()
		return true
	var clip: String = _cur.clip
	var a: Animation = _ap.get_animation(clip)
	var t: float = a.length * float(_si) / float(SAMPLES)
	_ap.seek(t, true)
	var tl := _skel.get_bone_global_pose(_skel.find_bone("LeftToeBase")).origin
	var tr := _skel.get_bone_global_pose(_skel.find_bone("RightToeBase")).origin
	var hp := _skel.get_bone_global_pose(_skel.find_bone("Hips")).origin
	if _si == 0:
		_cur.q0 = _skel.get_bone_global_pose(_skel.find_bone("LeftArm")).basis.get_rotation_quaternion()
	_cur.mtl = min(_cur.mtl, tl.y)
	_cur.mtr = min(_cur.mtr, tr.y)
	_cur.hx.append(hp.x)
	_cur.hz.append(hp.z)
	if tl.y > 0.05 and tr.y > 0.05:
		_cur.both += 1
	_si += 1
	if _si > SAMPLES:
		var q1 := _skel.get_bone_global_pose(_skel.find_bone("LeftArm")).basis.get_rotation_quaternion()
		var span := Vector2(_cur.hx.max() - _cur.hx.min(), _cur.hz.max() - _cur.hz.min()).length()
		_rows.append([clip, _cur.mtl, _cur.mtr, _cur.both, span, rad_to_deg(_cur.q0.angle_to(q1))])
		_ci += 1
		if _ci < _clips.size():
			_reset_clip()
	return false


func _report() -> void:
	print("%-13s | 脚尖最低 L    R   | 双脚离地 | 髋水平跨度 | 循环首尾差" % "clip")
	print("-".repeat(74))
	for r in _rows:
		print("%-13s | %6.3f %6.3f | %2d/%2d  | %8.3f | %6.2f°" % [r[0], r[1], r[2], r[3], SAMPLES, r[4], r[5]])
