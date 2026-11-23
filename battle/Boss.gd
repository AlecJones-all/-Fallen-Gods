extends Node2D
## Boss 基类：共享数值（15号 2.3：HP=小怪×15、碰撞伤=小怪×2、Boss弹=小怪伤×1.0）、
## 灼烧 DOT、弹体构造、血条绘制。五场专属子类在 battle/bosses/，由 spawn_boss 按 id 实例化。
## 公开契约（BattleScene 接线，不可破坏）：
##   setup(boss_id, mob_hp, mob_damage) / tick(delta) / take_damage(amount) / apply_burn(dps, dur)
##   信号 defeated / bullets_fired(bullets: Array)
##   字段 hp / max_hp / contact_damage / body_radius / position / is_defeated
## bullets_fired 中的 pos 使用父节点（BattleScene）本地坐标。
## battle 引用由 spawn_boss 注入（召唤小怪 / 读玩家位置 / 读战场矩形用）。

signal defeated
signal bullets_fired(bullets: Array)

# bosses.json 未落表的弹幕节奏默认值（16号第三节提案方向；HP/伤害等数值一律读 Data）
const DEFAULT_RING_DIRECTIONS := 8
const DEFAULT_RING_INTERVAL_S := 3.0
const BODY_CELLS := 2.0  # 体型占 2×2 格

const COLOR_BODY := Color(0.5, 0.25, 0.65)
const COLOR_BAR_BG := Color(0.15, 0.15, 0.15)
const COLOR_BAR := Color(0.85, 0.2, 0.3)
const COLOR_BURN := Color(1.0, 0.55, 0.15)

var battle = null  # BattleScene 引用（spawn_boss 注入）
var boss_id: String = ""
var boss_cfg: Dictionary = {}
var hp: float = 0.0
var max_hp: float = 0.0
var contact_damage: float = 0.0
var bullet_damage: float = 0.0
var body_radius: float = 48.0
var is_defeated: bool = false

var _ring_cd: float = 0.0
var _ring_directions: int = DEFAULT_RING_DIRECTIONS
var _ring_interval: float = DEFAULT_RING_INTERVAL_S
var _burn_dps: float = 0.0
var _burn_left: float = 0.0
var _volley: int = 0


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	boss_id = id
	boss_cfg = Data.bosses.get(id, {})
	var t: Dictionary = Data.tuning
	max_hp = mob_hp * float(t.boss.hp_mult)
	hp = max_hp
	contact_damage = mob_damage * float(t.boss.damage_mult)
	bullet_damage = mob_damage * float(t.boss.bullet_damage_mult)
	body_radius = float(t.grid.cell_px) * BODY_CELLS / 2.0
	var p1: Dictionary = boss_cfg.get("phase1", {})
	_ring_directions = int(p1.get("ring_directions", DEFAULT_RING_DIRECTIONS))
	_ring_interval = float(p1.get("ring_interval_s", DEFAULT_RING_INTERVAL_S))
	_ring_cd = _ring_interval
	queue_redraw()


## 由 BattleScene 每帧驱动（受 set_combat_paused 统一管控，本脚本不自行 _process）。
func tick(delta: float) -> void:
	if is_defeated:
		return
	if _burn_left > 0.0:
		_burn_left -= delta
		take_damage(_burn_dps * delta)
		if is_defeated:
			return
	_tick_attack(delta)
	queue_redraw()


## 子类覆写：各场弹幕/机制。默认 = 通用占位环形弹幕（未知 boss_id 兜底）。
func _tick_attack(delta: float) -> void:
	_ring_cd -= delta
	if _ring_cd <= 0.0:
		_ring_cd += _ring_interval
		_volley += 1
		bullets_fired.emit(_ring(_ring_directions))


func take_damage(amount: float) -> void:
	if is_defeated:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		is_defeated = true
		defeated.emit()
	queue_redraw()


func apply_burn(dps: float, duration_s: float) -> void:
	_burn_dps = dps
	_burn_left = duration_s


# ================= 子类挂接点（BattleScene 调用；基类默认空实现） =================

## 期望出生位置（spawn_boss 在 add_child 后调用）。默认战场上部中央；卡俄斯覆写为战场中心。
func get_spawn_position(field: Rect2) -> Vector2:
	return Vector2(field.get_center().x, field.position.y + float(Data.tuning.grid.cell_px) * 3.0)


## 出生定位完成后调用（spawn_boss 设置 position 之后）。卡俄斯在此布置封印节点。
func on_spawned() -> void:
	pass


## 弹球 vs Boss 附属目标（如封印节点）。返回 true 表示弹球被反弹（core 统一扣反弹次数）。
## 基类无附属目标，返回 false。卡俄斯覆写。
func collide_ball(_b: Dictionary) -> bool:
	return false


## 近战 vs Boss 附属目标。基类空实现；卡俄斯覆写以伤害封印节点。
func melee_hit(_pos: Vector2, _radius: float, _dmg: float, _burn: Variant, _chaos: float) -> void:
	pass


# ================= 弹体构造（数值读 Data.tuning） =================

## 单发 Boss 弹。extra 可覆写 pos/vel/radius/color 等字段（镜像弹/满屏弹用）。
func _bullet(dir: Vector2, speed_mult: float = 1.0, extra: Dictionary = {}) -> Dictionary:
	var t: Dictionary = Data.tuning.enemy_bullet
	var b: Dictionary = {
		"pos": position + dir * (body_radius + float(t.radius_px) + 2.0),
		"vel": dir * float(t.speed_px_s) * speed_mult,
		"radius": float(t.radius_px),
		"damage": bullet_damage,
		"corruption_gain": float(Data.tuning.corruption.per_elite_boss_hit),
		"reflected": false,
		"kind": "boss",
	}
	b.merge(extra, true)
	return b


## 环形弹幕；奇偶轮错开半格角度，避免完全重叠。
func _ring(directions: int, speed_mult: float = 1.0) -> Array:
	var out: Array = []
	var offset: float = TAU / float(directions) * 0.5 * float(_volley % 2)
	for i in directions:
		var angle: float = TAU * float(i) / float(directions) + offset
		out.append(_bullet(Vector2(cos(angle), sin(angle)), speed_mult))
	return out


## 朝玩家方向（无 battle 引用时朝下）。
func _aim_dir() -> Vector2:
	if battle != null and is_instance_valid(battle):
		var d: Vector2 = (battle.player_pos - position).normalized()
		if d != Vector2.ZERO:
			return d
	return Vector2.DOWN


# ================= 绘制助手（全几何色块） =================

func _draw() -> void:
	draw_set_transform(_shake_offset())
	_draw_body(COLOR_BODY)
	if boss_cfg.get("has_hp_bar", true):
		_draw_hp_bar()
	_draw_burn_dot()


## 震屏只平移绘制，不动 position（碰撞/测试契约坐标不变）。
func _shake_offset() -> Vector2:
	if battle != null and is_instance_valid(battle):
		return battle.juice_shake_offset()
	return Vector2.ZERO


func _draw_body(color: Color) -> void:
	var s: float = body_radius * 2.0
	draw_rect(Rect2(-Vector2(body_radius, body_radius), Vector2(s, s)), color)


func _draw_hp_bar() -> void:
	var ratio: float = hp / max_hp if max_hp > 0.0 else 0.0
	var bar_pos := Vector2(-body_radius, -body_radius - 16.0)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0, 8.0)), COLOR_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0 * ratio, 8.0)), COLOR_BAR)


func _draw_burn_dot() -> void:
	if _burn_left > 0.0:
		draw_circle(Vector2(0, -body_radius - 24.0), 3.0, COLOR_BURN)