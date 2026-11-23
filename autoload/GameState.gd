extends Node

var meta: Dictionary = default_meta()
var run: Dictionary = {}

static func default_meta() -> Dictionary:
	return {
		"unlocked_level": 1,
		"realm": 1,
		"weapons": { "prometheus_fire": "common" },
		"shards": 0,
		"evidence": [],
		"scars": [],
		"read_story": [],
	}

func start_level(level_id: int) -> void:
	run = {
		"level": level_id,
		"corruption": 0.0,
		"ichor": 0,
		"buffs": default_buffs(),
		"hp": 0.0,
	}
	run.hp = final_stats().hp
	add_corruption(Data.tuning.corruption.per_level_natural)
	EventBus.player_hp_changed.emit(run.hp, final_stats().hp)

static func default_buffs() -> Dictionary:
	return {
		"power": 0, "hp": 0, "speed": 0.0,
		"bounces": 0, "ball_count": 0,
		"pierce": false, "split": 0, "burn": null,
		"damage_mult": 0.0,
	}

func base_stats() -> Dictionary:
	var power: float = Data.tuning.player.base_power
	var hp: float = Data.tuning.player.base_hp
	var speed: float = Data.tuning.player.base_speed
	var all_mult := 1.0
	for realm in Data.realms:
		if realm.index > meta.realm:
			break
		power += realm.bonuses.get("power", 0)
		hp += realm.bonuses.get("hp", 0)
		speed += realm.bonuses.get("speed", 0.0)
		all_mult += realm.bonuses.get("all_mult", 0.0)
	return { "power": power * all_mult, "hp": hp * all_mult, "speed": speed * all_mult }

func final_stats() -> Dictionary:
	var b := base_stats()
	return {
		"power": minf(b.power + run.buffs.power, Data.tuning.caps.power),
		"hp": b.hp + run.buffs.hp,
		"speed": minf(b.speed + run.buffs.speed, Data.tuning.caps.attack_speed_mult),
	}

func damage_mult() -> float:
	return 1.0 + final_stats().power * Data.tuning.power_damage_per_point + run.buffs.damage_mult

func weapon_damage(card_id: String) -> float:
	var card: Dictionary = Data.cards[card_id]
	var rarity: String = meta.weapons.get(card_id, "common")
	var dmg: float = Data.tuning.rarity_damage[rarity] * (card.base_damage / 10.0) * damage_mult()
	if card.faction == "chaos":
		dmg *= 1.0 + run.corruption * Data.tuning.corruption.chaos_damage_bonus_per_point
	return dmg

func weapon_interval(card_id: String) -> float:
	var card: Dictionary = Data.cards[card_id]
	return 1.0 / (card.attack_speed * final_stats().speed)

func move_speed() -> float:
	var s: float = final_stats().speed
	return Data.tuning.player.move_px_s * (1.0 + (s - 1.0) / 0.2 * Data.tuning.player.move_bonus_per_02_speed)

func ball_params() -> Dictionary:
	var t: Dictionary = Data.tuning.ball
	return {
		"bounces": mini(t.base_bounces + run.buffs.bounces, t.max_bounces),
		"count": mini(t.base_count + run.buffs.ball_count, t.max_count),
		"pierce": run.buffs.pierce,
		"split": run.buffs.split,
		"burn": run.buffs.burn,
	}

func apply_build_option(option: Dictionary) -> void:
	var effects: Dictionary = option.effects
	for key in effects:
		match key:
			"power", "hp", "speed", "bounces", "ball_count", "split", "damage_mult":
				run.buffs[key] += effects[key]
				if key == "hp":
					heal(effects[key])
			"pierce":
				run.buffs.pierce = true
			"burn":
				run.buffs.burn = effects[key]
			"corruption_delta":
				add_corruption(effects[key])
			"heal":
				heal(effects[key])
	if option.corruption_cost > 0:
		add_corruption(option.corruption_cost)
	EventBus.player_hp_changed.emit(run.hp, final_stats().hp)

func heal(amount: float) -> void:
	run.hp = minf(run.hp + amount, final_stats().hp)
	EventBus.player_hp_changed.emit(run.hp, final_stats().hp)

