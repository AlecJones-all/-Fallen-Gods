extends Node2D
## 战斗核心场景：7列棋子怪阵 + 自定义弹球积分/镜面反射 + 敌弹 + 手动瞄准远程武器。
## 公开契约（LevelDirector 接线）：
##   setup(level_id) / spawn_wave(wave_index, elite_count) / spawn_boss(boss_id)
##   set_combat_paused(paused)
##   信号 wave_cleared(wave_index) / boss_defeated
## 数值全部读 Data.tuning / Data.cards / Data.levels；视觉全部 _draw 几何色块，无物理引擎。
## 经济（Ichor/残片）不在本模块发放，击杀仅发 EventBus.mob_died。

signal wave_cleared(wave_index: int)
signal boss_defeated

# ---- 布局/规则常量（战场与判定几何，非 tuning 数值） ----
const LOGICAL_SIZE := Vector2(640, 360)  # 横屏逻辑分辨率（中央纵深道路固定，不随窗口拉伸）
const FIELD_TOP := 44.0            # 顶部状态区；中央道路从其下方延伸至玩家
const PLAYER_SPAWN := Vector2(320, 316)
const MOB_SIZE := 40.0             # 近战/远程小怪 40px
const ELITE_SIZE := 72.0           # 精英 72px（占多格）
const MELEE_RADIUS := 64.0         # 近战环绕挥击半径（15号 1.2）
const FORMATION_COLUMNS := 7       # 敌方棋子阵列每行固定最多 7 个单位
const FORMATION_TOP_Y := 132.0     # 留出道路远端呼吸区；首排从这里开始
const FORMATION_BOTTOM_Y := 270.0  # 与玩家出生点保留明确的闪避/瞄准空间
const FORMATION_MIN_ROWS := 5
const CHAIN_RANGE := 150.0         # 雷霆连锁搜索半径
const SPLIT_DAMAGE_MULT := 0.5     # buff 分裂弹伤害系数（未指定，沿用许德拉 50%）
const EFFECT_TTL := 0.18           # 挥击/连锁线视觉残留时长

const COLOR_PLAYER := Color(0.2, 0.9, 0.9)
const COLOR_BALL := Color(1.0, 1.0, 1.0)
const COLOR_ENEMY_BULLET := Color(0.95, 0.25, 0.2)
const COLOR_REFLECTED := Color(0.4, 0.95, 0.9)
const COLOR_MOB_MELEE := Color(0.55, 0.6, 0.68)
const COLOR_MOB_RANGED := Color(0.75, 0.65, 0.3)
const COLOR_ELITE := Color(0.85, 0.35, 0.25)
const COLOR_BURN := Color(1.0, 0.55, 0.15)

# ---- 公开状态（测试/导演可读） ----
var level_id: int = 0
var level_cfg: Dictionary = {}
var player_pos: Vector2 = PLAYER_SPAWN
var combat_paused: bool = false
var mobs: Array = []          # Dictionary：id/kind/ranged/col/row/pos/half/hp/damage/fire_cd/burn_*
var balls: Array = []         # 玩家弹球（集中数组更新）
var enemy_bullets: Array = [] # 敌弹（集中数组更新）
var boss = null               # battle/Boss.gd 实例（可替换精细化脚本；动态类型便于替换）

var _bg_color := Color(0.08, 0.08, 0.1)
var _bg_node: TextureRect = null  # 关卡背景图（存在才挂；无图时 _draw 画原色块）
var _background_draw_suppressed := false  # 有背景节点时不再用 _draw 的不透明底色遮盖它
var _fx: Node2D = null            # battle/BattleFx.gd 特效池（纯视觉）
var _view_size := LOGICAL_SIZE
var _field := Rect2(0, FIELD_TOP, LOGICAL_SIZE.x, LOGICAL_SIZE.y - FIELD_TOP)
var _combat_lane
var _cols: int = FORMATION_COLUMNS
var _max_row: int = FORMATION_MIN_ROWS - 1
var _formation_row_step := 32.0
var _effects: Array = []
var _rng := RandomNumberGenerator.new()
var _grid_timer: float = 0.0
var _contact_cd: float = 0.0
var _cleanse_cd: float = 0.0
var _weapon_timers: Dictionary = {}
var _aim_direction := Vector2.UP
var _aim_dragging := false
var _aim_marker_pos := Vector2.ZERO
var _aim_marker_left := 0.0
var _wave_index: int = -1
var _wave_active: bool = false
var _next_mob_id: int = 1
var _boss_script: Script = preload("res://battle/Boss.gd")
var _fx_script: Script = preload("res://battle/BattleFx.gd")
const Juice := preload("res://battle/BattleJuice.gd")
var _juice: Juice = null
var _boss_shaken: bool = false
var _idle_redraw: bool = false
# 五场精细化 Boss 脚本（按 boss_id 实例化；未列出的 id 回退通用基类）
const BOSS_SCRIPTS: Dictionary = {
	"cephissus": preload("res://battle/bosses/Cephissus.gd"),
	"inner_demon": preload("res://battle/bosses/InnerDemon.gd"),
	"anaitios": preload("res://battle/bosses/Anaitios.gd"),
	"zeus": preload("res://battle/bosses/Zeus.gd"),
	"chaos": preload("res://battle/bosses/Chaos.gd"),
}
const CombatLane := preload("res://battle/CombatLane.gd")


func _ready() -> void:
	_rng.randomize()
	# 战场固定 640×360；实际可玩区域由第1关纵深道路梯形决定。
	_view_size = LOGICAL_SIZE
	_combat_lane = CombatLane.new(Data.combat_lane_config(1))
	_field = _combat_lane.bounds()
	_configure_formation()
	_fx = _fx_script.new()
	add_child(_fx)
	_juice = Juice.new()
	set_process(true)


