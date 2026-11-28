extends RefCounted
## Loads a .glb at runtime through GLTFDocument.
##
## The project's editor import queue is unreliable on this machine, so level
## art that is authored elsewhere is read straight from disk instead of going
## through the import cache. Export filters must keep `*.glb` for this to work
## in a build.

static func load_node(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		push_error("missing glb: " + path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	if err != OK:
		push_error("glb load failed (%s): %s" % [error_string(err), path])
		return null
	return doc.generate_scene(state) as Node3D


## Convenience: load, scale, rotate around Y and place on the floor plane.
static func place(parent: Node3D, path: String, at: Vector3, yaw_deg := 0.0, scale_factor := 1.0) -> Node3D:
	var node := load_node(path)
	if node == null:
		return null
	node.scale = Vector3.ONE * scale_factor
	node.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	node.position = at
	parent.add_child(node)
	return node
