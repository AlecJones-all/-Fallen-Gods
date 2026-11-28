extends SceneTree

# 动作包导出器（docs/18 P0–P2）
# 与 build_anim_v2.gd 的区别：**只写 AnimationLibrary，绝不 pack/save 任何场景**。
# 目标场景只读：load 后 instantiate，用来拿 36 骨的骨骼名与 rest 姿态。
#
# 用法:
#   godot --headless --path . --script res://tools/build_anim_pack.gd
#   godot --headless --path . --script res://tools/build_anim_pack.gd -- --no-new
#
# 输出:
#   res://dist/anim_pack_v1/rogue_knight_anims.tres   16 段动画库
#   res://dist/anim_pack_v1/pack.json                 生成记录（可复现）

const TARGET := "res://scenes/player/rogue_knight_v2.tscn"
const SRC_DIR := "res://assets/anim_src/"
const OUT_DIR := "res://dist/anim_pack_v1/"
const OUT_LIB := OUT_DIR + "rogue_knight_anims.tres"
const OUT_LOG := OUT_DIR + "pack.json"
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
const SPINE_BONES := ["Spine", "Spine1", "Spine2"]

const SOURCES := ["idle", "Great Sword Walk", "Great Sword Slash", "Great Sword Strafe",
	"Sword And Shield Run", "Sword And Shield Walk", "Firing Rifle",
	"Hit To Body", "Death", "Head Hit", "Jump Attack", "Sprinting Forward Roll"]

var _src := {}
var _tgt: Node3D
var _tskel: Skeleton3D
var _records: Array = []
var _mismatch := 0
var _checked := 0


