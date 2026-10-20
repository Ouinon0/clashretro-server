class_name ShopPage
extends Control
## Boutique de la 16.4 (item_shop_*, séparateurs shop_*_divider) aux offres de la 1.9 : offres
## spéciales de l'admin du serveur (« Offres »), cartes du jour (or, prix qui monte à chaque
## exemplaire), coffres et or contre des gemmes. Tout est décidé par le serveur ; la page affiche
## sa vue du compte et envoie les achats.

const RARITY_FRAME := {"Common": 0, "Rare": 1, "Epic": 2, "Legendary": 2}
## Couleur du fond d'une offre (images du clip « button ») : 1 bleu, 2 vert, 3 or, 4 violet.
const BUTTON_FRAME := {"Common": 1, "Rare": 3, "Epic": 4, "Legendary": 2, "chest": 2, "gold": 3}

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _timer_labels: Array = []       # [nœud .sc, chemin, instant de fin]


func _ready() -> void:
	var top := ScreenLayout.top() + TopBar.HEIGHT
	_scroll.position = Vector2(0, top)
	_scroll.size = Vector2(size.x, size.y - top)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_bottom", 40)
	_scroll.add_child(margin)
	_list.add_theme_constant_override("separation", 18)
	margin.add_child(_list)
	Player.changed.connect(_rebuild)
	_rebuild()


func _exit_tree() -> void:
	Player.changed.disconnect(_rebuild)


func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	var now := Player.server_now()
	for t in _timer_labels:
		ScUi.set_text(t[0], t[1], _left(int(t[2]) - now))


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_timer_labels.clear()
	if not Player.online():
		var off := ScUi.label("Connecte-toi à un serveur pour acheter.", 24)
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(off)
		return
	var p := Player.profile
	var now := Player.server_now()
	var inner := size.x - 40

	# Offres spéciales (programmées par l'admin du serveur).
	var offers: Array = p.get("offers", [])
	if not offers.is_empty():
		var header := ScUi.fit_width(ScUi.clip("ui", "shop_header_offers_default"), inner * 1.25)
		ScUi.hide(ScUi.node_of(header), ["btn_info"])
		var box := Control.new()
		box.custom_minimum_size = Vector2(inner, header.size.y * 0.55)
		header.position = Vector2((inner - header.size.x) / 2, -header.size.y * 0.2)
		box.add_child(header)
		_list.add_child(box)
		for o in offers:
			_list.add_child(_offer(o, inner, now))

	# Cartes du jour.
	var divider := ScUi.fit_width(ScUi.clip("ui", "shop_card_divider"), inner)
	var dn := ScUi.node_of(divider)
	ScUi.hide(dn, ["info_btn"])
	ScUi.set_text(dn, "card_cycle_time/card_cycle_time", _left(int(p.get("shop_reset", 0))))
	_timer_labels.append([dn, "card_cycle_time/card_cycle_time", now + int(p.get("shop_reset", 0))])
	_list.add_child(divider)
	var row := _row()
	var cards: Array = p.get("shop", [])
	var w := (inner - 2 * 14) / 3.0
	for i in cards.size():
		row.add_child(_card_offer(cards[i], i, w))
	_list.add_child(row)

	# Coffres.
	var chests := ScUi.fit_width(ScUi.clip("ui", "shop_chest_divider"), inner)
	ScUi.hide(ScUi.node_of(chests), ["btn_info"])
	ScUi.set_text(ScUi.node_of(chests), "TID_CONSUMABLES_CHESTS_SHOP_INFO", "Les coffres achetés s'ouvrent tout de suite.")
	_list.add_child(chests)
	row = _row()
	for chest: Dictionary in p.get("shop_chests", []):
		row.add_child(_chest_offer(chest, w))
	_list.add_child(row)

	# Or contre des gemmes.
	var gold_div := ScUi.fit_width(ScUi.clip("ui", "shop_gem_divider"), inner)
	ScUi.set_text(ScUi.node_of(gold_div), "TID_SHOP_DIAMONDS", GameDB.text("TID_GOLD") if GameDB.text("TID_GOLD") != "TID_GOLD" else "Or")
	_list.add_child(gold_div)
	row = _row()
	for pack: Dictionary in p.get("shop_gold", []):
		row.add_child(_gold_offer(pack, w))
	_list.add_child(row)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	return row


static func _left(seconds: int) -> String:
	seconds = maxi(0, seconds)
	if seconds >= 86400:
		return "%dj %dh" % [seconds / 86400, seconds % 86400 / 3600]
	if seconds >= 3600:
		return "%dh %02dmin" % [seconds / 3600, seconds % 3600 / 60]
	return "%dmin %02ds" % [seconds / 60, seconds % 60]


