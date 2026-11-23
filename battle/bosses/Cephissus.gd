extends "res://battle/Boss.gd"
## 关5 · 刻菲索斯（河神，站桩+召唤，有血条）。
## 阶段1 HP>50%：每 summon_interval_s 召 summon_count 只小怪 + 每 ring_interval_s 环形 8 向弹幕。
## 阶段2 HP≤50%：环形加密（phase2.ring_interval_s）+ 朝玩家扇形 fan_burst 连发。
## 召唤复用 BattleScene.summon_mob → 现有小怪逻辑（下移/吐弹/击杀发 mob_died）。
## 节奏数值全部读 data/bosses.json。

const FAN_SPREAD_DEG := 30.0  # 扇形几何张角（图案形状，非平衡数值）

var _summon_cd: float = 0.0
var _fan_cd: float = 0.0


func setup(id: String, mob_hp: float, mob_damage: float) -> void:
	super(id, mob_hp, mob_damage)
	var p1: Dictionary = boss_cfg.get("phase1", {})
	_summon_cd = float(p1.get("summon_interval_s", 8.0))
	_fan_cd = float(boss_cfg.get("phase2", {}).get("ring_interval_s", 2.0))


func _tick_attack(delta: float) -> void:
	var p1: Dictionary = boss_cfg.get("phase1", {})
	var p2: Dictionary = boss_cfg.get("phase2", {})
	var phase2: bool = hp <= max_hp * float(boss_cfg.get("phase_threshold", 0.5))
	# 召唤（两阶段持续）
	_summon_cd -= delta
	if _summon_cd <= 0.0:
		_summon_cd += float(p1.get("summon_interval_s", 8.0))
		_summon(int(p1.get("summon_count", 2)))
	# 环形弹幕：阶段2 加密
	var interval: float = float(p2.get("ring_interval_s", 2.0)) if phase2 else float(p1.get("ring_interval_s", 3.0))
	_ring_cd -= delta
	if _ring_cd <= 0.0:
		_ring_cd += interval
		_volley += 1
		bullets_fired.emit(_ring(_ring_directions))
	# 阶段2 追加扇形连发
	if phase2:
		_fan_cd -= delta
		if _fan_cd <= 0.0:
			_fan_cd += interval
			bullets_fired.emit(_fan(int(p2.get("fan_burst", 3))))


func _summon(count: int) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var cell: float = float(Data.tuning.grid.cell_px)
	for i in count:
		var off := Vector2((float(i) - float(count - 1) / 2.0) * cell, cell)
		battle.summon_mob(i % 2 == 1, position + off)


func _fan(count: int) -> Array:
	var out: Array = []
	var base_dir: Vector2 = _aim_dir()
	var spread: float = deg_to_rad(FAN_SPREAD_DEG)
	for i in count:
		var a: float = 0.0
		if count > 1:
			a = lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		out.append(_bullet(base_dir.rotated(a)))
	return out


func _draw() -> void:
	draw_set_transform(_shake_offset())
	_draw_body(Color(0.2, 0.5, 0.45))  # 河神·青绿
	_draw_hp_bar()
	_draw_burn_dot()