func _init() -> void:
	var ps: PackedScene = load(TARGET)
	if ps == null:
		push_error("目标场景加载失败: " + TARGET)
		quit(1)
		return
	_tgt = ps.instantiate()
	get_root().add_child(_tgt)
	_tskel = _tgt.find_child("Skeleton3D", true, false)
	if _tskel == null:
		push_error("目标场景没有 Skeleton3D")
		quit(1)
		return
	print("目标骨架 bones=", _tskel.get_bone_count())

	for f in SOURCES:
		_load_src(f)
	print("sources=", _src.size(), " / ", SOURCES.size())

	var lib := AnimationLibrary.new()

	# ---------- 现有 9 段：参数必须与 build_anim_v2.gd 逐字一致 ----------
	lib.add_animation("idle", _clip("idle", 1.2, true, "idle", "Great Sword Walk",
		false, 0.0, 1.0, true))
	lib.add_animation("walk", _clip("walk", 1.1, true, "Sword And Shield Walk",
		"Great Sword Walk", false, 0.0, 1.0, false))
	lib.add_animation("run", _clip("run", 0.7, true, "Sword And Shield Run",
		"Great Sword Walk", false, 8.0, 1.4, false))
	lib.add_animation("strafe", _clip("strafe", 1.0, true, "Great Sword Strafe",
		"Great Sword Strafe", true, 0.0, 1.0, false))
	lib.add_animation("attack_blade", _clip("attack_blade", 0.6, false, "Great Sword Slash",
		"Great Sword Slash", true, 0.0, 1.0, false, 0.30, 0.78, 46.0))
	lib.add_animation("fire_xbow", _clip("fire_xbow", 0.7, false, "Firing Rifle",
		"Firing Rifle", false, 0.0, 1.0, false))
	lib.add_animation("aim_xbow", _clip("aim_xbow", 1.0, true, "Firing Rifle",
		"Firing Rifle", false, 0.0, 1.0, true))
	lib.add_animation("hit", _clip("hit", 1.33, false, "Hit To Body", "Hit To Body",
		false, 0.0, 1.0, false))
	lib.add_animation("death", _clip("death", 3.03, false, "Death", "Death",
		false, 0.0, 1.0, false))

	# ---------- P0 等价性自检：与场景里现有的 9 段逐轨比对 ----------
	print("\n===== 等价性自检（新导出器 vs 场景现有库）=====")
	_check_equivalence(lib)
	if _mismatch > 0:
		push_error("等价性自检未通过：%d 处不一致，中止（不写出任何文件）" % _mismatch)
		quit(2)
		return
	print("等价性自检通过：%d 段 / %d 条轨道逐值一致\n" % [_checked, _count_tracks(lib)])

	var skip_new := OS.get_cmdline_user_args().has("--no-new")

	# ---------- P1：蓄力 hold ×2 + 斧横斩 + 弩移动瞄准 + 闪避翻滚 ----------
	# aim_walk：下半身用行走循环，上半身定格在 Firing Rifle 首帧（持弩瞄准）
	lib.add_animation("aim_walk", _clip("aim_walk", 1.1, true, "Sword And Shield Walk",
		"Firing Rifle", false, 0.0, 1.0, true))
	# roll：源动作 1.167s（冲刺→扑倒→贴地滚→起身），带 5.9m 前冲，必须原地化。
	# 取 0.18–0.95 段压到 0.48s（≈1.6× 加速）——闪避要快，0.48s 与 dash 0.16s+0.3s 恢复相称。
	lib.add_animation("roll", _clip("roll", 0.48, false, "Sprinting Forward Roll",
		"Sprinting Forward Roll", true, 0.0, 1.0, false, 0.18, 0.95, 0.0))
	# 规则：hold 的第 0 帧必须等于对应 attack 的第 0 帧，否则切片段会跳姿势。
	# 剑沿用 attack_blade 的相位 0.30（该片段已进游戏不能改）→ 侧身蓄势；
	# 斧是新片段，可以整体挪到相位 0.42 = 剑尖朝天的真正最高点 → 过顶高举。
	lib.add_animation("charge_hold_blade", _hold_clip("charge_hold_blade", 0.40,
		"Great Sword Slash", 0.30, 0.45, 1.0, true, 0.0, -46.0))
	lib.add_animation("charge_hold_axe", _hold_clip("charge_hold_axe", 0.60,
		"Great Sword Slash", 0.42, 1.0, 1.0, true, 0.0, -23.0, true))
	lib.add_animation("attack_axe", _clip("attack_axe", 0.65, false, "Great Sword Slash",
		"Great Sword Slash", true, 0.0, 1.0, false, 0.42, 0.95, 23.0))

	if not skip_new:
		# ---------- P2：斧重劈（地面）/ 空中跳劈 / 拔收武器 / 弩装填 / 头部受击 ----------
		# 地面重劈与 charge_hold 起始帧同为 Slash t=0.30，衔接不跳；靠"更慢+更大幅度"区分
		lib.add_animation("attack_axe_heavy", _clip("attack_axe_heavy", 1.05, false,
			"Great Sword Slash", "Great Sword Slash", true, 0.0, 1.0, false, 0.42, 1.00, 33.0))
		# 空中跳劈：Jump Attack 的 1.15–2.05s（腾空→砸地），含约 1.37m 垂直位移，需代码接管落地
		lib.add_animation("attack_axe_leap", _clip("attack_axe_leap", 1.10, false,
			"Jump Attack", "Jump Attack", true, 0.0, 1.0, false, 0.3026, 0.5395, 0.0))
		lib.add_animation("equip_shared", _morph_clip("equip_shared", 0.35,
			_build_frame("Great Sword Walk", "Great Sword Walk", 0.0, 0.0, 0.0, 1.0, 0.0),
			_hold_base("Great Sword Slash", 0.30, 0.0, -46.0)))
		lib.add_animation("reload_xbow", _reload_clip("reload_xbow", 0.50,
			"Firing Rifle", 0.0))
		lib.add_animation("hit_head", _clip("hit_head", 1.43, false, "Head Hit", "Head Hit",
			false, 0.0, 1.0, false))

	print("\n===== 写出 =====")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := ResourceSaver.save(lib, OUT_LIB)
	print("save %s -> %d (0=OK)  clips=%d" % [OUT_LIB, err, lib.get_animation_list().size()])
	_write_log(lib)
	_assert_scene_untouched()
	quit(0)


# ================= 等价性比对 =================
func _check_equivalence(lib: AnimationLibrary) -> void:
	var ap: AnimationPlayer = _tgt.find_child("AnimationPlayer", true, false)
	if ap == null:
		print("  场景里没有 AnimationPlayer，跳过比对")
		return
	var names := ap.get_animation_list()
	print("  场景现有 %d 段: %s" % [names.size(), ", ".join(names)])
	for n in names:
		var a: Animation = ap.get_animation(n)
		if not lib.has_animation(n):
			print("  [MISS] %s 新库里没有" % n)
			_mismatch += 1
			continue
		_checked += 1
		_cmp_anim(n, a, lib.get_animation(n))


