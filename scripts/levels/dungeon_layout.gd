class_name DungeonLayout
extends RefCounted

## Pure grid graph for one dungeon floor: visited cells, door bitmasks and the
## far exit. World placement stays in dungeon.gd.

const N := 1
const E := 2
const S := 4
const W := 8

const DIR_VECTORS := {
	1: Vector2i(0, 1),
	2: Vector2i(1, 0),
	4: Vector2i(0, -1),
	8: Vector2i(-1, 0),
}

const ALL_DIRECTIONS: Array[int] = [N, E, S, W]

var cells: Array[Vector2i] = []
var connections: Dictionary = {}
var start_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO


static func generate(floor_number: int, seed_value: int) -> DungeonLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var min_rooms := int(Tuning.value("dungeon", "min_rooms", 5))
	var max_rooms := int(Tuning.value("dungeon", "max_rooms", 8))
	var radius := int(Tuning.value("dungeon", "grid_radius", 2))
	var loop_chance := float(Tuning.value("dungeon", "extra_loop_chance", 0.25))
	var target := clampi(min_rooms + (floor_number - 1), min_rooms, max_rooms)

	var layout := DungeonLayout.new()
	layout.start_cell = Vector2i.ZERO

	var visited := {layout.start_cell: true}
	var stack: Array[Vector2i] = [layout.start_cell]
	layout._connect(layout.start_cell, 0)

	# Randomised DFS; if the stack dead-ends before the target, resume from any
	# visited cell that still borders unvisited space so the floor fills out.
	while visited.size() < target:
		var cell: Vector2i = stack.back()
		var options := layout._unvisited_directions(cell, visited, radius)
		if options.is_empty():
			var frontier := layout._frontier_cells(visited, radius)
			if frontier.is_empty():
				break
			stack.push_back(frontier[rng.randi_range(0, frontier.size() - 1)])
			continue
		var dir: int = options[rng.randi_range(0, options.size() - 1)]
		var next_cell: Vector2i = cell + (DIR_VECTORS[dir] as Vector2i)
		layout._connect(cell, dir)
		layout._connect(next_cell, _opposite(dir))
		visited[next_cell] = true
		stack.push_back(next_cell)

	layout.cells.assign(visited.keys())

	for cell: Vector2i in layout.cells:
		for dir: int in [E, S]:
			if layout.has_connection(cell, dir):
				continue
			if not visited.has(cell + (DIR_VECTORS[dir] as Vector2i)):
				continue
			if rng.randf() >= loop_chance:
				continue
			layout._connect(cell, dir)
			layout._connect(cell + (DIR_VECTORS[dir] as Vector2i), _opposite(dir))

	layout.exit_cell = layout._farthest_cell(rng)
	return layout


func has_connection(cell: Vector2i, dir: int) -> bool:
	if not connections.has(cell):
		return false
	return (int(connections[cell]) & dir) != 0


func _connect(cell: Vector2i, dir: int) -> void:
	connections[cell] = int(connections.get(cell, 0)) | dir


func _unvisited_directions(cell: Vector2i, visited: Dictionary, radius: int) -> Array[int]:
	var options: Array[int] = []
	for dir: int in ALL_DIRECTIONS:
		var next_cell: Vector2i = cell + (DIR_VECTORS[dir] as Vector2i)
		if absi(next_cell.x) > radius or absi(next_cell.y) > radius:
			continue
		if visited.has(next_cell):
			continue
		options.append(dir)
	return options


func _frontier_cells(visited: Dictionary, radius: int) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in visited:
		if not _unvisited_directions(cell, visited, radius).is_empty():
			frontier.append(cell)
	return frontier


func _farthest_cell(rng: RandomNumberGenerator) -> Vector2i:
	var distances := {start_cell: 0}
	var queue: Array[Vector2i] = [start_cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for dir: int in ALL_DIRECTIONS:
			if not has_connection(cell, dir):
				continue
			var next_cell: Vector2i = cell + (DIR_VECTORS[dir] as Vector2i)
			if distances.has(next_cell):
				continue
			distances[next_cell] = int(distances[cell]) + 1
			queue.push_back(next_cell)

	var deepest := 0
	for cell: Vector2i in distances:
		deepest = maxi(deepest, int(distances[cell]))

	var candidates: Array[Vector2i] = []
	for cell: Vector2i in distances:
		if int(distances[cell]) == deepest:
			candidates.append(cell)
	if candidates.is_empty():
		return start_cell
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _opposite(dir: int) -> int:
	match dir:
		N:
			return S
		E:
			return W
		S:
			return N
		W:
			return E
	return 0
