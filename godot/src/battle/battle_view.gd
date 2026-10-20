class_name BattleView
extends Node
## Affichage d'un combat : décor 2D de l'arène de la 16.4 (calque de fond), unités 3D ou sprites
## par-dessus (caméra orthographique inclinée, ArenaMap), effets et projectiles 2D (au sol ou
## au-dessus des unités), barres de vie. Ne fait que lire la simulation : aucune règle ici.

const SC_TOWERS := "building_tower"
const SMOOTH := 18.0                # rattrapage de la position simulée (20 ticks/s) par seconde
const PRINCESS_HEIGHT := 1.35       # hauteur de la plate-forme des tours de princesse (cases)
const ARC_PER_GRAVITY := 1.0 / 420.0 # hauteur de l'arc d'un projectile par unité de Gravity et de distance
const KING_WAKE_END := 97           # KingTower_* : images 1 à 97 = réveil du roi et sortie du canon

var sim: BattleSim
var viewer_team := 0
var location := "PvP_barbarian"
var hud_height := 330.0             # bas de l'écran laissé à la main de cartes
var map := ArenaMap.new()

var _bg: Node2D
var _world := Node3D.new()
var _bg_view := SubViewport.new()
var _camera := Camera3D.new()
var _backdrop: MeshInstance3D
const BACKDROP_SHADER := preload("res://src/battle/backdrop.gdshader")
var _overlay := Node2D.new()
var _views := {}                    # id d'entité → UnitView
var _towers := {}                   # id de tour → clip 2D
var _kings_awake := {}
var _shots := {}                    # pid → {node, shadow, from, height, pos}
var _area_fx := {}                  # aid → nœuds d'effets en boucle
var _shake := 0.0
var _camera_offset := Vector2.ZERO

var fx_ground := Node2D.new()       # effets au sol (sous les unités), repère .sc
var fx_top := Node2D.new()          # effets au-dessus des unités, repère .sc


func _init(battle: BattleSim, team: int) -> void:
	sim = battle
	viewer_team = team


func _ready() -> void:
	var size := get_viewport().get_visible_rect().size
	map.fit(Rect2(0, 0, size.x, size.y - hud_height), viewer_team)
	_build_background()
	_build_world(size)
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)
	fx_top.scale = Vector2.ONE * map.sc_scale
	fx_layer.add_child(fx_top)
	fx_ground.scale = Vector2.ONE * map.sc_scale
	_bg.add_child(fx_ground)
	var top := CanvasLayer.new()
	top.layer = 1
	add_child(top)
	top.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	sim.entity_spawned.connect(_on_spawned)
	sim.entity_removed.connect(_on_removed)
	sim.attack_started.connect(_on_attack)
	sim.damaged.connect(_on_damaged)
	sim.projectile_spawned.connect(_on_projectile)
	sim.projectile_hit.connect(_on_projectile_hit)
	sim.area_effect.connect(_on_area)
	for e in sim.entities:
		_on_spawned(e)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-SMOOTH * delta)
	for e in sim.entities:
		if e.kind == BattleSim.Kind.TOWER and e.king and e.active and not _kings_awake.has(e.id):
			_kings_awake[e.id] = true
			var king := _towers.get(e.id) as ScMovieClip
			if king:
				king.play_range(1, KING_WAKE_END)
		var view: UnitView = _views.get(e.id)
		if view == null:
			continue
		var target := map.to_world(e.x, e.y, view.position.y)
		if e.kind == BattleSim.Kind.TOWER:
			continue
		var moved := target - view.position
		view.position += moved * k
		view.sync_sprite(e, map.flipped)
		match e.state:
			BattleSim.State.DEPLOYING:
				view.set_state("deploy")
			BattleSim.State.MOVING:
				view.set_state("run")
				view.face(target + moved.normalized() * 0.5 if moved.length() > 0.01 else target)
			BattleSim.State.ATTACKING:
				var t := _entity(e.target)
				if not t.is_empty():
					view.face(map.to_world(t.x, t.y))
			_:
				view.set_state("idle")
	_update_shots(k)
	_clean_area_fx()
	_update_shake(delta)
	_overlay.queue_redraw()