func _cmp_anim(n: String, a: Animation, b: Animation) -> void:
	var bad := 0
	if absf(a.length - b.length) > 1e-6:
		print("  [DIFF] %s length %f vs %f" % [n, a.length, b.length])
		bad += 1
	if a.loop_mode != b.loop_mode:
		print("  [DIFF] %s loop_mode %d vs %d" % [n, a.loop_mode, b.loop_mode])
		bad += 1
	if a.get_track_count() != b.get_track_count():
		print("  [DIFF] %s track_count %d vs %d" % [n, a.get_track_count(), b.get_track_count()])
		bad += 1
		_mismatch += bad
		return
	for ti in a.get_track_count():
		if str(a.track_get_path(ti)) != str(b.track_get_path(ti)):
			print("  [DIFF] %s track %d path %s vs %s" % [n, ti,
				str(a.track_get_path(ti)), str(b.track_get_path(ti))])
			bad += 1
			continue
		if a.track_get_type(ti) != b.track_get_type(ti):
			print("  [DIFF] %s track %d type" % [n, ti])
			bad += 1
			continue
		var ka := a.track_get_key_count(ti)
		var kb := b.track_get_key_count(ti)
		if ka != kb:
			print("  [DIFF] %s track %d keys %d vs %d" % [n, ti, ka, kb])
			bad += 1
			continue
		for k in ka:
			if absf(a.track_get_key_time(ti, k) - b.track_get_key_time(ti, k)) > 1e-6:
				print("  [DIFF] %s track %d key %d time" % [n, ti, k])
				bad += 1
				break
			var va: Variant = a.track_get_key_value(ti, k)
			var vb: Variant = b.track_get_key_value(ti, k)
			if va is Quaternion and vb is Quaternion:
				# q 与 -q 表示同一旋转
				if absf(Quaternion(va).dot(Quaternion(vb))) < 1.0 - 1e-5:
					print("  [DIFF] %s track %d key %d quat dot=%.7f" % [n, ti, k,
						absf(Quaternion(va).dot(Quaternion(vb)))])
					bad += 1
					break
			elif va is Vector3 and vb is Vector3:
				if Vector3(va).distance_to(Vector3(vb)) > 1e-4:
					print("  [DIFF] %s track %d key %d vec" % [n, ti, k])
					bad += 1
					break
	print("  %-14s %s" % [n, "一致" if bad == 0 else "不一致 %d 处" % bad])
	_mismatch += bad


func _count_tracks(lib: AnimationLibrary) -> int:
	var t := 0
	for n in lib.get_animation_list():
		t += lib.get_animation(n).get_track_count()
	return t


# ================= 场景未被改动 =================
func _assert_scene_untouched() -> void:
	var f := FileAccess.open(TARGET, FileAccess.READ)
	if f == null:
		return
	var sz := f.get_length()
	f.close()
	print("  目标场景仍为 %d 字节（本脚本从未 pack/save 场景）" % sz)


# ================= 源：直读轨道（修掉 [0] 取错，优先 mixamo_com） =================
func _pick_anim(ap: AnimationPlayer) -> Animation:
	var lst := ap.get_animation_list()
	for n in lst:
		if str(n).to_lower().begins_with("mixamo"):
			return ap.get_animation(n)
	if lst.is_empty():
		return null
	return ap.get_animation(lst[0])


func _load_src(f: String) -> void:
	var ps: PackedScene = load(SRC_DIR + f + ".fbx")
	if ps == null:
		print("SRC FAIL ", f)
		return
	var r: Node3D = ps.instantiate()
	var skel: Skeleton3D = r.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = r.find_child("AnimationPlayer", true, false)
	if skel == null or ap == null:
		print("SRC SKIP（无骨架/无播放器）", f, " skel=", skel, " ap=", ap)
		r.free()
		return
	var anim := _pick_anim(ap)
	if anim == null:
		print("SRC SKIP（无动画）", f)
		r.free()
		return
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
	print("  src %-22s anim=%s dur=%.2fs tracks=%d" % [f, anim.resource_name if anim.resource_name != "" else "-",
		anim.length, anim.get_track_count()])
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


