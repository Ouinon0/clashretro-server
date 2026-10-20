class_name ScLibrary
extends RefCounted
## Un fichier .sc exporté (assets/gen/sc/<nom>.json + textures, tools/export_client_assets.py ou
## export_16.py). Crée les objets d'affichage par nom d'export.

const DATA_DIR := "res://assets/gen/sc/"

static var _cache := {}
static var _loading := {}           # nom -> [tâche WorkerThreadPool, bibliothèque en cours]

var file_name: String
var textures: Array[Texture2D] = []
var exports := {}
var matrices: Array[Transform2D] = []
var color_mul: Array[Color] = []
var color_add: Array[Color] = []
var shapes := {}
var movieclips := {}
var textfields := {}


static func get_library(sc_name: String) -> ScLibrary:
	if _loading.has(sc_name):
		var job: Array = _loading[sc_name]
		_loading.erase(sc_name)
		WorkerThreadPool.wait_for_task_completion(job[0])
		_cache[sc_name] = job[1]
	if not _cache.has(sc_name):
		var lib := ScLibrary.new()
		lib._load(sc_name)
		_cache[sc_name] = lib
	return _cache[sc_name]


## Libère le cache (avant de quitter : Godot détruit mal les ressources tenues par des statiques).
static func clear_cache() -> void:
	for sc_name in _loading.keys():
		get_library(sc_name)
	_cache.clear()


## Charge des fichiers en arrière-plan (JSON et textures) : le combat ne fige plus l'image à la
## première apparition d'une unité ni pendant l'intro.
static func preload_async(names: Array) -> void:
	for sc_name in names:
		if sc_name == "" or _cache.has(sc_name) or _loading.has(sc_name):
			continue
		if not FileAccess.file_exists(DATA_DIR + sc_name + ".json"):
			continue
		var lib := ScLibrary.new()
		_loading[sc_name] = [WorkerThreadPool.add_task(lib._load.bind(sc_name), false, "sc " + sc_name), lib]


## Crée l'export `export_name` du fichier `sc_name` (ex. "ui", "popup_card_info").
static func create(sc_name: String, export_name: String) -> Node2D:
	return get_library(sc_name).create_export(export_name)


func _load(sc_name: String) -> void:
	file_name = sc_name
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + sc_name + ".json"))
	for t in data.textures:
		textures.append(load(DATA_DIR + t.file) if t.has("file") else null)
	exports = data.exports
	for m in data.matrices:
		matrices.append(Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5])))
	for c in data.colors:
		color_add.append(Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, 0.0))
		color_mul.append(Color(c[3], c[4], c[5], c[6]))
	shapes = data.shapes
	movieclips = data.movieclips
	textfields = data.textfields


func has_export(export_name: String) -> bool:
	return exports.has(export_name)


func create_export(export_name: String) -> Node2D:
	if not exports.has(export_name):
		push_error("%s.sc : export '%s' introuvable" % [file_name, export_name])
		return Node2D.new()
	var node := create_by_id(int(exports[export_name]), export_name)
	node.name = export_name
	return node


func create_by_id(id: int, instance_name: String = "") -> Node2D:
	var key := str(id)
	if movieclips.has(key):
		return ScMovieClip.new(self, movieclips[key])
	if shapes.has(key):
		return ScShape.new(self, shapes[key])
	if textfields.has(key):
		return ScTextField.new(textfields[key], instance_name)
	return Node2D.new()