# ================= 公开 API =================

func setup(id: int) -> void:
	level_id = id
	level_cfg = Data.level_config(id)
	_combat_lane = CombatLane.new(Data.combat_lane_config(id))
	_field = _combat_lane.bounds()
	_configure_formation()
	_bg_color = Color(level_cfg.bg_color)
	_setup_background(id)
	if _fx != null:
		_fx.reset()
	mobs.clear()
	balls.clear()
	enemy_bullets.clear()
	_effects.clear()
	if boss != null:
		boss.queue_free()
		boss = null
	player_pos = _combat_lane.player_spawn(float(Data.tuning.player.radius_px))
	_grid_timer = 0.0
	_contact_cd = 0.0
	_cleanse_cd = 0.0
	_weapon_timers.clear()
	_aim_direction = Vector2.UP
	_aim_dragging = false
	_aim_marker_left = 0.0
	_wave_index = -1
	_wave_active = false
	combat_paused = false
	if _juice != null:
		_juice.reset()
	_boss_shaken = false
	_idle_redraw = false
	queue_redraw()


func spawn_wave(wave_index: int, elite_count: int) -> void:
	_wave_index = wave_index
	_wave_active = true
	var density: int = int(level_cfg.density)
	var cell: float = Data.tuning.grid.cell_px
	# 出生在上部若干行；多备一行供精英落位（精英不占密度）
	var rows_needed: int = ceili(float(density + elite_count) / float(_cols))
	var cells: Array = []
	for row in rows_needed:
		for col in _cols:
			cells.append(Vector2i(col, row))
	cells.shuffle()
	var ranged_count: int = int(round(density * float(Data.tuning.mob_ranged_ratio)))
	for i in density:
		_add_mob("mob", i < ranged_count, cells[i])
	for i in elite_count:
		_add_mob("elite", true, cells[density + i])
	queue_redraw()


func spawn_boss(boss_id: String) -> void:
	# 按 boss_id 实例化专属精细化脚本（保持 setup/tick/take_damage 接口与 defeated/bullets_fired 信号）。
	if boss != null:
		boss.queue_free()
	var script: Script = BOSS_SCRIPTS.get(boss_id, _boss_script)
	boss = script.new()
	boss.battle = self
	boss.setup(boss_id, float(level_cfg.mob_hp), float(level_cfg.mob_damage))
	boss.defeated.connect(_on_boss_defeated)
	boss.bullets_fired.connect(_on_boss_bullets)
	add_child(boss)
	boss.position = boss.get_spawn_position(_field)
	boss.on_spawned()
	# Boss 战期间召唤的小怪不得触发波次逻辑
	_wave_active = false


func set_combat_paused(paused: bool) -> void:
	combat_paused = paused


## 关卡背景图挂接：关卡叙事专用横屏 PNG 优先，旧 JPG 为兼容回退（TextureRect 拉伸满屏）。
## 有图时 _draw 不再画整屏底色矩形；无图保持原色块。
func _setup_background(id: int) -> void:
	var narrative_path := "res://assets/backgrounds/level_%02d_graveyard_road_landscape.png" % id
	var path := narrative_path if FileAccess.file_exists(narrative_path) else "res://assets/backgrounds/level_%02d.jpg" % id
	var tex: Texture2D = null
	if FileAccess.file_exists(path) and ResourceLoader.exists(path):
		tex = load(path)
	if tex != null:
		if _bg_node == null:
			_bg_node = TextureRect.new()
			_bg_node.z_index = -1
			_bg_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bg_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_bg_node.stretch_mode = TextureRect.STRETCH_SCALE
			_bg_node.position = Vector2.ZERO
			_bg_node.size = LOGICAL_SIZE
			add_child(_bg_node)
			move_child(_bg_node, 0)  # 同 z 下先画背景，精英光环(-1)垫在怪之下、背景之上
		_bg_node.texture = tex
		_bg_node.show()
		_background_draw_suppressed = true
	elif _bg_node != null:
		_bg_node.texture = null
		_bg_node.hide()
		_background_draw_suppressed = false
	else:
		_background_draw_suppressed = false


# ================= 主循环 =================

func _process(delta: float) -> void:
	# 视觉层用真实 delta：暂停/顿帧期间横幅、震屏、飘字等照常收尾
	_juice.update(delta)
	_aim_marker_left = maxf(0.0, _aim_marker_left - delta)
	var mobs_animating: bool = _decay_mob_juice(delta)
	_sync_shake_nodes()
	if combat_paused:
		var animating: bool = _juice.is_animating() or mobs_animating
		if animating or _idle_redraw:
			queue_redraw()
		_idle_redraw = animating
		return
	if _juice.freeze_left > 0.0:
		queue_redraw()
		return
	var sim_delta: float = delta
	if _juice.slowmo_left > 0.0:
		sim_delta *= float(Data.tuning.juice.slowmo_scale)
	_cleanse_cd -= sim_delta
	_update_player(sim_delta)
	_update_weapons(sim_delta)
	_update_grid(sim_delta)
	_update_mobs(sim_delta)
	_update_balls(sim_delta)
	_update_enemy_bullets(sim_delta)
	if boss != null and is_instance_valid(boss):
		boss.tick(sim_delta)
	_update_effects(sim_delta)
	_sync_mob_fx()
	_sweep_dead()
	_update_contact(sim_delta)
	queue_redraw()


func _decay_mob_juice(delta: float) -> bool:
	var active: bool = false
	for m in mobs:
		if m.flash > 0.0:
			m.flash = maxf(0.0, float(m.flash) - delta)
			active = active or m.flash > 0.0
		if m.pop > 0.0:
			m.pop = maxf(0.0, float(m.pop) - delta)
			active = active or m.pop > 0.0
	return active