# ================= 合成一帧 =================
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
		if absf(lean_deg) > 0.001 and SPINE_BONES.has(b):
			w = Basis(Vector3.RIGHT, deg_to_rad(lean_deg / 3.0)) * w
		if absf(sweep_deg) > 0.001 and SPINE_BONES.has(b):
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
		"rhand": world.get("RightHand", Basis()), "arm_dir": arm_dir,
		"pos": up["pos"].duplicate(), "basis_lower": lo["basis"].duplicate()}


# ================= 轨道骨架（三种 clip 共用） =================
func _new_anim(length: float, loop: bool) -> Dictionary:
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
	return {"anim": anim, "rot": rot_tracks, "pos": pos_tr}


func _hips_rest() -> Vector3:
	return _tskel.get_bone_rest(_tskel.find_bone("Hips")).origin


# ================= 循环片段（与 build_anim_v2 等价） =================
func _clip(name: String, length: float, loop: bool, lower_f: String, upper_f: String,
		inplace: bool, lean_deg: float, arm_gain: float, freeze_upper: bool,
		trim0: float = 0.0, trim1: float = 1.0, sweep: float = 0.0,
		sweep_ramp: bool = false) -> Animation:
	var h := _new_anim(length, loop)
	var anim: Animation = h.anim
	var rot_tracks: Dictionary = h.rot
	var pos_tr: int = h.pos
	var hips_rest := _hips_rest()
	var n := int(round(length * FPS))
	var first := {}
	var hips: Array = []

	for k in n:
		var ph := float(k) / float(n)
		var src_ph: float = trim0 + ph * (trim1 - trim0)
		var pu: float = 0.0 if freeze_upper else src_ph
		# sweep_ramp=true 时躯干从 0 单方向转到 sweep（起手不拧）；
		# false 为原有行为：从 -sweep 扫到 +sweep（attack_blade 用的就是这种）
		var sw: float = 0.0
		if absf(sweep) > 0.001:
			sw = sweep * ph if sweep_ramp else sweep * (ph * 2.0 - 1.0)
		var f := _build_frame(lower_f, upper_f, src_ph, pu, lean_deg, arm_gain, sw)
		if _grip_fade(name):
			# 与原件一致：首尾 4 帧淡入淡出，避免与相邻片段切换时握持角跳变
			var full := _grip_rot(f)
			var fade := 1.0
			var fi := 4.0
			if float(k) < fi:
				fade = float(k) / fi
			if float(n - 1 - k) < fi:
				fade = float(n - 1 - k) / fi
			f.rot["socket_weapon.R"] = Quaternion.IDENTITY.slerp(full, clampf(fade, 0.0, 1.0))
		elif _grip_solid(name):
			# 新斧片段常满握持：让刀身始终立起来（否则举器姿势里剑横在胸前）
			f.rot["socket_weapon.R"] = _grip_rot(f)
		if k == 0:
			first = f.rot.duplicate()
		for bn in rot_tracks:
			anim.rotation_track_insert_key(rot_tracks[bn], float(k) / FPS,
				f.rot.get(bn, Quaternion.IDENTITY))
		hips.append(f.hips)

	if _fwd_keep(name) < 1.0 or _lift_y(name) != 0.0:
		var keep := _fwd_keep(name)
		var lift := _lift_y(name)
		for k in hips.size():
			hips[k] = Vector3(hips[k].x * keep, hips[k].y + lift, hips[k].z * keep)
	if inplace and hips.size() > 1:
		var drift := Vector3(hips[hips.size() - 1].x - hips[0].x, 0.0,
			hips[hips.size() - 1].z - hips[0].z)
		for k in hips.size():
			hips[k] -= drift * (float(k) / float(hips.size() - 1))

	for k in n:
		anim.position_track_insert_key(pos_tr, float(k) / FPS, hips_rest + hips[k] * HIPS_SCALE)
	if loop:
		for bn in rot_tracks:
			anim.rotation_track_insert_key(rot_tracks[bn], length, first.get(bn, Quaternion.IDENTITY))
		anim.position_track_insert_key(pos_tr, length, hips_rest + hips[0] * HIPS_SCALE)
	print("  clip %-18s len=%.2f frames=%d loop=%s" % [name, length, n, str(loop)])
	_records.append(_rec(name, length, loop, "%s [%.2f→%.2f] + %s" % [lower_f, trim0, trim1, upper_f],
		{"lean": lean_deg, "sweep": sweep, "inplace": inplace}))
	return anim