## Après un retour en arrière (combat en ligne) : vues ajoutées ou retirées pour coller à la
## simulation recalculée, sans effets (les unités nées pendant le recalcul gardent leur arrivée).
func resync() -> void:
	var alive := {}
	for e in sim.entities:
		alive[e.id] = true
		if e.kind != BattleSim.Kind.TOWER and not _views.has(e.id):
			var view := UnitView.new()
			view.position = map.to_world(e.x, e.y)
			_world.add_child(view)
			view.setup(e, e.team != viewer_team)
			_views[e.id] = view
			if e.get("deploy", 0) > 0:
				Effects.play(GameDB.visual(e.name).get("SpawnEffect", ""), self, fx_point(e.x, e.y), e.team != viewer_team)
	for id in _views.keys():
		if not alive.has(id) and not _towers.has(id):
			_views[id].queue_free()
			_views.erase(id)
	var shots := {}
	for p in sim.projectiles:
		shots[p.pid] = true
		if not _shots.has(p.pid):
			_on_projectile(p)
	for pid in _shots.keys():
		if not shots.has(pid):
			_on_projectile_hit({"pid": pid, "x": 0, "y": 0, "team": viewer_team, "name": ""})


## Point de la simulation dans le repère .sc des calques d'effets.
func fx_point(x: float, y: float) -> Vector2:
	return map.to_screen(x, y) / map.sc_scale


## Secousse (ShakeScreen des effets : 250 pour le Zap, 1000 pour la Foudre).
func shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength / 100.0, 1.0, 10.0))


func _update_shake(delta: float) -> void:
	if _shake <= 0.01:
		return
	_shake = maxf(0.0, _shake - delta * 30.0)
	var offset := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	# (le décor suit la caméra : il est au fond de la scène 3D)
	fx_top.position = offset
	_camera.h_offset = _camera_offset.x - offset.x / map.cell_px()
	_camera.v_offset = _camera_offset.y + offset.y / map.cell_px()


## Ajoute un objet 3D au monde du combat (aperçu de pose).
func add_world_child(node: Node3D) -> void:
	_world.add_child(node)


## Ajoute un dessin 2D au sol, sous les tours et les unités (zone de pose interdite).
func add_ground_child(node: Node2D) -> void:
	_bg.add_child(node)
	_bg.move_child(node, mini(1, _bg.get_child_count() - 1))


# --- Construction --------------------------------------------------------------------------------

func _build_background() -> void:
	# Le décor 2D est rendu dans sa propre vue, affichée au fond de la scène 3D (un fond « canevas »
	# de l'environnement ou une vue 3D transparente ne s'affichent pas sur certains GPU : PowerVR
	# du Pixel 10).
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2i(get_window().size) if get_window().size.x > 0 else Vector2i(logical)
	_bg_view.disable_3d = true
	_bg_view.size = physical
	_bg_view.size_2d_override = Vector2i(logical)
	_bg_view.size_2d_override_stretch = true
	_bg_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bg_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_bg_view)
	var arena: Dictionary = GameDB.arena_layout(location)
	_bg = Node2D.new()
	_bg_view.add_child(_bg)
	if arena.is_empty():
		return
	var root := Node2D.new()
	root.transform = map.background_transform()
	_bg.add_child(root)
	root.add_child(ScLibrary.create(arena.bg[0], arena.bg[1]))
	# Décors : jamais retournés (comme le jeu), triés de haut en bas.
	var decos: Array = arena.decos.duplicate()
	decos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	for d in decos:
		if not ResourceLoader.exists(ScLibrary.DATA_DIR + d.sc + ".json"):
			continue
		var lib := ScLibrary.get_library(d.sc)
		if not lib.has_export(d.export):
			continue
		var clip := lib.create_export(d.export)
		clip.position = _deco_position(d.x, d.y)
		root.add_child(clip)


## Position d'un décor dans le repère .sc du fond (positions de lieu en millièmes de case).
func _deco_position(x: int, y: int) -> Vector2:
	return ArenaMap.SC_CENTER + Vector2((x - 9000) / 1000.0 * ArenaMap.CELL_X, (y - 16000) / 1000.0 * ArenaMap.CELL_Y)