func _sync_shake_nodes() -> void:
	var off: Vector2 = _juice.shake_offset
	if _bg_node != null:
		_bg_node.position = off
	if _fx != null:
		_fx.position = off
	if boss != null and is_instance_valid(boss):
		if off != Vector2.ZERO or _boss_shaken:
			boss.queue_redraw()
		_boss_shaken = off != Vector2.ZERO


func juice_shake_offset() -> Vector2:
	return _juice.shake_offset


func add_damage_floater(pos: Vector2, amount: float, gold: bool) -> void:
	_juice.add_floater(pos, amount, gold)


func _input(event: InputEvent) -> void:
	# _input 早于 Control 的 GUI 分发，确保全屏 Main / HUD 不会吞掉战斗左键。
	if combat_paused or not visible:
		return
	# 键盘是唯一移动方式；左键/第一指只指定自动射击方向，松开后保留最后方向。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_aim_dragging = event.pressed
		if event.pressed:
			_set_aim_from_input_event(event)
	elif event is InputEventMouseMotion and _aim_dragging:
		_set_aim_from_input_event(event)
	elif event is InputEventScreenTouch and event.index == 0:
		_aim_dragging = event.pressed
		if event.pressed:
			_set_aim_from_input_event(event)
	elif event is InputEventScreenDrag and event.index == 0:
		_set_aim_from_input_event(event)


func _set_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.001:
		_aim_direction = direction.normalized()


func _set_aim_from_input_event(event: InputEvent) -> void:
	# 交给 Godot 按当前 Canvas / Stretch 变换换算到本 Node2D 的局部战场坐标。
	# 不能直接手写矩阵反算：全屏 Control 的锚点与窗口缩放会使其方向翻转。
	var local_event: InputEvent = make_input_local(event)
	var battle_position := Vector2.ZERO
	if local_event is InputEventMouseButton:
		battle_position = local_event.position
	elif local_event is InputEventMouseMotion:
		battle_position = local_event.position
	elif local_event is InputEventScreenTouch:
		battle_position = local_event.position
	elif local_event is InputEventScreenDrag:
		battle_position = local_event.position
	else:
		return
	_set_aim_direction(battle_position - player_pos)
	_aim_marker_pos = battle_position
	_aim_marker_left = 0.18
	queue_redraw()


func _configure_formation() -> void:
	_cols = FORMATION_COLUMNS
	var density: int = int(level_cfg.get("density", 7))
	var elites: int = int(level_cfg.get("elites", 0))
	var required_rows: int = ceili(float(density + elites) / float(_cols))
	_max_row = maxi(FORMATION_MIN_ROWS - 1, required_rows - 1)
	_formation_row_step = (FORMATION_BOTTOM_Y - FORMATION_TOP_Y) / float(maxi(_max_row, 1))


