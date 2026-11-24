extends Node3D
## 骨骼动画状态机（v2 骨架）。挂在 player.tscn 的 Visual 节点上。
## 只读取父节点状态与信号，不改写任何变换，因此与 player.gd 的朝向逻辑互不干扰。

const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "run"
const CLIP_STRAFE := "strafe"
const CLIP_ATTACK_BLADE := "attack_blade"
const CLIP_FIRE_XBOW := "fire_xbow"
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

@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", true, false)

var _body: CharacterBody3D
var _current := ""
var _one_shot_left := 0.0
var _weapon := WEAPON_BLADE
var _dead := false
var _last_hp := -1.0
var _sword: Node3D
var _crossbow: Node3D


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
	_sword = find_child("Cube_009", true, false)
	_crossbow = find_child("Crossbow", true, false)
	_apply_weapon_visual()
	for from_clip in _anim.get_animation_list():
		for to_clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_STRAFE]:
			if from_clip != to_clip:
				_anim.set_blend_time(from_clip, to_clip, 0.16)
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

	if _attack_pressed():
		var clip := CLIP_FIRE_XBOW if _weapon != WEAPON_BLADE else CLIP_ATTACK_BLADE
		_play_one_shot(clip)
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

	_play(want)
	_anim.speed_scale = lerpf(_anim.speed_scale, scale, 1.0 - exp(-8.0 * delta))


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


func _play_one_shot(clip: String) -> void:
	var a: Animation = _anim.get_animation(clip)
	if a == null:
		return
	_current = clip
	_anim.speed_scale = 1.0
	_anim.play(clip)
	_one_shot_left = a.length


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
