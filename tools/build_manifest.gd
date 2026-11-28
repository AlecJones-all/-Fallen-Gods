extends SceneTree

# 由 .tres + pack.json 生成 manifest.json（数值全部现算，不手抄）
# 用法: godot --headless --path . --script res://tools/build_manifest.gd

const LIB_PATH := "res://dist/anim_pack_v1/rogue_knight_anims.tres"
const PACK_JSON := "res://dist/anim_pack_v1/pack.json"
const OUT := "res://dist/anim_pack_v1/manifest.json"

const ROLES := {
	"idle": "待机（下身 idle + 上身持大剑定格）",
	"walk": "行走",
	"run": "奔跑",
	"strafe": "侧向移动（已原地化，抬 2cm 防入地）",
	"attack_blade": "长剑横砍（裁前摇 + 46° 躯干横扫）",
	"fire_xbow": "连弩射击",
	"aim_xbow": "连弩瞄准/持弩待机（首帧定格）",
	"aim_walk": "连弩移动瞄准（下半身行走 + 上半身持弩定格）",
	"hit": "躯干受击",
	"hit_head": "头部受击（本次新接入，此前文件在手未进库）",
	"death": "死亡",
	"charge_hold_blade": "剑蓄力保持（0.40s 循环，微动幅度 ×0.45）",
	"charge_hold_axe": "斧蓄力保持（0.60s 循环，满幅微动）",
	"attack_axe": "斧横斩 / 蓄力释放（0.65s，起手过顶，躯干行程 46°）",
	"attack_axe_heavy": "斧地面重劈（1.05s，起手过顶，躯干行程 66°，无腾空）",
	"attack_axe_leap": "斧空中跳劈（含垂直位移，需代码接管落地）",
	"equip_shared": "拔/收武器（低持 → 举器，三武器共用）",
	"reload_xbow": "连弩装填（左手 42° 一个行程）",
	"roll": "闪避翻滚（源 1.167s 取 0.18–0.95 压到 0.48s，原地化，配 dash 0.16s/16m/s）",
}
const ORIGINAL := ["idle", "walk", "run", "strafe", "attack_blade", "fire_xbow",
	"aim_xbow", "hit", "death"]

const KNOWN_ISSUES := [
	{"clip": "attack_blade", "issue": "clip 0.60s vs 逻辑 0.42s（0.035+0.09+0.295）",
		"impact": "动作比判定长 0.18s", "fix_when": "接入时统一（docs/17 P1）"},
	{"clip": "death", "issue": "髋部向后位移 1.07m（倒地动作本身带位移）",
		"impact": "尸体相对原点后滑", "fix_when": "如需原地死亡再做 inplace 版"},
	{"clip": "attack_axe_leap", "issue": "hips 垂直位移约 1.37m（源动作是空中跳劈）",
		"impact": "播放期间角色会离地", "fix_when": "播放时关重力 / 由根运动接管"},
	{"clip": "attack_axe", "issue": "斧模型尚未接入（docs/17 P3）",
		"impact": "目前只能挂在大剑位置看动作", "fix_when": "Axe_LP 对轴后"},
]


func _init() -> void:
	var lib := ResourceLoader.load(LIB_PATH) as AnimationLibrary
	if lib == null:
		push_error("加载失败: " + LIB_PATH)
		quit(1)
		return
	var meta: Dictionary = {}
	var txt := FileAccess.get_file_as_string(PACK_JSON)
	if not txt.is_empty():
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			meta = parsed
	var by_name := {}
	for r: Dictionary in meta.get("clips", []):
		by_name[str(r.get("name", ""))] = r

	var clips: Array = []
	for n in lib.get_animation_list():
		var a: Animation = lib.get_animation(str(n))
		var m: Dictionary = by_name.get(str(n), {})
		var c := {
			"name": str(n),
			"status": "original" if ORIGINAL.has(str(n)) else "new",
			"role": ROLES.get(str(n), ""),
			"length": snappedf(a.length, 0.001),
			"loop": a.loop_mode != Animation.LOOP_NONE,
			"tracks": a.get_track_count(),
			"keys": _keys(a),
			"source": str(m.get("source", "")),
			"params": m.get("params", {}),
			"verified": _verify_clip(str(n), a),
		}
		clips.append(c)

	var doc := {
		"pack": "rogue_knight_anims",
		"version": "1.0.0",
		"created": Time.get_datetime_string_from_system(),
		"generator": "tools/build_anim_pack.gd",
		"verifier": "tools/verify_anim_pack.gd",
		"godot": Engine.get_version_info().string,
		"fps": 30,
		"rig": {
			"authority": "tools/build_rig_v2.gd",
			"bones": 36,
			"mapped_bones": 22,
			"root_node_expected": "..",
			"socket": "socket_weapon.R",
			"note": "轨道路径为 Skeleton3D:<骨名>，目标骨架骨名必须与 build_rig_v2.gd 产出一致",
		},
		"clip_count": clips.size(),
		"clips": clips,
		"known_issues": KNOWN_ISSUES,
		"licenses": {
			"animation_source": "Mixamo（Adobe，免费可商用；原始 FBX 不再分发，仅本人项目内使用）",
			"character_mesh": "Rogue Knight — Tramicful — CC BY 4.0 — https://sketchfab.com/3d-models/rogue-knight-555f434d1aa44443b2f23c6088fd713b",
			"axe_mesh": "bulky-knight 包内 Axe_LP（未包含在本包中）",
		},
		"redistribution": "本包只含派生的骨骼旋转曲线，不含任何第三方原始 FBX。",
	}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("写不了 " + OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("manifest 写出: ", OUT, "  片段=", clips.size())
	quit(0)


func _keys(a: Animation) -> int:
	var t := 0
	for ti in a.get_track_count():
		t += a.track_get_key_count(ti)
	return t


func _verify_clip(n: String, a: Animation) -> Dictionary:
	var seam := 0.0
	var drift := 0.0
	var hips_amp := 0.0
	var nan := false
	var looping := a.loop_mode != Animation.LOOP_NONE
	for ti in a.get_track_count():
		var kc := a.track_get_key_count(ti)
		if kc == 0:
			continue
		if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			var q0 := Quaternion(a.track_get_key_value(ti, 0))
			var ql := Quaternion(a.track_get_key_value(ti, kc - 1))
			for qi in [q0, ql]:
				if not (is_finite(qi.x) and is_finite(qi.y) and is_finite(qi.z) and is_finite(qi.w)):
					nan = true
			if looping:
				seam = maxf(seam, rad_to_deg(q0.angle_to(ql)))
		elif a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
			var p0 := Vector3(a.track_get_key_value(ti, 0))
			var pl := Vector3(a.track_get_key_value(ti, kc - 1))
			drift = Vector2(pl.x - p0.x, pl.z - p0.z).length()
			var lo := p0.y
			var hi := p0.y
			for k in kc:
				var v := Vector3(a.track_get_key_value(ti, k))
				if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
					nan = true
				lo = minf(lo, v.y)
				hi = maxf(hi, v.y)
			hips_amp = hi - lo
	return {"seam_deg": snappedf(seam, 0.001), "hips_drift_m": snappedf(drift, 0.001),
		"hips_amp_m": snappedf(hips_amp, 0.001), "nan": nan}
