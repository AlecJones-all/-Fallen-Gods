extends Node3D

## Procedural multi-room floor. Room geometry is rebuilt per floor from the
## "world"/"dungeon" tuning blocks; main owns the floor lifecycle and calls
## build_floor() after the portal completes.

signal status_changed(floor_number: int, cleared: int, total: int, enemies_left: int, active_left: int)
signal floor_completed(next_floor: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const GROUP_DUNGEON: StringName = &"dungeon"
const GROUP_PLAYER: StringName = &"player"
const GROUP_PROJECTILES: StringName = &"projectile_root"

const FLOOR_THICKNESS: float = 0.5
const GRID_LINE_WIDTH: float = 0.02
const GRID_LINE_HEIGHT: float = 0.006
const GRID_LINE_LIFT: float = 0.002
const DOOR_OPEN_TIME: float = 0.35
const DOOR_CLOSE_TIME: float = 0.22
const SPAWN_MARGIN: float = 2.0
const SPAWN_PLAYER_CLEARANCE: float = 3.0
const SPAWN_SPACING: float = 1.5
const MAX_ENEMIES_PER_ROOM: int = 8
const PORTAL_RING_HEIGHT: float = 0.06
const PORTAL_DISC_HEIGHT: float = 0.03

var floor_number: int = 1
var _rooms: Array[Dictionary] = []
var _start_index: int = 0
var _exit_index: int = 0
var _active_index: int = -1
var _geometry: Node3D
var _projectiles: Node3D
var _portal_area: Area3D
var _portal_material: StandardMaterial3D
var _portal_timer: Timer
var _descending: bool = false

var _tile_size: float = 2.0
var _room_width: float = 20.0
var _room_depth: float = 20.0
var _wall_height: float = 3.0
var _wall_thickness: float = 0.4
var _corridor_length: float = 6.0
var _corridor_width: float = 4.0
var _door_width: float = 4.0
var _enemies_base: float = 2.0
var _enemies_per_floor: float = 0.5
var _shooter_chance: float = 0.3
var _shooter_chance_per_floor: float = 0.04
var _portal_dwell: float = 0.6

var _material_floor: StandardMaterial3D
var _material_wall: StandardMaterial3D
var _material_door: StandardMaterial3D
var _material_grid: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP_DUNGEON)
	_read_tuning()
	_build_materials()

	_portal_timer = Timer.new()
	_portal_timer.name = "PortalTimer"
	_portal_timer.one_shot = true
	_portal_timer.wait_time = _portal_dwell
	_portal_timer.timeout.connect(_on_portal_timeout)
	add_child(_portal_timer)


func build_floor(number: int) -> void:
	floor_number = number
	_descending = false
	_active_index = -1
	_rooms.clear()
	_start_index = 0
	_exit_index = 0
	_portal_area = null
	if is_instance_valid(_portal_timer):
		_portal_timer.stop()
	# main rebuilds deferred, so freeing the old floor immediately is safe.
	if is_instance_valid(_geometry):
		_geometry.free()
	if is_instance_valid(_projectiles):
		_projectiles.free()

	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)
	for container_name: String in ["Rooms", "Corridors", "Doors", "Triggers", "Portal"]:
		_make_container(_geometry, container_name)

	_projectiles = Node3D.new()
	_projectiles.name = "Projectiles"
	_projectiles.add_to_group(GROUP_PROJECTILES)
	add_child(_projectiles)

	_apply_locked_portal_look()

	var layout := DungeonLayout.generate(number, randi())
	var index_of := {}
	for i: int in layout.cells.size():
		index_of[layout.cells[i]] = i
	_start_index = int(index_of.get(layout.start_cell, 0))
	_exit_index = int(index_of.get(layout.exit_cell, 0))

	for i: int in layout.cells.size():
		_rooms.append(_build_room(i, layout.cells[i], layout))
	_build_corridors(layout)
	_build_portal()
	_emit_status()


func activate_room(index: int) -> void:
	if index < 0 or index >= _rooms.size():
		return
	var room: Dictionary = _rooms[index]
	if bool(room["cleared"]) or bool(room["activated"]) or _descending:
		return
	var player := _get_player()
	if player == null:
		return
	if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
		return

	room["activated"] = true
	_active_index = index
	_close_doors(room)
	Audio.play_at(&"door_close", room["center"])
	_spawn_enemies(index, player)
	_emit_status()


func get_floor_number() -> int:
	return floor_number


func get_room_count() -> int:
	return _rooms.size()


