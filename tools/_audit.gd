extends SceneTree

# 武器改造后的完整体检（只读，不改任何文件）
# 用法: godot --headless --path . --script res://tools/_audit.gd

const SCENE := "res://scenes/player/rogue_knight_v2.tscn"
const PLAYER := "res://scenes/player/player.tscn"
const PACK := "res://dist/anim_pack_v1/rogue_knight_anims.tres"

var _fail := 0
var _root: Node3D
var _frame := 0


func _init() -> void:
	var ps: PackedScene = load(SCENE)
	_root = ps.instantiate()
	get_root().add_child(_root)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_run()
	return true


func _run() -> void:
	print("===== 1. 玩家骨架场景 =====")
	var root := _root

	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	var clips: Array = ap.get_animation_list() if ap != null else []
	_chk("动画片段 = 10（含合并的 aim_walk）", clips.size() == 10, str(clips.size()))
	_chk("idle 仍在", clips.has("idle"), "")
	_chk("attack_blade 仍在", clips.has("attack_blade"), "")
	_chk("剑 Cube_009 存在", root.find_child("Cube_009", true, false) != null, "")
	_chk("骨架 36 骨", _find_skel(root).get_bone_count() == 36, str(_find_skel(root).get_bone_count()))

	print("\n===== 2. 挂点结构 =====")
	var att: Node3D = root.find_child("WeaponAttachment", true, false)
	_chk("WeaponAttachment 存在", att != null, "")
	_chk("绑定的骨 = socket_weapon.R", att != null and att.get("bone_name") == "socket_weapon.R",
		str(att.get("bone_name")) if att != null else "-")
	var xp: Node3D = root.find_child("XbowPivot", true, false)
	var axp: Node3D = root.find_child("AxePivot", true, false)
	_chk("XbowPivot 存在", xp != null, "")
	_chk("AxePivot 存在", axp != null, "")
	if xp != null:
		print("  XbowPivot rot = ", xp.rotation_degrees, "  scale = ", xp.scale)
	if axp != null:
		print("  AxePivot  rot = ", axp.rotation_degrees, "  scale = ", axp.scale)

	print("\n===== 3. 三把武器的显示状态 =====")
	var sword: Node3D = root.find_child("Cube_009", true, false)
	var xbow: Node3D = root.find_child("Crossbow", true, false)
	var axe: Node3D = root.find_child("Axe", true, false)
	_chk("弩可见性默认 = false", xbow != null and not xbow.visible, str(xbow.visible) if xbow != null else "-")
	_chk("斧可见性默认 = false", axe != null and not axe.visible, str(axe.visible) if axe != null else "-")
	_chk("剑可见性默认 = true", sword != null and sword.visible, str(sword.visible) if sword != null else "-")
	print("  弩子件 = ", xbow.get_child_count() if xbow != null else -1)
	print("  斧子件 = ", axe.get_child_count() if axe != null else -1)

	print("\n===== 4. 材质（三平面必须是物体空间）=====")
	var world_tri := 0
	var total := 0
	var no_mat := 0
	for mi in _all_mesh(att):
		total += 1
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			no_mat += 1
			continue
		if m.uv1_world_triplanar:
			world_tri += 1
			print("  [问题] 世界空间三平面: ", mi.name)
	_chk("武器网格全部有材质", no_mat == 0, "无材质 %d 个" % no_mat)
	_chk("没有残留世界空间三平面", world_tri == 0, "世界空间 %d 个 / 共 %d" % [world_tri, total])

	print("\n===== 5. 尺寸（米）=====")
	if xbow != null:
		var b := _local_aabb(xbow)
		print("  连弩 局部 AABB  size = %.3f × %.3f × %.3f" % [b.size.x, b.size.y, b.size.z])
		_chk("弩臂展 0.30–0.60", b.size.x >= 0.30 and b.size.x <= 0.60, "%.3f" % b.size.x)
		_chk("弩身长 0.40–0.72（程序化 0.50 / 外部 0.63）", b.size.z >= 0.40 and b.size.z <= 0.72, "%.3f" % b.size.z)
	if axe != null:
		var b2 := _local_aabb(axe)
		print("  斧   局部 AABB  size = %.3f × %.3f × %.3f" % [b2.size.x, b2.size.y, b2.size.z])
		var longest: float = maxf(b2.size.x, maxf(b2.size.y, b2.size.z))
		_chk("斧总长 0.85–1.00", longest >= 0.85 and longest <= 1.00, "%.3f" % longest)
		_chk("斧刃宽 0.35–0.55", b2.size.x >= 0.35 and b2.size.x <= 0.55, "%.3f" % b2.size.x)

	print("\n===== 6. 面数 =====")
	var tris := 0
	for mi in _all_mesh(att):
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var iv: Variant = arr[Mesh.ARRAY_INDEX]
				if iv != null:
					tris += (iv as PackedInt32Array).size() / 3
				else:
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					tris += vv.size() / 3
	print("  武器总三角面 = ", tris)
	_chk("武器面数 ≤ 12000", tris <= 12000, str(tris))

	print("\n===== 7. 动画包与场景是否仍一致 =====")
	var lib: AnimationLibrary = load(PACK)
	_chk("动画包 19 段", lib.get_animation_list().size() == 19,
		str(lib.get_animation_list().size()))
	var missing := 0
	for n in clips:
		if not lib.has_animation(n):
			missing += 1
			print("  [问题] 包里缺场景片段: ", n)
	_chk("场景 9 段都在包里", missing == 0, "缺 %d" % missing)

	print("\n===== 8. 玩家场景可用性 =====")
	var pps: PackedScene = load(PLAYER)
	var p: Node = pps.instantiate()
	get_root().add_child(p)
	_chk("player.tscn 实例化", p != null, "")
	_chk("player 里能找到剑", p.find_child("Cube_009", true, false) != null, "")
	_chk("player 里能找到弩", p.find_child("Crossbow", true, false) != null, "")
	_chk("player 里能找到斧", p.find_child("Axe", true, false) != null, "")
	var pap: AnimationPlayer = p.find_child("AnimationPlayer", true, false)
	_chk("player 动画 10 段", pap.get_animation_list().size() == 10, str(pap.get_animation_list().size()))

	print("\n===== 结果 =====")
	print("失败项 = ", _fail)
	quit(1 if _fail > 0 else 0)


func _chk(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ✓ ", label, ("" if detail.is_empty() else "   [" + detail + "]"))
	else:
		_fail += 1
		print("  ✗ ", label, ("" if detail.is_empty() else "   [" + detail + "]"))


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _all_mesh(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out


## 局部包围盒：只累加到 group 自身为止的变换，不受 pivot 旋转影响
func _local_aabb(group: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect(group, group.transform, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


func _collect(n: Node, xf: Transform3D, boxes: Array[AABB]) -> void:
	for c in n.get_children():
		var t := xf
		if c is Node3D:
			t = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			boxes.append(t * (c as MeshInstance3D).mesh.get_aabb())
		_collect(c, t, boxes)
