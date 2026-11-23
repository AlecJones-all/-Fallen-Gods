extends SceneTree


func _init() -> void:
	for i in range(1, 16):
		var png := "res://assets/backgrounds/level_%02d.png" % i
		var jpg := "res://assets/backgrounds/level_%02d.jpg" % i
		var img := Image.load_from_file(png)
		if img == null:
			print("MISSING ", png)
			continue
		var err := img.save_jpg(jpg, 0.9)
		if err == OK:
			DirAccess.remove_absolute(png)
			DirAccess.remove_absolute(png + ".import")
		print("JPG ", jpg, " err=", err)
	quit()