## Offre de carte du jour : item_shop_cards_stack (illustration, rareté, prix en or, « Acheté ! »).
func _card_offer(offer: Dictionary, index: int, w: float) -> Control:
	var card := GameDB.card(offer.card)
	var node := ScUi.clip("ui", "item_shop_cards_stack") as ScMovieClip
	var sold_out: bool = int(offer.bought) >= int(offer.limit)
	ScUi.hide(node, ["progress", "card_info_bg"])
	node.set_sc_visible("TID_SHOP_OFFER_PURCHASED", sold_out)
	node.set_sc_visible("tick_icon", sold_out)
	node.set_sc_visible("cost", not sold_out)
	var legendary: bool = card.rarity == "Legendary"
	for f in ["stack/frame", "stack/frame_legendary", "stack/frame_champion"]:
		node.set_sc_visible(f, f == ("stack/frame_legendary" if legendary else "stack/frame"))
	var frame := node.get_sc("stack/frame") as ScMovieClip
	if frame:
		frame.goto_and_stop(RARITY_FRAME.get(card.rarity, 0))
	ScUi.hide(node, ["stack/rarity_glow"])
	var icon := CardView.icon_name(card)
	if icon != "":
		node.attach("stack/card_image", ScLibrary.get_library("ui_spells").create_export(icon), true,
				ScLibrary.create("ui", "card_mask_legendary" if legendary else "card_mask_normal"))
	node.set_text("cost", str(int(offer.price)))
	node.set_text("card_title", GameDB.text(card.name))
	node.set_text("card_rarity", GameDB.text("TID_RARITY_" + str(card.rarity).to_upper()))
	node.set_text("card_count", "×1")
	_button_frame(node, BUTTON_FRAME.get(card.rarity, 1))
	var box := ScUi.fit_width(node, w)
	if not sold_out:
		_currency(box, node, "gold")
	var left := ScUi.label("%d/%d" % [int(offer.bought), int(offer.limit)], 16, Color(1, 1, 1, 0.85))
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.position = Vector2(0, box.size.y * 0.66)
	left.size = Vector2(box.size.x, 22)
	box.add_child(left)
	var affordable := int(Player.profile.gold) >= int(offer.price)
	if not sold_out and not affordable:
		node.get_sc("cost").modulate = Color(1, 0.45, 0.45)
	ScUi.make_button(box, func() -> void:
		if sold_out:
			return
		_confirm("Acheter %s ?" % GameDB.text(card.name), int(offer.price), "gold", func() -> void:
			Net.send({"t": "buy_card", "i": index})
			Sounds.ui("buy_%s_card_01" % ("common" if card.rarity == "Common" else ("rare" if card.rarity == "Rare" else "legnedary")))))
	return box


## Coffre contre des gemmes : item_shop_chest et le coffre de ui_chest.
func _chest_offer(chest: Dictionary, w: float) -> Control:
	var node := ScUi.clip("ui", "item_shop_chest") as ScMovieClip
	ScUi.hide(node, ["TID_SHOP_OFFER_PURCHASED", "tick_icon", "new_tag", "arena_title"])
	var tid: String = GameDB.table("chests").get(chest.type, {}).get("TID", "")
	node.set_text("chest_title", GameDB.text(tid) if tid != "" else chest.type)
	node.set_text("cost", str(int(chest.price)))
	_button_frame(node, BUTTON_FRAME.chest)
	var box := ScUi.fit_width(node, w)
	var icon := ScUi.fit_width(ScUi.clip("ui_chest", "chest_item_" + HomeScreen.CHEST_ICONS.get(chest.type, "magical")), w * 0.78)
	icon.position = Vector2((w - icon.size.x) / 2, box.size.y * 0.52 - icon.size.y / 2)
	box.add_child(icon)
	_currency(box, node, "gems")
	ScUi.make_button(box, func() -> void:
		_confirm("Acheter ce coffre ?", int(chest.price), "gems", func() -> void:
			Net.send({"t": "buy_chest", "type": chest.type})))
	return box


## Or contre des gemmes : item_shop_resource.
func _gold_offer(pack: Dictionary, w: float) -> Control:
	var node := ScUi.clip("ui", "item_shop_resource") as ScMovieClip
	ScUi.hide(node, ["TID_SHOP_OFFER_PURCHASED", "tick_icon"])
	node.set_text("resource_count", str(int(pack.gold)))
	node.set_text("resource_title", "Or")
	node.set_text("cost", str(int(pack.price)))
	ScUi.hide(node, ["card_image"])
	_button_frame(node, BUTTON_FRAME.gold)
	var box := ScUi.fit_width(node, w)
	var art := ScUi.fit_width(ScUi.clip("ui_spells", "shop_gold0%d" % (clampi(int(pack.get("tier", 0)), 0, 2) + 1)), w * 0.74)
	art.position = Vector2((w - art.size.x) / 2, box.size.y * 0.44 - art.size.y / 2)
	box.add_child(art)
	_currency(box, node, "gems")
	ScUi.make_button(box, func() -> void:
		_confirm("Acheter %d pièces d'or ?" % int(pack.gold), int(pack.price), "gems", func() -> void:
			Net.send({"t": "buy_gold", "i": int(pack.get("i", 0))})
			Sounds.ui("get_gold_04")))
	return box