func _build_world(size: Vector2) -> void:
	add_child(_world)
	map.setup_camera(_camera, size)
	_camera_offset = Vector2(_camera.h_offset, _camera.v_offset)
	_world.add_child(_camera)
	_add_backdrop(size)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -35, 0)
	sun.light_energy = 0.95
	_world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -100
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.88)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)


## Fond : un rectangle face à la caméra, juste avant le plan lointain, couvrant exactement la vue
## orthographique, texturé par la vue du décor 2D (non éclairé, sans tonemapping).
func _add_backdrop(size: Vector2) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	var h := _camera.size
	mesh.size = Vector2(h * size.x / size.y, h)
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	mat.set_shader_parameter("tex", _bg_view.get_texture())
	quad.material_override = mat
	quad.position = Vector3(_camera.h_offset, _camera.v_offset, -(_camera.far - 2.0))
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(quad)
	_backdrop = quad


# --- Unités -------------------------------------------------------------------------------------

func _on_spawned(e: Dictionary) -> void:
	var enemy: bool = e.team != viewer_team
	if e.kind == BattleSim.Kind.TOWER:
		_build_tower(e, enemy)
		return
	var view := UnitView.new()
	view.position = map.to_world(e.x, e.y)
	_world.add_child(view)
	view.setup(e, enemy)
	_views[e.id] = view
	Effects.play(GameDB.visual(e.name).get("SpawnEffect", ""), self, fx_point(e.x, e.y), enemy)


func _build_tower(e: Dictionary, enemy: bool) -> void:
	var row: Dictionary = e.data
	var lib := ScLibrary.get_library(SC_TOWERS)
	var base := lib.create_export(row.get("RedExportName" if enemy else "BlueExportName", ""))
	base.position = map.to_screen(e.x, e.y)
	base.scale = Vector2.ONE * map.sc_scale
	if base is ScMovieClip and e.king:
		base.goto_and_stop(0)
	_bg.add_child(base)
	var parts := [base]
	var top_name: String = row.get("RedTopExportName" if enemy else "BlueTopExportName", "")
	if top_name != "":
		var top := lib.create_export(top_name)
		top.position = base.position
		top.scale = base.scale
		_bg.add_child(top)
		parts.append(top)
	base.set_meta("parts", parts)
	_towers[e.id] = base
	if not e.king:
		var princess := UnitView.new()
		princess.position = map.to_world(e.x, e.y, 0.0)
		_world.add_child(princess)
		princess.setup({"id": e.id, "name": "PrincessTower", "air": false, "radius": 0, "data": {}}, enemy)
		princess.lift(PRINCESS_HEIGHT)
		_views[e.id] = princess


func _on_removed(e: Dictionary) -> void:
	var enemy: bool = e.team != viewer_team
	var view: UnitView = _views.get(e.id)
	if view:
		view.queue_free()
		_views.erase(e.id)
	var death: String = GameDB.visual(e.name).get("DeathEffect", "")
	if death == "" and e.kind == BattleSim.Kind.TROOP:
		death = "Death_player"
	Effects.play(death, self, fx_point(e.x, e.y), enemy)
	var tower: Node2D = _towers.get(e.id)
	if tower:
		# Ruines d'origine à la place de la tour (socle et créneaux retirés).
		for node in tower.get_meta("parts", [tower]):
			node.queue_free()
		_towers.erase(e.id)
		var ruin := ScLibrary.create(SC_TOWERS, "kingtower_destroyed" if e.king else "princesstower_destroyed")
		ruin.position = map.to_screen(e.x, e.y)
		ruin.scale = Vector2.ONE * map.sc_scale
		_bg.add_child(ruin)
		_bg.move_child(ruin, fx_ground.get_index())


func _on_attack(e: Dictionary) -> void:
	var view: UnitView = _views.get(e.id)
	if view:
		view.strike(e.hit_ticks * Rules.TICK_MS / 1000.0)
	Effects.play(GameDB.visual(e.name).get("AttackStartEffect", ""), self, fx_point(e.x, e.y), e.team != viewer_team)


