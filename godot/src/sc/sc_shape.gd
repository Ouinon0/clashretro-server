class_name ScShape
extends Node2D
## Forme .sc : polygones texturés (une « bitmap » par polygone ; convexes en 1.9, souvent concaves
## dans les fichiers de la 16.4).

const ADD_SHADER := preload("res://src/sc/sc_color_add.gdshader")
## Modes de fusion .sc (numérotation Flash) : 3 multiplication, 4 écran, 8 addition.
const BLEND_MULTIPLY := 3
const BLEND_SCREEN := 4
const BLEND_ADD := 8

static var _blend_materials := {}
static var _blend_shaders := {}

var _commands: Array = []  # [texture, points, uvs, indices, couleurs]
var _source: Array = []    # polygones d'origine (avant découpe 9-slice)
var _add := Color(0, 0, 0, 0)
var _blend := 0


func _init(lib: ScLibrary, bitmaps: Array) -> void:
	for bm in bitmaps:
		var tex: Texture2D = lib.textures[int(bm.t)]
		if tex == null:
			continue
		var xy: Array = bm.xy
		var uv: Array = bm.uv
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in range(0, xy.size(), 2):
			points.append(Vector2(xy[i], xy[i + 1]))
			uvs.append(Vector2(uv[i], uv[i + 1]))
		var indices := _triangles(points)
		var colors := PackedColorArray()
		colors.resize(points.size())
		colors.fill(Color.WHITE)
		_commands.append([tex, points, uvs, indices, colors])


func _draw() -> void:
	var item := get_canvas_item()
	for cmd in _commands:
		RenderingServer.canvas_item_add_triangle_array(item, cmd[3], cmd[1], cmd[4], cmd[2],
				PackedInt32Array(), PackedFloat32Array(), cmd[0].get_rid())


## Couleur additive cumulée depuis les parents (transformations de couleur .sc).
func set_add(add: Color) -> void:
	if add == _add:
		return
	_add = add
	_update_material()


## Mode de fusion hérité du movieclip parent (lueurs des effets, reflets, ombres multipliées).
func set_blend(mode: int) -> void:
	if mode == _blend or mode not in [0, BLEND_MULTIPLY, BLEND_SCREEN, BLEND_ADD]:
		return
	_blend = mode
	_update_material()


func _update_material() -> void:
	var has_add := _add.r != 0.0 or _add.g != 0.0 or _add.b != 0.0
	if not has_add:
		material = null if _blend == 0 else _shared_blend_material(_blend)
		return
	if not (material is ShaderMaterial) or material == _blend_materials.get(_blend):
		material = ShaderMaterial.new()
	material.shader = ADD_SHADER if _blend == 0 else _blend_shader(_blend)
	material.set_shader_parameter("add_color", _add)


static func _shared_blend_material(mode: int) -> Material:
	if not _blend_materials.has(mode):
		var m := ShaderMaterial.new()
		m.shader = _blend_shader(mode)
		_blend_materials[mode] = m
	return _blend_materials[mode]


## Le multiplicatif éclaircit vers le blanc là où la forme est transparente ; l'écran est rendu
## en additif atténué (pas d'équivalent exact sans lire l'image de fond).
static func _blend_shader(mode: int) -> Shader:
	if not _blend_shaders.has(mode):
		var body := {
			BLEND_ADD: "render_mode blend_add;\nvoid fragment() { vec4 c = texture(TEXTURE, UV) * COLOR; COLOR = vec4(min(c.rgb + add_color.rgb, vec3(1.0)), c.a); }",
			BLEND_SCREEN: "render_mode blend_add;\nvoid fragment() { vec4 c = texture(TEXTURE, UV) * COLOR; COLOR = vec4(min(c.rgb + add_color.rgb, vec3(1.0)) * 0.8, c.a); }",
			BLEND_MULTIPLY: "render_mode blend_mul;\nvoid fragment() { vec4 c = texture(TEXTURE, UV) * COLOR; COLOR = vec4(mix(vec3(1.0), min(c.rgb + add_color.rgb, vec3(1.0)), c.a), 1.0); }",
		}
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nuniform vec4 add_color = vec4(0.0);\n" + body[mode]
		_blend_shaders[mode] = shader
	return _blend_shaders[mode]


