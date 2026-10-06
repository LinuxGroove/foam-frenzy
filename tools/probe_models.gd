extends SceneTree
## Prints each model's size and animation clips (development aid):
##   godot --headless --path . -s tools/probe_models.gd -- res://assets/kenney/blaster-kit
func _init() -> void:
	for dir in OS.get_cmdline_user_args():
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if not f.ends_with(".glb"):
				continue
			var scene: PackedScene = load(dir.path_join(f))
			var n := scene.instantiate()
			var aabb := _aabb(n, Transform3D())
			var clips := []
			for ap in n.find_children("*", "AnimationPlayer", true, false):
				clips = Array(ap.get_animation_list())
			print("%-34s size %s  min %s  %s" % [f, aabb.size.snapped(Vector3.ONE * 0.01), aabb.position.snapped(Vector3.ONE * 0.01), clips if clips.size() > 0 else ""])
			n.free()
	quit()

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _aabb(c, t)
		if a.size == Vector3.ZERO:
			continue
		out = a if first else out.merge(a)
		first = false
	return out
