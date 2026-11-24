extends Area3D

## Shared projectile (player crossbow and enemy shots). Motion is a manual
## raycast sweep so travel is deterministic and cheap in headless runs.

const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2
const LAYER_ENEMIES: int = 4
const LAYER_PLAYER_SHOTS: int = 8
const LAYER_ENEMY_SHOTS: int = 16

const DEFAULT_RADIUS: float = 0.16
const DEFAULT_SPEED: float = 10.0
const DEFAULT_DAMAGE: float = 10.0
const DEFAULT_LIFETIME: float = 2.0

const FRIENDLY_COLOR: Color = Color(0.55, 0.9, 1.0)
const HOSTILE_COLOR: Color = Color(1.0, 0.45, 0.2)
const EMISSION_ENERGY: float = 2.0

var _direction: Vector3 = Vector3.FORWARD
var _speed: float = DEFAULT_SPEED
var _damage: float = DEFAULT_DAMAGE
var _hostile: bool = false
var _life_left: float = DEFAULT_LIFETIME
var _configured: bool = false

var _radius: float = DEFAULT_RADIUS
var _collision: CollisionShape3D
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func configure(direction: Vector3, speed: float, damage: float, hostile: bool, lifetime: float) -> void:
	_configured = true
	_hostile = hostile
	_speed = maxf(speed, 0.0)
	_damage = damage
	_life_left = maxf(lifetime, 0.01)

	var flat := Vector3(direction.x, 0.0, direction.z)
	_direction = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD

	_apply_layers()
	if is_node_ready():
		_apply_visuals()


func get_direction() -> Vector3:
	return _direction


func get_damage() -> float:
	return _damage


func is_hostile() -> bool:
	return _hostile


func _ready() -> void:
	_radius = float(Tuning.value("combat", "projectile_radius", DEFAULT_RADIUS))
	if not _configured:
		_apply_layers()
	_build_visuals()
	_apply_visuals()


func _physics_process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return

	var from := global_position
	var to := from + _direction * _speed * delta

	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude.append(get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		_impact(hit.get("collider"))
		return
	global_position = to


func _apply_layers() -> void:
	if _hostile:
		collision_layer = LAYER_ENEMY_SHOTS
		collision_mask = LAYER_WORLD | LAYER_PLAYER
	else:
		collision_layer = LAYER_PLAYER_SHOTS
		collision_mask = LAYER_WORLD | LAYER_ENEMIES


func _build_visuals() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	_collision.shape = SphereShape3D.new()
	add_child(_collision)

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_material.emission_energy_multiplier = EMISSION_ENERGY

	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = SphereMesh.new()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _apply_visuals() -> void:
	var shape := _collision.shape as SphereShape3D
	shape.radius = _radius

	var sphere := _mesh.mesh as SphereMesh
	sphere.radius = _radius
	sphere.height = _radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6

	var color := HOSTILE_COLOR if _hostile else FRIENDLY_COLOR
	_material.albedo_color = color
	_material.emission = color


func _impact(collider: Variant) -> void:
	if collider != null and collider is Object and (collider as Object).has_method(&"take_damage"):
		collider.call(&"take_damage", _damage)
	else:
		Audio.play_at(&"bolt_wall", global_position)
	queue_free()
