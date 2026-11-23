extends "res://battle/Boss.gd"
## 关13 · 阿奈提俄斯（镜像，有血条）。
## 影子弹 = 复制玩家当前弹球形态：数量/反弹读 GameState.ball_params()，弹色暗紫，伤害用 Boss 弹规则。
## 影子弹在本脚本内做墙面镜面反射（复用敌弹字典引用，不改敌弹核心），反弹次数耗尽后飞出。
## 阶段2 HP≤50%：弹幕加密 + 弹速 × phase2_speed_mult（读 bosses.json）。

const FIRE_INTERVAL_S := 1.6    # 镜像发射间隔（提案默认，表未落）
const SHADOW_TTL_S := 10.0      # 影子弹追踪上限（界定引用数组）
const COLOR_SHADOW := Color(0.45, 0.2, 0.6)  # 暗紫影子弹
const COLOR_BODY_MIRROR := Color(0.42, 0.42, 0.58)

var _fire_cd: float = 0.0
var _shadows: Array = []  # {b: Dictionary, bounces: int, ttl: float}


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	super(id, mob_hp, mob_damage)
	_fire_cd = FIRE_INTERVAL_S


func _tick_attack(delta: float) -> void:
	var phase2: bool = hp <= max_hp * float(boss_cfg.get("phase_threshold", 0.5))
	var mult: float = float(boss_cfg.get("phase2_speed_mult", 1.5)) if phase2 else 1.0
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd += FIRE_INTERVAL_S / mult  # 阶段2 加密
		_fire_mirror(mult)
	_update_shadows(delta)


func _fire_mirror(speed_mult: float) -> void:
	var bp: Dictionary = GameState.ball_params()
	var count: int = int(bp.count)
	var bounces: int = int(bp.bounces)
	var t: Dictionary = Data.tuning.ball
	var spread: float = deg_to_rad(float(t.spread_deg))
	var base_dir: Vector2 = _aim_dir()
	var speed: float = float(Data.tuning.enemy_bullet.speed_px_s) * speed_mult
	var out: Array = []
	for i in count:
		var a: float = 0.0
		if count > 1:
			a = lerpf(-spread, spread, float(i) / float(count - 1))
		var dir: Vector2 = base_dir.rotated(a)
		var b: Dictionary = _bullet(dir, 1.0, {
			"vel": dir * speed,
			"radius": float(t.radius_px),
			"color": COLOR_SHADOW,
		})
		out.append(b)
		_shadows.append({"b": b, "bounces": bounces, "ttl": SHADOW_TTL_S})
	bullets_fired.emit(out)


func _update_shadows(delta: float) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var field: Rect2 = battle._field
	for i in range(_shadows.size() - 1, -1, -1):
		var e: Dictionary = _shadows[i]
		var b: Dictionary = e.b
		e.ttl -= delta
		if e.ttl <= 0.0 or b.reflected or not field.grow(float(b.radius)).has_point(b.pos):
			_shadows.remove_at(i)
			continue
		if e.bounces <= 0:
			continue  # 反弹耗尽，任其飞出
		# 预测性镜面反射：在越界前一帧折返，保证不被核心移除
		var margin: float = float(b.radius) + b.vel.length() * delta
		if b.pos.x - margin < field.position.x and b.vel.x < 0.0:
			b.vel.x = absf(b.vel.x)
			e.bounces -= 1
		elif b.pos.x + margin > field.end.x and b.vel.x > 0.0:
			b.vel.x = -absf(b.vel.x)
			e.bounces -= 1
		if b.pos.y - margin < field.position.y and b.vel.y < 0.0:
			b.vel.y = absf(b.vel.y)
			e.bounces -= 1
		elif b.pos.y + margin > field.end.y and b.vel.y > 0.0:
			b.vel.y = -absf(b.vel.y)
			e.bounces -= 1


func _draw() -> void:
	draw_set_transform(_shake_offset())
	_draw_body(COLOR_BODY_MIRROR)
	# 镜像轮廓：内嵌暗色方块
	var inner: float = body_radius * 0.55
	draw_rect(Rect2(-Vector2(inner, inner), Vector2(inner * 2.0, inner * 2.0)), COLOR_SHADOW)
	_draw_hp_bar()
	_draw_burn_dot()