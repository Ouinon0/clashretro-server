extends Node3D
## Visionneuse d'unité 3D : --unit=knight --anim=run (premier essai de la chaîne sc3d).

const UNITS := "res://assets/gen/units/"


func _ready() -> void:
	var unit := "knight"
	var anim := "run"
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--unit="):
			unit = arg.get_slice("=", 1)
		elif arg.begins_with("--anim="):
			anim = arg.get_slice("=", 1)

	var model: Node3D = load(UNITS + unit + ".glb").instantiate()
	add_child(model)
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if player:
		print("animations : ", player.get_animation_list())
		if player.has_animation(anim):
			player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
			player.play(anim)

	var aabb := _bounds(model)
	print("taille : ", aabb.size)
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	var center := aabb.get_center()
	cam.look_at_from_position(center + Vector3(0, aabb.size.y * 2.2, aabb.size.y * 3.0), center)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.55, 0.32)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.6
	add_child(env)


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