func _on_damaged(target: Dictionary, _damage: int, attacker: Dictionary) -> void:
	var name: String = attacker.get("Name", "")
	Effects.play(GameDB.visual(name).get("DamageEffect", ""), self, fx_point(target.x, target.y),
			target.team == viewer_team)


# --- Projectiles et sorts -----------------------------------------------------------------------

func _on_projectile(p: Dictionary) -> void:
	var visual := GameDB.visual(p.name)
	var file := str(visual.get("FileName", "")).get_file().get_basename()
	var export_name: String = visual.get("ExportName", "")
	if p.get("rolling", false) or file == "" or not ResourceLoader.exists(ScLibrary.DATA_DIR + file + ".json"):
		return
	var lib := ScLibrary.get_library(file)
	if not lib.has_export(export_name):
		return
	var node := lib.create_export(export_name)
	if node is ScMovieClip:
		node.loop = true
		node.play()
	fx_top.add_child(node)
	var shot := {"node": node, "from": fx_point(p.x, p.y), "pos": fx_point(p.x, p.y), "target": fx_point(p.tx, p.ty),
		"gravity": float(visual.get("Gravity", 0)), "z0": 0.0}
	# Départ en hauteur : tours (créneaux) et unités (ProjectileStartZ).
	var shooter := _entity_at(p.x, p.y, p.team)
	if not shooter.is_empty():
		shot.z0 = 2.0 * ArenaMap.CELL_Y if shooter.kind == BattleSim.Kind.TOWER else \
				Rules.num(GameDB.visual(shooter.name), "ProjectileStartZ", 400) / 1000.0 * ArenaMap.CELL_Y
	var shadow_name: String = visual.get("ShadowExportName", "")
	if shadow_name != "" and lib.has_export(shadow_name):
		var shadow := lib.create_export(shadow_name)
		shadow.modulate.a = 0.5
		fx_ground.add_child(shadow)
		shot.shadow = shadow
	shot.trail = Effects.play(visual.get("TrailEffect", ""), self, shot.pos)
	_shots[p.pid] = shot
	_place_shot(shot, p)


func _update_shots(k: float) -> void:
	for p in sim.projectiles:
		var shot: Dictionary = _shots.get(p.pid, {})
		if not shot.is_empty():
			_place_shot(shot, p, k)


func _place_shot(shot: Dictionary, p: Dictionary, k := 1.0) -> void:
	var target := fx_point(p.x, p.y)
	shot.pos = shot.pos.lerp(target, k)
	shot.target = fx_point(p.tx, p.ty)
	var total: float = maxf(1.0, (shot.target - shot.from).length())
	var t := clampf(1.0 - (shot.target - shot.pos).length() / total, 0.0, 1.0)
	var arc: float = total * shot.gravity * ARC_PER_GRAVITY * 4.0 * t * (1.0 - t)
	var z: float = lerpf(shot.z0, 0.0, t) + arc
	var node: Node2D = shot.node
	var prev: Vector2 = node.position
	node.position = shot.pos - Vector2(0, z)
	if prev != Vector2.ZERO and node.position.distance_to(prev) > 0.1:
		node.rotation = (node.position - prev).angle() + PI / 2
	if shot.has("shadow"):
		shot.shadow.position = shot.pos
	for trail in shot.get("trail", []):
		if is_instance_valid(trail):
			trail.position = node.position


func _on_projectile_hit(p: Dictionary) -> void:
	var shot: Dictionary = _shots.get(p.pid, {})
	_shots.erase(p.pid)
	for key in ["node", "shadow"]:
		if shot.has(key) and is_instance_valid(shot[key]):
			shot[key].queue_free()
	for trail in shot.get("trail", []):
		if is_instance_valid(trail):
			trail.queue_free()
	var visual := GameDB.visual(p.get("name", ""))
	Effects.play(visual.get("HitEffect", ""), self, fx_point(p.x, p.y), p.team != viewer_team)


## Sort de zone : effet ponctuel, sol à son rayon et effet en boucle tant que la zone dure.
func _on_area(a: Dictionary) -> void:
	var visual := GameDB.visual(a.name)
	var at := fx_point(a.x, a.y)
	var enemy: bool = a.team != viewer_team
	var kept: Array = Effects.play(visual.get("OneShotEffect", ""), self, at, enemy)
	kept.append_array(Effects.play(visual.get("ScaledEffect", ""), self, at, enemy))
	kept.append_array(Effects.play(visual.get("LoopingEffect", ""), self, at, enemy))
	if not kept.is_empty():
		_area_fx[a.aid] = kept


