extends Node3D
## 骨骼动画状态机（v2 骨架）。挂在 player.tscn 的 Visual 节点上。
## 只读取父节点状态与信号，不改写任何变换，因此与 player.gd 的朝向逻辑互不干扰。

const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "run"
const CLIP_STRAFE := "strafe"
const CLIP_ATTACK_BLADE := "attack_blade"
const CLIP_FIRE_XBOW := "fire_xbow"
const CLIP_AIM_XBOW := "aim_xbow"
const CLIP_AIM_WALK := "aim_walk"
const CLIP_HIT := "hit"
const CLIP_DEATH := "death"

const WEAPON_BLADE := 0

## 片段自身对应的地面速度基准（米/秒），用于把播放速率对齐到实际移速
const WALK_REF_SPEED := 2.4
const RUN_REF_SPEED := 4.8
const IDLE_SPEED := 0.25
const RUN_SPEED := 3.4
const WALK_SCALE_MAX := 2.0
const RUN_SCALE_MAX := 2.2
## aim_walk 是慢速瞄准步，基准速度比普通走低
const AIM_WALK_REF_SPEED := 1.7
## 开火后维持瞄准姿态的时间（含冷却与松手缓冲）
const AIM_HOLD_MSEC := 420
## fire_xbow 只播到后坐结束就交回状态机（整段 0.70s 会锁腿）
const FIRE_HOLD_SEC := 0.30

@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", true, false)

var _body: CharacterBody3D
var _current := ""
var _one_shot_left := 0.0
var _weapon := WEAPON_BLADE
var _dead := false
var _last_hp := -1.0
var _sword: Node3D
var _crossbow: Node3D
var _last_shot_msec: int = -100000


func _ready() -> void:
	_body = _find_ancestor_body()
	if _anim == null:
		push_warning("player_visual: 实例里没有 AnimationPlayer")
		return
	if _body != null:
		if _body.has_signal("weapon_changed"):
			_body.weapon_changed.connect(_on_weapon_changed)
		if _body.has_signal("hp_changed"):
			_body.hp_changed.connect(_on_hp_changed)
		if _body.has_signal("died"):
			_body.died.connect(_on_died)
		if _body.has_signal("fired"):
			_body.fired.connect(_on_fired)
	_sword = find_child("Cube_009", true, false)
	_crossbow = find_child("Crossbow", true, false)
	_apply_weapon_visual()
	for from_clip in _anim.get_animation_list():
		for to_clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_STRAFE]:
			if from_clip != to_clip:
				_anim.set_blend_time(from_clip, to_clip, 0.16)
	# 瞄准态与基础态之间也要柔和过渡，否则切弩/松手会硬切
	for from_clip in [CLIP_AIM_XBOW, CLIP_AIM_WALK]:
		for to_clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_STRAFE, CLIP_AIM_XBOW, CLIP_AIM_WALK]:
			if from_clip != to_clip:
				_anim.set_blend_time(from_clip, to_clip, 0.14)
	_play(CLIP_IDLE)


func _process(delta: float) -> void:
	if _anim == null or _body == null or _dead:
		return

	if _one_shot_left > 0.0:
		_one_shot_left = maxf(_one_shot_left - delta, 0.0)
		if _one_shot_left <= 0.0:
			_current = ""
		else:
			return

	# 长剑：按下即挥；弩的后坐由 fired 信号驱动（连发才有动画）
	if _weapon == WEAPON_BLADE and _attack_pressed():
		_play_one_shot(CLIP_ATTACK_BLADE)
		return

	var v := _body.velocity
	var speed := Vector2(v.x, v.z).length()
	var want := CLIP_IDLE
	var scale := 1.0

	var lat := _lateral(v, speed)
	if speed > RUN_SPEED:
		want = lat if lat != "" else CLIP_RUN
		scale = clampf(speed / RUN_REF_SPEED, 0.85, RUN_SCALE_MAX)
	elif speed > IDLE_SPEED:
		want = lat if lat != "" else CLIP_WALK
		scale = clampf(speed / WALK_REF_SPEED, 0.8, WALK_SCALE_MAX)

	# 拿弩时：按住攻击或刚开过火 → 锁在瞄准姿态，不回到持剑的 idle
	if _is_aiming():
		if speed > IDLE_SPEED:
			want = CLIP_AIM_WALK
			scale = clampf(speed / AIM_WALK_REF_SPEED, 0.7, 1.8)
		else:
			want = CLIP_AIM_XBOW
			scale = 1.0

	_play(want)
	_anim.speed_scale = lerpf(_anim.speed_scale, scale, 1.0 - exp(-8.0 * delta))


## 是否处于瞄准态：拿弩 + (按住攻击 或 刚开过火)
func _is_aiming() -> bool:
	if _weapon == WEAPON_BLADE:
		return false
	if InputMap.has_action("attack") and Input.is_action_pressed("attack"):
		return true
	return Time.get_ticks_msec() - _last_shot_msec < AIM_HOLD_MSEC


## 侧向移动时用 strafe 片段（角色朝向锁定鼠标，所以横移很常见）
func _lateral(v: Vector3, speed: float) -> String:
	var parent_xf := get_parent() as Node3D
	if parent_xf == null or speed < 0.01:
		return ""
	var local := parent_xf.global_transform.basis.inverse() * Vector3(v.x, 0.0, v.z)
	# FacingWedge 的 -Z 为前方
	var fwd := absf(local.z)
	var side := absf(local.x)
	if side > fwd * 1.25:
		return CLIP_STRAFE
	return ""


func _play(clip: String) -> void:
	if _current == clip:
		return
	_current = clip
	_anim.speed_scale = 1.0
	_anim.play(clip)


func _play_one_shot(clip: String, hold_sec: float = -1.0) -> void:
	var a: Animation = _anim.get_animation(clip)
	if a == null:
		return
	_current = clip
	_anim.speed_scale = 1.0
	_anim.play(clip)
	_one_shot_left = a.length if hold_sec < 0.0 else minf(hold_sec, a.length)


## 每次真实开火都重播后坐；fire_xbow 的 t=0 本来就是瞄准姿态，重播不会跳
func _on_fired() -> void:
	_last_shot_msec = Time.get_ticks_msec()
	_play_one_shot(CLIP_FIRE_XBOW, FIRE_HOLD_SEC)


func _attack_pressed() -> bool:
	return InputMap.has_action("attack") and Input.is_action_just_pressed("attack")


func _on_weapon_changed(index: int, _label: String) -> void:
	_weapon = index
	_apply_weapon_visual()


## 长剑时显示大剑、隐藏连弩；连弩反之
func _apply_weapon_visual() -> void:
	if _sword != null:
		_sword.visible = _weapon == WEAPON_BLADE
	if _crossbow != null:
		_crossbow.visible = _weapon != WEAPON_BLADE


func _on_hp_changed(current: float, _maximum: float) -> void:
	var damaged := _last_hp >= 0.0 and current < _last_hp
	_last_hp = current
	if damaged and not _dead:
		_play_one_shot(CLIP_HIT)


func _on_died() -> void:
	_dead = true
	if _anim != null:
		_play_one_shot(CLIP_DEATH)


## Visual 挂在 FacingWedge 之下，需要向上找到 CharacterBody3D
func _find_ancestor_body() -> CharacterBody3D:
	var n: Node = get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as CharacterBody3D
		n = n.get_parent()
	return null
