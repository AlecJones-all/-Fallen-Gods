extends RefCounted
## 图标工具：读 data/icons.json（cards/builds/ichor/shards/hp）→ assets/icons/itemN.png。
## 缺失（无映射/无文件）时返回 null 或隐藏节点，不报错、不影响布局。纯 UI，无玩法影响。
## 图标为 16×16 TextureRect + scale 2（视觉 32×32），外层 Control 占位 32×32 保证容器布局不重叠。

static var _map: Dictionary = {}
static var _loaded: bool = false
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/icons.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_map = parsed


static func texture_for(key: String) -> Texture2D:
	_ensure()
	var file := ""
	var cards: Dictionary = _map.get("cards", {})
	var builds: Dictionary = _map.get("builds", {})
	if cards.has(key):
		file = str(cards[key])
	elif builds.has(key):
		file = str(builds[key])
	elif _map.get(key) is String:
		file = str(_map[key])
	if file.is_empty():
		return null
	if _cache.has(file):
		return _cache[file]
	var path := "res://assets/icons/" + file
	if not FileAccess.file_exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex != null:
		_cache[file] = tex
	return tex


## 生成图标占位 Control（内含 16×16 scale2 的 TextureRect）；缺失时占位 0×0 且隐藏。
static func make_icon(key: String) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tr := TextureRect.new()
	tr.name = "Tex"
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(16, 16)
	tr.scale = Vector2(2, 2)
	wrap.add_child(tr)
	set_icon(wrap, key)
	return wrap


## 刷新已有占位节点的图标（供 offer 等动态 key 使用）。
static func set_icon(wrap: Control, key: String) -> void:
	var tr := wrap.get_node("Tex") as TextureRect
	var tex := texture_for(key)
	if tex == null:
		tr.visible = false
		tr.texture = null
		wrap.custom_minimum_size = Vector2.ZERO
		return
	tr.texture = tex
	tr.visible = true
	wrap.custom_minimum_size = tex.get_size() * 2.0