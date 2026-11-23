extends "res://battle/Boss.gd"
## 关10 · 心魔（生存战，无血条，不召唤小怪）。
## 玩家生存 survive_s（30s）即胜 → defeated；期间追踪弹 + 环形弹（"黑潮"）。
## 头顶进度条可视化倒计时。追踪弹在本脚本内转向（复用敌弹字典引用，不改敌弹核心）。
## survive_s 读 bosses.json；转向节奏为 16 号提案默认（表未落）。

const HOMING_INTERVAL_S := 1.2   # 追踪弹发射间隔（提案默认）
const HOMING_TURN_RAD_S := 2.0   # 追踪转向速率（可躲）
const HOMING_TTL_S := 5.0        # 追踪时长，之后直线飞出
const RING_DIRECTIONS := 12      # 黑潮环形方向数
const COLOR_BODY_DEMON := Color(0.16, 0.06, 0.22)
const COLOR_TIMER := Color(0.55, 0.25, 0.7)

var _survive_left: float = 0.0
var _homing_cd: float = 0.0
var _homing: Array = []  # {b: Dictionary(与 enemy_bullets 共享引用), ttl: float}


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	super(id, mob_hp, mob_damage)
	_survive_left = float(boss_cfg.get("survive_s", 30.0))
	_homing_cd = HOMING_INTERVAL_S
	_ring_cd = DEFAULT_RING_INTERVAL_S


## 生存战不可被伤害击杀：扣血无效（弹球/近战仍照常反弹）。
func take_damage(_amount: float) -> void:
	pass


func _tick_attack(delta: float) -> void:
	_survive_left -= delta
	if _survive_left <= 0.0:
		_survive_left = 0.0
		is_defeated = true
		defeated.emit()
		return
	# 追踪弹
	_homing_cd -= delta
	if _homing_cd <= 0.0:
		_homing_cd += HOMING_INTERVAL_S
		var b: Dictionary = _bullet(_aim_dir())
		_homing.append({"b": b, "ttl": HOMING_TTL_S})
		bullets_fired.emit([b])
	# 黑潮环形
	_ring_cd -= delta
	if _ring_cd <= 0.0:
		_ring_cd += DEFAULT_RING_INTERVAL_S
		_volley += 1
		bullets_fired.emit(_ring(RING_DIRECTIONS))
	_steer_homing(delta)


func _steer_homing(delta: float) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var speed: float = float(Data.tuning.enemy_bullet.speed_px_s)
	for i in range(_homing.size() - 1, -1, -1):
		var e: Dictionary = _homing[i]
		var b: Dictionary = e.b
		e.ttl -= delta
		# 已被矛反弹/飞出战场/追踪超时 → 停止追踪（字典若已被核心移除，改它无副作用）
		if e.ttl <= 0.0 or b.reflected or not battle._field.grow(float(b.radius)).has_point(b.pos):
			_homing.remove_at(i)
			continue
		var desired: Vector2 = battle.player_pos - b.pos
		if desired == Vector2.ZERO:
			continue
		var diff: float = wrapf(desired.angle() - b.vel.angle(), -PI, PI)
		var turn: float = clampf(diff, -HOMING_TURN_RAD_S * delta, HOMING_TURN_RAD_S * delta)
		b.vel = Vector2.from_angle(b.vel.angle() + turn) * speed


func _draw() -> void:
	draw_set_transform(_shake_offset())
	_draw_body(COLOR_BODY_DEMON)
	# 黑潮涌动：外圈暗环
	draw_arc(Vector2.ZERO, body_radius + 8.0, 0.0, TAU, 32, Color(0.35, 0.1, 0.5, 0.6), 3.0)
	# 头顶倒计时进度条（生存进度 = 已存活 / survive_s）
	var total: float = float(boss_cfg.get("survive_s", 30.0))
	var ratio: float = clampf(1.0 - _survive_left / total, 0.0, 1.0)
	var bar_pos := Vector2(-body_radius, -body_radius - 16.0)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0, 8.0)), COLOR_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0 * ratio, 8.0)), COLOR_TIMER)
	_draw_burn_dot()