extends Node

## Small feedback toolbox shared by player, enemies and the HUD: hit-stop,
## camera shake, floating damage numbers, dash ghosts and death shards.

const GROUP_DAMAGE_NUMBERS: StringName = &"damage_numbers"
const GROUP_FX_TRANSIENT: StringName = &"fx_transient"
const GROUP_HIT_SPARKS: StringName = &"hit_sparks"
const SPARK_RAYS: int = 5
const SPARK_MELEE_COLOR := Color(1.0, 0.84, 0.42)
const SPARK_RANGED_COLOR := Color(0.55, 0.9, 1.0)

const DAMAGE_RISE: float = 1.0
const DAMAGE_LIFETIME: float = 0.55
const DAMAGE_FONT_SIZE: int = 72
const DAMAGE_PIXEL_SIZE: float = 0.006
const DAMAGE_OUTLINE: int = 12
const DAMAGE_OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)

const GHOST_LIFETIME: float = 0.25
const GHOST_COLOR: Color = Color(0.45, 0.9, 1.0, 0.4)

const SHARD_COUNT: int = 7
const SHARD_LIFETIME: float = 0.35
const SHARD_SIZE: float = 0.18
const SHARD_END_SCALE: float = 0.05

var _hitstop_scale: float = 0.08
var _stop_until_msec: int = 0
var _impacts: Dictionary = {}
var _impact_interval_msec: int = 160
var _impact_until_msec: int = 0
var _impact_priority: int = -1
var _spark_sec: float = 0.09
var _spark_melee_size: float = 0.24
var _spark_ranged_size: float = 0.14


func _ready() -> void:
	# Feedback must keep ticking while the tree is paused so time_scale is restored.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fx: Dictionary = Tuning.section("fx")
	_hitstop_scale = clampf(float(fx.get("hitstop_scale", _hitstop_scale)), 0.01, 1.0)
	_impacts = fx["impacts"]
	_impact_interval_msec = int(float(fx.get("impact_interval_sec", 0.16)) * 1000.0)
	_spark_sec = float(fx.get("spark_sec", _spark_sec))
	_spark_melee_size = float(fx.get("spark_melee_size", _spark_melee_size))
	_spark_ranged_size = float(fx.get("spark_ranged_size", _spark_ranged_size))


func _process(_delta: float) -> void:
	if _stop_until_msec <= 0:
		return
	# Hit-stop is measured on the wall clock: Engine.time_scale also slows any
	# timer we could use to measure its own duration.
	if Time.get_ticks_msec() >= _stop_until_msec:
		_stop_until_msec = 0
		Engine.time_scale = 1.0


func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	_stop_until_msec = maxi(_stop_until_msec, until)
	Engine.time_scale = minf(Engine.time_scale, _hitstop_scale)


func impact(kind: StringName) -> void:
	var profile: Dictionary = _impacts[String(kind)]
	var priority := int(profile["priority"])
	var now := Time.get_ticks_msec()
	if now < _impact_until_msec and priority <= _impact_priority:
		return
	_impact_until_msec = now + _impact_interval_msec
	_impact_priority = priority
	hitstop(float(profile["hitstop_sec"]))
	shake(float(profile["shake"]), float(profile["shake_time"]))


func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var rig := camera.get_parent()
	if rig != null and rig.has_method(&"add_shake"):
		rig.call(&"add_shake", strength, duration)


func hit_spark(world_position: Vector3, ranged: bool = false) -> void:
	var parent := _fx_parent()
	if parent == null:
		return
	var size := _spark_ranged_size if ranged else _spark_melee_size
	var vertices := PackedVector3Array()
	for i in SPARK_RAYS:
		var angle := TAU * float(i) / float(SPARK_RAYS)
		var direction := Vector3(cos(angle), sin(angle), 0.0)
		var side := Vector3(-sin(angle), cos(angle), 0.0) * size * 0.08
		var inner := direction * size * 0.1
		var outer := direction * size
		vertices.append_array(PackedVector3Array([
			inner - side, inner + side, outer + side,
			inner - side, outer + side, outer - side]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = SPARK_RANGED_COLOR if ranged else SPARK_MELEE_COLOR
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 1.8
	var spark := MeshInstance3D.new()
	spark.name = "RangedHitSpark" if ranged else "MeleeHitSpark"
	spark.mesh = mesh
	spark.material_override = material
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(spark)
	spark.global_position = world_position
	spark.add_to_group(GROUP_HIT_SPARKS)
	spark.add_to_group(GROUP_FX_TRANSIENT)
	var tween := spark.create_tween().set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3.ONE * 0.25, _spark_sec)
	tween.tween_property(spark, "transparency", 1.0, _spark_sec)
	tween.chain().tween_callback(spark.queue_free)


func damage_number(world_position: Vector3, amount: float, color: Color = Color.WHITE,
		scale_mult: float = 1.0) -> void:
	var parent := _fx_parent()
	if parent == null or amount <= 0.0:
		return

	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.font_size = int(round(DAMAGE_FONT_SIZE * clampf(scale_mult, 0.4, 3.0)))
	label.pixel_size = DAMAGE_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_size = DAMAGE_OUTLINE
	label.outline_modulate = DAMAGE_OUTLINE_COLOR
	label.render_priority = 10
	parent.add_child(label)
	label.global_position = world_position
	label.add_to_group(GROUP_DAMAGE_NUMBERS)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", world_position + Vector3.UP * DAMAGE_RISE,
		DAMAGE_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_LIFETIME * 0.5) \
		.set_delay(DAMAGE_LIFETIME * 0.5)
	tween.chain().tween_callback(label.queue_free)


func dash_ghost(world_position: Vector3, radius: float, height: float) -> void:
	var parent := _fx_parent()
	if parent == null:
		return

	var ghost := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	ghost.mesh = capsule

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GHOST_COLOR
	ghost.material_override = material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	parent.add_child(ghost)
	ghost.global_position = world_position
	ghost.add_to_group(GROUP_FX_TRANSIENT)

	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "transparency", 1.0, GHOST_LIFETIME)
	tween.tween_property(ghost, "scale", Vector3.ONE * 0.85, GHOST_LIFETIME)
	tween.chain().tween_callback(ghost.queue_free)


func death_burst(world_position: Vector3, color: Color) -> void:
	var parent := _fx_parent()
	if parent == null:
		return

	for i in SHARD_COUNT:
		var shard := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * SHARD_SIZE
		shard.mesh = box

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = color
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		parent.add_child(shard)
		var angle := TAU * float(i) / float(SHARD_COUNT)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		shard.global_position = world_position + dir * SHARD_SIZE
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		shard.add_to_group(GROUP_FX_TRANSIENT)

		var target := shard.global_position + dir * randf_range(0.7, 1.3) \
			+ Vector3.UP * randf_range(0.1, 0.6)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position", target, SHARD_LIFETIME)
		tween.tween_property(shard, "scale", Vector3.ONE * SHARD_END_SCALE, SHARD_LIFETIME)
		tween.tween_property(shard, "transparency", 1.0, SHARD_LIFETIME)
		tween.chain().tween_callback(shard.queue_free)


func _fx_parent() -> Node3D:
	# Menus are CanvasLayers; there is no 3D stage to attach world feedback to.
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene as Node3D