func damage_player(amount: float, corruption_gain: float) -> void:
	if run.hp <= 0.0:
		return
	run.hp -= amount
	if corruption_gain > 0.0:
		add_corruption(corruption_gain)
	EventBus.player_hp_changed.emit(run.hp, final_stats().hp)
	if run.hp <= 0.0:
		EventBus.player_died.emit()

func add_ichor(amount: int) -> void:
	run.ichor += amount
	EventBus.ichor_changed.emit(run.ichor)

func spend_ichor(cost: int) -> bool:
	if run.ichor < cost:
		return false
	run.ichor -= cost
	EventBus.ichor_changed.emit(run.ichor)
	return true

func add_corruption(amount: float) -> void:
	var old_tier := corruption_tier()
	run.corruption = clampf(run.corruption + amount, 0.0, Data.tuning.corruption.max)
	EventBus.corruption_changed.emit(run.corruption)
	var new_tier := corruption_tier()
	if new_tier != old_tier:
		EventBus.corruption_tier_changed.emit(new_tier)

func corruption_tier() -> int:
	var tier := 0
	for threshold in Data.tuning.corruption.tier_thresholds:
		if run.corruption >= threshold:
			tier += 1
	return tier

func gain_shards(amount: int) -> void:
	meta.shards += amount
	EventBus.shards_changed.emit(meta.shards)

func buy_weapon(card_id: String) -> bool:
	if card_id in meta.weapons:
		return false
	if not spend_ichor(Data.economy.shop.new_weapon):
		return false
	meta.weapons[card_id] = "common"
	return true

func upgrade_weapon(card_id: String) -> bool:
	var rarity: String = meta.weapons.get(card_id, "")
	var cost: int
	match rarity:
		"common": cost = Data.economy.shop.upgrade_common_to_rare
		"rare": cost = Data.economy.shop.upgrade_rare_to_divine
		_: return false
	if not spend_ichor(cost):
		return false
	meta.weapons[card_id] = Data.tuning.rarity_order[Data.tuning.rarity_order.find(rarity) + 1]
	return true

func buy_stat_point(stat: String) -> bool:
	if not spend_ichor(Data.economy.shop.stat_point):
		return false
	var amount: float = Data.economy.shop.stat_point_options[stat]
	run.buffs[stat] += amount
	if stat == "hp":
		heal(amount)
	EventBus.player_hp_changed.emit(run.hp, final_stats().hp)
	return true

func altar_choice(key: String, stat: String = "") -> bool:
	var entry: Dictionary = Data.economy.altar[key]
	if not spend_ichor(entry.cost):
		return false
	match key:
		"purify":
			add_corruption(entry.corruption_delta)
			meta.scars.append("净礼蚀痕·第%d关" % run.level)
		"heal":
			heal(entry.hp_delta)
		"enhance":
			run.buffs[stat] += entry.options[stat]
			if stat == "hp":
				heal(entry.options[stat])
			EventBus.player_hp_changed.emit(run.hp, final_stats().hp)
	return true

func forge_artifacts() -> Array:
	var forged: Array = []
	for card_id in meta.weapons:
		if Data.cards[card_id].faction != "order":
			continue
		while meta.weapons[card_id] == "divine" and meta.shards >= Data.economy.shards.forge_cost:
			meta.shards -= Data.economy.shards.forge_cost
			meta.weapons[card_id] = "artifact"
			forged.append(Data.cards[card_id].name)
	EventBus.shards_changed.emit(meta.shards)
	return forged

func grant_settlement() -> Dictionary:
	var first_clear: bool = run.level >= meta.unlocked_level
	var gained: int = Data.economy.ichor_gain.settle
	if first_clear:
		gained += Data.economy.ichor_gain.first_clear_bonus
	add_ichor(gained)
	return { "first_clear": first_clear, "ichor": gained }

func finish_level() -> void:
	var cfg := Data.level_config(run.level)
	if run.level >= meta.unlocked_level:
		meta.unlocked_level = mini(run.level + 1, 15)
	if cfg.realm_unlock != null:
		meta.realm = maxi(meta.realm, int(cfg.realm_unlock))
	run.ichor = 0
	SaveManager.save_game()

func mark_story_read(node_id: String) -> void:
	if node_id not in meta.read_story:
		meta.read_story.append(node_id)