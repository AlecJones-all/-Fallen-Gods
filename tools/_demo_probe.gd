extends SceneTree
var n := 0
var r: Node
func _initialize() -> void:
	var ps: PackedScene = load("res://dist/anim_pack_v1/demo/anim_viewer.tscn")
	if ps == null:
		print("DEMO FAIL: 场景加载失败"); quit(1); return
	r = ps.instantiate()
	get_root().add_child(r)
	print("demo 实例化 OK: ", r.name, " script=", r.get_script() != null)
func _process(_d: float) -> bool:
	n += 1
	if n < 4:
		return false
	var ap: AnimationPlayer = r.find_child("AnimationPlayer", true, false)
	print("AnimationPlayer=", ap != null)
	if ap != null:
		print("  当前片段=", ap.current_animation, " 库数=", ap.get_animation_library_list().size(),
			" 片段总数=", ap.get_animation_list().size(), " 正在播=", ap.is_playing())
	var picker: OptionButton = _find_opt(r)
	print("  下拉项=", picker.item_count if picker != null else -1)
	# 逐段切换一次，确认都能 play 且有轨道
	var bad := 0
	for nm in ap.get_animation_list():
		ap.play(nm)
		var a: Animation = ap.get_animation(nm)
		if a == null or a.get_track_count() == 0:
			print("  [BAD] ", nm); bad += 1
	print("  切换测试: ", ap.get_animation_list().size() - bad, "/", ap.get_animation_list().size(), " 段可播")
	quit(0 if bad == 0 else 1)
	return true
func _find_opt(n: Node) -> OptionButton:
	if n is OptionButton: return n
	for c in n.get_children():
		var x := _find_opt(c)
		if x != null: return x
	return null
