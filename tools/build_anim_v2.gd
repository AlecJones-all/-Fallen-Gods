extends SceneTree

# A3：Mixamo 动作重定向到 36 骨新骨架 + 上下半身分层合成 + 原地化
# 采样不依赖 AnimationPlayer，直接对 Animation 轨道插值，避免初始化阶段 seek 失效
# 用法: godot --headless --path . --script res://tools/build_anim_v2.gd

const TARGET := "res://scenes/player/rogue_knight_v2.tscn"
const SRC_DIR := "res://assets/anim_src/"
const FPS := 30.0
const HIPS_SCALE := 0.94

const MAP := {
	"Hips": "mixamorig_Hips", "Spine": "mixamorig_Spine", "Spine1": "mixamorig_Spine1",
	"Spine2": "mixamorig_Spine2", "Neck": "mixamorig_Neck", "Head": "mixamorig_Head",
	"LeftShoulder": "mixamorig_LeftShoulder", "LeftArm": "mixamorig_LeftArm",
	"LeftForeArm": "mixamorig_LeftForeArm", "LeftHand": "mixamorig_LeftHand",
	"RightShoulder": "mixamorig_RightShoulder", "RightArm": "mixamorig_RightArm",
	"RightForeArm": "mixamorig_RightForeArm", "RightHand": "mixamorig_RightHand",
	"LeftUpLeg": "mixamorig_LeftUpLeg", "LeftLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot", "LeftToeBase": "mixamorig_LeftToeBase",
	"RightUpLeg": "mixamorig_RightUpLeg", "RightLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot", "RightToeBase": "mixamorig_RightToeBase",
}
const LOWER := ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
	"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const ARM_BONES := ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]

var _src := {}
var _tgt: Node3D
var _tskel: Skeleton3D


func _init() -> void:
	var ps: PackedScene = load(TARGET)
	_tgt = ps.instantiate()
	get_root().add_child(_tgt)
	_tskel = _tgt.find_child("Skeleton3D", true, false)

	for f in ["idle", "Great Sword Walk", "Great Sword Slash", "Great Sword Strafe",
			"Sword And Shield Run", "Sword And Shield Walk", "Firing Rifle",
			"Hit To Body", "Death"]:
		_load_src(f)
	print("sources=", _src.size())
	_dbg()
	_dbg3()

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _clip("idle", 1.2, true, "idle", "Great Sword Walk", false, 0.0, 1.0, true))
	lib.add_animation("walk", _clip("walk", 1.1, true, "Sword And Shield Walk", "Great Sword Walk", false, 0.0, 1.0, false))
	lib.add_animation("run", _clip("run", 0.7, true, "Sword And Shield Run", "Great Sword Walk", false, 8.0, 1.4, false))
	lib.add_animation("strafe", _clip("strafe", 1.0, true, "Great Sword Strafe", "Great Sword Strafe", true, 0.0, 1.0, false))
	lib.add_animation("attack_blade", _clip("attack_blade", 0.6, false, "Great Sword Slash", "Great Sword Slash", true, 0.0, 1.0, false, 0.30, 0.78, 46.0))
	lib.add_animation("fire_xbow", _clip("fire_xbow", 0.7, false, "Firing Rifle", "Firing Rifle", false, 0.0, 1.0, false))
	lib.add_animation("aim_xbow", _clip("aim_xbow", 1.0, true, "Firing Rifle", "Firing Rifle", false, 0.0, 1.0, true))
	lib.add_animation("hit", _clip("hit", 1.33, false, "Hit To Body", "Hit To Body", false, 0.0, 1.0, false))
	lib.add_animation("death", _clip("death", 3.03, false, "Death", "Death", false, 0.0, 1.0, false))

	var ap: AnimationPlayer = _tgt.find_child("AnimationPlayer", true, false)
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		_tgt.add_child(ap)
		ap.owner = _tgt
	ap.root_node = NodePath("..")
	for l in ap.get_animation_library_list():
		ap.remove_animation_library(l)
	ap.add_animation_library("", lib)

	var packed := PackedScene.new()
	print("pack=", packed.pack(_tgt))
	print("SAVED ", ResourceSaver.save(packed, TARGET))
	quit()


func _dbg3() -> void:
	var cands := {
		"up(0,1,0)": Vector3(0, 1, 0), "arm(-1,0,0)": Vector3(-1, 0, 0),
		"antiarm(1,0,0)": Vector3(1, 0, 0), "fwd(0,0,1)": Vector3(0, 0, 1),
		"back(0,0,-1)": Vector3(0, 0, -1), "diag(-0.6,-0.8,0)": Vector3(-0.6, -0.8, 0),
	}
	for combo in [["idle", 0.3], ["Great Sword Walk", 0.25], ["Great Sword Slash", 0.5]]:
		var lo := _sample(combo[0], float(_src[combo[0]].dur) * combo[1])
		var rh: String = "RightHand"
		var delta: Basis = lo["basis"][rh] * _src[combo[0]].rest_global[MAP[rh]].basis.inverse()
		print("--- ", combo[0], " t=", combo[1])
		for k in cands:
			# 剑尖方向 = (剑格->剑尖) 的世界朝向；GRIP_ALONG 定义为剑尖在 bind 空间的方向
			var wdir: Vector3 = (delta * Vector3(cands[k]).normalized()).normalized()
			print("    %-16s -> world %s" % [k, str(wdir.snapped(Vector3.ONE * 0.01))])


