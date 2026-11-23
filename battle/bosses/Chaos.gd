extends "res://battle/Boss.gd"
## 关15 · 卡俄斯（终 Boss，无血条，特殊胜利）。
## 战场中心"帷裂口"持续涌小怪 + 弹幕；四周 seal_count 个封印节点（几何块，
## 各 HP = 小怪HP × seal_hp_mult），可被玩家弹球/近战打坏；每破 1 个 +progress_per_seal% 隔绝进度。
## 进度 100% → defeated。节点不是怪：不发 mob_died、不计 wave_cleared。
## 节点碰撞在本脚本内处理（collide_ball / melee_hit 挂接），复用弹球字典字段，不改弹球核心。

const SPAWN_INTERVAL_S := 4.0    # 涌怪间隔（提案默认，表未落）
const SPAWN_COUNT := 2           # 每次涌怪数
const RING_DIRECTIONS := 10      # 裂口环形弹幕方向数
const SEAL_OFFSET_CELLS := 3.0   # 节点距中心格数（四角分布）
const COLOR_RIFT := Color(0.1, 0.02, 0.15)
const COLOR_RIFT_CORE := Color(0.35, 0.06, 0.45)
const COLOR_SEAL := Color(0.75, 0.65, 0.35)
const COLOR_SEAL_DEAD := Color(0.25, 0.25, 0.28)
const COLOR_PROGRESS := Color(0.3, 0.85, 0.75)

var _mob_hp: float = 0.0
var _spawn_cd: float = 0.0
var _progress: float = 0.0
var seals: Array = []  # {id, pos, half, hp, max_hp, alive}


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	super(id, mob_hp, mob_damage)
	_mob_hp = mob_hp
	_spawn_cd = SPAWN_INTERVAL_S
	_ring_cd = DEFAULT_RING_INTERVAL_S


## 无血条：扣血无效，胜利仅靠封印进度。
func take_damage(_amount: float) -> void:
	pass


func get_spawn_position(field: Rect2) -> Vector2:
	return field.get_center()


func on_spawned() -> void:
	var cell: float = float(Data.tuning.grid.cell_px)
	var seal_hp: float = _mob_hp * float(boss_cfg.get("seal_hp_mult", 10))
	var half: float = cell * 0.5
	var count: int = int(boss_cfg.get("seal_count", 4))
	var dirs: Array = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for i in count:
		var off: Vector2 = dirs[i % dirs.size()] * SEAL_OFFSET_CELLS * cell
		seals.append({
			"id": -(i + 1),  # 负数 id，避免与小怪(≥1)/Boss本体(0)的 hit_ids 冲突
			"pos": position + off,
			"half": half,
			"hp": seal_hp,
			"max_hp": seal_hp,
			"alive": true,
		})
	queue_redraw()


func _tick_attack(delta: float) -> void:
	# 持续涌怪（复用现有小怪逻辑）
	if boss_cfg.get("continuous_spawns", true):
		_spawn_cd -= delta
		if _spawn_cd <= 0.0:
			_spawn_cd += SPAWN_INTERVAL_S
			_spawn_mobs()
	# 裂口环形弹幕
	_ring_cd -= delta
	if _ring_cd <= 0.0:
		_ring_cd += DEFAULT_RING_INTERVAL_S
		_volley += 1
		bullets_fired.emit(_ring(RING_DIRECTIONS))


func _spawn_mobs() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var cell: float = float(Data.tuning.grid.cell_px)
	for i in SPAWN_COUNT:
		var off := Vector2((float(i) - float(SPAWN_COUNT - 1) / 2.0) * cell, cell * 0.5)
		battle.summon_mob(i % 2 == 1, position + off)


## 弹球 vs 封印节点（圆-圆）。返回 true = 被反弹（core 统一扣反弹次数）。
func collide_ball(b: Dictionary) -> bool:
	for s in seals:
		if not s.alive or b.hit_ids.has(s.id):
			continue
		if b.pos.distance_to(s.pos) < s.half + float(b.radius):
			_damage_seal(s, float(b.damage))
			if float(b.chaos) > 0.0:
				GameState.add_corruption(float(b.chaos))
			if int(b.pierce_left) != 0:
				b.hit_ids[s.id] = true
				if int(b.pierce_left) > 0:
					b.pierce_left -= 1
				return false  # 穿透：不反弹
			var n: Vector2 = (b.pos - s.pos).normalized()
			if n == Vector2.ZERO:
				n = Vector2.UP
			b.vel = b.vel.bounce(n)
			b.pos = s.pos + n * (s.half + float(b.radius) + 0.5)
			return true
	return false


## 近战 vs 封印节点。
func melee_hit(pos: Vector2, radius: float, dmg: float, _burn: Variant, chaos: float) -> void:
	for s in seals:
		if s.alive and pos.distance_to(s.pos) <= radius + s.half:
			_damage_seal(s, dmg)
			if chaos > 0.0:
				GameState.add_corruption(chaos)


func _damage_seal(s: Dictionary, amount: float) -> void:
	if not s.alive:
		return
	s.hp -= amount
	if battle != null and is_instance_valid(battle):
		battle.add_damage_floater(s.pos + Vector2(0.0, -float(s.half) - 6.0), amount, true)
	if s.hp <= 0.0:
		s.hp = 0.0
		s.alive = false
		_progress += float(boss_cfg.get("progress_per_seal", 25))
		if _progress >= 100.0:
			_progress = 100.0
			is_defeated = true
			defeated.emit()
	queue_redraw()


func _draw() -> void:
	draw_set_transform(_shake_offset())
	# 帷裂口（中心暗紫块 + 涌动核心）
	_draw_body(COLOR_RIFT)
	draw_circle(Vector2.ZERO, body_radius * 0.6, COLOR_RIFT_CORE)
	draw_arc(Vector2.ZERO, body_radius * 0.85, 0.0, TAU, 24, Color(0.5, 0.1, 0.6, 0.7), 2.0)
	# 封印节点（几何块 + 各自血条）
	for s in seals:
		var local: Vector2 = s.pos - position
		var h: float = s.half
		var col: Color = COLOR_SEAL if s.alive else COLOR_SEAL_DEAD
		draw_rect(Rect2(local - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), col)
		if s.alive:
			var ratio: float = s.hp / s.max_hp if s.max_hp > 0.0 else 0.0
			var bp := local + Vector2(-h, -h - 10.0)
			draw_rect(Rect2(bp, Vector2(h * 2.0, 5.0)), COLOR_BAR_BG)
			draw_rect(Rect2(bp, Vector2(h * 2.0 * ratio, 5.0)), COLOR_BAR)
	# 隔绝进度条（裂口头顶）
	var pr: float = _progress / 100.0
	var bar_pos := Vector2(-body_radius, -body_radius - 20.0)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0, 10.0)), COLOR_BAR_BG)
	draw_rect(Rect2(bar_pos, Vector2(body_radius * 2.0 * pr, 10.0)), COLOR_PROGRESS)