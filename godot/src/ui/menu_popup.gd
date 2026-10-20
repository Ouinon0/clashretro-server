class_name MenuPopup
extends Control
## Menu ☰ de la 16.4 : bulle blanche (context_menu_bubble_main) et boutons bleus à icône
## (comme main_list_menu), sous le bouton du menu ; un toucher ailleurs la ferme.

var _items: Array = []
var _anchor := Vector2.ZERO


## `items` : [texte, export d'icône de ui.sc ou "", action] ; `anchor` : coin haut-droit de la bulle.
static func make(items: Array, anchor: Vector2) -> MenuPopup:
	var m := MenuPopup.new()
	m._items = items
	m._anchor = anchor
	return m


func _ready() -> void:
	size = ScreenLayout.size()
	position = -get_parent().global_position if get_parent() is Control else Vector2.ZERO
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.size = size
	add_child(shade)
	ScUi.make_button(shade, queue_free, "", false)
	var w := 420.0
	var item_h := 84.0
	var h := _items.size() * (item_h + 14) + 30
	var bubble := Control.new()
	bubble.size = Vector2(w, h)
	bubble.position = _anchor - Vector2(w, 0)
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bubble)
	var bg := ScSlice.make("ui_common", "bg_r25", Color("f4f7fb"), 1.4)
	bg.size = bubble.size
	bubble.add_child(bg)
	for i in _items.size():
		var item: Array = _items[i]
		var b := ScUi.text_button("blue", item[0], Vector2(w - 36, item_h), func() -> void:
			queue_free()
			item[2].call(), 26)
		b.position = Vector2(18, 18 + i * (item_h + 14))
		bubble.add_child(b)
		if item[1] != "":
			var icon := ScUi.fit_height(ScUi.clip("ui", item[1]), item_h * 0.7)
			icon.position = Vector2(14, (item_h * 0.9 - icon.size.y) / 2)
			b.add_child(icon)
			var text := b.get_child(1) as Label
			text.position.x = icon.size.x + 18
			text.size.x = b.size.x - icon.size.x - 30
	bubble.pivot_offset = Vector2(w, 0)
	bubble.scale = Vector2.ONE * 0.7
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(bubble, "scale", Vector2.ONE, 0.18)
