extends CanvasLayer

var _rect: ColorRect
var _tween: Tween = null


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)


func fade_in(duration: float = 0.3) -> void:
	_kill()
	_rect.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, duration)


func fade_out_in(out_time: float = 0.2, hold: float = 0.05, in_time: float = 0.3) -> void:
	_kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, out_time)
	_tween.tween_interval(hold)
	_tween.tween_property(_rect, "modulate:a", 0.0, in_time)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null