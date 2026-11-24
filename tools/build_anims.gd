extends SceneTree

# 给 rigged 场景生成动画库（idle/walk/run/attack）
# 用法: godot --headless --path . --script res://tools/build_anims.gd

const SCENE := "res://scenes/player/rogue_knight_rigged.tscn"
const FPS := 30.0

var _skel: Skeleton3D
var _bones: Array = []          # 所有骨名
var _rest: Dictionary = {}      # 骨名 -> 局部静止位置
var _anim_player: AnimationPlayer


func _init() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("LOAD_FAIL")
		quit()
		return
	var root: Node3D = ps.instantiate()
	_skel = root.find_child("Skeleton3D", true, false)
	for i in _skel.get_bone_count():
		var nm := _skel.get_bone_name(i)
		_bones.append(nm)
		_rest[nm] = _skel.get_bone_rest(i).origin

	_anim_player = root.find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		root.add_child(_anim_player)
		_anim_player.owner = root
	_anim_player.root_node = NodePath("..")

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _build("idle", 2.4, true, _pose_idle))
	lib.add_animation("walk", _build("walk", 1.0, true, _pose_walk))
	lib.add_animation("run", _build("run", 0.66, true, _pose_run))
	lib.add_animation("attack", _build_attack())

	for l in _anim_player.get_animation_library_list():
		_anim_player.remove_animation_library(l)
	var old := _anim_player.get_animation_library("")
	if old:
		_anim_player.remove_animation_library("")
	_anim_player.add_animation_library("", lib)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	print("pack err=", err)
	err = ResourceSaver.save(packed, SCENE)
	print("SAVED anims -> ", SCENE, " err=", err)
	quit()


func _build(nm: String, length: float, loop: bool, pose_fn: Callable) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.step = 1.0 / FPS
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_create_tracks(anim)

	var frames := int(round(length * FPS))
	for f in frames + 1:
		var t: float = float(f) / FPS
		var phase: float = float(f) / float(frames)
		_key_pose(anim, t, pose_fn.call(phase))
	# 收尾对齐首帧，确保循环无缝
	_key_pose(anim, length, pose_fn.call(0.0))
	print("  ", nm, " len=", length, " tracks=", anim.get_track_count(), " keys=", frames + 1)
	return anim


func _create_tracks(anim: Animation) -> void:
	for b in _bones:
		var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(tr, "Skeleton3D:" + b)
		anim.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
		anim.rotation_track_insert_key(tr, 0.0, Quaternion.IDENTITY)
	var pt := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pt, "Skeleton3D:hips")
	anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_CUBIC)


func _key_pose(anim: Animation, t: float, pose: Dictionary) -> void:
	for ti in anim.get_track_count():
		var path := anim.track_get_path(ti)
		var bone := str(path).get_slice(":", 1)
		var p: Dictionary = pose.get(bone, {})
		if anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			var e := Vector3(deg_to_rad(p.get("x", 0.0)), deg_to_rad(p.get("y", 0.0)), deg_to_rad(p.get("z", 0.0)))
			anim.rotation_track_insert_key(ti, t, Quaternion.from_euler(e))
		else:
			var base: Vector3 = _rest[bone]
			var off := Vector3(p.get("px", 0.0), p.get("py", 0.0), p.get("pz", 0.0))
			anim.position_track_insert_key(ti, t, base + off)


# ---------------- 姿势函数 ----------------
func _pose_idle(ph: float) -> Dictionary:
	var p := TAU * ph
	var s := sin(p * 2.0)
	return {
		"hips": {"x": 0.8 * s, "py": 0.005 * s},
		"spine": {"x": 1.2 * sin(p * 2.0 + 0.4)},
		"chest": {"x": 0.9 * sin(p * 2.0 + 0.8), "y": 0.8 * sin(p)},
		"neck": {"x": -0.6 * sin(p * 2.0)},
		"head": {"x": -0.5 * sin(p * 2.0), "y": 1.6 * sin(p * 0.5)},
		"clavicle.L": {"z": 1.0 * s},
		"clavicle.R": {"z": -1.0 * s},
		"upper_arm.L": {"x": 1.6 * sin(p * 2.0 + 0.5), "z": 1.2 * s},
		"upper_arm.R": {"x": 1.6 * sin(p * 2.0 + 0.5), "z": -1.2 * s},
		"forearm.L": {"x": -7.0 - 1.5 * s},
		"forearm.R": {"x": -7.0 - 1.5 * s},
		"shin.L": {"x": 1.0},
		"shin.R": {"x": 1.0},
	}


