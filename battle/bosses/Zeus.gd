extends "res://battle/Boss.gd"
## 关14 · 宙斯（站桩三阶段，有血条）。阈值读 bosses.json.phase_thresholds=[0.66,0.33]。
## HP>66%「威严」：规整环形 + 直线弹幕；66–33%「裂缝」：加密 + 随机方向；
## ≤33%「崩溃」：满屏弹幕但弹速 × phase3.bullet_speed_mult(0.6)，可躲。
## 图案名读 cfg.patterns；节奏为 16 号提案默认（表未落间隔）。

const ATTACK_INTERVAL_S := 2.0   # 基础攻击间隔（提案默认）
const LINE_COUNT := 5            # 直线弹幕弹数
const RANDOM_COUNT := 6          # 裂缝随机弹数
const FILL_COLS := 10            # 崩溃满屏横向弹数
const COLOR_BODY_ZEUS := Color(0.85, 0.7, 0.3)

var _atk_cd: float = 0.0


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	super(id, mob_hp, mob_damage)
	_atk_cd = ATTACK_INTERVAL_S


func _phase() -> int:
	var th: Array = boss_cfg.get("phase_thresholds", [0.66, 0.33])
	var ratio: float = hp / max_hp if max_hp > 0.0 else 0.0
	if ratio <= float(th[1]):
		return 3
	if ratio <= float(th[0]):
		return 2
	return 1


func _tick_attack(delta: float) -> void:
	_atk_cd -= delta
	if _atk_cd > 0.0:
		return
	var phase: int = _phase()
	var interval: float = ATTACK_INTERVAL_S
	if phase == 2:
		interval *= 0.6  # 裂缝加密
	elif phase == 3:
		interval *= 0.8
	_atk_cd += interval
	_volley += 1
	var out: Array = []
	if phase == 1:
		out.append_array(_ring(8))
		out.append_array(_line())
	elif phase == 2:
		out.append_array(_ring(16))
		out.append_array(_random(RANDOM_COUNT))
	else:
		var mult: float = float(boss_cfg.get("phase3", {}).get("bullet_speed_mult", 0.6))
		out.append_array(_ring(24, mult))
		out.append_array(_screen_fill(mult))
	bullets_fired.emit(out)


## 直线弹幕：朝玩家方向的一束等距弹。
func _line() -> Array:
	var out: Array = []
	var dir: Vector2 = _aim_dir()
	var r: float = float(Data.tuning.enemy_bullet.radius_px)
	for i in LINE_COUNT:
		var pos: Vector2 = position + dir * (body_radius + r + 2.0 + float(i) * r * 2.5)
		out.append(_bullet(dir, 1.0, {"pos": pos}))
	return out


## 随机方向弹。
func _random(n: int) -> Array:
	var out: Array = []
	for i in n:
		var a: float = randf() * TAU
		out.append(_bullet(Vector2(cos(a), sin(a))))
	return out


## 满屏弹幕：横向一排慢速下压弹（配合慢速环形，逐渐铺满，可躲）。
func _screen_fill(mult: float) -> Array:
	var out: Array = []
	if battle == null or not is_instance_valid(battle):
		return out
	var field: Rect2 = battle._field
	for i in FILL_COLS:
		var x: float = lerpf(field.position.x + 20.0, field.end.x - 20.0, float(i) / float(FILL_COLS - 1))
		out.append(_bullet(Vector2.DOWN, mult, {"pos": Vector2(x, position.y)}))
	return out


func _draw() -> void:
	draw_set_transform(_shake_offset())
	_draw_body(COLOR_BODY_ZEUS)
	# 阶段色泽：裂缝/崩溃时泛红
	var phase: int = _phase()
	if phase >= 2:
		var inner: float = body_radius * 0.5
		var c: Color = Color(0.8, 0.3, 0.2) if phase == 2 else Color(0.6, 0.1, 0.15)
		draw_rect(Rect2(-Vector2(inner, inner), Vector2(inner * 2.0, inner * 2.0)), c)
	_draw_hp_bar()
	_draw_burn_dot()