func get_room_total() -> int:
	return maxi(_rooms.size() - 1, 0)


func get_cleared_count() -> int:
	var count := 0
	for i: int in _rooms.size():
		if i == _start_index:
			continue
		if bool(_rooms[i]["cleared"]):
			count += 1
	return count


func get_enemies_alive_total() -> int:
	var total := 0
	for room: Dictionary in _rooms:
		var enemies: Array = room["enemies"]
		total += enemies.size()
	return total


func get_active_enemies_left() -> int:
	if _active_index < 0 or _active_index >= _rooms.size():
		return 0
	var enemies: Array = _rooms[_active_index]["enemies"]
	return enemies.size()


func get_start_room_index() -> int:
	return _start_index


func get_exit_room_index() -> int:
	return _exit_index


func get_room_center(index: int) -> Vector3:
	if index < 0 or index >= _rooms.size():
		return Vector3.ZERO
	var center: Vector3 = _rooms[index]["center"]
	return center


func get_spawn_position() -> Vector3:
	var center := get_room_center(_start_index)
	return Vector3(center.x, 0.0, center.z)


func get_exit_position() -> Vector3:
	var center := get_room_center(_exit_index)
	return Vector3(center.x, 0.0, center.z)


func is_room_cleared(index: int) -> bool:
	if index < 0 or index >= _rooms.size():
		return false
	return bool(_rooms[index]["cleared"])


func _read_tuning() -> void:
	_tile_size = maxf(float(Tuning.value("world", "tile_size", 2.0)), 0.5)
	_room_width = float(int(Tuning.value("world", "room_tiles_x", 10))) * _tile_size
	_room_depth = float(int(Tuning.value("world", "room_tiles_z", 10))) * _tile_size
	_wall_height = float(Tuning.value("world", "wall_height", 3.0))
	_wall_thickness = float(Tuning.value("world", "wall_thickness", 0.4))

	_corridor_length = float(Tuning.value("dungeon", "corridor_length", 6.0))
	_corridor_width = float(Tuning.value("dungeon", "corridor_width", 4.0))
	_door_width = float(Tuning.value("dungeon", "door_width", 4.0))
	_enemies_base = float(Tuning.value("dungeon", "enemies_base", 2))
	_enemies_per_floor = float(Tuning.value("dungeon", "enemies_per_floor", 0.5))
	_shooter_chance = float(Tuning.value("dungeon", "shooter_chance", 0.3))
	_shooter_chance_per_floor = float(Tuning.value("dungeon", "shooter_chance_per_floor", 0.04))
	_portal_dwell = float(Tuning.value("dungeon", "portal_dwell", 0.6))


func _build_materials() -> void:
	_material_floor = _make_material(Color(0.20, 0.21, 0.24), 0.95)
	_material_wall = _make_material(Color(0.30, 0.31, 0.35), 0.9)
	_material_grid = _make_material(Color(0.06, 0.06, 0.08), 1.0)

	_material_door = _make_material(Color(0.40, 0.33, 0.28), 0.8)
	_material_door.emission_enabled = true
	_material_door.emission = Color(0.35, 0.22, 0.1)
	_material_door.emission_energy_multiplier = 0.25

	_portal_material = StandardMaterial3D.new()
	_portal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_portal_material.roughness = 0.6


func _apply_locked_portal_look() -> void:
	if _portal_material == null:
		return
	_portal_material.albedo_color = Color(0.32, 0.35, 0.42)
	_portal_material.emission_enabled = true
	_portal_material.emission = Color(0.30, 0.35, 0.45)
	_portal_material.emission_energy_multiplier = 0.5


