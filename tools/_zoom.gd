extends SceneTree

# 截图局部放大：用于核对 1~2m 级的墙体细节。
# 用法：godot --headless --path . --script res://tools/_zoom.gd -- <in.png> <x> <y> <w> <h> <scale> <out.png>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 7:
		print("用法: <in> <x> <y> <w> <h> <scale> <out>")
		quit(1)
		return
	var src := String(args[0])
	var img := Image.load_from_file(src)
	if img == null:
		print("读不到 ", src)
		quit(1)
		return
	var rect := Rect2i(int(args[1]), int(args[2]), int(args[3]), int(args[4]))
	var scale := float(args[5])
	var crop := img.get_region(rect)
	crop.resize(int(crop.get_width() * scale), int(crop.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	crop.save_png(String(args[6]))
	print("zoom -> ", String(args[6]))
	quit(0)
