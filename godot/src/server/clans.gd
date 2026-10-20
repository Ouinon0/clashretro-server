class_name Clans
extends RefCounted
## Clans (serveur) : création, entrée libre, départ, discussion, demandes et dons de cartes comme
## la 1.9 (communes jusqu'à 40, rares jusqu'à 4 ; le donateur gagne or et expérience).
## Données : clans.json du serveur ; le compte garde l'identifiant de son clan (`clan`).

const MAX_MEMBERS := 50
const CHAT_KEEP := 80
const REQUEST_LIMIT := {"Common": 40, "Rare": 4}
const DONATE_GOLD := {"Common": 5, "Rare": 50}
const DONATE_EXP := {"Common": 1, "Rare": 10}

var clans := {}                     # id (texte) → clan
var _next_id := 1


func load_data(data: Dictionary) -> void:
	clans = data.get("clans", {})
	_next_id = int(data.get("next", 1))


func save_data() -> Dictionary:
	return {"clans": clans, "next": _next_id}


## Liste des clans (pour en rejoindre un), les plus peuplés d'abord.
func listing() -> Array:
	var out := []
	for id in clans:
		var c: Dictionary = clans[id]
		out.append({"id": id, "name": c.name, "members": c.members.size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.members > b.members)
	return out


func create(acc: Dictionary, name: String) -> String:
	name = name.strip_edges().left(20)
	if name.length() < 3 or acc.get("clan", "") != "":
		return ""
	var id := str(_next_id)
	_next_id += 1
	clans[id] = {"name": name, "leader": acc.id, "members": [], "chat": [], "next_msg": 1}
	join(acc, id)
	return id


func join(acc: Dictionary, id: String) -> bool:
	var c: Dictionary = clans.get(id, {})
	if c.is_empty() or acc.get("clan", "") != "" or c.members.size() >= MAX_MEMBERS:
		return false
	c.members.append(int(acc.id))
	acc.clan = id
	_post(c, {"k": "info", "text": "%s a rejoint le clan" % acc.name})
	return true


func leave(acc: Dictionary) -> String:
	var id: String = acc.get("clan", "")
	var c: Dictionary = clans.get(id, {})
	acc.clan = ""
	if c.is_empty():
		return ""
	c.members.erase(int(acc.id))
	if c.members.is_empty():
		clans.erase(id)
	else:
		if int(c.leader) == int(acc.id):
			c.leader = c.members[0]
		_post(c, {"k": "info", "text": "%s a quitté le clan" % acc.name})
	return id


func say(acc: Dictionary, text: String) -> bool:
	var c: Dictionary = clans.get(acc.get("clan", ""), {})
	text = text.strip_edges().left(200)
	if c.is_empty() or text == "":
		return false
	_post(c, {"k": "msg", "from": int(acc.id), "name": acc.name, "text": text})
	return true


## Demande de cartes (une à la fois, toutes les `cooldown` secondes).
func request(acc: Dictionary, card: String, now: int, cooldown: int) -> bool:
	var c: Dictionary = clans.get(acc.get("clan", ""), {})
	var rarity: String = GameDB.card(card).get("rarity", "")
	if c.is_empty() or not REQUEST_LIMIT.has(rarity) or not acc.cards.has(card):
		return false
	if now < int(acc.get("request_next", 0)):
		return false
	acc.request_next = now + cooldown
	for m in c.chat:                    # l'ancienne demande du joueur s'arrête
		if m.k == "req" and int(m.from) == int(acc.id):
			m.closed = true
	_post(c, {"k": "req", "from": int(acc.id), "name": acc.name, "card": card, "got": 0,
		"need": REQUEST_LIMIT[rarity], "time": now})
	return true


## Don d'une carte à une demande : renvoie l'identifiant du receveur (0 si refusé).
func donate(acc: Dictionary, msg_id: int, accounts_by_id: Dictionary, progress: Progression) -> int:
	var c: Dictionary = clans.get(acc.get("clan", ""), {})
	if c.is_empty():
		return 0
	for m in c.chat:
		if m.k != "req" or int(m.id) != msg_id or m.get("closed", false) or int(m.from) == int(acc.id):
			continue
		var card: String = m.card
		var have: Dictionary = acc.cards.get(card, {})
		if have.is_empty() or int(have.n) < 1 or int(m.got) >= int(m.need):
			return 0
		var receiver: Dictionary = accounts_by_id.get(int(m.from), {})
		if receiver.is_empty():
			return 0
		var rarity: String = GameDB.card(card).rarity
		have.n = int(have.n) - 1
		progress.add_cards(receiver, card, 1)
		acc.gold += DONATE_GOLD[rarity]
		progress.add_exp(acc, DONATE_EXP[rarity])
		m.got = int(m.got) + 1
		if int(m.got) >= int(m.need):
			m.closed = true
		return int(m.from)
	return 0


## Vue d'un clan pour ses membres (noms et trophées des membres, 50 derniers messages).
func view(id: String, accounts_by_id: Dictionary) -> Dictionary:
	var c: Dictionary = clans.get(id, {})
	if c.is_empty():
		return {}
	var members := []
	for mid in c.members:
		var a: Dictionary = accounts_by_id.get(int(mid), {})
		members.append({"id": mid, "name": a.get("name", "?"), "trophies": a.get("trophies", 0),
			"leader": int(mid) == int(c.leader)})
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.trophies > b.trophies)
	return {"id": id, "name": c.name, "members": members, "chat": c.chat.slice(-50)}


func _post(c: Dictionary, m: Dictionary) -> void:
	m.id = int(c.next_msg)
	c.next_msg = int(c.next_msg) + 1
	m.at = int(Time.get_unix_time_from_system())
	c.chat.append(m)
	if c.chat.size() > CHAT_KEEP:
		c.chat = c.chat.slice(-CHAT_KEEP)
