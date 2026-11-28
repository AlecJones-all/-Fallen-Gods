extends SceneTree

# 给蒸汽朋克弩套统一色调（默认 B 铁锈暖），写回 tscn
# 用法: godot --headless --path . --script res://tools/apply_tint_xbow.gd -- [warm|cold|ember]

const TSCN := "res://assets/weapons/xbow_steampunk/xbow_steampunk.tscn"

const PRESETS := {
	"warm": {"tint": Color(1.00, 0.78, 0.62), "metal": 0.08, "rough": 0.90},
	"cold": {"tint": Color(0.80, 0.82, 0.86), "metal": 0.05, "rough": 0.94},
	"ember": {"tint": Color(0.62, 0.56, 0.56), "metal": 0.10, "rough": 0.88},
	"orig": {"tint": Color(1.0, 1.0, 1.0), "metal": 0.15, "rough": 0.82},
}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var key := "warm" if a.size() < 1 else String(a[0])
	var tscn := TSCN
	if a.size() >= 2:
		tscn = String(a[1])
	if not PRESETS.has(key):
		print("未知预设 ", key, " 可选：", PRESETS.keys())
		quit(1)
		return
	var p: Dictionary = PRESETS[key]

	var root: Node3D = (load(tscn) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var n := 0
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var mat := (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.albedo_color = p["tint"]
		mat.metallic = p["metal"]
		mat.roughness = p["rough"]
		mi.material_override = mat
		n += 1
	var out := PackedScene.new()
	print("预设=", key, " 部件=", n, " pack=", out.pack(root), " save=", ResourceSaver.save(out, tscn))
	quit(0)