func _pose_walk(ph: float) -> Dictionary:
	var p := TAU * ph
	var sw := sin(p)
	var knee_l: float = 6.0 + 40.0 * pow(maxf(0.0, cos(p)), 1.5)
	var knee_r: float = 6.0 + 40.0 * pow(maxf(0.0, cos(p + PI)), 1.5)
	var th_l := -30.0 * sw
	var th_r := 30.0 * sw
	return {
		"hips": {"y": 5.0 * sw, "z": 2.0 * sw, "py": 0.013 - 0.016 * cos(2.0 * p), "px": 0.012 * sw},
		"spine": {"x": 3.0, "y": -3.0 * sw},
		"chest": {"x": 1.5, "y": -5.0 * sw},
		"neck": {"x": -1.0},
		"head": {"y": 3.5 * sw},
		"clavicle.L": {"z": 2.0 * sw},
		"clavicle.R": {"z": 2.0 * sw},
		"upper_arm.L": {"x": 16.0 * sw, "z": 3.0},
		"upper_arm.R": {"x": -16.0 * sw, "z": -3.0},
		"forearm.L": {"x": -20.0 - 10.0 * maxf(0.0, sw)},
		"forearm.R": {"x": -20.0 - 10.0 * maxf(0.0, -sw)},
		"thigh.L": {"x": th_l},
		"thigh.R": {"x": th_r},
		"shin.L": {"x": knee_l},
		"shin.R": {"x": knee_r},
		"foot.L": {"x": -(th_l + knee_l) * 0.45},
		"foot.R": {"x": -(th_r + knee_r) * 0.45},
		"toe.L": {"x": 6.0 * maxf(0.0, -sw)},
		"toe.R": {"x": 6.0 * maxf(0.0, sw)},
	}


func _pose_run(ph: float) -> Dictionary:
	var p := TAU * ph
	var sw := sin(p)
	var knee_l: float = 18.0 + 68.0 * pow(maxf(0.0, cos(p)), 1.3)
	var knee_r: float = 18.0 + 68.0 * pow(maxf(0.0, cos(p + PI)), 1.3)
	var th_l := -48.0 * sw + 4.0
	var th_r := 48.0 * sw + 4.0
	return {
		"hips": {"y": 8.0 * sw, "z": 3.0 * sw, "py": 0.011 - 0.03 * cos(2.0 * p), "px": 0.02 * sw},
		"spine": {"x": 12.0, "y": -5.0 * sw},
		"chest": {"x": 4.0, "y": -8.0 * sw},
		"neck": {"x": -8.0},
		"head": {"x": -4.0, "y": 5.0 * sw},
		"clavicle.L": {"z": 3.0 * sw},
		"clavicle.R": {"z": 3.0 * sw},
		"upper_arm.L": {"x": 34.0 * sw + 6.0, "z": 8.0},
		"upper_arm.R": {"x": -34.0 * sw + 6.0, "z": -8.0},
		"forearm.L": {"x": -72.0 - 18.0 * maxf(0.0, sw)},
		"forearm.R": {"x": -72.0 - 18.0 * maxf(0.0, -sw)},
		"thigh.L": {"x": th_l},
		"thigh.R": {"x": th_r},
		"shin.L": {"x": knee_l},
		"shin.R": {"x": knee_r},
		"foot.L": {"x": -(th_l + knee_l) * 0.4},
		"foot.R": {"x": -(th_r + knee_r) * 0.4},
		"toe.L": {"x": 12.0 * maxf(0.0, -sw)},
		"toe.R": {"x": 12.0 * maxf(0.0, sw)},
	}


