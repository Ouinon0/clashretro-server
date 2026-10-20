class_name ScMovieClip
extends Node2D
## Movieclip .sc : enfants positionnés image par image (matrice + couleur), lecture à `fps`.
##
## Le code du jeu pilote l'UI comme le moteur d'origine : on retrouve un enfant par son nom
## d'instance (get_sc), on le masque (set_sc_visible), on change un texte (set_text), on joue
## une étiquette (play_label).

signal finished
signal label_reached(label: String)

var lib: ScLibrary
var fps := 30
var frames: Array = []
var loop := true
var playing := false
var current_frame := 0
var scaling_grid := Rect2()  # 9-slice, vide si absent

var _children: Array[Node2D] = []
var _child_names: Array[String] = []
var _hidden := {}  # indices masqués par le code
var _adjust := {}  # index -> Transform2D de mise en page appliquée par-dessus la matrice
var _order := PackedInt32Array()
var _time := 0.0
var _labels := {}
var _stop_at := -1  # image où s'arrêter (play_range), -1 = aucune
var _local_add: Array[Color] = []  # composante additive propre à chaque enfant
var _inherited_add := Color(0, 0, 0, 0)


func _init(library: ScLibrary, data: Dictionary) -> void:
	lib = library
	fps = maxi(1, int(data.fps))
	frames = data.frames
	if data.grid != null:
		scaling_grid = Rect2(data.grid[0], data.grid[1], data.grid[2], data.grid[3])
	var ids: Array = data.children
	var names: Array = data.names
	var blends: Array = data.get("blend", [])
	for i in ids.size():
		var instance_name: String = names[i] if names[i] != null else ""
		var child := lib.create_by_id(int(ids[i]), instance_name)
		if instance_name != "":
			child.name = instance_name
		child.visible = false
		if i < blends.size() and int(blends[i]) != 0:
			_push_blend(child, int(blends[i]))
		add_child(child)
		_children.append(child)
		_child_names.append(instance_name)
		_local_add.append(Color(0, 0, 0, 0))
	for f in frames.size():
		var label = frames[f].l
		if label != null and label != "":
			_labels[label] = f
	_show_frame(0)
	set_process(false)
	# Les clips à 2 images sont des clips d'états (normal/annuler, coffre 1/2…) pilotés par le code ;
	# au-delà ce sont des animations, qui jouent dès leur création comme dans le moteur d'origine.
	if frames.size() > 2:
		play()


func _process(delta: float) -> void:
	_time += delta
	var step := 1.0 / fps
	while _time >= step and playing:
		_time -= step
		_advance()


func _advance() -> void:
	if _stop_at >= 0 and current_frame == _stop_at:
		_stop_at = -1
		stop()
		finished.emit()
		return
	var next := current_frame + 1
	if next < frames.size() and frames[next].l != null and frames[next].l != "":
		label_reached.emit(frames[next].l)
	if next >= frames.size():
		if not loop:
			stop()
			finished.emit()
			return
		next = 0
	_show_frame(next)


func _show_frame(f: int) -> void:
	current_frame = f
	var elements: Array = frames[f].e
	var order := PackedInt32Array()
	var shown := {}
	for e in elements:
		var index := int(e[0])
		var child := _children[index]
		var m := int(e[1])
		var c := int(e[2])
		child.transform = lib.matrices[m] if m >= 0 else Transform2D.IDENTITY
		if child is ScMovieClip and child.scaling_grid.size != Vector2.ZERO:
			_apply_grid(child)
		if _adjust.has(index):
			child.transform = _adjust[index] * child.transform
		child.modulate = lib.color_mul[c] if c >= 0 else Color.WHITE
		var add := lib.color_add[c] if c >= 0 else Color(0, 0, 0, 0)
		if add != _local_add[index]:
			_local_add[index] = add
			_push_add(child, _inherited_add + add)
		shown[index] = true
		order.append(index)
	for i in _children.size():
		_children[i].visible = shown.has(i) and not _hidden.has(i)
	# L'ordre des éléments d'une frame est l'ordre de dessin.
	if order != _order:
		_order = order
		for z in order.size():
			move_child(_children[order[z]], z)


## Un enfant à grille 9-slice étiré par sa matrice garde ses coins : l'étirement passe dans ses
## formes (set_slice_rect), la matrice ne garde que rotation, symétrie et position.
static func _apply_grid(child: ScMovieClip) -> void:
	var t := child.transform
	var s := t.get_scale()
	if absf(absf(s.x) - 1.0) < 0.01 and absf(absf(s.y) - 1.0) < 0.01:
		if child.has_meta("slice_target"):
			child.set_slice_rect(child.get_meta("slice_bounds"))
			child.remove_meta("slice_target")
		return
	if not child.has_meta("slice_bounds"):
		child.set_meta("slice_bounds", bounds_of(child))
	var b: Rect2 = child.get_meta("slice_bounds")
	var a := s.abs()
	var target := Rect2(b.position * a, b.size * a)
	if not child.has_meta("slice_target") or not (child.get_meta("slice_target") as Rect2).is_equal_approx(target):
		child.set_slice_rect(target)
		child.set_meta("slice_target", target)
	child.transform = Transform2D(t.get_rotation(), Vector2(signf(s.x), signf(s.y)), t.get_skew(), t.origin)


