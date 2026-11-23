extends Node

signal mob_died(kind: String, world_pos: Vector2)
signal wave_cleared(wave_index: int)
signal level_cleared(level_id: int)
signal player_died
signal player_hp_changed(hp: float, max_hp: float)
signal corruption_changed(value: float)
signal corruption_tier_changed(tier: int)
signal ichor_changed(total: int)
signal shards_changed(total: int)
signal story_node_started(node_id: String)
signal story_node_finished(node_id: String)