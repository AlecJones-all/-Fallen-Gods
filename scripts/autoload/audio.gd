extends Node

## Data-driven one-shot SFX layer. Event definitions live in data/tuning.json
## under audio.events: files (one is picked at random), db offset, pitch and
## variation, and a minimum interval so rapid hits do not machine-gun.
## Sounds are routed to the "SFX" bus owned by Settings.

const BUS_NAME: StringName = &"SFX"
const POOL_SIZE: int = 10
const MAX_3D_VOICES: int = 16
const GROUP_3D_VOICES: StringName = &"audio_voices_3d"
const DEFAULT_VARY: float = 0.05
const NO_LAST_PLAYED: int = -1000000

var _events: Dictionary = {}
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_played: Dictionary = {}
var _counts: Dictionary = {}
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_events = Tuning.section("audio").get("events", {})
	if AudioServer.get_bus_index(BUS_NAME) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS_NAME)
	_build_pool()
	# Menus are built in code; catch every button added from now on.
	get_tree().node_added.connect(_on_node_added)


func play(event: StringName) -> void:
	_emit(event, null)


func play_at(event: StringName, world_position: Vector3) -> void:
	_emit(event, world_position)


## Total successful plays of an event; used by the headless probes.
func play_count(event: StringName) -> int:
	return int(_counts.get(String(event), 0))


## Loads every configured file once; returns the paths that failed to load.
func verify_events() -> PackedStringArray:
	var missing := PackedStringArray()
	for key: String in _events.keys():
		var definition: Variant = _events[key]
		if not (definition is Dictionary):
			continue
		var files: Variant = (definition as Dictionary).get("files", [])
		if not (files is Array):
			continue
		for path: Variant in (files as Array):
			if load(String(path)) == null:
				missing.append(String(path))
	return missing


func _emit(event: StringName, world_position: Variant) -> void:
	var key := String(event)
	var definition := _definition(key)
	if definition.is_empty():
		return
	if not _interval_elapsed(key, definition):
		return
	var stream := _stream_for(key, definition)
	if stream == null:
		return

	var vary := float(definition.get("vary", DEFAULT_VARY))
	var pitch := float(definition.get("pitch", 1.0)) * randf_range(1.0 - vary, 1.0 + vary)
	var volume := float(definition.get("db", 0.0))
	if world_position == null:
		_play_global(stream, pitch, volume)
	else:
		_play_positional(stream, world_position as Vector3, pitch, volume)

	_counts[key] = play_count(event) + 1


func _definition(key: String) -> Dictionary:
	var definition: Variant = _events.get(key)
	if definition is Dictionary:
		return definition
	if not _warned.has(key):
		_warned[key] = true
		push_warning("Audio: tuning.json 里没有音频事件 %s" % key)
	return {}


func _interval_elapsed(key: String, definition: Dictionary) -> bool:
	var interval_ms := int(float(definition.get("min_interval", 0.0)) * 1000.0)
	if interval_ms <= 0:
		return true
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, NO_LAST_PLAYED)) < interval_ms:
		return false
	_last_played[key] = now
	return true


func _stream_for(key: String, definition: Dictionary) -> AudioStream:
	var files: Variant = definition.get("files", [])
	if files is not Array or (files as Array).is_empty():
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Audio: 音频事件 %s 没有配置 files" % key)
		return null

	var picked := String((files as Array)[randi() % (files as Array).size()])
	var cached: Variant = _streams.get(picked)
	if cached is AudioStream:
		return cached

	var stream := load(picked) as AudioStream
	if stream == null:
		if not _warned.has(picked):
			_warned[picked] = true
			push_warning("Audio: 无法加载 %s（WAV 未导入？）" % picked)
		return null
	_streams[picked] = stream
	return stream


func _play_global(stream: AudioStream, pitch: float, volume_db: float) -> void:
	var player := _next_free_player()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func _play_positional(stream: AudioStream, world_position: Vector3, pitch: float,
		volume_db: float) -> void:
	var scene := get_tree().current_scene as Node3D
	if scene == null:
		# Menu screens have no 3D stage; fall back to a flat one-shot.
		_play_global(stream, pitch, volume_db)
		return
	if get_tree().get_nodes_in_group(GROUP_3D_VOICES).size() >= MAX_3D_VOICES:
		return

	var player := AudioStreamPlayer3D.new()
	player.bus = _bus()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 28.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	scene.add_child(player)
	player.global_position = world_position
	player.add_to_group(GROUP_3D_VOICES)
	player.finished.connect(player.queue_free)
	player.play()


func _next_free_player() -> AudioStreamPlayer:
	for i in _players.size():
		var index := (_next_player + i) % _players.size()
		if not _players[index].playing:
			_next_player = (index + 1) % _players.size()
			return _players[index]
	# Everything is busy: steal the oldest slot rather than dropping the sound.
	var fallback := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return fallback


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = _bus()
		add_child(player)
		_players.append(player)


func _bus() -> StringName:
	return BUS_NAME if AudioServer.get_bus_index(BUS_NAME) != -1 else &"Master"


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.pressed.connect(play.bind(&"ui_click"))
