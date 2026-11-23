extends Node2D
## 战斗特效池：AnimatedSprite2D 复用，并发上限 MAX_SPRITES（H5 性能）。
## 纯视觉层：不参与任何判定/数值/信号契约。
## 一次性特效（death/hit）播完自动回池；循环特效（burn/aura）按 id 管理，随挂接方清除。
## z_index：aura=-1 垫底（怪色块之下、背景之上），其余 1 盖在怪之上。

const MAX_SPRITES := 48
const FRAMES := {
	"death": preload("res://assets/fx/effects/explosions/explosion-fire-48-a.tres"),
	"hit": preload("res://assets/fx/effects/hit-sparks/hit-spark-white-32.tres"),
	"burn": preload("res://assets/fx/loops/flames/flame-fire-32.tres"),
	"aura": preload("res://assets/fx/loops/auras/aura-gold-48.tres"),
}
const Z_ORDER := {"death": 1, "hit": 1, "burn": 1, "aura": -1}

var _free: Array = []          # 空闲池
var _ones: Array = []          # 播放中的一次性特效
var _loops: Dictionary = {}    # "kind:id" -> AnimatedSprite2D
var _created: int = 0


## 一次性播放（怪死亡爆炸 / 弹球撞怪火花）；池满时丢弃本次视觉，不影响逻辑。
func burst(kind: String, pos: Vector2) -> void:
	var s := _take()
	if s == null:
		return
	_configure(s, kind, pos)
	_ones.append(s)
	s.play()


## 循环特效挂接/跟随（灼烧火苗 / 精英光环）；同 kind+id 只保留一个并更新位置。
func set_loop(kind: String, id: int, pos: Vector2) -> void:
	var key := kind + ":" + str(id)
	var s: AnimatedSprite2D = _loops.get(key)
	if s == null:
		s = _take()
		if s == null:
			return
		_loops[key] = s
		_configure(s, kind, pos)
		s.play()
	else:
		s.position = pos


## 移除某 id 的全部循环特效（怪死）。
func clear_loop(id: int) -> void:
	clear_kind("burn", id)
	clear_kind("aura", id)


## 移除某 id 的指定循环特效（burn 结束但怪仍存活时只清火苗，保留精英光环）。
func clear_kind(kind: String, id: int) -> void:
	var key := kind + ":" + str(id)
	var s: AnimatedSprite2D = _loops.get(key)
	if s != null:
		_loops.erase(key)
		_release(s)


## 关卡重置：回收所有在播特效。
func reset() -> void:
	for key in _loops.keys():
		_release(_loops[key])
	_loops.clear()
	for s in _ones.duplicate():
		_ones.erase(s)
		_release(s)


func _take() -> AnimatedSprite2D:
	if not _free.is_empty():
		return _free.pop_back()
	if _created >= MAX_SPRITES:
		return null
	var s := AnimatedSprite2D.new()
	s.animation_finished.connect(_on_finished.bind(s))
	add_child(s)
	_created += 1
	return s


func _configure(s: AnimatedSprite2D, kind: String, pos: Vector2) -> void:
	s.sprite_frames = FRAMES[kind]
	s.animation = &"default"
	s.frame = 0
	s.position = pos
	s.z_index = Z_ORDER[kind]
	s.visible = true


func _on_finished(s: AnimatedSprite2D) -> void:
	# 循环动画不触发 finished；此处只回收一次性特效
	_ones.erase(s)
	_release(s)


func _release(s: AnimatedSprite2D) -> void:
	s.stop()
	s.visible = false
	_free.append(s)