extends RefCounted
## 单关纵深道路的统一几何：所有可交互实体都必须留在此梯形内。

const EDGE_EPSILON := 0.05

var top_y: float
var bottom_y: float
var top_left: float
var top_right: float
var bottom_left: float
var bottom_right: float
var player_spawn_y: float


func _init(config: Dictionary) -> void:
	top_y = float(config.top_y)
	bottom_y = float(config.bottom_y)
	top_left = float(config.top_left)
	top_right = float(config.top_right)
	bottom_left = float(config.bottom_left)
	bottom_right = float(config.bottom_right)
	player_spawn_y = float(config.player_spawn_y)


func bounds() -> Rect2:
	var left := minf(top_left, bottom_left)
	var right := maxf(top_right, bottom_right)
	return Rect2(Vector2(left, top_y), Vector2(right - left, bottom_y - top_y))


func left_at(y: float) -> float:
	return lerpf(top_left, bottom_left, _progress(y))


func right_at(y: float) -> float:
	return lerpf(top_right, bottom_right, _progress(y))


func contains(point: Vector2, radius: float = 0.0) -> bool:
	if point.y < top_y + radius - EDGE_EPSILON or point.y > bottom_y - radius + EDGE_EPSILON:
		return false
	return point.x >= left_at(point.y) + radius - EDGE_EPSILON and point.x <= right_at(point.y) - radius + EDGE_EPSILON


func clamp_point(point: Vector2, radius: float = 0.0) -> Vector2:
	var y := clampf(point.y, top_y + radius, bottom_y - radius)
	return Vector2(clampf(point.x, left_at(y) + radius, right_at(y) - radius), y)


func player_spawn(radius: float) -> Vector2:
	return clamp_point(Vector2((left_at(player_spawn_y) + right_at(player_spawn_y)) * 0.5, player_spawn_y), radius)


func position_for_grid(col: int, cols: int, y: float, radius: float) -> Vector2:
	var left := left_at(y) + radius
	var right := right_at(y) - radius
	var t := 0.5 if cols <= 1 else float(col) / float(cols - 1)
	return Vector2(lerpf(left, right, t), y)


func column_for_x(x: float, cols: int, y: float) -> int:
	if cols <= 1:
		return 0
	var width := maxf(right_at(y) - left_at(y), 1.0)
	return clampi(roundi((x - left_at(y)) / width * float(cols - 1)), 0, cols - 1)


func left_normal() -> Vector2:
	return Vector2(1.0, -_left_slope()).normalized()


func right_normal() -> Vector2:
	return Vector2(1.0, -_right_slope()).normalized()


func max_width() -> float:
	return maxf(top_right - top_left, bottom_right - bottom_left)


func _progress(y: float) -> float:
	return clampf((y - top_y) / maxf(bottom_y - top_y, 1.0), 0.0, 1.0)


func _left_slope() -> float:
	return (bottom_left - top_left) / maxf(bottom_y - top_y, 1.0)


func _right_slope() -> float:
	return (bottom_right - top_right) / maxf(bottom_y - top_y, 1.0)
