extends SceneTree

# 对比图：2 张 → 一行两格；4 张 → 上排卡口、下排院子。
# 用法：godot --headless --path . --script res://tools/pair.gd -- <out> <A> <B> [<A2> <B2>]
const CELL := Vector2i(720, 405)
const GAP := 8


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("用法: <out> <A> <B> [<A2> <B2>]")
		quit(1)
		return
	var paths: Array = [String(args[1]), String(args[2])]
	if args.size() >= 5:
		paths.append(String(args[3]))
		paths.append(String(args[4]))
	var rows := int(ceil(float(paths.size()) / 2.0))
	var canvas := Image.create(CELL.x * 2 + GAP, CELL.y * rows + GAP * (rows - 1), false, Image.FORMAT_RGB8)
	canvas.fill(Color(0.05, 0.05, 0.06))
	for i: int in paths.size():
		var img := Image.load_from_file(paths[i])
		if img == null:
			print("读不到 ", paths[i])
			continue
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		canvas.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 2) * (CELL.x + GAP), (i / 2) * (CELL.y + GAP)))
	canvas.save_png(String(args[0]))
	print("pair -> ", String(args[0]))
	quit(0)
