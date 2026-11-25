extends SceneTree

# 统计截图明度：均值 / 暗部占比(<0.25) / 亮部占比(>0.70)。用于验收"暗部 >= 65%"。
func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			print("LOAD FAIL ", path)
			continue
		var w := img.get_width()
		var h := img.get_height()
		var total := 0.0
		var dark := 0
		var bright := 0
		var count := 0
		for y: int in range(0, h, 2):
			for x: int in range(0, w, 2):
				var c := img.get_pixel(x, y)
				var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
				total += l
				if l < 0.25:
					dark += 1
				if l > 0.70:
					bright += 1
				count += 1
		print("%s  mean=%.3f  dark=%.1f%%  bright=%.1f%%" % [path, total / count, 100.0 * dark / count, 100.0 * bright / count])
	quit()