## Découpe les polygones par `mask` (polygone convexe dans le repère local de la forme) :
## intersection géométrique + coordonnées de texture recalculées, sans coût au rendu.
func clip_to(mask: PackedVector2Array) -> void:
	var clipped: Array = []
	for cmd in _commands:
		var points: PackedVector2Array = cmd[1]
		var uvs: PackedVector2Array = cmd[2]
		var parts := Geometry2D.intersect_polygons(points, mask)
		if parts.is_empty():
			continue
		var tri := _base_triangle(points)
		if tri.is_empty():
			continue
		var to_uv := _affine(tri.map(func(i: int) -> Vector2: return points[i]),
				tri.map(func(i: int) -> Vector2: return uvs[i]))
		# Les trous laissés par la découpe sont orientés à l'inverse de la plus grande surface.
		var outer := _signed_area(parts[0])
		for part in parts:
			if absf(_signed_area(part)) > absf(outer):
				outer = _signed_area(part)
		for part in parts:
			if _signed_area(part) * outer < 0.0:
				continue
			var new_uvs := PackedVector2Array()
			for p in part:
				new_uvs.append(to_uv * p)
			var indices := _triangles(part)
			var colors := PackedColorArray()
			colors.resize(part.size())
			colors.fill(Color.WHITE)
			clipped.append([cmd[0], part, new_uvs, indices, colors])
	_commands = clipped
	queue_redraw()


## 9-slice : les polygones sont découpés selon les 9 cases de la grille `cells` (repère du clip
## qui porte la grille ; `to_clip` = repère de la forme → clip), puis leurs sommets sont déplacés
## par `remap` (clip → clip) ; les coins gardent leur taille, les bords et le centre s'étirent.
func nine_slice(to_clip: Transform2D, cells: Array, remap: Callable) -> void:
	if _source.is_empty():
		_source = _commands
	var back := to_clip.affine_inverse()
	var out: Array = []
	for cmd in _source:
		var points: PackedVector2Array = cmd[1]
		var uvs: PackedVector2Array = cmd[2]
		var tri := _base_triangle(points)
		if tri.is_empty():
			continue
		var to_uv := _affine(tri.map(func(i: int) -> Vector2: return points[i]),
				tri.map(func(i: int) -> Vector2: return uvs[i]))
		var in_clip := to_clip * points
		for cell in cells:
			var r: Rect2 = cell
			var box := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			for part in Geometry2D.intersect_polygons(in_clip, box):
				if absf(_signed_area(part)) < 0.01:
					continue
				var local := PackedVector2Array()
				var new_uvs := PackedVector2Array()
				for p in part:
					new_uvs.append(to_uv * (back * p))
					local.append(back * (remap.call(p) as Vector2))
				var colors := PackedColorArray()
				colors.resize(local.size())
				colors.fill(Color.WHITE)
				out.append([cmd[0], local, new_uvs, _triangles(local), colors])
	_commands = out
	queue_redraw()


static func _signed_area(points: PackedVector2Array) -> float:
	var a := 0.0
	for i in points.size():
		a += points[i].cross(points[(i + 1) % points.size()])
	return a / 2.0


## Triangles d'un polygone : éventail pour les petits polygones convexes (fichiers 1.9), vraie
## triangulation sinon (formes de la 16.4 qui épousent le dessin, souvent concaves).
static func _triangles(points: PackedVector2Array) -> PackedInt32Array:
	if points.size() > 4:
		var tri := Geometry2D.triangulate_polygon(points)
		if not tri.is_empty():
			return tri
	var fan := PackedInt32Array()
	for i in range(1, points.size() - 1):
		fan.append_array([0, i, i + 1])
	return fan


static func _base_triangle(points: PackedVector2Array) -> Array:
	for i in points.size():
		for j in range(i + 1, points.size()):
			for k in range(j + 1, points.size()):
				var area := (points[j] - points[i]).cross(points[k] - points[i])
				if absf(area) > 0.01:
					return [i, j, k]
	return []


## Transformation affine qui envoie les 3 points `src` sur `dst`.
static func _affine(src: Array, dst: Array) -> Transform2D:
	var a := Transform2D(src[1] - src[0], src[2] - src[0], src[0])
	var b := Transform2D(dst[1] - dst[0], dst[2] - dst[0], dst[0])
	return b * a.affine_inverse()
