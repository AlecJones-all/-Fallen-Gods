extends SceneTree


func _init() -> void:
	for i in range(1, 16):
		var path := "res://assets/backgrounds/level_%02d.png" % i
		var img := Image.load_from_file(path)
		if img == null:
			print("MISSING ", path)
			continue
		img.resize(480, 854, Image.INTERPOLATE_LANCZOS)
		var err := img.save_png(path)
		print("RESIZED ", path, " err=", err)
	quit()