func _clean_area_fx() -> void:
	if _area_fx.is_empty():
		return
	var alive := {}
	for a in sim.areas:
		alive[a.aid] = true
	for aid in _area_fx.keys():
		if not alive.has(aid):
			for node in _area_fx[aid]:
				if is_instance_valid(node):
					if node is ParticleEmitter:
						node.finish()
					else:
						node.queue_free()
			_area_fx.erase(aid)


## Unité de l'équipe à cette position exacte (tireur d'un projectile qui vient de partir).
func _entity_at(x: int, y: int, team: int) -> Dictionary:
	for e in sim.entities:
		if e.team == team and e.x == x and e.y == y:
			return e
	return {}


func _entity(id: int) -> Dictionary:
	for e in sim.entities:
		if e.id == id:
			return e
	return {}


# --- Barres de vie ------------------------------------------------------------------------------

## Point 3D du monde → point du canevas.
func world_to_canvas(p: Vector3) -> Vector2:
	return _camera.unproject_position(p)


## Barres de vie comme la 16.4 : barre arrondie bleue / rouge, badge de niveau à gauche, points
## de vie écrits sur les tours.
func _draw_overlay() -> void:
	var font := ScTextField.font_for("Supercell-Magic")
	for e in sim.entities:
		var tower: bool = e.kind == BattleSim.Kind.TOWER
		if e.hp >= e.max_hp and not tower:
			continue
		if tower and e.hp <= 0:
			continue
		var at: Vector2
		var width := 0.9
		var view: UnitView = _views.get(e.id)
		if tower and (e.king or view == null):
			at = map.to_screen(e.x, e.y) + Vector2(0, -2.9 if e.king else -2.3) * map.cell_px()
			width = 2.2 if e.king else 1.9
		elif view:
			width = 1.6 if tower else 0.9
			at = world_to_canvas(view.position + Vector3(0, view.head + 0.25, 0))
		else:
			continue
		var cell := map.cell_px()
		var w := width * cell
		var h := maxf(6.0, (0.32 if tower else 0.17) * cell)
		var rect := Rect2(at - Vector2(w / 2, h / 2), Vector2(w, h))
		var enemy: bool = e.team != viewer_team
		var main := Color("e8344a") if enemy else Color("3d9bff")
		var dark := Color("6b0f1c") if enemy else Color("0f3a85")
		var r := h * 0.5
		_overlay.draw_rect(rect.grow(2.0), Color(0.05, 0.05, 0.08, 0.9))
		var ratio := clampf(float(e.hp) / maxf(1.0, e.max_hp), 0.0, 1.0)
		_overlay.draw_rect(rect, dark)
		_overlay.draw_rect(Rect2(rect.position, Vector2(w * ratio, h)), main)
		_overlay.draw_rect(Rect2(rect.position, Vector2(w * ratio, h * 0.35)), main.lightened(0.35))
		# Badge du niveau.
		var level := int(e.get("level", 0))
		if not e.get("no_badge", false):
			var bs := h * (1.5 if tower else 1.6)
			var badge := Rect2(rect.position - Vector2(bs - 1, (bs - h) / 2), Vector2(bs, bs))
			_overlay.draw_rect(badge.grow(1.5), Color(0.05, 0.05, 0.08, 0.95))
			_overlay.draw_rect(badge, main.darkened(0.15))
			var txt := str(GameDB.display_level(e.get("rarity", "Common"), level))
			var fs := int(bs * 0.72)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_overlay.draw_string_outline(font, badge.position + Vector2((bs - tw) / 2, bs * 0.78), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
			_overlay.draw_string(font, badge.position + Vector2((bs - tw) / 2, bs * 0.78), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if tower:
			var hp_txt := str(int(e.hp))
			var fs := int(h * 1.05)
			var pos := rect.position + Vector2(4, h * 0.85)
			_overlay.draw_string_outline(font, pos, hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			_overlay.draw_string(font, pos, hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