func _dbg2() -> void:
	# 反推：让剑在指定姿势下朝世界"上"方向，所需的 bind 空间剑轴
	for combo in [["idle", 0.3], ["Great Sword Walk", 0.25], ["Great Sword Slash", 0.5]]:
		var lo := _sample(combo[0], float(_src[combo[0]].dur) * combo[1])
		var rh: String = "RightHand"
		var delta: Basis = lo["basis"][rh] * _src[combo[0]].rest_global[MAP[rh]].basis.inverse()
		print("GRIP for %-18s t=%.2f -> up=%s  fwd=%s  down=%s" % [combo[0], combo[1],
			str((delta.inverse() * Vector3.UP).snapped(Vector3.ONE * 0.01)),
			str((delta.inverse() * Vector3(0, 0, 1)).snapped(Vector3.ONE * 0.01)),
			str((delta.inverse() * Vector3.DOWN).snapped(Vector3.ONE * 0.01))])


func _dbg() -> void:
	for f in ["idle", "Great Sword Walk"]:
		var g := _sample(f, 0.5)
		for b in ["Hips", "LeftArm", "LeftUpLeg"]:
			var ang: float = _src[f].rest_global[MAP[b]].basis.get_rotation_quaternion().angle_to(
				g["basis"][b].get_rotation_quaternion())
			print("DBG %-18s %-11s angle=%6.2f°  hips=%s" % [f, b, rad_to_deg(ang), str(g["hips"].snapped(Vector3.ONE * 0.01))])


# ---------------- 源：直读 Animation 轨道 ----------------
func _load_src(f: String) -> void:
	var ps: PackedScene = load(SRC_DIR + f + ".fbx")
	if ps == null:
		print("SRC FAIL ", f)
		return
	var r: Node3D = ps.instantiate()
	var skel: Skeleton3D = r.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = r.find_child("AnimationPlayer", true, false)
	var lst := ap.get_animation_list()
	var anim: Animation = ap.get_animation(lst[0])
	var rot := {}
	var pos := {}
	for ti in anim.get_track_count():
		var bone := str(anim.track_get_path(ti)).get_slice(":", 1)
		var tt := anim.track_get_type(ti)
		if tt == Animation.TYPE_ROTATION_3D:
			rot[bone] = ti
		elif tt == Animation.TYPE_POSITION_3D:
			pos[bone] = ti
	var rest_local := {}
	var rest_global := {}
	var parent := {}
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		rest_local[bn] = skel.get_bone_rest(i)
		rest_global[bn] = skel.get_bone_global_rest(i)
		var pi := skel.get_bone_parent(i)
		parent[bn] = skel.get_bone_name(pi) if pi >= 0 else ""
	_src[f] = {"anim": anim, "rot": rot, "pos": pos, "rest_local": rest_local,
		"rest_global": rest_global, "parent": parent, "dur": anim.length}
	r.free()


func _glob(s: Dictionary, bn: String, t: float, cache: Dictionary) -> Transform3D:
	if cache.has(bn):
		return cache[bn]
	var anim: Animation = s.anim
	var q := Quaternion.IDENTITY
	if s.rot.has(bn):
		q = anim.rotation_track_interpolate(s.rot[bn], t)
	var rl: Transform3D = s.rest_local[bn]
	var local := Transform3D(Basis(q).orthonormalized(), rl.origin)
	if s.pos.has(bn):
		local.origin = anim.position_track_interpolate(s.pos[bn], t)
	var p: String = s.parent[bn]
	var g := local
	if p != "":
		g = _glob(s, p, t, cache) * local
	cache[bn] = g
	return g


func _sample(f: String, t: float) -> Dictionary:
	var s: Dictionary = _src[f]
	var cache := {}
	var basis := {}
	var pos := {}
	for b in MAP:
		var g := _glob(s, MAP[b], t, cache)
		basis[b] = g.basis
		pos[b] = g.origin
	return {"basis": basis, "pos": pos, "hips": _glob(s, "mixamorig_Hips", t, cache).origin}


