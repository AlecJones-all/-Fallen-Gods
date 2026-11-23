extends Node

var main: Control
var frames := 0
var aim_seen := false
var hold_seen := false
var strafe_seen := false
var lunge_windup_seen := false
var lunge_jump_seen := false
var prev_cols: Dictionary = {}
var prev_rows: Dictionary = {}
var hold_candidates: Dictionary = {}
var windup_ids: Dictionary = {}


func _ready() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.meta = GameState.default_meta()
	main.menu_panel.set_mode(false)
	main.menu_panel.start_requested.emit()


func _process(_delta: float) -> void:
	frames += 1
	if frames > 2400:
		_report()
		return
	if main.dialogue.is_playing():
		main.dialogue.skip()
		return
	if main.build_panel.visible:
		main.build_panel.chosen.emit(Data.build_pool[0])
		main.build_panel.hide()
		return
	if main.altar_panel.visible:
		main.altar_panel.skipped.emit()
		main.altar_panel.hide()
		return
	if main.shop_panel.visible:
		main.shop_panel.closed.emit()
		main.shop_panel.hide()
		return
	var battle: Node2D = main.battle
	if not battle.visible or battle.combat_paused:
		return
	GameState.run.hp = 1e9
	if frames == 300:
		var forced_ranged := false
		var forced_melee := false
		for m in battle.mobs:
			if not forced_ranged and m.ranged and m.kind != "elite":
				m.row = int(Data.tuning.mob_ai.ranged_hold_row)
				m.pos = battle._grid_pos(m.col, m.row, m.half)
				m.hp = 1e9
				m.max_hp = 1e9
				forced_ranged = true
			elif not forced_melee and not m.ranged and m.kind != "elite":
				m.row = battle._max_row - 3
				m.pos = battle._grid_pos(m.col, m.row, m.half)
				m.hp = 1e9
				m.max_hp = 1e9
				forced_melee = true
	var hold_row: int = int(Data.tuning.mob_ai.ranged_hold_row)
	var max_row: int = battle._max_row
	for b in battle.balls:
		if battle.mobs.size() > 0 and absf(b.vel.angle() + PI / 2.0) > 0.2:
			aim_seen = true
	for m in battle.mobs:
		var id: int = m.id
		if prev_cols.has(id) and int(prev_cols[id]) != m.col:
			strafe_seen = true
		if prev_rows.has(id) and m.row - int(prev_rows[id]) >= 2:
			lunge_jump_seen = true
		if float(m.lunge_left) > 0.0:
			lunge_windup_seen = true
			windup_ids[id] = true
		elif windup_ids.has(id) and prev_rows.has(id) and m.row > int(prev_rows[id]):
			lunge_jump_seen = true
		if m.ranged and m.kind != "elite" and m.row >= hold_row and m.row < max_row:
			if hold_candidates.has(id):
				var c: Dictionary = hold_candidates[id]
				if int(c.row) == m.row and frames - int(c.frame) > 150:
					hold_seen = true
			else:
				hold_candidates[id] = {"row": m.row, "frame": frames}
		prev_cols[id] = m.col
		prev_rows[id] = m.row
	if frames % 600 == 0:
		print("probe frame=", frames, " mobs=", battle.mobs.size(), " aim=", aim_seen, " hold=", hold_seen, " strafe=", strafe_seen, " windup=", lunge_windup_seen, " jump=", lunge_jump_seen)


func _report() -> void:
	var ok := aim_seen and hold_seen and strafe_seen and lunge_windup_seen and lunge_jump_seen
	print("PROBE_AI ", "PASS" if ok else "FAIL", " aim=", aim_seen, " hold=", hold_seen, " strafe=", strafe_seen, " windup=", lunge_windup_seen, " jump=", lunge_jump_seen)
	get_tree().quit(0 if ok else 1)