# ---------------- 攻击（关键姿势 + 缓动插值）----------------
func _attack_keys() -> Array:
	var rest := {}
	return [
		[0.00, rest],
		[0.14, {
			"hips": {"y": 9.0, "py": 0.027},
			"spine": {"y": 10.0, "x": -3.0},
			"chest": {"y": 20.0, "x": -4.0},
			"head": {"y": -12.0},
			"clavicle.R": {"z": -8.0},
			"upper_arm.R": {"x": 32.0, "z": -38.0},
			"forearm.R": {"x": -95.0},
			"hand.R": {"z": -18.0},
			"upper_arm.L": {"x": -16.0, "z": 14.0},
			"forearm.L": {"x": -35.0},
			"thigh.R": {"x": 8.0},
			"thigh.L": {"x": -6.0},
		}],
		[0.26, {
			"hips": {"y": 11.0, "py": 0.019},
			"spine": {"y": 12.0, "x": -5.0},
			"chest": {"y": 24.0, "x": -6.0},
			"head": {"y": -14.0},
			"clavicle.R": {"z": -10.0},
			"upper_arm.R": {"x": 36.0, "z": -44.0},
			"forearm.R": {"x": -105.0},
			"hand.R": {"z": -20.0},
			"upper_arm.L": {"x": -18.0, "z": 16.0},
			"forearm.L": {"x": -38.0},
			"thigh.R": {"x": 10.0},
			"thigh.L": {"x": -8.0},
		}],
		[0.42, {
			"hips": {"y": -12.0, "py": -0.017, "pz": 0.05},
			"spine": {"y": -14.0, "x": 10.0},
			"chest": {"y": -26.0, "x": 6.0},
			"head": {"y": 14.0, "x": 6.0},
			"clavicle.R": {"z": 8.0},
			"upper_arm.R": {"x": -46.0, "z": 52.0},
			"forearm.R": {"x": -22.0},
			"hand.R": {"z": 14.0},
			"upper_arm.L": {"x": 22.0, "z": -24.0},
			"forearm.L": {"x": -55.0},
			"thigh.R": {"x": -14.0},
			"thigh.L": {"x": 12.0},
			"shin.R": {"x": 18.0},
			"shin.L": {"x": 14.0},
		}],
		[0.56, {
			"hips": {"y": -16.0, "py": -0.003, "pz": 0.03},
			"spine": {"y": -16.0, "x": 8.0},
			"chest": {"y": -30.0, "x": 5.0},
			"head": {"y": 16.0},
			"upper_arm.R": {"x": -22.0, "z": 74.0},
			"forearm.R": {"x": -16.0},
			"upper_arm.L": {"x": 16.0, "z": -30.0},
			"forearm.L": {"x": -50.0},
			"thigh.R": {"x": -10.0},
			"thigh.L": {"x": 8.0},
		}],
		[0.78, {
			"hips": {"y": -6.0, "py": 0.021},
			"spine": {"y": -6.0, "x": 3.0},
			"chest": {"y": -10.0},
			"head": {"y": 6.0},
			"upper_arm.R": {"x": -8.0, "z": 30.0},
			"forearm.R": {"x": -18.0},
			"upper_arm.L": {"x": 6.0, "z": -10.0},
			"forearm.L": {"x": -20.0},
		}],
		[1.00, rest],
	]


func _build_attack() -> Animation:
	var keys := _attack_keys()
	var length := 0.9
	var anim := Animation.new()
	anim.length = length
	anim.step = 1.0 / FPS
	anim.loop_mode = Animation.LOOP_NONE
	_create_tracks(anim)
	var frames := int(round(length * FPS))
	for f in frames + 1:
		var t: float = float(f) / FPS
		var u: float = t / length
		# 找到所在区间
		var i := 0
		while i < keys.size() - 2 and u > keys[i + 1][0]:
			i += 1
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		var k: float = clampf((u - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)  # smoothstep
		_key_pose(anim, t, _merge_pose(keys[i][1], keys[i + 1][1], k))
	print("  attack len=", length, " tracks=", anim.get_track_count())
	return anim


func _merge_pose(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := {}
	var names := {}
	for key in a:
		names[key] = true
	for key in b:
		names[key] = true
	for nm in names:
		var pa: Dictionary = a.get(nm, {})
		var pb: Dictionary = b.get(nm, {})
		var d := {}
		for f in ["x", "y", "z", "px", "py", "pz"]:
			var va: float = pa.get(f, 0.0)
			var vb: float = pb.get(f, 0.0)
			var v: float = lerpf(va, vb, k)
			if absf(v) > 0.0001:
				d[f] = v
		out[nm] = d
	return out