func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _make_container(parent: Node3D, container_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = container_name
	parent.add_child(node)
	return node


func _cell_center(cell: Vector2i) -> Vector3:
	var step_x := _room_width + _corridor_length
	var step_z := _room_depth + _corridor_length
	return Vector3(float(cell.x) * step_x, 0.0, float(cell.y) * step_z)


func _build_room(index: int, cell: Vector2i, layout: DungeonLayout) -> Dictionary:
	var center := _cell_center(cell)
	var mask := int(layout.connections.get(cell, 0))

	var room_root := Node3D.new()
	room_root.name = "Room%d" % index
	(_geometry.get_node("Rooms") as Node3D).add_child(room_root)

	var room := {
		"cell": cell,
		"center": center,
		"connections": mask,
		"cleared": false,
		"activated": false,
		"enemies": [],
		"doors": [],
		"trigger": null,
	}

	_build_room_floor(room_root, center)
	_build_room_walls(room_root, center, mask)
	_build_room_grid(room_root, center)
	_build_room_doors(room, center, mask, index)
	if index != _start_index:
		_build_room_trigger(room, center, index)
	else:
		room["cleared"] = true
		room["activated"] = true
		_open_doors(room, true)
	return room


func _build_room_floor(parent: Node3D, center: Vector3) -> void:
	var size := Vector3(_room_width, FLOOR_THICKNESS, _room_depth)
	var offset := Vector3(center.x, -FLOOR_THICKNESS * 0.5, center.z)
	_add_static_box(parent, "Floor", size, offset, _material_floor)


func _build_room_walls(parent: Node3D, center: Vector3, mask: int) -> void:
	var half_width := _room_width * 0.5
	var half_depth := _room_depth * 0.5
	var half_thickness := _wall_thickness * 0.5
	var wall_y := _wall_height * 0.5
	var gap := _door_width * 0.5

	for dir: int in DungeonLayout.ALL_DIRECTIONS:
		var suffix := _direction_suffix(dir)
		var side := 1.0 if dir == DungeonLayout.N or dir == DungeonLayout.E else -1.0
		var along_x := dir == DungeonLayout.N or dir == DungeonLayout.S
		var has_door := (mask & dir) != 0

		if along_x:
			var line_z: float = center.z + side * half_depth
			if not has_door:
				_add_static_box(
					parent,
					"Wall" + suffix,
					Vector3(_room_width + _wall_thickness, _wall_height, _wall_thickness),
					Vector3(center.x, wall_y, line_z),
					_material_wall
				)
				continue
			var segment := half_width + half_thickness - gap
			for segment_side: float in [-1.0, 1.0]:
				var label := "Left" if segment_side < 0.0 else "Right"
				_add_static_box(
					parent,
					"Wall%s%s" % [suffix, label],
					Vector3(segment, _wall_height, _wall_thickness),
					Vector3(center.x + segment_side * (gap + segment * 0.5), wall_y, line_z),
					_material_wall
				)
		else:
			var line_x: float = center.x + side * half_width
			if not has_door:
				_add_static_box(
					parent,
					"Wall" + suffix,
					Vector3(_wall_thickness, _wall_height, _room_depth - _wall_thickness),
					Vector3(line_x, wall_y, center.z),
					_material_wall
				)
				continue
			var segment := half_depth + half_thickness - gap
			for segment_side: float in [-1.0, 1.0]:
				var label := "Left" if segment_side < 0.0 else "Right"
				_add_static_box(
					parent,
					"Wall%s%s" % [suffix, label],
					Vector3(_wall_thickness, _wall_height, segment),
					Vector3(line_x, wall_y, center.z + segment_side * (gap + segment * 0.5)),
					_material_wall
				)


func _build_room_grid(parent: Node3D, center: Vector3) -> void:
	var grid := Node3D.new()
	grid.name = "Grid"
	parent.add_child(grid)

	var half_width := _room_width * 0.5
	var half_depth := _room_depth * 0.5
	var line_y := GRID_LINE_HEIGHT * 0.5 + GRID_LINE_LIFT
	var tiles_x := maxi(int(round(_room_width / _tile_size)), 1)
	var tiles_z := maxi(int(round(_room_depth / _tile_size)), 1)

	for i: int in tiles_x + 1:
		var x := center.x - half_width + float(i) * (_room_width / float(tiles_x))
		_add_grid_line(
			grid,
			"GridX%d" % i,
			Vector3(GRID_LINE_WIDTH, GRID_LINE_HEIGHT, _room_depth),
			Vector3(x, line_y, center.z)
		)
	for j: int in tiles_z + 1:
		var z := center.z - half_depth + float(j) * (_room_depth / float(tiles_z))
		_add_grid_line(
			grid,
			"GridZ%d" % j,
			Vector3(_room_width, GRID_LINE_HEIGHT, GRID_LINE_WIDTH),
			Vector3(center.x, line_y, z)
		)


func _build_room_doors(room: Dictionary, center: Vector3, mask: int, index: int) -> void:
	var doors_root := _geometry.get_node("Doors") as Node3D
	var doors: Array = room["doors"]
	var half_width := _room_width * 0.5
	var half_depth := _room_depth * 0.5

	for dir: int in DungeonLayout.ALL_DIRECTIONS:
		if (mask & dir) == 0:
			continue

		var root := Node3D.new()
		root.name = "Room%dDoor%s" % [index, _direction_suffix(dir)]
		match dir:
			DungeonLayout.N:
				root.position = center + Vector3(0.0, 0.0, half_depth)
			DungeonLayout.S:
				root.position = center + Vector3(0.0, 0.0, -half_depth)
			DungeonLayout.E:
				root.position = center + Vector3(half_width, 0.0, 0.0)
			DungeonLayout.W:
				root.position = center + Vector3(-half_width, 0.0, 0.0)
		doors_root.add_child(root)

		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 0
		body.collision_mask = 0
		root.add_child(body)

		var along_x := dir == DungeonLayout.N or dir == DungeonLayout.S
		var size := Vector3(_door_width, _wall_height, _wall_thickness)
		if not along_x:
			size = Vector3(_wall_thickness, _wall_height, _door_width)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		mesh_instance.material_override = _material_door
		mesh_instance.position = Vector3(0.0, _wall_height * 0.5, 0.0)
		body.add_child(mesh_instance)

		var shape_node := CollisionShape3D.new()
		shape_node.name = "Collision"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape_node.shape = box_shape
		shape_node.position = Vector3(0.0, _wall_height * 0.5, 0.0)
		body.add_child(shape_node)

		# Doors start sunk below the floor, i.e. open.
		root.visible = false
		body.position.y = -_wall_height
		doors.append({"root": root, "body": body})


func _build_room_trigger(room: Dictionary, center: Vector3, index: int) -> void:
	var trigger := Area3D.new()
	trigger.name = "Trigger%d" % index
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitorable = false
	trigger.position = center + Vector3(0.0, 1.0, 0.0)

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(_room_width - 4.0, 2.0, _room_depth - 4.0)
	shape_node.shape = box_shape
	trigger.add_child(shape_node)

	(_geometry.get_node("Triggers") as Node3D).add_child(trigger)
	trigger.body_entered.connect(_on_room_trigger.bind(index))
	room["trigger"] = trigger


func _build_corridors(layout: DungeonLayout) -> void:
	var corridor_index := 0
	for cell: Vector2i in layout.cells:
		for dir: int in [DungeonLayout.E, DungeonLayout.S]:
			if not layout.has_connection(cell, dir):
				continue
			var other: Vector2i = cell + (DungeonLayout.DIR_VECTORS[dir] as Vector2i)
			_build_corridor(_cell_center(cell), _cell_center(other), dir, corridor_index)
			corridor_index += 1


func _build_corridor(from_center: Vector3, to_center: Vector3, dir: int, corridor_index: int) -> void:
	var corridor := Node3D.new()
	corridor.name = "Corridor%d" % corridor_index
	(_geometry.get_node("Corridors") as Node3D).add_child(corridor)

	var mid := (from_center + to_center) * 0.5
	var along_x := dir == DungeonLayout.E
	var width := _corridor_width
	var wall_offset := width * 0.5 + _wall_thickness * 0.5

	var floor_size := Vector3(_corridor_length, FLOOR_THICKNESS, width)
	if not along_x:
		floor_size = Vector3(width, FLOOR_THICKNESS, _corridor_length)
	var floor_center := Vector3(mid.x, -FLOOR_THICKNESS * 0.5, mid.z)
	_add_static_box(corridor, "Floor", floor_size, floor_center, _material_floor)

	for side: float in [-1.0, 1.0]:
		if along_x:
			_add_static_box(
				corridor,
				"Wall",
				Vector3(_corridor_length, _wall_height, _wall_thickness),
				Vector3(mid.x, _wall_height * 0.5, mid.z + side * wall_offset),
				_material_wall
			)
		else:
			_add_static_box(
				corridor,
				"Wall",
				Vector3(_wall_thickness, _wall_height, _corridor_length),
				Vector3(mid.x + side * wall_offset, _wall_height * 0.5, mid.z),
				_material_wall
			)


func _build_portal() -> void:
	var center := get_exit_position()
	var portal_root := _geometry.get_node("Portal") as Node3D

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus_mesh := TorusMesh.new()
	torus_mesh.inner_radius = 0.9
	torus_mesh.outer_radius = 1.3
	torus_mesh.rings = 32
	torus_mesh.ring_segments = 16
	ring.mesh = torus_mesh
	ring.material_override = _portal_material
	ring.position = center + Vector3(0.0, PORTAL_RING_HEIGHT, 0.0)
	portal_root.add_child(ring)

	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.9
	disc_mesh.bottom_radius = 0.9
	disc_mesh.height = 0.05
	disc_mesh.radial_segments = 32
	disc.mesh = disc_mesh
	disc.material_override = _portal_material
	disc.position = center + Vector3(0.0, PORTAL_DISC_HEIGHT, 0.0)
	portal_root.add_child(disc)

	_portal_area = Area3D.new()
	_portal_area.name = "PortalArea"
	_portal_area.collision_layer = 0
	_portal_area.collision_mask = 2
	_portal_area.monitorable = false
	_portal_area.position = center + Vector3(0.0, 1.0, 0.0)

	var shape_node := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 1.1
	cylinder_shape.height = 2.0
	shape_node.shape = cylinder_shape
	_portal_area.add_child(shape_node)

	_portal_area.body_entered.connect(_on_portal_body_entered)
	_portal_area.body_exited.connect(_on_portal_body_exited)
	portal_root.add_child(_portal_area)


func _spawn_enemies(index: int, player: Node3D) -> void:
	var room: Dictionary = _rooms[index]
	var count := clampi(
		roundi(_enemies_base + float(floor_number - 1) * _enemies_per_floor) + randi_range(-1, 1),
		2,
		MAX_ENEMIES_PER_ROOM
	)
	var shooter_chance := clampf(
		_shooter_chance + float(floor_number - 1) * _shooter_chance_per_floor,
		0.0,
		0.6
	)

	var kinds: Array[StringName] = []
	for i: int in count:
		kinds.append(&"shooter" if randf() < shooter_chance else &"grunt")
	if index == _exit_index:
		kinds.append(&"grunt")
		kinds.append(&"grunt")
		kinds.append(&"brute")

	var center: Vector3 = room["center"]
	var points := _pick_spawn_points(kinds.size(), player.global_position, center)
	var enemies: Array = room["enemies"]
	var spawn_root := _get_enemy_root(index)

	for i: int in kinds.size():
		var enemy := ENEMY_SCENE.instantiate() as Node3D
		if enemy == null:
			continue
		enemy.call(&"configure", kinds[i], floor_number, points[i])
		spawn_root.add_child(enemy)
		if enemy.has_signal(&"died"):
			# Enemy emits died(self); adapt to the room bookkeeping signature.
			enemy.connect(&"died", func(_reported: Node) -> void: _on_enemy_died(index, enemy))
		enemies.append(enemy)


func _pick_spawn_points(count: int, player_position: Vector3, center: Vector3) -> Array[Vector3]:
	var half_x := maxf(_room_width * 0.5 - SPAWN_MARGIN, 0.5)
	var half_z := maxf(_room_depth * 0.5 - SPAWN_MARGIN, 0.5)
	var player_flat := Vector3(player_position.x, 0.0, player_position.z)
	var points: Array[Vector3] = []

	for i: int in count:
		var chosen := Vector3.INF
		for attempt: int in 30:
			var candidate := Vector3(
				center.x + randf_range(-half_x, half_x),
				0.0,
				center.z + randf_range(-half_z, half_z)
			)
			if _spawn_is_valid(candidate, player_flat, points, SPAWN_PLAYER_CLEARANCE, SPAWN_SPACING):
				chosen = candidate
				break
		if not chosen.is_finite():
			# Relax the keep-away rules after the first pass exhausts its budget.
			var player_clearance := SPAWN_PLAYER_CLEARANCE
			var spacing := SPAWN_SPACING
			for attempt: int in 120:
				player_clearance = maxf(player_clearance - 0.02, 1.0)
				spacing = maxf(spacing - 0.01, 0.6)
				var candidate := Vector3(
					center.x + randf_range(-half_x, half_x),
					0.0,
					center.z + randf_range(-half_z, half_z)
				)
				if _spawn_is_valid(candidate, player_flat, points, player_clearance, spacing):
					chosen = candidate
					break
		if not chosen.is_finite():
			chosen = Vector3(center.x, 0.0, center.z)
		points.append(chosen)
	return points


func _spawn_is_valid(candidate: Vector3, player_flat: Vector3, points: Array[Vector3], clearance: float, spacing: float) -> bool:
	if candidate.distance_to(player_flat) < clearance:
		return false
	for other: Vector3 in points:
		if candidate.distance_to(other) < spacing:
			return false
	return true


func _get_enemy_root(index: int) -> Node3D:
	var root_name := "Enemies%d" % index
	var existing := _geometry.get_node_or_null(NodePath(root_name)) as Node3D
	if existing != null:
		return existing
	var root := Node3D.new()
	root.name = root_name
	_geometry.add_child(root)
	return root


func _on_enemy_died(index: int, enemy: Node3D) -> void:
	if index < 0 or index >= _rooms.size():
		return
	var room: Dictionary = _rooms[index]
	var enemies: Array = room["enemies"]
	enemies.erase(enemy)
	if not bool(room["cleared"]) and enemies.is_empty():
		_clear_room(index)
	_emit_status()


func _clear_room(index: int) -> void:
	var room: Dictionary = _rooms[index]
	room["cleared"] = true
	_open_doors(room, false)
	Audio.play_at(&"door_open", room["center"])
	Audio.play_at(&"room_clear", room["center"])
	if index == _active_index:
		_active_index = -1
	if index == _exit_index:
		_unlock_portal()
		if _player_inside_portal() and is_instance_valid(_portal_timer) and not _descending:
			_portal_timer.start()
	_emit_status()


func _unlock_portal() -> void:
	Audio.play(&"portal_unlock")
	if _portal_material == null:
		return
	_portal_material.albedo_color = Color(1.0, 0.55, 0.15)
	_portal_material.emission = Color(1.0, 0.55, 0.15)
	_portal_material.emission_energy_multiplier = 2.2


func _player_inside_portal() -> bool:
	if _portal_area == null or not is_instance_valid(_portal_area):
		return false
	for body: Node3D in _portal_area.get_overlapping_bodies():
		if body.is_in_group(GROUP_PLAYER):
			return true
	return false


func _open_doors(room: Dictionary, instant: bool) -> void:
	var doors: Array = room["doors"]
	for door: Dictionary in doors:
		var root: Node3D = door["root"]
		var body: StaticBody3D = door["body"]
		if not is_instance_valid(root) or not is_instance_valid(body):
			continue
		if not root.visible and int(body.collision_layer) == 0 and is_equal_approx(body.position.y, -_wall_height):
			continue
		if instant:
			body.collision_layer = 0
			body.position.y = -_wall_height
			root.visible = false
			continue
		body.collision_layer = 0
		var tween := create_tween()
		tween.tween_property(body, "position:y", -_wall_height, DOOR_OPEN_TIME)
		tween.tween_callback(root.hide)


func _close_doors(room: Dictionary) -> void:
	var doors: Array = room["doors"]
	for door: Dictionary in doors:
		var root: Node3D = door["root"]
		var body: StaticBody3D = door["body"]
		if not is_instance_valid(root) or not is_instance_valid(body):
			continue
		if root.visible and int(body.collision_layer) == 1 and is_equal_approx(body.position.y, 0.0):
			continue
		root.visible = true
		body.collision_layer = 1
		var tween := create_tween()
		tween.tween_property(body, "position:y", 0.0, DOOR_CLOSE_TIME)


func _on_room_trigger(_body: Node3D, index: int) -> void:
	activate_room(index)


func _on_portal_body_entered(body: Node3D) -> void:
	if _descending or not body.is_in_group(GROUP_PLAYER):
		return
	if _exit_index < 0 or _exit_index >= _rooms.size():
		return
	if not bool(_rooms[_exit_index]["cleared"]):
		return
	if is_instance_valid(_portal_timer):
		_portal_timer.start()


func _on_portal_body_exited(body: Node3D) -> void:
	if body.is_in_group(GROUP_PLAYER) and is_instance_valid(_portal_timer):
		_portal_timer.stop()


func _on_portal_timeout() -> void:
	if _descending:
		return
	_descending = true
	Audio.play(&"portal_enter")
	floor_completed.emit(floor_number + 1)


func _get_player() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var node := tree.get_first_node_in_group(GROUP_PLAYER)
	return node as Node3D


func _emit_status() -> void:
	status_changed.emit(
		floor_number,
		get_cleared_count(),
		get_room_total(),
		get_enemies_alive_total(),
		get_active_enemies_left()
	)


func _direction_suffix(dir: int) -> String:
	match dir:
		DungeonLayout.N:
			return "N"
		DungeonLayout.E:
			return "E"
		DungeonLayout.S:
			return "S"
		DungeonLayout.W:
			return "W"
	return "?"


func _add_grid_line(parent: Node3D, line_name: String, size: Vector3, center: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = line_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = _material_grid
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = center
	parent.add_child(mesh_instance)


func _add_static_box(
	parent: Node3D,
	body_name: String,
	size: Vector3,
	center: Vector3,
	material: StandardMaterial3D
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var shape_node := CollisionShape3D.new()
	shape_node.name = "Collision"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	body.add_child(shape_node)

	return body
