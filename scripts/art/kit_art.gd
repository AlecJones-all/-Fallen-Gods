class_name KitArt
extends RefCounted

## 运行时只做一件事：把烘焙好的贴图组装成材质。
## 贴图由 tools/bake_textures.gd 生成，参数在 data/materials/surfaces.json。
## 方块不用展 UV——统一走世界三平面映射。

const SURFACES_PATH := "res://data/materials/surfaces.json"


## 返回 name -> Material。键名与场景里用的老名字保持一致，场景代码不用改。
static func build() -> Dictionary:
	var surfaces := _load_surfaces()
	if surfaces.is_empty():
		return {}

	var base: Dictionary = {}
	for id: String in surfaces:
		base[id] = _make_material(surfaces[id] as Dictionary)

	var out: Dictionary = {}
	for id: String in base:
		out[id] = base[id]

	# 兼容场景里现有的旧名字
	out["stone"] = base.get("plaster", base.get("stone_crack"))
	out["stone_light"] = _tint(base["stone_crack"], Color(1.08, 1.04, 0.96))
	out["wood"] = base.get("wood_dry", out["stone"])
	out["iron"] = base.get("iron_rust", out["stone"])
	out["cloth"] = base.get("cloth_rot", out["stone"])
	out["dirt"] = _tint(base["stone_crack"], Color(0.96, 0.90, 0.80))
	out["pave"] = _tint(base["stone_crack"], Color(1.04, 1.02, 0.98))
	out["mud"] = _tint(base["stone_crack"], Color(0.72, 0.66, 0.58))
	out["road_approach"] = _tint(base["stone_crack"], Color(1.05, 0.97, 0.85))
	out["road_gate"] = _tint(base["stone_crack"], Color(1.04, 1.02, 0.98))
	out["road_yard"] = _tint(base["stone_crack"], Color(0.52, 0.48, 0.43))
	out["blood"] = base.get("blood_dry", out["stone"])
	out["bone"] = base.get("bone", out["stone"])
	out["glow"] = _make_glow()
	return out


static func _load_surfaces() -> Dictionary:
	var text := FileAccess.get_file_as_string(SURFACES_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("KitArt: 无法解析 %s" % SURFACES_PATH)
		return {}
	return (parsed as Dictionary).get("surfaces", {})


static func _make_material(recipe: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var albedo_path := String(recipe.get("albedo", ""))
	var normal_path := String(recipe.get("normal", ""))
	if not albedo_path.is_empty() and ResourceLoader.exists(albedo_path):
		material.albedo_texture = load(albedo_path)
	if not normal_path.is_empty() and ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path)
		material.normal_scale = float(recipe.get("normal_scale", 1.2))
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	var scale := float(recipe.get("triplanar", 0.9))
	material.uv1_scale = Vector3.ONE * scale
	material.roughness = float(recipe.get("rough", 0.9))
	material.metallic = float(recipe.get("metal", 0.0))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


## 同一张贴图 + 不同底色 = 变体，不新建贴图
static func _tint(source: Material, color: Color) -> StandardMaterial3D:
	var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_color = color
	return material


static func _make_glow() -> StandardMaterial3D:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.72, 0.34)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.15)
	glow.emission_energy_multiplier = 0.35
	return glow
