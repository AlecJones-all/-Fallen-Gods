extends SceneTree

# 动作包验收：只读 dist/anim_pack_v1/rogue_knight_anims.tres，不需要游戏场景。
# 用法: godot --headless --path . --script res://tools/verify_anim_pack.gd
# 产出: res://dist/anim_pack_v1/verify.txt（通过/失败逐项记录），失败时退出码 1

const LIB_PATH := "res://dist/anim_pack_v1/rogue_knight_anims.tres"
const OUT_TXT := "res://dist/anim_pack_v1/verify.txt"
const FPS := 30.0
const FRAME := 1.0 / FPS
const RIG_BONES := 36          # 22 映射 + root + socket_weapon.R + 12 裙摆链
const HOLD_CLIPS := ["charge_hold_blade", "charge_hold_axe"]
const LOOP_CLIPS := ["idle", "walk", "run", "strafe", "aim_xbow", "aim_walk",
	"charge_hold_blade", "charge_hold_axe"]
## 原有片段：death 是倒地，本来就要向后滑 1.07m（v2 场景里就是这样），不算缺陷
const DRIFT_EXEMPT := ["death"]
## 衔接对：from 的末帧 → to 的首帧 必须几乎相同，否则游戏里切片段会跳姿势
const LINKS := [
	["charge_hold_blade", "attack_blade"],
	["charge_hold_axe", "attack_axe"],
	["equip_shared", "charge_hold_blade"],
]
const SPEC := {
	"idle": 1.20, "walk": 1.10, "run": 0.70, "strafe": 1.00,
	"attack_blade": 0.60, "fire_xbow": 0.70, "aim_xbow": 1.00,
	"hit": 1.33, "death": 3.03, "aim_walk": 1.10,
	"charge_hold_blade": 0.40, "charge_hold_axe": 0.60, "attack_axe": 0.65,
	"attack_axe_heavy": 1.05, "attack_axe_leap": 1.10,
	"equip_shared": 0.35, "reload_xbow": 0.50, "hit_head": 1.43, "roll": 0.48,
}

var _lines: Array[String] = []
var _fails := 0


func _init() -> void:
	_say("动作包验收  %s" % Time.get_datetime_string_from_system())
	_say("库文件: %s" % LIB_PATH)

	var lib := ResourceLoader.load(LIB_PATH) as AnimationLibrary
	if lib == null:
		_fail("库加载失败（不是 AnimationLibrary 或文件损坏）")
		_finish()
		return
	_say("类型: AnimationLibrary  片段数: %d\n" % lib.get_animation_list().size())

	# 1) 段数与命名
	var got: Array = lib.get_animation_list()
	var missing: Array[String] = []
	for n in SPEC:
		if not lib.has_animation(n):
			missing.append(n)
	if missing.is_empty():
		_ok("%d 段齐全（与 spec 表逐项对应）" % SPEC.size())
	else:
		_fail("缺片段: %s" % ", ".join(missing))
	var extra: Array[String] = []
	for n in got:
		if not SPEC.has(n):
			extra.append(str(n))
	if extra.is_empty():
		_ok("无多余片段")
	else:
		_fail("多余片段: %s" % ", ".join(extra))

	# 2) 逐段检查
	_say("\n%-20s %7s %5s %6s %7s %8s %8s %9s" % ["片段", "时长", "循环", "轨数", "关键帧",
		"接缝°", "髋漂移", "髋振幅"])
	_say("-".repeat(76))
	for n in SPEC:
		if not lib.has_animation(n):
			continue
		_check_clip(str(n), lib.get_animation(str(n)))

	# 3) 衔接连续性：hold 末帧 → attack 首帧、equip 末帧 → hold 首帧
	_say("\n衔接连续性（同一骨骼最大角差，阈值 2.0°）")
	_say("-".repeat(76))
	for pair in LINKS:
		_check_link(lib, str(pair[0]), str(pair[1]))

	_finish()


