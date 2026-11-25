extends SceneTree

## 贴图烘焙：按 data/materials/surfaces.json 生成 albedo + normal 两套 PNG。
## 只跑一次，之后运行时直接读图，不再现算。
## 用法：godot --headless --path . --script res://tools/bake_textures.gd

const SURFACES_PATH := "res://data/materials/surfaces.json"
const OUT_DIR := "res://assets/materials"
const SIZE := 256

var _soft := FastNoiseLite.new()
var _fine := FastNoiseLite.new()
var _mid := FastNoiseLite.new()


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(SURFACES_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		print("BAKE FAIL: 无法解析 ", SURFACES_PATH)
		quit(1)
		return
	var surfaces: Dictionary = (parsed as Dictionary).get("surfaces", {})

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var count := 0
	for id: String in surfaces:
		var recipe: Dictionary = surfaces[id]
		_bake(id, recipe)
		count += 1
	print("BAKE OK  %d 个表面，每个 2 张图（%dx%d）" % [count, SIZE, SIZE])
	quit(0)


func _bake(id: String, recipe: Dictionary) -> void:
	var pattern := String(recipe.get("pattern", "stone_crack"))
	var base := _color(recipe.get("base", [0.5, 0.5, 0.5]))
	var accent := _color(recipe.get("accent", [0.2, 0.2, 0.2]))
	var contrast := float(recipe.get("contrast", 0.3))

	_seed_noise(id)

	# 高度场：颜色和法线共用，凹凸才和花纹对得上
	var height := PackedFloat32Array()
	height.resize(SIZE * SIZE)
	var tint := PackedFloat32Array()
	tint.resize(SIZE * SIZE)

	for y: int in SIZE:
		for x: int in SIZE:
			var s := _sample(pattern, x, y)
			height[y * SIZE + x] = s.x
			tint[y * SIZE + x] = s.y

	var albedo := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y: int in SIZE:
		for x: int in SIZE:
			var shade := height[y * SIZE + x]
			var mix := clampf(tint[y * SIZE + x], 0.0, 1.0)
			var color := base.lerp(accent, mix) * (1.0 + shade * contrast)
			albedo.set_pixel(x, y, Color(
				clampf(color.r, 0.0, 1.0),
				clampf(color.g, 0.0, 1.0),
				clampf(color.b, 0.0, 1.0)
			))
	albedo.generate_mipmaps()
	albedo.save_png("%s/%s_albedo.png" % [OUT_DIR, id])

	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var strength := 4.5
	for y: int in SIZE:
		for x: int in SIZE:
			var left := height[y * SIZE + ((x - 1 + SIZE) % SIZE)]
			var right := height[y * SIZE + ((x + 1) % SIZE)]
			var up := height[((y - 1 + SIZE) % SIZE) * SIZE + x]
			var down := height[((y + 1) % SIZE) * SIZE + x]
			var n := Vector3(-(right - left) * strength, -(down - up) * strength, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	normal.generate_mipmaps()
	normal.save_png("%s/%s_normal.png" % [OUT_DIR, id])

	print("  baked ", id)


func _seed_noise(id: String) -> void:
	_soft.seed = hash(id)
	_soft.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_soft.frequency = 0.010
	_soft.fractal_octaves = 3

	_mid.seed = hash(id) + 31
	_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mid.frequency = 0.012
	_mid.fractal_octaves = 2

	_fine.seed = hash(id) + 77
	_fine.frequency = 0.35
	_fine.fractal_octaves = 2


## 返回 (明暗扰动 -1..1, 强调色混合 0..1)
func _sample(pattern: String, x: int, y: int) -> Vector2:
	var n := _soft.get_noise_2d(float(x), float(y))
	var nm := _mid.get_noise_2d(float(x), float(y))
	var nf := _fine.get_noise_2d(float(x), float(y))

	match pattern:
		"plaster":
			# 白灰：基本平整，只有少量竖向渗痕 + 稀疏细裂
			var streak := 0.0
			if (x % 71) < 2:
				streak = clampf(nm + 0.75, 0.0, 1.0)
			var seam := _ridge(nm, 1.4, 0.84) * 0.35
			var blood := clampf(streak + seam, 0.0, 1.0)
			return Vector2(nf * 0.30 + n * 0.18 - blood * 0.75, blood)

		"stone_crack":
			# 斑驳石面 + 稀疏低频裂纹：不要规则缝网，避免“虫爬纹”和网格感
			var crack := _ridge(nm, 1.6, 0.90) * 0.6
			return Vector2(n * 0.16 + nf * 0.10 - crack * 0.22, crack * 0.45)

		"bone":
			# 骨：低频斑 + 细孔
			var pore := 0.8 if nf > 0.55 else 0.0
			return Vector2(n * 0.45 + nf * 0.25 - pore * 0.5, clampf(nm * 0.4 + 0.2, 0.0, 1.0))

		"wood_dry":
			# 干木：竖向纤维 + 横向裂纹 + 上缘烟熏
			var fiber := sin((float(x) + n * 6.0) * 1.4)
			var split := -0.7 if (y % 96) < 2 else 0.0
			var soot := -0.35 if y < 48 else 0.0
			return Vector2(fiber * 0.30 + n * 0.45 + split + soot, clampf(nf * 0.35 + 0.1, 0.0, 1.0))

		"iron_rust":
			# 锈铁：铜绿斑 + 划痕
			var patina := clampf((nm + 0.15) * 1.4, 0.0, 1.0)
			var scratch := 0.6 if ((x * 3 + y * 7) % 97) < 1 else 0.0
			return Vector2(nf * 0.35 + n * 0.30 + scratch, patina)

		"cloth_rot":
			# 腐布：经纬 + 破损
			var weave := sin(float(x) * 1.9) * sin(float(y) * 1.9)
			var thread := -0.35 if (x % 4 == 0 or y % 4 == 0) else 0.0
			var wear := -0.5 if nm > 0.55 else 0.0
			return Vector2(weave * 0.40 + nf * 0.20 + thread + wear, clampf(nf * 0.4 + 0.15, 0.0, 1.0))

		"blood_dry":
			# 干血：池状 + 边缘发黑
			var pool := clampf((n + 0.25) * 1.6, 0.0, 1.0)
			var edge := clampf(1.0 - absf(n) * 2.4, 0.0, 1.0)
			return Vector2(nf * 0.25 - edge * 0.45, pool * 0.9)

	return Vector2(n, 0.2)


## 脊状噪声：|n| 越小越接近 0，用于取裂缝
func _ridge(n: float, sharpness: float, threshold: float) -> float:
	var v := 1.0 - absf(n) * sharpness
	return clampf((v - threshold) * 3.0, 0.0, 1.0)


func _color(values: Variant) -> Color:
	if values is Array and (values as Array).size() >= 3:
		var a: Array = values
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.5, 0.5, 0.5)
