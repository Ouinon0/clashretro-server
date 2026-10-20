class_name ScSlice
extends Control
## Panneau 9-slice .sc qui suit la taille du Control (cadres de fenêtres, fonds de listes).

var _node: Node2D
var _scale := 1.0


static func make(lib: String, export_name: String, color := Color.WHITE, corner := 1.0) -> ScSlice:
	var s := ScSlice.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s._node = ScUi.clip(lib, export_name)
	s._node.modulate = color
	s._scale = corner * ScUi.k()
	s._node.scale = Vector2.ONE * s._scale
	s.add_child(s._node)
	s.resized.connect(s._fit)
	return s


func _ready() -> void:
	_fit()                              # taille donnée avant l'entrée dans l'arbre (« resized » non émis)


func _fit() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if _node is ScMovieClip and (_node as ScMovieClip).scaling_grid.size != Vector2.ZERO:
		_node.scale = Vector2.ONE * _scale
		(_node as ScMovieClip).set_slice_rect(Rect2(Vector2.ZERO, size / _scale))
	else:                               # pas de grille : simple étirement
		if not has_meta("b"):
			set_meta("b", ScMovieClip.bounds_of(_node))
		var b: Rect2 = get_meta("b")
		_node.scale = size / b.size
		_node.position = -b.position * _node.scale