func _push_add(node: Node2D, add: Color) -> void:
	if node is ScShape:
		node.set_add(add)
	elif node is ScMovieClip:
		node.set_inherited_add(add)


## Le mode de fusion d'un enfant s'applique à toutes les formes qu'il contient.
static func _push_blend(node: Node2D, mode: int) -> void:
	if node is ScShape:
		node.set_blend(mode)
	elif node is ScMovieClip:
		for c in node._children:
			_push_blend(c, mode)


func set_inherited_add(add: Color) -> void:
	if add == _inherited_add:
		return
	_inherited_add = add
	for i in _children.size():
		_push_add(_children[i], add + _local_add[i])


# --- Lecture ---------------------------------------------------------------------------------

func play() -> void:
	playing = true
	set_process(true)


func stop() -> void:
	playing = false
	set_process(false)


func goto_and_stop(frame) -> void:
	_show_frame(_frame_index(frame))
	stop()


func goto_and_play(frame) -> void:
	_show_frame(_frame_index(frame))
	play()


## Joue de l'étiquette `start` jusqu'à `end` (ex. "icon_in_start" → "icon_in_end").
func play_label(start: String, end: String = "") -> void:
	if end == "":
		goto_and_play(start)
		loop = false
	else:
		play_range(start, end)


## Joue de `from` à `to` (images ou étiquettes) puis s'arrête et émet `finished`.
func play_range(from, to) -> void:
	_show_frame(_frame_index(from))
	_stop_at = _frame_index(to)
	if current_frame == _stop_at:
		_stop_at = -1
		stop()
		finished.emit.call_deferred()
		return
	play()


func has_label(label: String) -> bool:
	return _labels.has(label)


func _frame_index(frame) -> int:
	if frame is String:
		return _labels.get(frame, 0)
	return clampi(int(frame), 0, frames.size() - 1)


# --- Accès aux enfants -----------------------------------------------------------------------

## Enfant par nom d'instance ; accepte un chemin "a/b/c".
func get_sc(path: String) -> Node2D:
	var node: Node2D = self
	for part in path.split("/"):
		if not node is ScMovieClip:
			return null
		var clip: ScMovieClip = node
		var index := clip._child_names.find(part)
		if index < 0:
			return null
		node = clip._children[index]
	return node


func set_sc_visible(path: String, value: bool) -> void:
	var parts := path.rsplit("/", true, 1)
	var parent: ScMovieClip = self if parts.size() == 1 else get_sc(parts[0]) as ScMovieClip
	if parent == null:
		return
	var index := parent._child_names.find(parts[-1])
	if index < 0:
		return
	if value:
		parent._hidden.erase(index)
	else:
		parent._hidden[index] = true
	parent._show_frame(parent.current_frame)


## Décale un enfant direct (ancrage à l'écran) ; conservé d'une image à l'autre.
func set_sc_offset(child_name: String, offset: Vector2) -> void:
	set_sc_adjust(child_name, Transform2D(0.0, offset))


## Transformation de mise en page (repère du parent) appliquée par-dessus la matrice de l'image.
func set_sc_adjust(child_name: String, adjust: Transform2D) -> void:
	var index := _child_names.find(child_name)
	if index < 0:
		return
	_adjust[index] = adjust
	_show_frame(current_frame)


## Matrice d'origine (image courante, sans ajustement) d'un enfant direct.
func base_transform(child_name: String) -> Transform2D:
	var index := _child_names.find(child_name)
	for e in frames[current_frame].e:
		if int(e[0]) == index and int(e[1]) >= 0:
			return lib.matrices[int(e[1])]
	return Transform2D.IDENTITY


func set_text(path: String, text: String) -> void:
	var field := get_sc(path) as ScTextField
	if field:
		field.set_text(text)


## Remplace le contenu d'un enfant « zone » (placeholder) par un autre objet, à sa place.
## `fit` : met l'objet à l'échelle de la zone (comme les images de cartes) ;
## `mask` : découpe l'objet par la forme de cet export (ex. ScLibrary.create("ui", "card_mask_normal")).
func attach(path: String, node: Node2D, fit := false, mask: Node2D = null) -> void:
	var holder := get_sc(path)
	if holder == null:
		return
	var area := bounds_of(holder)
	for c in holder.get_children():
		if c is ScShape:
			c.visible = false
	if fit and area.size.x > 0:
		var own := bounds_of(node)
		if own.size.x > 0:
			var k := area.size.x / own.size.x
			node.scale = Vector2(k, k)
			node.position = area.get_center() - own.get_center() * k
	holder.add_child(node)
	if mask:
		_clip_by_mask(node, mask)


