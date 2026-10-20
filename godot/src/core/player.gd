extends Node
## Compte du joueur tel que le serveur l'envoie (message « profile ») : trophées, or, gemmes,
## niveau du roi, cartes {id: {lvl, n}}, deck, coffres. Hors ligne : profil local de départ.

signal changed
signal chest_opened(content: Dictionary)
signal celebrate(kind: String, value: Variant)    # « level » (niveau du roi), « arena » (nouvelle arène)
signal clan_changed
signal clans_listed(list: Array)
signal notice(text: String)          # annonce de l'admin, refus du serveur (compte suspendu…)
signal invites_listed(info: Dictionary)
signal players_listed(list: Array)

var profile := {}
var clan := {}                      # vue du clan (membres, discussion) ; {} sans clan
var celebrations: Array = []        # [genre, valeur] pas encore montrées (le menu les vide)
var _received_at := 0               # heure locale (s) de la dernière vue, pour les minuteurs


func _ready() -> void:
	Net.message.connect(_on_message)


func _on_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"profile":
			var before := profile
			profile = msg.profile
			if not before.is_empty():
				if int(profile.level) > int(before.level):
					celebrations.append(["level", int(profile.level)])
				if profile.get("arena", "") != before.get("arena", "") and int(profile.trophies) > int(before.trophies):
					celebrations.append(["arena", profile.arena])
				if not celebrations.is_empty():
					celebrate.emit(celebrations[-1][0], celebrations[-1][1])
			_received_at = int(Time.get_unix_time_from_system())
			changed.emit()
		"chest":
			chest_opened.emit(msg.content)
		"clan":
			clan = msg.clan
			clan_changed.emit()
		"clans":
			clans_listed.emit(msg.list)
		"notice":
			notice.emit(str(msg.get("text", "")))
		"invites":
			invites_listed.emit(msg)
		"players":
			players_listed.emit(msg.list)
		"error":
			match str(msg.get("code", "")):
				"banned":
					notice.emit("Ce compte est suspendu par l'admin du serveur.")
				"kicked":
					notice.emit(str(msg.get("text", "Déconnecté par l'admin.")))


## Heure du serveur (s), d'après la dernière vue du compte.
func server_now() -> int:
	return int(profile.get("now", 0)) + int(Time.get_unix_time_from_system()) - _received_at


func online() -> bool:
	return not profile.is_empty()


## Deck du joueur (celui du serveur s'il est connu, sinon celui de l'appareil).
func deck() -> Array:
	return profile.deck if online() else Profile.deck()


## Niveau d'une carte (relatif à sa rareté ; niveau 9 affiché hors ligne, pour l'entraînement).
const TRAINING_LEVEL := 9


func card_level(card: String) -> int:
	if not online():
		return GameDB.relative_level(GameDB.card(card).rarity, TRAINING_LEVEL)
	return int(profile.cards.get(card, {"lvl": 0}).lvl)


func has_card(card: String) -> bool:
	return not online() or profile.cards.has(card)


## Secondes restantes d'un coffre en cours de déverrouillage (heure du serveur estimée).
func chest_seconds_left(chest: Dictionary) -> int:
	if chest.state == "ready":
		return 0
	if chest.state == "locked":
		return int(chest.seconds)
	var server_now := int(profile.now) + int(Time.get_unix_time_from_system()) - _received_at
	return maxi(0, int(chest.end) - server_now)


## Amélioration suivante : {cards, gold, have} ({} au niveau max ou hors ligne).
func upgrade_info(card: String) -> Dictionary:
	if not online() or not profile.cards.has(card):
		return {}
	var c: Dictionary = profile.cards[card]
	var r := GameDB.rarity(GameDB.card(card).rarity)
	if int(c.lvl) >= int(r.levels) - 1:
		return {}
	return {"cards": int(r.upgrade_cards[int(c.lvl)]), "gold": int(r.upgrade_gold[int(c.lvl)]), "have": int(c.n)}


func set_deck(cards: Array) -> void:
	if online():
		Net.send({"t": "deck", "cards": cards})
	Profile.set_value("deck", cards)
