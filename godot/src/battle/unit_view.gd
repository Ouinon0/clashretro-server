class_name UnitView
extends Node3D
## Une unité de la simulation dans le monde 3D : modèle animé de la 16.4 (assets/gen/units), tourné
## vers sa marche ou sa cible, rouge chez l'adversaire, avec une ombre au sol. Les unités sans
## modèle ont pour l'instant un repère simple (sprites HD de la 16.4 : étape suivante).

const UNITS := "res://assets/gen/units/"
const TEAM_SHADER := preload("res://src/battle/team_color.gdshader")
const MODEL_SCALE := 1.6            # modèles de la 16.4 → cases
const TURN_SPEED := 10.0            # rad/s

## Animations à essayer par état, dans l'ordre (les noms varient d'une unité à l'autre).
const CLIPS := {
	"idle": ["basic_idle", "idle", "basic_idle_l"],
	"run": ["run", "walk", "basic_run", "fly"],
	"attack": ["attack", "basic_attack", "attack01", "attack_l"],
	"deploy": ["drop", "deploy", "spawn"],
}

var entity_id := -1
var air := false
var head := 1.6                     # hauteur du haut du modèle (barre de vie au-dessus)
var _body := Node3D.new()           # modèle (en hauteur pour les volants) ; l'ombre reste au sol
var _shadow: MeshInstance3D
var _sprite: SpriteBody            # unité sans modèle 3D : sprites .sc
var _player: AnimationPlayer
var _state := ""
var _yaw := 0.0
var _target_yaw := 0.0
var _clip_len := {}


## `enemy` : unité de l'adversaire du joueur qui regarde (teinte rouge).
func setup(e: Dictionary, enemy: bool) -> void:
	entity_id = e.id
	air = e.air
	add_child(_body)
	if air:
		# Même hauteur à l'écran que les sprites de la 1.9 (FlyingHeight en millièmes de case).
		_body.position.y = Rules.num(e.data, "FlyingHeight", 2000) / 1000.0 * ArenaMap.CELL_Y \
				/ ArenaMap.CELL_X / cos(deg_to_rad(ArenaMap.PITCH)) * 0.55
	var model_name := GameDB.model(e.name)
	var path := UNITS + model_name + ".glb"
	if model_name != "" and ResourceLoader.exists(path):
		var model: Node3D = load(path).instantiate()
		model.scale = Vector3.ONE * MODEL_SCALE * Rules.num(e.data, "Scale", 100) / 100.0
		_body.add_child(model)
		head = _top(model) + _body.position.y
		_player = model.find_child("AnimationPlayer", true, false)
		_apply_team(model, enemy)
	else:
		var sprite := SpriteBody.new()
		_body.add_child(sprite)
		if sprite.setup(GameDB.visual(e.name), enemy):
			_sprite = sprite
			head = sprite.top() + _body.position.y
			var filter: String = GameDB.visual(e.name).get("DeployBaseAnimExportName", "")
			if filter != "" and e.get("deploy", 0) > 0:
				sprite.play_deploy(filter)
		else:
			sprite.free()
			_add_marker(e, enemy)
	_add_shadow(e)
	_yaw = PI if enemy else 0.0
	_target_yaw = _yaw
	rotation.y = _yaw
	set_state("deploy" if e.get("deploy", 0) > 0 else "idle")


## Unité posée en hauteur sans ombre au sol (princesse sur sa tour).
func lift(height: float) -> void:
	head += height - _body.position.y
	_body.position.y = height
	_shadow.visible = false


func set_state(state: String) -> void:
	if state == _state or _player == null:
		return
	var clip := _find_clip(state)
	if clip == "" and state == "deploy":
		clip = _find_clip("idle")
	if clip == "":
		return
	_state = state
	var anim := _player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_NONE if state == "deploy" else Animation.LOOP_LINEAR
	_player.play(clip, 0.12)


## Unité en sprites : animation et direction d'après la simulation (vue retournée si `flipped`).
func sync_sprite(e: Dictionary, flipped: bool) -> void:
	if _sprite == null:
		return
	var action := "run"
	match e.state:
		BattleSim.State.ATTACKING:
			action = "attack"
		BattleSim.State.IDLE, BattleSim.State.DEPLOYING:
			action = "idle"
		_:
			if e.get("charging", false):
				action = "charge"
	var dir: int = e.dir
	if flipped:
		var turned := 10 - absi(dir)
		dir = turned if turned == 1 or turned == 9 else (turned if dir < 0 else -turned)
	_sprite.show_anim(action, dir)


## Coup porté : l'animation d'attaque repart du début, calée sur la cadence de l'unité.
func strike(hit_seconds: float) -> void:
	if _player == null:
		return
	var clip := _find_clip("attack")
	if clip == "":
		return
	_state = "attack"
	var anim := _player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_NONE
	_player.play(clip, 0.05, clampf(anim.length / maxf(hit_seconds, 0.2), 0.6, 2.5))


## Orientation vers un point du monde (marche ou cible).
func face(world_point: Vector3) -> void:
	var d := world_point - position
	if Vector2(d.x, d.z).length() > 0.02:
		_target_yaw = atan2(d.x, d.z)


func _process(delta: float) -> void:
	_yaw = lerp_angle(_yaw, _target_yaw, minf(1.0, TURN_SPEED * delta))
	rotation.y = _yaw


## Haut du modèle (pose de repos), dans le repère de l'unité (déjà dans l'arbre de scène).
func _top(model: Node3D) -> float:
	var top := 0.0
	var to_local := global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (to_local * mesh.global_transform * mesh.get_aabb()).end.y)
	return top if top > 0.0 else 1.6


func _find_clip(state: String) -> String:
	for name in CLIPS[state]:
		if _player.has_animation(name):
			return name
	return ""


func _apply_team(model: Node3D, enemy: bool) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.mesh.get_surface_count():
			var src := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = TEAM_SHADER
			mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			mat.set_shader_parameter("enemy", enemy)
			mat.set_shader_parameter("roughness", src.roughness)
			mat.set_shader_parameter("metallic", src.metallic)
			if src.normal_enabled and src.normal_texture:
				mat.set_shader_parameter("normal_tex", src.normal_texture)
				mat.set_shader_parameter("has_normal", true)
			mesh.set_surface_override_material(i, mat)


## Ombre ronde au sol, à la taille de l'unité (plus pâle sous les volants).
func _add_shadow(e: Dictionary) -> void:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.gradient = Gradient.new()
	tex.gradient.set_color(0, Color(0, 0, 0, 0.45 if not e.air else 0.25))
	tex.gradient.set_color(1, Color(0, 0, 0, 0))
	var quad := QuadMesh.new()
	var r := maxf(0.5, e.radius / 1000.0) * 2.2
	quad.size = Vector2(r, r * ArenaMap.depth_stretch())
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = -1
	quad.material = mat
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.rotation.x = -PI / 2
	_shadow.position.y = 0.02
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func _add_marker(e: Dictionary, enemy: bool) -> void:
	var mesh := CapsuleMesh.new()
	var r := maxf(0.25, e.radius / 1000.0 * 0.8)
	mesh.radius = r
	mesh.height = maxf(r * 2.2, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.25, 0.25) if enemy else Color(0.25, 0.5, 0.95)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.y = mesh.height / 2.0
	_body.add_child(node)