## Découpe toutes les formes de `node` par la forme de `mask` (même repère que `node`).
static func _clip_by_mask(node: Node2D, mask: Node2D) -> void:
	var mask_shapes := mask.find_children("*", "ScShape", true, false)
	if mask_shapes.is_empty():
		mask.free()
		return
	var mask_shape: ScShape = mask_shapes[0]
	var mask_to_holder := mask.transform * _relative_transform(mask, mask_shape)
	var mask_poly := PackedVector2Array()
	for p in mask_shape._commands[0][1]:
		mask_poly.append(mask_to_holder * p)
	mask.free()
	for shape in [node] + node.find_children("*", "ScShape", true, false):
		if shape is ScShape:
			var to_holder: Transform2D = node.transform * _relative_transform(node, shape)
			var local := PackedVector2Array()
			for p in mask_poly:
				local.append(to_holder.affine_inverse() * p)
			shape.clip_to(local)


## Contour local (formes et champs texte visibles ou non) d'un objet .sc.
static func bounds_of(node: Node2D) -> Rect2:
	var r := Rect2()
	var first := true
	var inv := node.global_transform.affine_inverse() if node.is_inside_tree() else Transform2D.IDENTITY
	for item in [node] + node.find_children("*", "Node2D", true, false):
		var points: Array = []
		if item is ScShape:
			for cmd in item._commands:
				points.append_array(Array(cmd[1]))
		elif item is ScTextField:
			var l: Label = item.label
			points = [l.position, l.position + l.size]
		if points.is_empty():
			continue
		var t := _relative_transform(node, item)
		for p in points:
			var q: Vector2 = t * p
			r = Rect2(q, Vector2.ZERO) if first else r.expand(q)
			first = false
	return r


## Contour des seules parties visibles (enfants masqués par set_sc_visible ou par l'image courante
## ignorés).
static func visible_bounds(node: Node2D) -> Rect2:
	var r := Rect2()
	var first := true
	for item in [node] + node.find_children("*", "Node2D", true, false):
		if not (item is ScShape or item is ScTextField) or not _shown_under(node, item):
			continue
		var points: Array = []
		if item is ScShape:
			for cmd in item._commands:
				points.append_array(Array(cmd[1]))
		else:
			var l: Label = item.label
			if l.text == "":
				continue
			points = [l.position, l.position + l.size]
		var t := _relative_transform(node, item)
		for p in points:
			var q: Vector2 = t * p
			r = Rect2(q, Vector2.ZERO) if first else r.expand(q)
			first = false
	return r


static func _shown_under(root: Node2D, item: Node) -> bool:
	var n: Node = item
	while n != root and n != null:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return true


static func _relative_transform(root: Node2D, item: Node2D) -> Transform2D:
	var t := Transform2D.IDENTITY
	var n: Node = item
	while n != root and n is Node2D:
		t = (n as Node2D).transform * t
		n = n.get_parent()
	return t


## Étire un clip à grille 9-slice (boutons, panneaux, bulles de la 16.4) au rectangle `target`
## (repère du clip) : coins intacts, bords et centre étirés.
func set_slice_rect(target: Rect2) -> void:
	if scaling_grid.size == Vector2.ZERO:
		return
	if not has_meta("slice_bounds"):
		set_meta("slice_bounds", bounds_of(self))
	var b: Rect2 = get_meta("slice_bounds")
	var g := scaling_grid.intersection(b)
	if g.size == Vector2.ZERO:
		g = Rect2(b.get_center(), Vector2.ZERO)
	var xs := [b.position.x, g.position.x, g.end.x, b.end.x]
	var ys := [b.position.y, g.position.y, g.end.y, b.end.y]
	var cells: Array = []
	for i in 3:
		for j in 3:
			cells.append(Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j]))
	var tx := _slice_axis(xs, target.position.x, target.end.x)
	var ty := _slice_axis(ys, target.position.y, target.end.y)
	var remap := func(p: Vector2) -> Vector2: return Vector2(_slice_map(p.x, xs, tx), _slice_map(p.y, ys, ty))
	for shape in find_children("*", "ScShape", true, false):
		(shape as ScShape).nine_slice(_relative_transform(self, shape), cells, remap)


## Positions cibles des 4 lignes d'un axe ; les coins rétrécissent si la cible est trop petite.
static func _slice_axis(src: Array, start: float, end: float) -> Array:
	var head: float = src[1] - src[0]
	var tail: float = src[3] - src[2]
	var k := minf(1.0, (end - start) / maxf(head + tail, 0.001))
	return [start, start + head * k, end - tail * k, end]


static func _slice_map(v: float, src: Array, dst: Array) -> float:
	for i in 3:
		if v <= src[i + 1] + 0.001 or i == 2:
			var span: float = src[i + 1] - src[i]
			var t: float = 0.0 if span <= 0.0 else (v - src[i]) / span
			return lerpf(dst[i], dst[i + 1], t)
	return v


func child_names() -> Array[String]:
	return _child_names