# ---------------- 合成一帧 ----------------
func _build_frame(lower_f: String, upper_f: String, ph_l: float, ph_u: float,
		lean_deg: float, arm_gain: float, sweep_deg: float) -> Dictionary:
	var lo := _sample(lower_f, float(_src[lower_f].dur) * ph_l)
	var up := _sample(upper_f, float(_src[upper_f].dur) * ph_u)

	var world := {}
	for b in MAP:
		var is_lower: bool = LOWER.has(b)
		var src: Dictionary = lo if is_lower else up
		var sf: String = lower_f if is_lower else upper_f
		var delta: Basis = src["basis"][b] * _src[sf].rest_global[MAP[b]].basis.inverse()
		var w: Basis = delta
		if absf(lean_deg) > 0.001 and (b == "Spine" or b == "Spine1" or b == "Spine2"):
			w = Basis(Vector3.RIGHT, deg_to_rad(lean_deg / 3.0)) * w
		if absf(sweep_deg) > 0.001 and (b == "Spine" or b == "Spine1" or b == "Spine2"):
			w = Basis(Vector3.UP, deg_to_rad(sweep_deg / 3.0)) * w
		if arm_gain != 1.0 and ARM_BONES.has(b):
			var q := delta.get_rotation_quaternion()
			if q.w < 0.0:
				q = -q
			var ang := q.get_angle()
			var ax := q.get_axis()
			if absf(ang) > 0.0005 and ax.length_squared() > 1e-8:
				w = Basis(ax.normalized(), ang * arm_gain)
		world[b] = w

	var local := {}
	for i in _tskel.get_bone_count():
		var bname := _tskel.get_bone_name(i)
		if not world.has(bname):
			local[bname] = Quaternion.IDENTITY
			continue
		var pidx := _tskel.get_bone_parent(i)
		var pw := Basis()
		if pidx >= 0:
			var pn := _tskel.get_bone_name(pidx)
			if world.has(pn):
				pw = world[pn]
		local[bname] = (pw.inverse() * world[bname]).get_rotation_quaternion()
	var arm_dir: Vector3 = (up["pos"]["RightHand"] - up["pos"]["RightForeArm"]).normalized()
	return {"rot": local, "hips": lo["hips"] - _src[lower_f].rest_global["mixamorig_Hips"].origin,
		"rhand": world.get("RightHand", Basis()), "arm_dir": arm_dir}


func _clip(name: String, length: float, loop: bool, lower_f: String, upper_f: String,
		inplace: bool, lean_deg: float, arm_gain: float, freeze_upper: bool,
		trim0: float = 0.0, trim1: float = 1.0, sweep: float = 0.0) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.step = 1.0 / FPS
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var rot_tracks := {}
	for i in _tskel.get_bone_count():
		var bt := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(bt, "Skeleton3D:" + _tskel.get_bone_name(i))
		anim.track_set_interpolation_type(bt, Animation.INTERPOLATION_LINEAR)
		rot_tracks[_tskel.get_bone_name(i)] = bt
	var pos_tr := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_tr, "Skeleton3D:Hips")
	anim.track_set_interpolation_type(pos_tr, Animation.INTERPOLATION_LINEAR)

	var hips_rest := _tskel.get_bone_rest(_tskel.find_bone("Hips")).origin
	var n := int(round(length * FPS))
	var first := {}
	var hips: Array = []

	for k in n:
		var ph := float(k) / float(n)
		var src_ph: float = trim0 + ph * (trim1 - trim0)
		var pu: float = 0.0 if freeze_upper else src_ph
		var sw: float = sweep * (ph * 2.0 - 1.0) if absf(sweep) > 0.001 else 0.0
		var f := _build_frame(lower_f, upper_f, src_ph, pu, lean_deg, arm_gain, sw)
		if name == "attack_blade":
			# 剑身对齐前臂（握持的正确方向），首尾 4 帧淡入淡出避免跳变
			var want_local: Vector3 = (f.rhand.inverse() * f.arm_dir).normalized()
			var full := Quaternion(Vector3(0, 0, 1), want_local)
			var fade := 1.0
			var fi := 4.0
			if float(k) < fi:
				fade = float(k) / fi
			if float(n - 1 - k) < fi:
				fade = float(n - 1 - k) / fi
			f.rot["socket_weapon.R"] = Quaternion.IDENTITY.slerp(full, clampf(fade, 0.0, 1.0))
		if k == 0:
			first = f.rot.duplicate()
		for bn in rot_tracks:
			anim.rotation_track_insert_key(rot_tracks[bn], float(k) / FPS, f.rot.get(bn, Quaternion.IDENTITY))
		hips.append(f.hips)

	if name == "attack_blade" or name == "strafe":
		# 攻击只保留 30% 前冲（角色本身不位移）；strafe 抬 2cm 避免脚尖入地
		var keep := 0.3 if name == "attack_blade" else 1.0
		for k in hips.size():
			hips[k] = Vector3(hips[k].x * keep, hips[k].y + (0.02 if name == "strafe" else 0.0), hips[k].z * keep)
	if inplace and hips.size() > 1:
		var drift := Vector3(hips[hips.size() - 1].x - hips[0].x, 0.0, hips[hips.size() - 1].z - hips[0].z)
		for k in hips.size():
			hips[k] -= drift * (float(k) / float(hips.size() - 1))

	for k in n:
		anim.position_track_insert_key(pos_tr, float(k) / FPS, hips_rest + hips[k] * HIPS_SCALE)
	if loop:
		for bn in rot_tracks:
			anim.rotation_track_insert_key(rot_tracks[bn], length, first.get(bn, Quaternion.IDENTITY))
		anim.position_track_insert_key(pos_tr, length, hips_rest + hips[0] * HIPS_SCALE)
	print("  clip %-13s len=%.2f frames=%d loop=%s" % [name, length, n, str(loop)])
	return anim