func _check_link(lib: AnimationLibrary, from_clip: String, to_clip: String) -> void:
	if not lib.has_animation(from_clip) or not lib.has_animation(to_clip):
		_fail("%s → %s: 片段缺失" % [from_clip, to_clip])
		return
	var a := lib.get_animation(from_clip)
	var b := lib.get_animation(to_clip)
	var worst := 0.0
	var worst_bone := ""
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var path := str(a.track_get_path(ti))
		var ti2 := -1
		for t in b.get_track_count():
			if str(b.track_get_path(t)) == path and b.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				ti2 = t
				break
		if ti2 < 0:
			continue
		var ka := a.track_get_key_count(ti)
		var qa := Quaternion(a.track_get_key_value(ti, ka - 1))
		var qb := Quaternion(b.track_get_key_value(ti2, 0))
		var d := rad_to_deg(qa.angle_to(qb))
		if d > worst:
			worst = d
			worst_bone = path.get_slice(":", 1)
	if worst <= 2.0:
		_ok("%s → %s：最大 %.2f°（%s）" % [from_clip, to_clip, worst, worst_bone])
	else:
		_fail("%s → %s：最大 %.2f°（%s）超过 2.0°" % [from_clip, to_clip, worst, worst_bone])


func _check_clip(n: String, a: Animation) -> void:
	var want: float = SPEC[n]
	var len_ok := absf(a.length - want) <= FRAME + 1e-6
	var loop_ok := (a.loop_mode != Animation.LOOP_NONE) == LOOP_CLIPS.has(n)
	var tracks := a.get_track_count()
	var tracks_ok := tracks == RIG_BONES + 1
	var keys := 0
	var nan := false
	var seam := 0.0
	var drift := 0.0
	var hips_amp := 0.0
	var bad_paths: Array[String] = []

	for ti in tracks:
		var p := str(a.track_get_path(ti))
		if not p.begins_with("Skeleton3D:"):
			bad_paths.append(p)
		keys += a.track_get_key_count(ti)
		if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			var kc := a.track_get_key_count(ti)
			if kc > 0:
				var q0 := Quaternion(a.track_get_key_value(ti, 0))
				var ql := Quaternion(a.track_get_key_value(ti, kc - 1))
				if not _finite_q(q0) or not _finite_q(ql):
					nan = true
				if LOOP_CLIPS.has(n):
					seam = maxf(seam, rad_to_deg(q0.angle_to(ql)))
		elif a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			var kc := a.track_get_key_count(ti)
			if kc > 0:
				var p0 := Vector3(a.track_get_key_value(ti, 0))
				var pl := Vector3(a.track_get_key_value(ti, kc - 1))
				drift = Vector2(pl.x - p0.x, pl.z - p0.z).length()
				var lo := p0.y
				var hi := p0.y
				for k in kc:
					var v := Vector3(a.track_get_key_value(ti, k))
					if not _finite_v(v):
						nan = true
					lo = minf(lo, v.y)
					hi = maxf(hi, v.y)
				hips_amp = hi - lo

	_say("%-20s %7.2f %5s %6d %7d %8.3f %8.4f %9.4f" % [n, a.length,
		"是" if a.loop_mode != Animation.LOOP_NONE else "否", tracks, keys, seam, drift, hips_amp])

	var problems: Array[String] = []
	if not len_ok:
		problems.append("时长 %.3f≠%.2f" % [a.length, want])
	if not loop_ok:
		problems.append("循环标志错")
	if not tracks_ok:
		problems.append("轨数 %d≠%d" % [tracks, RIG_BONES + 1])
	if nan:
		problems.append("含 NaN/Inf")
	if not bad_paths.is_empty():
		problems.append("非法轨道路径 %d 条" % bad_paths.size())
	if LOOP_CLIPS.has(n) and seam > 0.5:
		problems.append("接缝 %.3f° > 0.5°" % seam)
	if HOLD_CLIPS.has(n):
		if drift > 0.002:
			problems.append("hold 水平漂移 %.4f > 0.002" % drift)
		if hips_amp > 0.05:
			problems.append("hold 髋振幅 %.4f 过大" % hips_amp)
	elif drift > 0.05 and not DRIFT_EXEMPT.has(n):
		problems.append("水平位移 %.4f > 0.05" % drift)

	if problems.is_empty():
		_ok("%s 通过" % n)
	else:
		_fail("%s: %s" % [n, " / ".join(problems)])


func _finite_q(q: Quaternion) -> bool:
	return is_finite(q.x) and is_finite(q.y) and is_finite(q.z) and is_finite(q.w)


func _finite_v(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _say(s: String) -> void:
	print(s)
	_lines.append(s)


func _ok(s: String) -> void:
	_say("  ✓ " + s)


func _fail(s: String) -> void:
	_fails += 1
	_say("  ✗ " + s)


func _finish() -> void:
	_say("")
	if _fails == 0:
		_say("结果: 全部通过")
	else:
		_say("结果: %d 项失败" % _fails)
	var f := FileAccess.open(OUT_TXT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
		print("写入 ", OUT_TXT)
	quit(0 if _fails == 0 else 1)
