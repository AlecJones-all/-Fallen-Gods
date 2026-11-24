extends SceneTree
var _f := 0
var _out := "res://.tmp_game.png"
var _clip := ""

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1: _out = "res://" + a[0]
	if a.size() >= 2: _clip = a[1]
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	# 把相机拉近一点便于观察
	var cam: Camera3D = m.find_child("Camera3D", true, false)
	if cam:
		cam.size = 5.0

func _process(_d: float) -> bool:
	_f += 1
	if _f == 5 and _clip != "":
		var p = get_root().find_child("Player", true, false)
		if p:
			var ap: AnimationPlayer = p.find_child("AnimationPlayer", true, false)
			if ap:
				ap.play(_clip)
				ap.seek(0.25, true)
				ap.pause()
				print("forced ", _clip)
	if _f == 12:
		get_root().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