func _update_player(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	dir = dir.limit_length(1.0)
	if dir != Vector2.ZERO:
		player_pos += dir * GameState.move_speed() * delta
		_clamp_player()


func _clamp_player() -> void:
	var r: float = Data.tuning.player.radius_px
	player_pos = _combat_lane.clamp_point(player_pos, r)


# ================= 怪物 =================

func _add_mob(kind: String, ranged: bool, cell: Vector2i) -> void:
	var t: Dictionary = Data.tuning
	var hp: float = float(level_cfg.mob_hp)
	var dmg: float = float(level_cfg.mob_damage)
	var size: float = MOB_SIZE
	if kind == "elite":
		hp *= float(t.elite.hp_mult)
		dmg *= float(t.elite.damage_mult)
		size = ELITE_SIZE
	var half: float = size / 2.0
	mobs.append({
		"id": _next_mob_id,
		"kind": kind,
		"ranged": ranged,
		"col": cell.x,
		"row": cell.y,
		"half": half,
		"hp": hp,
		"max_hp": hp,
		"damage": dmg,
		"pos": _grid_pos(cell.x, cell.y, half),
		"fire_cd": _rand_fire_interval(),
		"burn_dps": 0.0,
		"burn_left": 0.0,
		"flash": 0.0,
		"pop": 0.0,
		"lunge_left": 0.0,
	})
	_next_mob_id += 1


## Boss 召唤小怪入口：把世界坐标吸附到网格，复用现有小怪逻辑（下移/吐弹/击杀发 mob_died）。
func summon_mob(ranged: bool, world_pos: Vector2) -> void:
	var row: int = clampi(roundi((world_pos.y - FORMATION_TOP_Y) / _formation_row_step), 0, _max_row)
	var y: float = FORMATION_TOP_Y + row * _formation_row_step
	var col: int = _combat_lane.column_for_x(world_pos.x, _cols, y)
	_add_mob("mob", ranged, Vector2i(col, row))


func _grid_pos(col: int, row: int, half: float) -> Vector2:
	var y: float = clampf(FORMATION_TOP_Y + row * _formation_row_step, _combat_lane.top_y + half, FORMATION_BOTTOM_Y)
	return _combat_lane.position_for_grid(col, _cols, y, half)


func _mob_visual_scale(y: float) -> float:
	var progress := inverse_lerp(FORMATION_TOP_Y, FORMATION_BOTTOM_Y, y)
	return lerpf(0.58, 1.0, clampf(progress, 0.0, 1.0))


func _rand_fire_interval() -> float:
	var t: Dictionary = Data.tuning.enemy_bullet
	if level_id in t.dense_levels:
		return float(t.interval_dense_s)
	return _rng.randf_range(float(t.interval_s_min), float(t.interval_s_max))


func _update_grid(delta: float) -> void:
	_grid_timer += delta
	var tick: float = Data.tuning.grid.tick_s
	while _grid_timer >= tick:
		_grid_timer -= tick
		_grid_tick()


## 网格个性包（2026-11-23 用户裁决，覆盖定稿§1.8纯下移）：
## 远程怪中场停驻当炮台；小怪概率横移包抄；底排近战蓄力冲刺；精英追踪玩家列。
func _grid_tick() -> void:
	var ai: Dictionary = Data.tuning.mob_ai
	var player_col: int = _combat_lane.column_for_x(player_pos.x, _cols, player_pos.y)
	for m in mobs:
		if m.hp <= 0.0 or float(m.lunge_left) > 0.0:
			continue
		var is_elite: bool = m.kind == "elite"
		var hold: bool = m.ranged and not is_elite and m.row >= int(ai.ranged_hold_row)
		if not hold and m.row < _max_row:
			m.row += 1
		var strafe_chance: float = float(ai.elite_strafe_chance) if is_elite else float(ai.strafe_chance)
		if _rng.randf() < strafe_chance:
			var step: int = signi(player_col - m.col)
			if step != 0 and _cell_free(m.col + step, m.row, m.id):
				m.col += step
		if not m.ranged and not hold and m.row >= _max_row - int(ai.lunge_from_bottom) \
				and _rng.randf() < float(ai.lunge_chance):
			m.lunge_left = float(ai.lunge_windup_s)
		m.pos = _grid_pos(m.col, m.row, m.half)


func _cell_free(col: int, row: int, exclude_id: int) -> bool:
	if col < 0 or col >= _cols:
		return false
	for m in mobs:
		if m.id != exclude_id and m.hp > 0.0 and m.col == col and m.row == row:
			return false
	return true


func _update_mobs(delta: float) -> void:
	var ai: Dictionary = Data.tuning.mob_ai
	for m in mobs:
		if m.hp <= 0.0:
			continue
		if float(m.lunge_left) > 0.0:
			m.lunge_left -= delta
			if m.lunge_left <= 0.0:
				m.row = mini(m.row + int(ai.lunge_rows), _max_row)
				m.pos = _grid_pos(m.col, m.row, m.half)
				m.pop = float(Data.tuning.juice.hit_pop_s)
		if m.burn_left > 0.0:
			m.burn_left -= delta
			_damage_mob(m, m.burn_dps * delta)
		if m.ranged and m.hp > 0.0:
			m.fire_cd -= delta
			if m.fire_cd <= 0.0:
				m.fire_cd += _rand_fire_interval()
				_fire_enemy_bullet(m)


func _fire_enemy_bullet(m: Dictionary) -> void:
	var t: Dictionary = Data.tuning.enemy_bullet
	var dir: Vector2 = (player_pos - m.pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var mult: float = float(t.damage_mult)
	var corruption: float = float(Data.tuning.corruption.per_remote_hit)
	if m.kind == "elite":
		mult = float(Data.tuning.elite.bullet_damage_mult)
		corruption = float(Data.tuning.corruption.per_elite_boss_hit)
	enemy_bullets.append({
		"pos": m.pos + dir * (m.half + float(t.radius_px)),
		"vel": dir * float(t.speed_px_s),
		"radius": float(t.radius_px),
		"damage": float(level_cfg.mob_damage) * mult,
		"corruption_gain": corruption,
		"reflected": false,
	})


func _damage_mob(m: Dictionary, amount: float) -> void:
	m.hp -= amount


func _apply_burn_mob(m: Dictionary, burn: Dictionary) -> void:
	m.burn_dps = float(burn.dps)
	m.burn_left = float(burn.duration_s)


func _sweep_dead() -> void:
	var j: Dictionary = Data.tuning.juice
	for i in range(mobs.size() - 1, -1, -1):
		var m: Dictionary = mobs[i]
		if m.hp <= 0.0:
			if _fx != null:
				_fx.clear_loop(m.id)
				_fx.burst("death", m.pos)
			_juice.add_corpse(m.pos, m.half, m.kind, m.ranged)
			if m.kind == "elite":
				_juice.shake(float(j.shake_elite_px), float(j.shake_elite_s))
			EventBus.mob_died.emit(m.kind, m.pos)
			mobs.remove_at(i)
	if _wave_active and mobs.is_empty() and boss == null:
		_wave_active = false
		wave_cleared.emit(_wave_index)
		_juice.start_banner(_wave_index)


func _update_contact(delta: float) -> void:
	_contact_cd -= delta
	if _contact_cd > 0.0:
		return
	var pr: float = Data.tuning.player.radius_px
	for m in mobs:
		if m.hp > 0.0 and player_pos.distance_to(m.pos) < pr + m.half:
			var cg: float = 0.0
			if m.kind == "elite":
				cg = float(Data.tuning.corruption.per_elite_boss_hit)
			GameState.damage_player(m.damage, cg)
			_juice.on_player_hit(false)
			_contact_cd = float(Data.tuning.player.contact_cooldown_s)
			return
	if boss != null and is_instance_valid(boss) and player_pos.distance_to(boss.position) < pr + boss.body_radius:
		GameState.damage_player(boss.contact_damage, float(Data.tuning.corruption.per_elite_boss_hit))
		_juice.on_player_hit(true)
		_contact_cd = float(Data.tuning.player.contact_cooldown_s)


# ================= 武器（8 卡） =================

func _update_weapons(delta: float) -> void:
	var bp: Dictionary = GameState.ball_params()
	for card_id in GameState.meta.weapons:
		var card: Dictionary = Data.cards[card_id]
		if card.kind == "shield" or float(card.attack_speed) <= 0.0:
			continue  # 埃癸斯无攻击，被动生效
		var timer: float = float(_weapon_timers.get(card_id, 0.0)) - delta
		if timer <= 0.0:
			timer = GameState.weapon_interval(card_id)
			if card.kind == "ranged":
				_fire_ranged(card_id, card, bp)
			else:
				_melee_swing(card_id, card, bp)
		_weapon_timers[card_id] = timer


func _fire_ranged(card_id: String, card: Dictionary, bp: Dictionary) -> void:
	var t: Dictionary = Data.tuning.ball
	var count: int = int(bp.count)
	var spread: float = deg_to_rad(float(t.spread_deg))
	var base_speed: float = float(t.speed_px_s)
	var variance: float = float(card.effects.get("speed_variance", 0.0))
	var dmg: float = GameState.weapon_damage(card_id)
	var spawn_r: float = _player_bounce_radius() + float(t.radius_px) + 1.0
	var base_angle: float = _aim_angle()
	for i in count:
		var angle: float
		if count == 1:
			angle = base_angle + _rng.randf_range(-spread, spread)
		else:
			angle = base_angle + lerpf(-spread, spread, float(i) / float(count - 1))
		var dir := Vector2(cos(angle), sin(angle))
		var speed: float = base_speed
		if variance > 0.0:
			speed *= 1.0 + _rng.randf_range(-variance, variance)
		balls.append(_make_ball(player_pos + dir * spawn_r, dir * speed, dmg, card_id, card, bp, true))


## 自动射击：方向由最近一次鼠标/触屏瞄准决定；无输入则保持朝上。
func _aim_angle() -> float:
	if _aim_direction.length_squared() > 0.001:
		return _aim_direction.angle()
	var best_d: float = INF
	var target: Vector2 = Vector2.ZERO
	var found: bool = false
	for m in mobs:
		if m.hp <= 0.0:
			continue
		var d: float = player_pos.distance_squared_to(m.pos)
		if d < best_d:
			best_d = d
			target = m.pos
			found = true
	if not found and boss != null and is_instance_valid(boss):
		target = boss.position
		found = true
	if not found:
		return -PI / 2.0
	var dir: Vector2 = (target - player_pos).normalized()
	if dir == Vector2.ZERO:
		return -PI / 2.0
	return atan2(dir.y, dir.x)


func _make_ball(pos: Vector2, vel: Vector2, dmg: float, card_id: String, card: Dictionary, bp: Dictionary, can_split: bool) -> Dictionary:
	var pierce_left: int = 0
	if bp.pierce:
		pierce_left = -1  # buff 穿透：无限穿怪
	elif card.effects.has("pierce"):
		pierce_left = int(card.effects.pierce)
	var split_count: int = 0
	if can_split:
		if int(bp.split) > 0:
			split_count = int(bp.split)
		elif card.effects.has("split"):
			split_count = int(card.effects.split)
	var burn: Variant = card.effects.get("burn", null)
	if burn == null:
		burn = bp.burn  # buff 灼烧：全武器附 DOT
	return {
		"pos": pos,
		"vel": vel,
		"radius": float(Data.tuning.ball.radius_px),
		"bounces": int(bp.bounces),
		"damage": dmg,
		"card_id": card_id,
		"pierce_left": pierce_left,
		"hit_ids": {},
		"split_count": split_count,
		"split_mult": float(card.effects.get("split_damage_mult", SPLIT_DAMAGE_MULT)),
		"chain_left": int(card.effects.get("chain", 0)),
		"burn": burn,
		"chaos": float(card.corruption_per_hit) if card.faction == "chaos" else 0.0,
		"trail": [],
	}


func _melee_swing(card_id: String, card: Dictionary, bp: Dictionary) -> void:
	var dmg: float = GameState.weapon_damage(card_id)
	var chaos: float = float(card.corruption_per_hit) if card.faction == "chaos" else 0.0
	var burn: Variant = card.effects.get("burn", null)
	if burn == null:
		burn = bp.burn
	var lifesteal: float = float(card.effects.get("lifesteal", 0.0))
	var knockback: bool = card.effects.has("knockback_px")
	var split_n: int = int(card.effects.get("split", 0))
	var split_mult: float = float(card.effects.get("split_damage_mult", SPLIT_DAMAGE_MULT))
	_effects.append({"type": "ring", "pos": player_pos, "radius": MELEE_RADIUS, "t": EFFECT_TTL, "color": COLOR_PLAYER})
	var healed: float = 0.0
	for m in mobs:
		if m.hp <= 0.0:
			continue
		if player_pos.distance_to(m.pos) <= MELEE_RADIUS + m.half:
			var dealt: float = minf(m.hp, dmg)
			_damage_mob(m, dmg)
			_juice.hit_mob(m, dealt)
			if chaos > 0.0:
				GameState.add_corruption(chaos)
			if burn != null:
				_apply_burn_mob(m, burn)
			if lifesteal > 0.0:
				healed += dealt * lifesteal
			if knockback:
				# 击退 48px = 上移一格
				m.row = maxi(m.row - 1, 0)
				m.pos = _grid_pos(m.col, m.row, m.half)
			if split_n > 0:
				var template: Dictionary = _make_ball(m.pos, Vector2.ZERO, dmg, card_id, card, bp, false)
				_spawn_split_balls(m.pos, template, split_n, split_mult)
	if healed > 0.0:
		GameState.heal(healed)
	if boss != null and is_instance_valid(boss) and player_pos.distance_to(boss.position) <= MELEE_RADIUS + boss.body_radius:
		var boss_ref = boss
		_juice.add_floater(boss_ref.position + Vector2(0.0, -float(boss_ref.body_radius) - 8.0), dmg, true)
		boss_ref.take_damage(dmg)
		if chaos > 0.0:
			GameState.add_corruption(chaos)
		if burn != null and is_instance_valid(boss_ref) and not boss_ref.is_defeated:
			boss_ref.apply_burn(float(burn.dps), float(burn.duration_s))
	# Boss 附属目标（卡俄斯封印节点）近战判定
	if boss != null and is_instance_valid(boss):
		boss.melee_hit(player_pos, MELEE_RADIUS, dmg, burn, chaos)


func _spawn_split_balls(origin: Vector2, base: Dictionary, count: int, mult: float) -> void:
	var speed: float = float(Data.tuning.ball.speed_px_s)
	var fresh_bounces: int = int(GameState.ball_params().bounces)
	for i in count:
		var angle: float = -PI / 2.0 + _rng.randf_range(-PI / 3.0, PI / 3.0)
		var dir := Vector2(cos(angle), sin(angle))
		var child: Dictionary = base.duplicate(true)
		child.pos = origin + dir * (float(base.radius) + 2.0)
		child.vel = dir * speed
		child.damage = float(base.damage) * mult
		child.split_count = 0      # 分裂弹不再分裂
		child.chain_left = 0
		child.pierce_left = 0
		child.hit_ids = {}
		child.bounces = fresh_bounces
		child.trail = []
		balls.append(child)


# ================= 弹球（自定义积分 + 镜面反射） =================

func _update_balls(delta: float) -> void:
	var pr: float = _player_bounce_radius()
	var trail_len: int = int(Data.tuning.juice.trail_len)
	for i in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[i]
		b.pos += b.vel * delta
		var r: float = b.radius
		var consumed: bool = false
		# 纵深道路边界：上下为横墙，两侧为道路梯形的斜墙。
		if b.pos.y - r < _combat_lane.top_y:
			b.pos.y = _combat_lane.top_y + r
			b.vel.y = absf(b.vel.y)
			consumed = true
			_juice.add_bounce_ring(Vector2(b.pos.x, _combat_lane.top_y))
		elif b.pos.y + r > _combat_lane.bottom_y:
			b.pos.y = _combat_lane.bottom_y - r
			b.vel.y = -absf(b.vel.y)
			consumed = true
			_juice.add_bounce_ring(Vector2(b.pos.x, _combat_lane.bottom_y))
		var road_left: float = _combat_lane.left_at(b.pos.y)
		var road_right: float = _combat_lane.right_at(b.pos.y)
		if b.pos.x - r < road_left:
			b.pos.x = road_left + r
			b.vel = b.vel.bounce(_combat_lane.left_normal())
			consumed = true
			_juice.add_bounce_ring(Vector2(road_left, b.pos.y))
		elif b.pos.x + r > road_right:
			b.pos.x = road_right - r
			b.vel = b.vel.bounce(_combat_lane.right_normal())
			consumed = true
			_juice.add_bounce_ring(Vector2(road_right, b.pos.y))
		# 玩家（仅当球朝玩家运动时反弹，避免刚发射的球立即回弹）
		if b.pos.distance_to(player_pos) < pr + r and b.vel.dot(player_pos - b.pos) > 0.0:
			var n: Vector2 = (b.pos - player_pos).normalized()
			if n == Vector2.ZERO:
				n = Vector2.UP
			b.vel = b.vel.bounce(n)
			b.pos = player_pos + n * (pr + r + 0.5)
			consumed = true
			_juice.add_bounce_ring(player_pos + n * pr)
			_try_aegis_cleanse()
		# Boss（圆-圆）
		if boss != null and is_instance_valid(boss) and not b.hit_ids.has(0) \
				and b.pos.distance_to(boss.position) < boss.body_radius + r:
			var boss_ref = boss  # take_damage 可能触发 defeated 置空 boss，先存引用
			var boss_pos: Vector2 = boss_ref.position
			var boss_r: float = boss_ref.body_radius
			_hit_boss(b, boss_ref)
			if b.pierce_left != 0:
				b.hit_ids[0] = true
				if b.pierce_left > 0:
					b.pierce_left -= 1
			else:
				var nb: Vector2 = (b.pos - boss_pos).normalized()
				if nb == Vector2.ZERO:
					nb = Vector2.UP
				b.vel = b.vel.bounce(nb)
				b.pos = boss_pos + nb * (boss_r + r + 0.5)
				consumed = true
		# 怪物（圆-圆）
		for m in mobs:
			if m.hp <= 0.0 or b.hit_ids.has(m.id):
				continue
			if b.pos.distance_to(m.pos) < m.half + r:
				_hit_mob(b, m)
				if b.pierce_left != 0:
					b.hit_ids[m.id] = true
					if b.pierce_left > 0:
						b.pierce_left -= 1
				else:
					var nm: Vector2 = (b.pos - m.pos).normalized()
					if nm == Vector2.ZERO:
						nm = Vector2.UP
					b.vel = b.vel.bounce(nm)
					b.pos = m.pos + nm * (m.half + r + 0.5)
					consumed = true
					break
		# Boss 附属目标（卡俄斯封印节点等）；反弹时交由 core 统一扣反弹次数
		if not consumed and boss != null and is_instance_valid(boss):
			if boss.collide_ball(b):
				consumed = true
		if consumed:
			b.bounces -= 1
			if b.bounces <= 0:
				balls.remove_at(i)
				continue
		var trail: Array = b.trail
		trail.append(b.pos)
		if trail.size() > trail_len:
			trail.pop_front()


func _hit_mob(b: Dictionary, m: Dictionary) -> void:
	if _fx != null:
		_fx.burst("hit", m.pos)
	_damage_mob(m, b.damage)
	_juice.hit_mob(m, b.damage)
	if b.chaos > 0.0:
		GameState.add_corruption(b.chaos)
	if b.burn != null:
		_apply_burn_mob(m, b.burn)
	if b.split_count > 0:
		_spawn_split_balls(m.pos, b, b.split_count, b.split_mult)
	if b.chain_left > 0:
		_chain_from(m, b)


func _hit_boss(b: Dictionary, boss_ref) -> void:
	_juice.add_floater(boss_ref.position + Vector2(0.0, -float(boss_ref.body_radius) - 8.0), b.damage, true)
	boss_ref.take_damage(b.damage)
	if b.chaos > 0.0:
		GameState.add_corruption(b.chaos)
	if b.burn != null and is_instance_valid(boss_ref) and not boss_ref.is_defeated:
		boss_ref.apply_burn(float(b.burn.dps), float(b.burn.duration_s))
	if b.split_count > 0:
		_spawn_split_balls(boss_ref.position, b, b.split_count, b.split_mult)


func _chain_from(first_mob: Dictionary, b: Dictionary) -> void:
	# 雷霆：撞怪后 150px 内最近怪连锁弹射，即时伤害 + 画线
	var hit: Dictionary = {first_mob.id: true}
	var current: Dictionary = first_mob
	var remaining: int = b.chain_left
	while remaining > 0:
		var best: Dictionary = {}
		var best_d: float = CHAIN_RANGE
		for m in mobs:
			if m.hp <= 0.0 or hit.has(m.id):
				continue
			var d: float = current.pos.distance_to(m.pos)
			if d <= best_d:
				best_d = d
				best = m
		if best.is_empty():
			break
		hit[best.id] = true
		_effects.append({"type": "line", "a": current.pos, "b": best.pos, "t": EFFECT_TTL, "color": Color(1.0, 0.9, 0.4)})
		_damage_mob(best, b.damage)
		_juice.hit_mob(best, b.damage)
		if b.chaos > 0.0:
			GameState.add_corruption(b.chaos)
		if b.burn != null:
			_apply_burn_mob(best, b.burn)
		current = best
		remaining -= 1


# ================= 敌弹 =================

func _update_enemy_bullets(delta: float) -> void:
	var has_spear: bool = "ares_spear" in GameState.meta.weapons
	var player_r: float = Data.tuning.player.radius_px
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b: Dictionary = enemy_bullets[i]
		b.pos += b.vel * delta
		if not _combat_lane.contains(b.pos, b.radius):
			enemy_bullets.remove_at(i)
			continue
		if b.reflected:
			# 被矛反弹的敌弹转而伤害怪物/Boss
			var hit: bool = false
			for m in mobs:
				if m.hp > 0.0 and b.pos.distance_to(m.pos) < m.half + b.radius:
					_damage_mob(m, b.damage)
					_juice.hit_mob(m, b.damage)
					hit = true
					break
			if not hit and boss != null and is_instance_valid(boss) \
					and b.pos.distance_to(boss.position) < boss.body_radius + b.radius:
				_juice.add_floater(boss.position + Vector2(0.0, -float(boss.body_radius) - 8.0), b.damage, true)
				boss.take_damage(b.damage)
				hit = true
			if hit:
				enemy_bullets.remove_at(i)
			continue
		# 阿瑞斯之矛：近战范围内反弹敌弹
		if has_spear and player_pos.distance_to(b.pos) <= MELEE_RADIUS + b.radius:
			var n: Vector2 = (b.pos - player_pos).normalized()
			if n == Vector2.ZERO:
				n = Vector2.UP
			b.vel = n * b.vel.length()
			b.reflected = true
			continue
		if player_pos.distance_to(b.pos) < player_r + b.radius:
			GameState.damage_player(b.damage, b.corruption_gain)
			_juice.on_player_hit(b.get("kind", "") == "boss")
			enemy_bullets.remove_at(i)


# ================= 埃癸斯 / 玩家反弹半径 =================

func _player_bounce_radius() -> float:
	var r: float = Data.tuning.player.radius_px
	if "aegis" in GameState.meta.weapons:
		r *= float(Data.cards.aegis.effects.bounce_radius_mult)
	return r


func _try_aegis_cleanse() -> void:
	if not ("aegis" in GameState.meta.weapons):
		return
	if _cleanse_cd > 0.0:
		return
	var eff: Dictionary = Data.cards.aegis.effects
	GameState.add_corruption(-float(eff.cleanse_on_ball))
	_cleanse_cd = float(eff.cleanse_interval_s)


# ================= Boss 接线 =================

func _on_boss_bullets(bullets: Array) -> void:
	enemy_bullets.append_array(bullets)


func _on_boss_defeated() -> void:
	var dead: Node2D = boss
	var dead_radius: float = boss.body_radius
	boss = null
	if _fx != null:
		_fx.burst("death", dead.position)
	_juice.add_corpse(dead.position, dead_radius, "boss", false)
	_juice.shake(float(Data.tuning.juice.shake_boss_px), float(Data.tuning.juice.shake_boss_s))
	EventBus.mob_died.emit("boss", dead.position)
	boss_defeated.emit()
	dead.queue_free()


# ================= 视觉残留 =================

## 循环特效跟随：灼烧怪头顶火苗（burn 结束/怪死移除）、存活精英垫底光环。纯视觉。
func _sync_mob_fx() -> void:
	if _fx == null:
		return
	for m in mobs:
		if m.hp <= 0.0:
			continue
		if m.burn_left > 0.0:
			_fx.set_loop("burn", m.id, m.pos + Vector2(0.0, -m.half - 14.0))
		else:
			_fx.clear_kind("burn", m.id)
		if m.kind == "elite":
			_fx.set_loop("aura", m.id, m.pos)


func _update_effects(delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i].t -= delta
		if _effects[i].t <= 0.0:
			_effects.remove_at(i)


# ================= 绘制（全几何色块） =================

func _draw() -> void:
	var j: Dictionary = Data.tuning.juice
	# 无贴图时才画不随震屏的底色；有背景时不能遮盖 TextureRect 子节点。
	if not _background_draw_suppressed:
		draw_rect(Rect2(Vector2.ZERO, _view_size), _bg_color)
	draw_set_transform(_juice.shake_offset)
	draw_line(Vector2(0.0, FIELD_TOP), Vector2(_view_size.x, FIELD_TOP), Color(1, 1, 1, 0.08), 1.0)
	# 实际战斗区的轻量边界：跟随背景道路的近窄远宽，不遮盖墓地场景细节。
	var lane_left_top := Vector2(_combat_lane.top_left, _combat_lane.top_y)
	var lane_left_bottom := Vector2(_combat_lane.bottom_left, _combat_lane.bottom_y)
	var lane_right_top := Vector2(_combat_lane.top_right, _combat_lane.top_y)
	var lane_right_bottom := Vector2(_combat_lane.bottom_right, _combat_lane.bottom_y)
	var lane_glow := Color(0.62, 0.74, 0.78, 0.07)
	var lane_line := Color(0.72, 0.82, 0.84, 0.28)
	draw_line(lane_left_top, lane_left_bottom, lane_glow, 5.0, true)
	draw_line(lane_right_top, lane_right_bottom, lane_glow, 5.0, true)
	draw_line(lane_left_top, lane_left_bottom, lane_line, 1.0, true)
	draw_line(lane_right_top, lane_right_bottom, lane_line, 1.0, true)
	# 挥击环 / 连锁线
	for e in _effects:
		var a: float = clampf(e.t / EFFECT_TTL, 0.0, 1.0)
		if e.type == "ring":
			draw_arc(e.pos, e.radius, 0.0, TAU, 24, Color(e.color, a * 0.8), 2.0)
		elif e.type == "line":
			draw_line(e.a, e.b, Color(e.color, a), 2.0)
	_juice.draw_world(self)
	# 怪物（受击闪白 + 缩放弹跳）
	var flash_dur: float = float(j.hit_flash_s)
	var pop_dur: float = float(j.hit_pop_s)
	var pop_scale: float = float(j.hit_pop_scale)
	for m in mobs:
		if m.hp <= 0.0:
			continue
		var depth_scale: float = _mob_visual_scale(m.pos.y)
		var h: float = m.half * depth_scale * (1.0 + (pop_scale - 1.0) * clampf(float(m.pop) / pop_dur, 0.0, 1.0))
		var flash_k: float = clampf(float(m.flash) / flash_dur, 0.0, 1.0)
		if m.kind == "elite":
			draw_rect(Rect2(m.pos - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), COLOR_ELITE.lerp(Color.WHITE, flash_k))
		elif m.ranged:
			draw_colored_polygon(PackedVector2Array([
				m.pos + Vector2(0.0, -h),
				m.pos + Vector2(-h, h),
				m.pos + Vector2(h, h),
			]), COLOR_MOB_RANGED.lerp(Color.WHITE, flash_k))
		else:
			var melee_color: Color = COLOR_MOB_MELEE
			if float(m.lunge_left) > 0.0:
				var pulse: float = 0.4 + 0.6 * absf(sin(float(m.lunge_left) * 25.0))
				melee_color = melee_color.lerp(COLOR_BURN, pulse)
			draw_rect(Rect2(m.pos - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), melee_color.lerp(Color.WHITE, flash_k))
		if m.burn_left > 0.0:
			draw_circle(m.pos + Vector2(0.0, -h - 4.0), 3.0, COLOR_BURN)
	# 弹球（拖尾残影 + 本体）
	var trail_alpha: float = float(j.trail_alpha)
	for b in balls:
		var trail: Array = b.trail
		var n: int = trail.size()
		for ti in n - 1:
			var k: float = float(ti + 1) / float(n)
			draw_circle(trail[ti], float(b.radius) * k * 0.8, Color(1.0, 1.0, 1.0, trail_alpha * k))
		draw_circle(b.pos, b.radius, COLOR_BALL)
	# 敌弹（Boss 可自定义弹色，如镜像影子弹暗紫）
	for b in enemy_bullets:
		var bc: Color = COLOR_REFLECTED if b.reflected else b.get("color", COLOR_ENEMY_BULLET)
		draw_circle(b.pos, b.radius, bc)
	# 玩家
	draw_circle(player_pos, float(Data.tuning.player.radius_px), COLOR_PLAYER)
	# 自动射击方向：短线只提示方向，不盖住纵深道路和敌方阵列。
	var aim_end := player_pos + _aim_direction * 30.0
	draw_line(player_pos + _aim_direction * 16.0, aim_end, Color(0.88, 0.82, 0.54, 0.72), 1.5, true)
	draw_circle(aim_end, 2.0, Color(0.95, 0.88, 0.58, 0.82))
	if _aim_marker_left > 0.0:
		var marker_alpha: float = _aim_marker_left / 0.18
		draw_arc(_aim_marker_pos, 8.0, 0.0, TAU, 16, Color(1.0, 0.87, 0.44, marker_alpha * 0.85), 1.5)
		draw_line(_aim_marker_pos + Vector2(-4.0, 0.0), _aim_marker_pos + Vector2(4.0, 0.0), Color(1.0, 0.87, 0.44, marker_alpha), 1.0)
		draw_line(_aim_marker_pos + Vector2(0.0, -4.0), _aim_marker_pos + Vector2(0.0, 4.0), Color(1.0, 0.87, 0.44, marker_alpha), 1.0)
	if "aegis" in GameState.meta.weapons:
		draw_arc(player_pos, _player_bounce_radius(), 0.0, TAU, 32, Color(0.5, 0.9, 1.0, 0.5), 2.0)
	_juice.draw_floaters(self)
	# 屏幕空间层（红闪/横幅）不随震屏
	draw_set_transform(Vector2.ZERO)
	_juice.draw_screen(self, _view_size)
