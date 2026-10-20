class_name ArenaMap
extends RefCounted
## Correspondance entre la simulation (millièmes de case), l'écran (repère 2D du canevas) et le
## monde 3D des unités.
##
## Le décor de l'arène (2D, fichiers level_*_arena de la 16.4) garde le repère de la 1.9 :
## 29,64 × 27,26 unités .sc par case, centre de l'arène en (−2,5 ; 392,1). Les unités 3D sont vues
## par une caméra orthographique inclinée de PITCH degrés ; on étire la profondeur du monde pour que
## leurs pieds tombent exactement sur les cases du décor.

const CELL_X := 29.64               # unités .sc par case, en largeur
const CELL_Y := 27.26               # en hauteur (le décor est légèrement écrasé)
const SC_CENTER := Vector2(-2.5, 392.1)
const PITCH := 52.0                 # inclinaison de la caméra (degrés sous l'horizontale)

var sc_scale := 1.0                 # pixels d'écran par unité .sc
var center := Vector2.ZERO          # centre de l'arène à l'écran
var flipped := false                # vue depuis l'équipe du haut : arène retournée


## Arène dans le rectangle `area` (zone libre au-dessus de la main de cartes) : toute la largeur,
## 18 cases + une demi-case de marge de chaque côté, sans dépasser la hauteur.
func fit(area: Rect2, viewer_team: int) -> void:
	flipped = viewer_team == 1
	sc_scale = minf(area.size.x / (19.0 * CELL_X), area.size.y / (33.0 * CELL_Y))
	center = area.get_center()


## Pixels d'écran par case (en largeur).
func cell_px() -> float:
	return CELL_X * sc_scale


## Position du décor .sc (Node2D de l'export de fond) pour que l'arène tombe au bon endroit.
func background_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(sc_scale, sc_scale), 0.0, center - SC_CENTER * sc_scale)


## Point de la simulation → écran.
func to_screen(x: float, y: float) -> Vector2:
	if flipped:
		x = Rules.ARENA_W - x
		y = Rules.ARENA_H - y
	return center + Vector2((x - 9000.0) / 1000.0 * CELL_X, (y - 16000.0) / 1000.0 * CELL_Y) * sc_scale


## Écran → point de la simulation.
func to_arena(p: Vector2) -> Vector2i:
	var d := (p - center) / sc_scale
	var x := int(d.x / CELL_X * 1000.0) + 9000
	var y := int(d.y / CELL_Y * 1000.0) + 16000
	if flipped:
		x = Rules.ARENA_W - x
		y = Rules.ARENA_H - y
	return Vector2i(x, y)


## Point de la simulation → monde 3D (1 unité = 1 case en largeur, sol en y = 0).
func to_world(x: float, y: float, height := 0.0) -> Vector3:
	if flipped:
		x = Rules.ARENA_W - x
		y = Rules.ARENA_H - y
	return Vector3((x - 9000.0) / 1000.0, height, (y - 16000.0) / 1000.0 * depth_stretch())


## Étirement de la profondeur : une case de décor (CELL_Y) doit mesurer, une fois inclinée,
## la même hauteur à l'écran.
static func depth_stretch() -> float:
	return CELL_Y / (CELL_X * sin(deg_to_rad(PITCH)))


## Règle la caméra orthographique : centre de l'arène au point `center` de l'écran.
func setup_camera(cam: Camera3D, viewport_size: Vector2) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var ppu := cell_px()
	cam.size = viewport_size.y / ppu
	var pitch := deg_to_rad(PITCH)
	cam.transform = Transform3D(Basis.from_euler(Vector3(-pitch, 0.0, 0.0)),
			Vector3(0.0, 40.0 * sin(pitch), 40.0 * cos(pitch)))
	cam.h_offset = -(center.x - viewport_size.x / 2.0) / ppu
	cam.v_offset = (center.y - viewport_size.y / 2.0) / ppu
	cam.near = 1.0
	cam.far = 120.0
