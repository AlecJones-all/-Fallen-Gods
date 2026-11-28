extends SceneTree

# 校准校验：量弩口与前方的夹角，并出"待机/瞄准 × 全身/近景"四张图
const OUT := "res://docs/19_武器模型/review"

var _p: Node3D
var _cam: Camera3D
var _frame := 0
var _job := 0
var _phase := 0
var _jobs := [
	["idle", 0.60, 0, 4.0],
	["idle", 0.60, 1, 1.0],
	["aim_xbow", 0.50, 0, 4.0],
	["aim_xbow", 0.50, 1, 1.0],
	["aim_xbow", 0.50, 2, 0.85],
]


func _initialize() -> void:
	_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node3D
	get_root().add_child(_p)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.105, 0.10, 0.093)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.ambient_light_energy = 1.0
	we.environment = env
	get_root().add_child(we)
	for l in [[Vector3(-30, -35, 0), 2.6], [Vector3(-10, 140, 0), 1.3], [Vector3(-160, 200, 0), 1.4]]:
		var dl := DirectionalLight3D.new()
		dl.rotation_degrees = l[0]
		dl.light_energy = l[1]
		get_root().add_child(dl)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.01
	_cam.far = 100
	_cam.current = true
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	get_root().add_child(_cam)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		_p.select_weapon(1)
	if _frame < 8:
		return false
	if _job >= _jobs.size():
		return true

	var j: Array = _jobs[_job]
	var ap: AnimationPlayer = _p.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var xb: Node3D = _p.find_child("Crossbow", true, false) as Node3D
	var facing: Node3D = _p.find_child("FacingWedge", true, false) as Node3D

	if _phase == 0:
		ap.play(String(j[0]))
		ap.seek(float(j[1]), true)
		ap.pause()
		var wfwd := xb.global_transform.basis.z.normalized()
		var afwd := -facing.global_basis.z
		afwd.y = 0
		afwd = afwd.normalized()
		var flat := Vector3(wfwd.x, 0, wfwd.z).normalized()
		print("%-9s 弩口=%s  偏航差=%.1f°  俯仰=%.1f°" % [j[0], str(wfwd.snapped(Vector3.ONE * 0.01)),
			rad_to_deg(flat.signed_angle_to(afwd, Vector3.UP)), rad_to_deg(asin(clampf(wfwd.y, -1, 1)))])
		_phase = 1
		return false

	if _phase == 1:
		var box := AABB()
		var first := true
		for m: Node in xb.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		var ang := Vector3(-55, 45, 0) if int(j[2]) < 2 else Vector3(-78, 0, 0)
		var b := Basis.from_euler(Vector3(deg_to_rad(ang.x), deg_to_rad(ang.y), 0))
		var target: Vector3 = _p.global_position + Vector3(0, 1.0, 0) if int(j[2]) == 0 else box.get_center()
		_cam.global_transform = Transform3D(b, target + b * Vector3(0, 0, 3))
		_cam.size = float(j[3])
		_phase = 2
		return false

	get_root().get_texture().get_image().save_png("%s/align_%s_%d.png" % [OUT, j[0], int(j[2])])
	print("  saved align_%s_%d" % [j[0], int(j[2])])
	_phase = 0
	_job += 1
	return false
