class_name TopBar
extends Control
## Barre du haut de la 16.4 (Menu_topLayer_Banner de ui.sc), commune à tous les onglets : niveau du
## roi et expérience à gauche, or et gemmes à droite. Le « + » des ressources mène à la boutique.

signal shop_requested

const HEIGHT := 64.0                # hauteur de la barre (px) sous la marge du haut

var _xp: ScMovieClip
var _coins: ScMovieClip
var _gems: ScMovieClip
var _star: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := ScreenLayout.top()
	size = Vector2(ScreenLayout.size().x, top + HEIGHT)
	var left := ScUi.element(ScUi.clip("ui", "Menu_topLayer_Banner/left_top/xp"))
	_xp = ScUi.node_of(left)
	ScUi.hide(_xp, ["xp_bar/TID_CLAIM", "xp_bar/notification"])
	left.position = Vector2(14, top + (HEIGHT - left.size.y) / 2)
	add_child(left)
	# Étoile du niveau (icon_xp) par-dessus l'icône de la route du roi de la 16.4.
	var star_node := ScUi.clip("ui", "Menu_topLayer_Banner/left_top/xp/icon_xp")
	_star = ScUi.fit_height(star_node, HEIGHT * 0.95)
	_star.position = Vector2(4, top + (HEIGHT - _star.size.y) / 2)
	add_child(_star)
	ScUi.make_button(left, func() -> void: ScUi.popup(self, ProfilePopup.new()))
	var right := ScUi.clip("ui", "Menu_topLayer_Banner/right_top") as ScMovieClip
	_coins = right.get_sc("coins") as ScMovieClip
	_gems = right.get_sc("gems") as ScMovieClip
	var x := size.x - 12
	for c in [_gems, _coins]:
		c.get_parent().remove_child(c)
		c.transform = Transform2D.IDENTITY
		var box := ScUi.element(c)
		x -= box.size.x
		box.position = Vector2(x, top + (HEIGHT - box.size.y) / 2)
		x -= 14
		add_child(box)
		ScUi.make_button(box, func() -> void: shop_requested.emit())
	right.free()
	Player.changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	Player.changed.disconnect(refresh)


func refresh() -> void:
	var p := Player.profile
	ScUi.set_text(_coins, "gold/txt", str(int(p.get("gold", 0))))
	ScUi.set_text(_gems, "gems/txt", str(int(p.get("gems", 0))))
	var level := int(p.get("level", 1))
	var levels: Array = GameDB.table("exp_levels")
	var need := int(levels[clampi(level - 1, 0, levels.size() - 1)])
	var exp := int(p.get("exp", 0))
	var bar := _xp.get_sc("xp_bar") as ScMovieClip
	if bar:
		bar.goto_and_stop(clampi(int(99.0 * exp / maxf(1, need)), 0, 99) if level < 13 else 99)
	ScUi.set_text(_xp, "xp_bar/xp_count", "%d/%d" % [exp, need] if level < 13 else "Max")
	ScUi.set_any_text(ScUi.node_of(_star), "xp_level", str(level))
