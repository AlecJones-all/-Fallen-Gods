@tool
extends Node3D
## 独立岸线环境。Assets 下的标记可在编辑器中移动、旋转和缩放；
## 运行时和编辑器预览共用同一份 GLB 模型，不依赖项目的 GLB 导入缓存。

const ROOT := "res://art/environments/腺海岸线/"
const MODEL_PATHS := {
	"rock": ROOT + "骨膜岩石.glb",
	"gland": ROOT + "腺体组织.glb",
	"bank": ROOT + "岸缘地形.glb",
}
# 由各 GLB 的实际局部包围盒测得，使模型最低点落在地面。
const BASE_OFFSETS := {"rock": 0.26831, "gland": 0.17261, "bank": 0.080811}

var _pulsing: Array[Node3D] = []
var _time := 0.0

func _ready() -> void:
	_setup_ground()
	_build_assets()
	set_process(not Engine.is_editor_hint())

func _setup_ground() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "腺海岸线地面.png"))
	if image == null or image.is_empty():
		push_error("腺海岸线：无法读取地面纹理")
		return
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_scale = Vector3(9.0, 4.25, 1.0)
	material.texture_repeat = true
	material.albedo_color = Color(0.63, 0.59, 0.64, 1.0)
	material.roughness = 0.57
	material.metallic = 0.0
	$Ground.mesh = _shore_mesh(false)
	$Ground.material_override = material
	$Shallows.mesh = _shore_mesh(true)

# 主路保持平坦；仅岸边轮廓起伏，地面贴图与碰撞独立。
func _shore_mesh(shallow: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var segments := 64
	for i in range(segments + 1):
		var x := -24.0 + 48.0 * float(i) / float(segments)
		var edge := -5.4 + 0.40 * sin(x * 0.31) + 0.18 * sin(x * 0.73)
		var near_z := edge - 0.65 if shallow else edge
		var far_z := edge + 0.50 if shallow else 22.0
		var y := 0.015 if shallow else 0.0
		for z in [near_z, far_z]:
			vertices.append(Vector3(x, y, z))
			normals.append(Vector3.UP)
			uvs.append(Vector2((x + 24.0) / 48.0, (z + 6.0) / 28.0))
	for i in range(segments):
		var a := i * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 2, a + 3, a + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_assets() -> void:
	var prototypes: Dictionary = {}
	for kind in MODEL_PATHS:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var path: String = MODEL_PATHS[kind]
		var result := document.append_from_file(ProjectSettings.globalize_path(path), state)
		if result != OK:
			push_error("腺海岸线：无法读取模型 %s (%s)" % [path, error_string(result)])
			continue
		prototypes[kind] = document.generate_scene(state)
		_tint_asset(prototypes[kind])
	for marker in $Assets.get_children():
		if not marker is Node3D:
			continue
		var kind := str(marker.get_meta("asset_kind", ""))
		if not prototypes.has(kind):
			continue
		# 未设置 owner，预览节点不会写入场景；标记本身仍可在编辑器中摆放。
		var existing := marker.get_node_or_null("ArtPreview")
		if existing:
			existing.queue_free()
		var visual := (prototypes[kind] as Node3D).duplicate() as Node3D
		visual.name = "ArtPreview"
		visual.position.y = float(BASE_OFFSETS[kind])
		marker.add_child(visual)
		if kind == "gland":
			_pulsing.append(visual)
	for prototype in prototypes.values():
		(prototype as Node3D).free()

# 对整件源模型调整材质参数，不改写贴图或推断局部区域。
func _tint_asset(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh:
			for surface in instance.mesh.get_surface_count():
				var source := instance.get_active_material(surface)
				if source is BaseMaterial3D:
					var material := source.duplicate() as BaseMaterial3D
					material.albedo_color *= Color(0.72, 0.67, 0.73, 1.0)
					instance.set_surface_override_material(surface, material)
	for child in node.get_children():
		_tint_asset(child)

func _process(delta: float) -> void:
	_time += delta
	for i in _pulsing.size():
		var pulse := sin(_time * 0.72 + float(i) * 1.1)
		var visual := _pulsing[i]
		visual.scale = Vector3(1.0 + 0.018 * pulse, 1.0 + 0.035 * pulse, 1.0 + 0.018 * pulse)
		visual.position.y = float(BASE_OFFSETS["gland"]) * visual.scale.y
