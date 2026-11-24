extends Node3D

## Graybox test room. All geometry is generated at runtime from the "world"
## tuning block so the room stays in sync with data/tuning.json.

const GROUP_LEVEL: StringName = &"level"

const FLOOR_THICKNESS: float = 0.5
const PILLAR_SIZE: float = 0.8
const CRATE_SIZE: float = 1.0
const DOORWAY_TILES: float = 2.0
const GRID_LINE_WIDTH: float = 0.02
const GRID_LINE_HEIGHT: float = 0.006
const GRID_LINE_LIFT: float = 0.002

@onready var _player_spawn: Marker3D = $PlayerSpawn

var _tile_size: float = 2.0
var _tiles_x: int = 10
var _tiles_z: int = 10
var _wall_height: float = 3.0
var _wall_thickness: float = 0.4

var _room_width: float = 0.0
var _room_depth: float = 0.0

var _material_floor: StandardMaterial3D
var _material_wall: StandardMaterial3D
var _material_pillar: StandardMaterial3D
var _material_crate: StandardMaterial3D
var _material_grid: StandardMaterial3D

var _built: bool = false


func _ready() -> void:
	add_to_group(GROUP_LEVEL)
	if _built:
		return
	_built = true

	_read_tuning()
	_build_materials()
	_build_floor()
	_build_walls()
	_build_pillars()
	_build_crates()
	_build_grid()


func get_spawn_position() -> Vector3:
	return _player_spawn.global_position


func _read_tuning() -> void:
	_tile_size = float(Tuning.value("world", "tile_size", 2.0))
	_tiles_x = int(Tuning.value("world", "room_tiles_x", 10))
	_tiles_z = int(Tuning.value("world", "room_tiles_z", 10))
	_wall_height = float(Tuning.value("world", "wall_height", 3.0))
	_wall_thickness = float(Tuning.value("world", "wall_thickness", 0.4))

	_room_width = float(_tiles_x) * _tile_size
	_room_depth = float(_tiles_z) * _tile_size


func _build_materials() -> void:
	_material_floor = _make_material(Color(0.20, 0.21, 0.24), 0.95)
	_material_wall = _make_material(Color(0.30, 0.31, 0.35), 0.9)
	_material_pillar = _make_material(Color(0.36, 0.37, 0.41), 0.9)
	_material_crate = _make_material(Color(0.45, 0.43, 0.38), 0.8)
	_material_grid = _make_material(Color(0.06, 0.06, 0.08), 1.0)


func _make_material(albedo: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = 0.0
	return material


func _build_floor() -> void:
	var size := Vector3(_room_width, FLOOR_THICKNESS, _room_depth)
	var center := Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	_add_static_box(self, "Floor", size, center, _material_floor)


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)

	var half_width := _room_width * 0.5
	var half_depth := _room_depth * 0.5
	var half_thickness := _wall_thickness * 0.5
	var wall_y := _wall_height * 0.5
	var doorway_width := DOORWAY_TILES * _tile_size

	var north_length := half_width + half_thickness - doorway_width * 0.5
	var north_offset := doorway_width * 0.5 + north_length * 0.5
	for side: float in [-1.0, 1.0]:
		var label := "Left" if side < 0.0 else "Right"
		_add_static_box(
			walls,
			"WallNorth" + label,
			Vector3(north_length, _wall_height, _wall_thickness),
			Vector3(side * north_offset, wall_y, half_depth),
			_material_wall
		)

	_add_static_box(
		walls,
		"WallSouth",
		Vector3(_room_width + _wall_thickness, _wall_height, _wall_thickness),
		Vector3(0.0, wall_y, -half_depth),
		_material_wall
	)

	var side_length := _room_depth - _wall_thickness
	_add_static_box(
		walls,
		"WallEast",
		Vector3(_wall_thickness, _wall_height, side_length),
		Vector3(half_width, wall_y, 0.0),
		_material_wall
	)
	_add_static_box(
		walls,
		"WallWest",
		Vector3(_wall_thickness, _wall_height, side_length),
		Vector3(-half_width, wall_y, 0.0),
		_material_wall
	)


func _build_pillars() -> void:
	var pillars := Node3D.new()
	pillars.name = "Pillars"
	add_child(pillars)

	var quarter_x := _room_width * 0.25
	var quarter_z := _room_depth * 0.25
	var size := Vector3(PILLAR_SIZE, _wall_height, PILLAR_SIZE)
	var index := 1
	for x: float in [-quarter_x, quarter_x]:
		for z: float in [-quarter_z, quarter_z]:
			_add_static_box(
				pillars,
				"Pillar%d" % index,
				size,
				Vector3(x, _wall_height * 0.5, z),
				_material_pillar
			)
			index += 1


func _build_crates() -> void:
	var crates := Node3D.new()
	crates.name = "Crates"
	add_child(crates)

	var placements: Array[Vector3] = [
		Vector3(3.0, 0.0, -3.0),
		Vector3(-3.0, 0.0, 2.0),
		Vector3(6.0, 0.0, 7.0),
	]
	var yaw_angles: Array[float] = [0.25, -0.4, 0.6]
	var size := Vector3(CRATE_SIZE, CRATE_SIZE, CRATE_SIZE)
	var center_y := CRATE_SIZE * 0.5
	for i: int in placements.size():
		var placement := placements[i]
		placement.y = center_y
		_add_static_box(
			crates,
			"Crate%d" % (i + 1),
			size,
			placement,
			_material_crate,
			yaw_angles[i]
		)


func _build_grid() -> void:
	var grid := Node3D.new()
	grid.name = "Grid"
	add_child(grid)

	var half_width := _room_width * 0.5
	var half_depth := _room_depth * 0.5
	var line_y := GRID_LINE_HEIGHT * 0.5 + GRID_LINE_LIFT

	for i: int in _tiles_x + 1:
		var x := -half_width + float(i) * _tile_size
		_add_grid_line(
			grid,
			"GridX%d" % i,
			Vector3(GRID_LINE_WIDTH, GRID_LINE_HEIGHT, _room_depth),
			Vector3(x, line_y, 0.0)
		)
	for j: int in _tiles_z + 1:
		var z := -half_depth + float(j) * _tile_size
		_add_grid_line(
			grid,
			"GridZ%d" % j,
			Vector3(_room_width, GRID_LINE_HEIGHT, GRID_LINE_WIDTH),
			Vector3(0.0, line_y, z)
		)


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
	material: StandardMaterial3D,
	yaw: float = 0.0
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = center
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 1
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