## Image du clip de fond d'une offre (couleur).
static func _button_frame(node: ScMovieClip, frame: int) -> void:
	var b := node.get_sc("button") as ScMovieClip
	if b:
		b.goto_and_stop(clampi(frame, 0, b.frames.size() - 1))


## Pièce ou gemme devant le prix (champ « cost »).
func _currency(box: Control, node: ScMovieClip, currency: String) -> void:
	var field := node.get_sc("cost") as ScTextField
	if field == null:
		return
	var icon := ScUi.fit_height(ScUi.clip("ui", "icon_gold" if currency == "gold" else "icon_gems"), box.size.y * 0.075)
	var k := node.scale.x
	var center := (node.position + (field.position + field.label.position + field.label.size / 2) * k)
	var text_w := field.text_width() * k
	icon.position = Vector2(center.x - text_w / 2 - icon.size.x - 4, center.y - icon.size.y / 2)
	box.add_child(icon)
	field.position.x += (icon.size.x / 2 + 2) / k


## Offre spéciale de l'admin : ruban titre, fin, contenu et prix (or, gemmes ou gratuit).
func _offer(o: Dictionary, inner: float, now: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var ribbon := ScUi.fit_width(ScUi.clip("ui", "shop_divider"), inner)
	ScUi.set_text(ScUi.node_of(ribbon), "txt", str(o.get("title", "Offre")))
	col.add_child(ribbon)
	if int(o.get("ends", 0)) > 0:
		var ends := ScUi.label("Fin dans : " + _left(int(o.ends) - now), 18, Color("cfe3ff"))
		ends.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(ends)
	var panel := ScUi.panel("ui_common", "bg_r25", Vector2(inner, 250), Color("1b8f8f"), 0.8)
	col.add_child(panel)
	var items: Array = o.get("items", [])
	var iw := minf(150.0, (inner - 40) / maxf(1, items.size()) - 16)
	var x := (inner - items.size() * (iw + 16) + 16) / 2
	for it: Dictionary in items:
		var cell := _offer_item(it, iw)
		cell.position = Vector2(x, 18)
		panel.add_child(cell)
		x += iw + 16
	var sold_out: bool = int(o.get("limit", 0)) > 0 and int(o.get("bought", 0)) >= int(o.limit)
	var price := int(o.get("price", 0))
	var currency: String = o.get("currency", "gems")
	var label := "Acheté !" if sold_out else ("Gratuit" if price == 0 else "%d %s" % [price, "or" if currency == "gold" else "gemmes"])
	var buy := ScUi.text_button("green" if not sold_out else "blue", label, Vector2(300, 74), func() -> void:
		if sold_out:
			return
		if price == 0:
			Net.send({"t": "buy_offer", "id": o.id})
		else:
			_confirm(str(o.get("title", "Offre")), price, currency, func() -> void: Net.send({"t": "buy_offer", "id": o.id})), 26)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(inner, 84)
	buy.position = Vector2((inner - 300) / 2, 4)
	holder.add_child(buy)
	col.add_child(holder)
	return col


## Élément d'une offre : carte (illustration), or, gemmes ou coffre, avec sa quantité.
func _offer_item(it: Dictionary, w: float) -> Control:
	var cell := Control.new()
	cell.size = Vector2(w, 210)
	var kind: String = it.get("kind", "gold")
	var visual: Control
	match kind:
		"card":
			visual = CardView.make(it.get("id", "Knight"), w, false)
			visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		"chest":
			visual = ScUi.fit_width(ScUi.clip("ui_chest", "chest_item_" + HomeScreen.CHEST_ICONS.get(it.get("id", "Gold"), "gold")), w)
		"gems":
			visual = ScUi.fit_height(ScUi.clip("ui", "icon_gems"), w * 0.8)
		_:
			visual = ScUi.fit_height(ScUi.clip("ui", "icon_gold"), w * 0.8)
	visual.position = Vector2((w - visual.size.x) / 2, 0)
	cell.add_child(visual)
	var n := ScUi.label(("×%d" if kind == "card" else "%d") % int(it.get("n", 1)), 26, Color("ffe14d") if kind == "gold" else Color.WHITE)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 176)
	n.size = Vector2(w, 34)
	cell.add_child(n)
	return cell


## Confirmation d'achat (popup_confirm de la 16.4 : texte et bouton au prix).
func _confirm(text: String, price: int, currency: String, action: Callable) -> void:
	var have := int(Player.profile.get(currency, 0))
	var popup := Popup16.make("Confirmer", size.x - 80)
	popup.content.add_child(Popup16.text(text, 26))
	if have < price:
		popup.content.add_child(Popup16.text("Pas assez %s !" % ("d'or" if currency == "gold" else "de gemmes"), 24, Color("d03030")))
		popup.content.add_child(Popup16.buttons([["OK", "blue", popup.close]]))
	else:
		popup.content.add_child(Popup16.buttons([["%d %s" % [price, "or" if currency == "gold" else "gemmes"], "green", func() -> void:
			popup.close()
			action.call()]]))
	ScUi.popup(self, popup)