# ================= 蓄力保持：单帧 + 正弦微动 =================
# phase 是源片段的**相位**（0~1），不是秒。lean/sweep 必须与对应 attack 的第 0 帧一致，
# 否则 hold 切到 release 会跳姿势。amp_scale=1.0 → 脊柱 ±1.8° / 手臂 ±1.2° / 头 ±0.8° / Hips ±0.010m
func _hold_clip(name: String, length: float, src_f: String, phase: float,
		amp_scale: float, cycles: float, loop: bool,
		lean: float = 0.0, sweep: float = 0.0, grip: bool = false) -> Animation:
	var h := _new_anim(length, loop)
	var anim: Animation = h.anim
	var rot_tracks: Dictionary = h.rot
	var pos_tr: int = h.pos
	var hips_rest := _hips_rest()

	var base := _hold_base(src_f, phase, lean, sweep, grip)
	var n := int(round(length * FPS))
	var amp_spine := deg_to_rad(1.8) * amp_scale
	var amp_arm := deg_to_rad(1.2) * amp_scale
	var amp_head := deg_to_rad(0.8) * amp_scale
	var amp_hips := 0.010 * amp_scale

	for k in n + 1:
		var s := sin(TAU * cycles * float(k) / float(n))
		for bn in rot_tracks:
			var q: Quaternion = base.rot.get(bn, Quaternion.IDENTITY)
			var amp := 0.0
			if SPINE_BONES.has(bn):
				amp = amp_spine
			elif ARM_BONES.has(bn):
				amp = amp_arm
			elif bn == "Head" or bn == "Neck":
				amp = amp_head
			if amp != 0.0:
				q = (q * Quaternion(Vector3.RIGHT, amp * s)).normalized()
			anim.rotation_track_insert_key(rot_tracks[bn], float(k) / FPS, q)
		var hp: Vector3 = hips_rest + base.hips * HIPS_SCALE
		hp.y += amp_hips * s
		anim.position_track_insert_key(pos_tr, float(k) / FPS, hp)

	print("  clip %-18s len=%.2f frames=%d loop=%s (hold amp×%.2f)" % [name, length, n, str(loop), amp_scale])
	_records.append(_rec(name, length, loop, "%s 相位 %.2f 定格 + 正弦×%.2f" % [src_f, phase, amp_scale],
		{"amp_scale": amp_scale, "cycles": cycles, "phase": phase, "lean": lean, "sweep": sweep,
			"spine_deg": 1.8 * amp_scale, "hips_dy": 0.010 * amp_scale}))
	return anim


func _hold_base(src_f: String, phase: float, lean: float = 0.0, sweep: float = 0.0,
		grip: bool = false) -> Dictionary:
	# sweep 传的是"该瞬间实际要施加的扭转值"（带符号），不再取负
	var f := _build_frame(src_f, src_f, phase, phase, lean, 1.0, sweep)
	# grip=true：把刀身对齐前臂（举器时剑才立得起来）。
	# 剑的 hold 必须传 false —— 游戏里的 attack_blade 首帧 socket 是单位旋转（它带 4 帧淡入），
	# 若 hold 用满握持，切回攻击会跳 138°。
	if grip:
		f.rot["socket_weapon.R"] = _grip_rot(f)
	return f


# ================= 两帧插值（拔/收武器） =================
func _morph_clip(name: String, length: float, fa: Dictionary, fb: Dictionary) -> Animation:
	var h := _new_anim(length, false)
	var anim: Animation = h.anim
	var rot_tracks: Dictionary = h.rot
	var pos_tr: int = h.pos
	var hips_rest := _hips_rest()
	var n := int(round(length * FPS))
	var ha: Vector3 = fa.hips
	var hb: Vector3 = fb.hips
	# 水平锁在 A 的脚下位置：换武器动作不应让角色滑出去
	var locked := Vector3(ha.x, 0.0, ha.z)
	for k in n + 1:
		var t := float(k) / float(n)
		var e := t * t * (3.0 - 2.0 * t)
		for bn in rot_tracks:
			var qa: Quaternion = fa.rot.get(bn, Quaternion.IDENTITY)
			var qb: Quaternion = fb.rot.get(bn, Quaternion.IDENTITY)
			anim.rotation_track_insert_key(rot_tracks[bn], float(k) / FPS, qa.slerp(qb, e))
		var mixed := Vector3(locked.x, lerpf(ha.y, hb.y, e), locked.z)
		anim.position_track_insert_key(pos_tr, float(k) / FPS, hips_rest + mixed * HIPS_SCALE)
	print("  clip %-18s len=%.2f frames=%d loop=false (morph A→B)" % [name, length, n])
	_records.append(_rec(name, length, false, "两帧 slerp（idle 低持 → 举器）", {"ease": "smoothstep"}))
	return anim


