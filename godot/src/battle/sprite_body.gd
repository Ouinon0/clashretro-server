class_name SpriteBody
extends Node3D
## Unité dessinée avec ses sprites .sc de la 16.4 (chr_*.sc, building_*.sc), pour les cartes sans
## modèle 3D : le clip est rendu dans une petite vue 2D et affiché sur un panneau tourné vers la
## caméra, pieds sur le sol. Les sprites et les modèles 3D se cachent ainsi selon leur profondeur.
##
## Exports « <base>_<action>1_<direction> » comme dans la 1.9 : actions idle, run, attack (charge
## pour le Prince), directions 1 (dos) à 9 (face), les autres côtés par miroir.

const RESOLUTION := 2.0             # pixels de la vue par unité .sc
const MARGIN := 0.15                # marge autour du contour du sprite

static var _bounds_cache := {}
static var _filters := {}

var _lib: ScLibrary
var _base := ""
var _scale := 1.0
var _viewport := SubViewport.new()
var _holder := Node2D.new()
var _sprite := Sprite3D.new()
var _clip: Node2D
var _name := ""
var _mirror := false
var _filter: Array = []             # arrivée (DeployBaseAnimExportName) : images à appliquer
var _filter_time := 0.0


## `visual` : apparence 16.4 (GameDB.visual) ; `enemy` : exports rouges.
func setup(visual: Dictionary, enemy: bool) -> bool:
	var file := str(visual.get("FileName", "")).get_file().get_basename()
	if file == "" or not ResourceLoader.exists(ScLibrary.DATA_DIR + file + ".json"):
		return false
	_lib = ScLibrary.get_library(file)
	_base = visual.get("RedExportName" if enemy else "BlueExportName", "")
	if _base == "":
		_base = visual.get("BlueExportName", "")
	if _first_export() == "":
		return false
	_scale = float(visual.get("Scale", 100)) / 100.0
	var box := _bounds()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.size = Vector2i(ceili(box.size.x * RESOLUTION), ceili(box.size.y * RESOLUTION))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_viewport)
	_holder.position = -box.position * RESOLUTION
	_holder.scale = Vector2.ONE * RESOLUTION
	_viewport.add_child(_holder)
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = 1.0 / (ArenaMap.CELL_X * RESOLUTION)
	_sprite.centered = false
	# Pieds (origine du clip) à l'origine du nœud ; le haut de la texture est en haut.
	var feet := _holder.position
	_sprite.offset = Vector2(-feet.x, feet.y - _viewport.size.y)
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	show_anim("idle", 5)
	return true


## Arrivée de l'unité : l'export « filter_* » d'effects.sc n'est qu'un gabarit dont l'animation
## (chute, étirement, blanc qui s'estompe) s'applique au sprite, comme un filtre du moteur d'origine.
func play_deploy(export_name: String) -> void:
	_filter = _filter_frames(export_name)
	_filter_time = 0.0
	if not _filter.is_empty():
		_apply_filter(0.0)


func _process(delta: float) -> void:
	if not _filter.is_empty():
		_apply_filter(delta)


func _apply_filter(delta: float) -> void:
	_filter_time += delta
	var index := int(_filter_time * _filter[0][3])
	var base := Transform2D(0, Vector2.ONE * RESOLUTION, 0, _holder.get_meta("origin", _holder.position))
	if not _holder.has_meta("origin"):
		_holder.set_meta("origin", _holder.position)
	if index >= _filter.size():
		_holder.transform = base
		_holder.modulate = Color.WHITE
		if _clip is ScMovieClip:
			_clip.set_inherited_add(Color(0, 0, 0, 0))
		_filter = []
		return
	var frame: Array = _filter[index]
	_holder.transform = base * frame[0]
	_holder.modulate = frame[1]
	if _clip is ScMovieClip:
		_clip.set_inherited_add(frame[2])


static func _filter_frames(export_name: String) -> Array:
	if _filters.has(export_name):
		return _filters[export_name]
	var out: Array = []
	if ResourceLoader.exists(ScLibrary.DATA_DIR + "effects.json"):
		var lib := ScLibrary.get_library("effects")
		if lib.has_export(export_name) and lib.movieclips.has(str(lib.exports[export_name])):
			var data: Dictionary = lib.movieclips[str(lib.exports[export_name])]
			for f in data.frames:
				var e: Array = f.e[0] if not f.e.is_empty() else [0, -1, -1]
				out.append([lib.matrices[int(e[1])] if int(e[1]) >= 0 else Transform2D.IDENTITY,
						lib.color_mul[int(e[2])] if int(e[2]) >= 0 else Color.WHITE,
						lib.color_add[int(e[2])] if int(e[2]) >= 0 else Color(0, 0, 0, 0), int(data.fps)])
	_filters[export_name] = out
	return out


## Hauteur du haut du sprite (cases), pour la barre de vie.
func top() -> float:
	return _viewport.size.y / RESOLUTION / ArenaMap.CELL_X * 0.8


## Animation `action` (idle, run, attack, charge) vue dans la direction `dir` de la simulation
## (1 à 9, négative = vers la gauche), déjà tournée pour le joueur qui regarde.
func show_anim(action: String, dir: int) -> void:
	var mirror := dir < 0
	var name := "%s_%s1_%d" % [_base, action, absi(dir)]
	if not _lib.has_export(name):
		name = "%s_idle1_%d" % [_base, absi(dir)]
	if not _lib.has_export(name):
		name = _first_export()
		mirror = false
	if name == _name and mirror == _mirror:
		return
	if _clip:
		_clip.queue_free()
	_clip = _lib.create_export(name)
	_clip.scale = Vector2(-_scale if mirror else _scale, _scale)
	_holder.add_child(_clip)
	_name = name
	_mirror = mirror


func _first_export() -> String:
	for name in [_base + "_idle1_5", _base + "_idle1_1", _base]:
		if _lib.has_export(name):
			return name
	return ""


## Contour commun des animations (repère .sc, origine aux pieds), mis en cache par sprite.
func _bounds() -> Rect2:
	var key := _lib.file_name + "/" + _base
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var box := Rect2()
	var first := true
	for action in ["idle", "run", "attack"]:
		for dir in [1, 3, 5, 7, 9]:
			var name := "%s_%s1_%d" % [_base, action, dir]
			if not _lib.has_export(name):
				continue
			var clip := _lib.create_export(name)
			var b := ScMovieClip.bounds_of(clip)
			clip.free()
			b = Rect2(Vector2(-maxf(absf(b.position.x), absf(b.end.x)), b.position.y),
					Vector2(2.0 * maxf(absf(b.position.x), absf(b.end.x)), b.size.y))
			box = b if first else box.merge(b)
			first = false
	if first:
		var clip := _lib.create_export(_first_export())
		box = ScMovieClip.bounds_of(clip)
		clip.free()
	box = box.grow_individual(box.size.x * MARGIN, box.size.y * MARGIN, box.size.x * MARGIN, box.size.y * MARGIN)
	box.position *= _scale
	box.size *= _scale
	_bounds_cache[key] = box
	return box