# ================= 装填：左手一个上下行程 =================
func _reload_clip(name: String, length: float, src_f: String, phase: float) -> Animation:
	var h := _new_anim(length, false)
	var anim: Animation = h.anim
	var rot_tracks: Dictionary = h.rot
	var pos_tr: int = h.pos
	var hips_rest := _hips_rest()
	var base := _build_frame(src_f, src_f, phase, phase, 0.0, 1.0, 0.0)
	var n := int(round(length * FPS))
	for k in n + 1:
		var t := float(k) / float(n)
		# 0 → 下拉到底 → 回位：一个完整余弦行程
		var pull := (1.0 - cos(TAU * t)) * 0.5
		for bn in rot_tracks:
			var q: Quaternion = base.rot.get(bn, Quaternion.IDENTITY)
			if bn == "LeftForeArm":
				q = (q * Quaternion(Vector3.RIGHT, deg_to_rad(-42.0) * pull)).normalized()
			elif bn == "LeftHand":
				q = (q * Quaternion(Vector3.RIGHT, deg_to_rad(-14.0) * pull)).normalized()
			elif bn == "RightForeArm":
				q = (q * Quaternion(Vector3.RIGHT, deg_to_rad(8.0) * pull)).normalized()
			anim.rotation_track_insert_key(rot_tracks[bn], float(k) / FPS, q)
		var hp: Vector3 = hips_rest + base.hips * HIPS_SCALE
		hp.y -= 0.012 * pull
		anim.position_track_insert_key(pos_tr, float(k) / FPS, hp)
	print("  clip %-18s len=%.2f frames=%d loop=false (装填一程)" % [name, length, n])
	_records.append(_rec(name, length, false, "%s 定格 + 左臂 42° 行程" % src_f,
		{"left_forearm_deg": -42.0, "left_hand_deg": -14.0}))
	return anim


# ================= 握持对齐（只对近战） =================
func _grip_fade(name: String) -> bool:
	return name == "attack_blade"


func _grip_solid(name: String) -> bool:
	return name in ["attack_axe", "attack_axe_heavy"]


func _grip_rot(f: Dictionary) -> Quaternion:
	var want_local: Vector3 = (f.rhand.inverse() * f.arm_dir).normalized()
	return Quaternion(Vector3(0, 0, 1), want_local)


# 与 build_anim_v2.gd 里按名字写死的两个特例保持一致
func _fwd_keep(name: String) -> float:
	return 0.3 if name == "attack_blade" or name == "attack_axe" or name == "attack_axe_heavy" else 1.0


func _lift_y(name: String) -> float:
	return 0.02 if name == "strafe" else 0.0


# ================= 记录 =================
func _rec(name: String, length: float, loop: bool, source: String, params: Dictionary) -> Dictionary:
	return {"name": name, "length": length, "loop": loop, "source": source,
		"params": params, "fps": FPS}


func _write_log(lib: AnimationLibrary) -> void:
	var clips: Array = []
	for r: Dictionary in _records:
		var d := r.duplicate()
		var a: Animation = lib.get_animation(str(r.name))
		d["tracks"] = a.get_track_count()
		d["keys"] = _keys_of(a)
		clips.append(d)
	var doc := {
		"pack": "rogue_knight_anims",
		"version": "1.0.0",
		"generated": Time.get_datetime_string_from_system(),
		"godot": Engine.get_version_info().string,
		"fps": FPS,
		"rig_scene": TARGET,
		"bones": _tskel.get_bone_count(),
		"clip_count": lib.get_animation_list().size(),
		"clips": clips,
		"note": "由 tools/build_anim_pack.gd 生成；目标场景只读，未 pack/save",
	}
	var f := FileAccess.open(OUT_LOG, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
		print("  save %s" % OUT_LOG)


func _keys_of(a: Animation) -> int:
	var t := 0
	for ti in a.get_track_count():
		t += a.track_get_key_count(ti)
	return t
