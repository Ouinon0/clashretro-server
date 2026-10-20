class_name ServerAdmin
extends RefCounted
## Administration du serveur par le web (port HTTP, AdminHttp) : pages publiques (accueil,
## invitation, téléchargement de l'appli) et admin protégée par mot de passe (/admin) avec son API
## JSON : vue d'ensemble, joueurs, réglages, événements, offres de la boutique, invitations,
## actualités, clans, journal.
##
## Vie privée : l'admin ne voit ni adresse IP (le serveur n'en garde aucune), ni jeton, ni
## appareil ; seulement le pseudo, la progression et des dates (jour).
##
## Données (dossier du serveur) : admin.json (empreinte du mot de passe), events.json,
## offers.json, invites.json, news.json.

const WEB_DIR := "res://src/server/web/"
const SESSION_SECONDS := 12 * 3600
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const EVENT_MODES := {
	"": "Bonus seulement (pas de mode de jeu)",
	"double_elixir": "Double élixir",
	"triple_elixir": "Triple élixir",
	"tournament": "Niveaux de tournoi (9/7/4/1)",
	"sudden_death": "Mort subite (1 min, double élixir)",
	"draft_free": "Libre : combat normal hors trophées",
}
## Réglages modifiables, avec leur description (l'admin les affiche dans cet ordre).
const SETTING_INFO := [
	["server_name", "Nom du serveur (page d'accueil, appli)"],
	["access_mode", "Accès des nouveaux comptes : open (libre), code (code commun), invite (invitation)"],
	["access_code", "Code commun (mode « code »)"],
	["player_invites", "Invitations qu'un joueur peut créer (0 = aucune)"],
	["invite_days", "Validité d'une invitation (jours, 0 = sans fin)"],
	["start_gold", "Or d'un nouveau compte"],
	["start_gems", "Gemmes d'un nouveau compte"],
	["cards_percent", "Cartes des coffres (%)"],
	["gold_percent", "Or des combats et des coffres (%)"],
	["unlock_percent", "Durée de déverrouillage des coffres (%)"],
	["shop_percent", "Prix de la boutique (%)"],
	["gold_packs", "Or contre gemmes : [[or, gemmes], …]"],
	["request_seconds", "Délai entre deux demandes de cartes au clan (s)"],
	["bots_after", "IA si personne n'arrive après (s, -1 = jamais)"],
	["match_seconds", "Durée d'un combat (s)"],
]

var server: GameServer
var http := AdminHttp.new()
var events: Array = []
var invites: Array = []
var news: Array = []
var _auth := {}                      # salt, hash
var _sessions := {}                  # jeton → fin de validité
var _fails: Array = []               # instants des derniers échecs de connexion
var _started := 0
var _pages := {}


func _init(game_server: GameServer) -> void:
	server = game_server
	_started = int(Time.get_unix_time_from_system())
	http.handler = _handle
	events = server._load_json("events.json", [])
	invites = server._load_json("invites.json", [])
	news = server._load_json("news.json", [])
	server._progress.offers = server._load_json("offers.json", [])
	server._progress.events = events
	server._progress.news = news
	_auth = server._load_json("admin.json", {})
	var env := OS.get_environment("CLASH_ADMIN_PASSWORD")
	if env != "":
		_set_password(env)
	elif not _auth.has("hash"):
		var pw := _random_code(14)
		_set_password(pw)
		print("Mot de passe de l'admin web (à changer dans l'admin) : %s" % pw)
	for name in ["admin.html", "index.html"]:
		var f := FileAccess.open(WEB_DIR + name, FileAccess.READ)
		_pages[name] = f.get_as_text() if f else "<h1>%s introuvable</h1>" % name


func listen(port: int) -> void:
	var err := http.listen(port)
	if err == OK:
		print("Admin web : http://<adresse>:%d/admin" % port)
	else:
		push_error("Port HTTP %d indisponible (%s)" % [port, error_string(err)])


func poll() -> void:
	if http.is_listening():
		http.poll()


func save() -> void:
	server._save_json("events.json", events)
	server._save_json("invites.json", invites)
	server._save_json("news.json", news)
	server._save_json("offers.json", server._progress.offers)


# --- Mot de passe ---------------------------------------------------------------------------------

func _set_password(pw: String) -> void:
	var salt := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(12))
	_auth = {"salt": salt, "hash": _digest(salt, pw)}
	server._save_json("admin.json", _auth)


static func _digest(salt: String, pw: String) -> String:
	var h := (salt + ":" + pw).to_utf8_buffer()
	var s := salt.to_utf8_buffer()
	for i in 5000:                      # étirement simple (pas de bcrypt dans Godot)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(h)
		ctx.update(s)
		h = ctx.finish()
	return h.hex_encode()


func _check_password(pw: String) -> bool:
	return _auth.has("hash") and _digest(str(_auth.salt), pw) == str(_auth.hash)


static func _random_code(length: int) -> String:
	var bytes := Crypto.new().generate_random_bytes(length)
	var out := ""
	for b in bytes:
		out += CODE_ALPHABET[b % CODE_ALPHABET.length()]
	return out


func _authed(req: Dictionary) -> bool:
	var cookie: String = req.headers.get("cookie", "")
	for part in cookie.split(";"):
		var kv := part.strip_edges()
		if kv.begins_with("admin="):
			var token := kv.substr(6)
			var until := int(_sessions.get(token, 0))
			if until > _now():
				return true
			_sessions.erase(token)
	return false


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


# --- Routage ----------------------------------------------------------------------------------------

func _handle(req: Dictionary) -> Dictionary:
	var path: String = req.path
	var method: String = req.method
	if method == "GET" and (path == "/" or path.begins_with("/i/")):
		return _landing(path.substr(3).to_upper() if path.begins_with("/i/") else "")
	if method == "GET" and path == "/app.apk":
		var apk := server.data_dir.path_join("clash-modern.apk")
		if FileAccess.file_exists(apk):
			return {"file": apk, "type": "application/vnd.android.package-archive",
				"headers": {"Content-Disposition": "attachment; filename=clash-modern.apk"}}
		return _text(404, "Pas d'appli à télécharger sur ce serveur (déposer clash-modern.apk dans le dossier des données).")
	if method == "GET" and (path == "/admin" or path == "/admin/"):
		return {"status": 200, "type": "text/html; charset=utf-8", "body": _pages["admin.html"],
			"headers": {"Content-Security-Policy": "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:"}}
	if path == "/api/login" and method == "POST":
		return _login(req)
	if not path.begins_with("/api/"):
		return _text(404, "introuvable")
	if not _authed(req):
		return _json(401, {"error": "connexion requise"})
	if method == "POST" and not _same_origin(req):
		return _json(403, {"error": "origine refusée"})
	var parts := path.substr(5).split("/", false)
	var body: Dictionary = req.json if req.json is Dictionary else {}
	match parts[0] if parts.size() > 0 else "":
		"logout":
			_sessions.clear()
			return _json(200, {"ok": true}, {"Set-Cookie": "admin=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"})
		"password":
			if str(body.get("password", "")).length() < 8:
				return _json(400, {"error": "8 caractères minimum"})
			_set_password(str(body.password))
			return _json(200, {"ok": true})
		"overview":
			return _json(200, _overview())
		"players":
			if parts.size() >= 2 and method == "POST":
				return _player_action(int(parts[1]), body)
			return _json(200, {"players": _players()})
		"settings":
			if method == "POST":
				return _set_settings(body)
			return _json(200, _settings())
		"events":
			return _crud(events, parts, method, body, "events", _clean_event)
		"offers":
			return _crud(server._progress.offers, parts, method, body, "offers", _clean_offer)
		"news":
			return _crud(news, parts, method, body, "news", _clean_news)
		"invites":
			return _invites_api(parts, method, body)
		"clans":
			return _clans_api(parts, method, body)
		"cards":
			return _json(200, {"cards": GameDB.cards.map(func(c: Dictionary) -> Dictionary:
				return {"id": c.id, "name": GameDB.text(c.name), "rarity": c.rarity}),
				"chests": ["Silver", "Gold", "Magic", "Giant", "Super", "Epic", "Legendary"], "modes": EVENT_MODES})
		"log":
			return _json(200, {"log": server._log_history.slice(-300)})
		"announce":
			var text := str(body.get("text", "")).strip_edges().left(300)
			if text == "":
				return _json(400, {"error": "texte vide"})
			server.broadcast({"t": "notice", "text": text})
			return _json(200, {"ok": true, "sent": server.online_count()})
	return _json(404, {"error": "inconnu"})


## Protection CSRF : un POST doit venir de la même origine (en-têtes Origin / Referer).
func _same_origin(req: Dictionary) -> bool:
	var host: String = req.headers.get("host", "")
	for h in ["origin", "referer"]:
		var v: String = req.headers.get(h, "")
		if v != "":
			return v.get_slice("://", 1).get_slice("/", 0) == host
	return req.headers.get("content-type", "").begins_with("application/json")


func _login(req: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	_fails = _fails.filter(func(t: int) -> bool: return now - t < 60000)
	if _fails.size() >= 6:
		return _json(429, {"error": "trop d'essais, attends une minute"})
	var body: Dictionary = req.json if req.json is Dictionary else {}
	if not _check_password(str(body.get("password", ""))):
		_fails.append(now)
		return _json(401, {"error": "mot de passe incorrect"})
	var token := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(24)).replace("/", "_").replace("+", "-")
	_sessions[token] = _now() + SESSION_SECONDS
	return _json(200, {"ok": true}, {"Set-Cookie": "admin=%s; Path=/; Max-Age=%d; HttpOnly; SameSite=Strict" % [token, SESSION_SECONDS]})


static func _json(status: int, data: Variant, headers := {}) -> Dictionary:
	return {"status": status, "type": "application/json; charset=utf-8", "body": JSON.stringify(data), "headers": headers}


static func _text(status: int, text: String) -> Dictionary:
	return {"status": status, "type": "text/plain; charset=utf-8", "body": text}


# --- Pages publiques --------------------------------------------------------------------------------

func _landing(code: String) -> Dictionary:
	var invite := {}
	for i in invites:
		if str(i.code) == code:
			invite = i
	var valid := not invite.is_empty() and _invite_usable(invite)
	var s: Dictionary = server._progress.settings
	var html: String = _pages["index.html"]
	html = html.replace("{{NAME}}", _esc(str(s.get("server_name", "Clash Royale : Modern Classic"))))
	html = html.replace("{{PORT}}", str(server.port))
	html = html.replace("{{CODE}}", _esc(code) if valid else "")
	html = html.replace("{{HAS_CODE}}", "1" if valid else "0")
	html = html.replace("{{BAD_CODE}}", "1" if code != "" and not valid else "0")
	html = html.replace("{{HAS_APK}}", "1" if FileAccess.file_exists(server.data_dir.path_join("clash-modern.apk")) else "0")
	html = html.replace("{{ACCESS}}", str(s.get("access_mode", "invite")))
	return {"status": 200, "type": "text/html; charset=utf-8", "body": html}


static func _esc(s: String) -> String:
	return s.xml_escape()


# --- Vue d'ensemble, joueurs ------------------------------------------------------------------------

func _overview() -> Dictionary:
	var queues := {}
	for k in server._queues:
		queues[k] = server._queues[k].size()
	return {"uptime": _now() - _started, "online": server.online_count(), "accounts": server._accounts.size(),
		"matches": server._matches.filter(func(m: Dictionary) -> bool: return not m.ended).map(func(m: Dictionary) -> Dictionary:
			return {"id": m.id, "mode": m.mode, "players": m.players.map(func(p: Dictionary) -> String: return p.name),
				"seconds": int(m.sim.tick / 20)}),
		"queues": queues, "clans": server._clans.clans.size(), "port": server.port,
		"events_active": _active(events).size(), "version": Protocol.VERSION}


func _players() -> Array:
	var online := {}
	for s in server._sessions.values():
		if not s.account.is_empty():
			online[int(s.account.id)] = true
	var by_id := server._accounts_by_id()
	var out := []
	for a in server._accounts.values():
		var clan: Dictionary = server._clans.clans.get(a.get("clan", ""), {})
		out.append({"id": a.id, "name": a.name, "level": a.level, "trophies": a.trophies, "best": a.best,
			"gold": a.gold, "gems": a.gems, "cards": a.cards.size(), "wins": a.wins, "losses": a.losses,
			"clan": clan.get("name", ""), "created": _day(int(a.get("created", 0))), "seen": _day(int(a.get("seen", 0))),
			"invited_by": by_id.get(int(a.get("invited_by", 0)), {}).get("name", "admin" if int(a.get("invited_by", -1)) == 0 else ""),
			"banned": a.get("banned", false), "online": online.has(int(a.id)), "deck": a.deck})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.trophies > y.trophies)
	return out


static func _day(t: int) -> String:
	return Time.get_date_string_from_unix_time(t) if t > 0 else ""


func _player_action(id: int, body: Dictionary) -> Dictionary:
	var acc: Dictionary = server._accounts_by_id().get(id, {})
	if acc.is_empty():
		return _json(404, {"error": "joueur inconnu"})
	var p := server._progress
	match str(body.get("action", "")):
		"grant":
			acc.gold += clampi(int(body.get("gold", 0)), -1000000, 1000000)
			acc.gems += clampi(int(body.get("gems", 0)), -100000, 100000)
			acc.gold = maxi(0, acc.gold)
			acc.gems = maxi(0, acc.gems)
			var card := GameDB.card(str(body.get("card", "")))
			if not card.is_empty():
				p.add_cards(acc, card.id, clampi(int(body.get("count", 1)), 1, 10000))
			var chest := str(body.get("chest", ""))
			if chest != "" and acc.chests.size() < Progression.SLOTS:
				acc.chests.append({"type": chest, "state": "locked", "end": 0, "arena": int(p.arena(acc).number)})
		"set":
			if body.has("trophies"):
				acc.trophies = clampi(int(body.trophies), 0, 10000)
				acc.best = maxi(acc.best, acc.trophies)
			if body.has("name") and str(body.name).strip_edges() != "":
				acc.name = str(body.name).strip_edges().left(16)
			if body.has("level"):
				acc.level = clampi(int(body.level), 1, 13)
		"max_cards":
			for c in GameDB.cards:
				var r := GameDB.rarity(c.rarity)
				acc.cards[c.id] = {"lvl": int(r.levels) - 1, "n": 0}
		"ban":
			acc.banned = true
			server.kick(id, "Compte suspendu par l'admin.")
		"unban":
			acc.banned = false
		"reset":
			var keep := {"id": acc.id, "name": acc.name, "created": acc.get("created", 0), "invited_by": acc.get("invited_by", 0)}
			var fresh := p.new_account(int(acc.id), acc.name)
			acc.clear()
			acc.merge(fresh)
			acc.merge(keep, true)
			server.kick(id, "Compte réinitialisé par l'admin.")
		"delete":
			server.kick(id, "Compte supprimé par l'admin.")
			server.delete_account(id)
			return _json(200, {"ok": true})
		_:
			return _json(400, {"error": "action inconnue"})
	server.account_changed(acc)
	return _json(200, {"ok": true})


# --- Réglages --------------------------------------------------------------------------------------

func _settings() -> Dictionary:
	var s: Dictionary = server._progress.settings
	var out := []
	for info in SETTING_INFO:
		out.append({"key": info[0], "label": info[1], "value": s.get(info[0])})
	return {"settings": out}


func _set_settings(body: Dictionary) -> Dictionary:
	var s: Dictionary = server._progress.settings
	for info in SETTING_INFO:
		var key: String = info[0]
		if not body.has(key):
			continue
		var v = body[key]
		var old = s.get(key)
		if old is int or old is float:
			v = int(v)
		elif old is Array:
			v = JSON.parse_string(v) if v is String else v
			if not v is Array:
				return _json(400, {"error": "%s : liste attendue" % key})
		elif old is String:
			v = str(v).strip_edges().left(80)
		if key == "access_mode" and not v in ["open", "code", "invite"]:
			return _json(400, {"error": "access_mode : open, code ou invite"})
		s[key] = v
	server._save_json("settings.json", s)
	server.apply_settings()
	return _json(200, _settings())


# --- Événements, offres, actualités (listes génériques) -------------------------------------------------

func _crud(list: Array, parts: Array, method: String, body: Dictionary, file: String, clean: Callable) -> Dictionary:
	if method == "POST":
		if parts.size() >= 3 and parts[2] == "delete":
			for i in list.size():
				if str(list[i].get("id", "")) == parts[1]:
					list.remove_at(i)
					break
		else:
			var item: Dictionary = clean.call(body)
			if item.has("error"):
				return _json(400, item)
			var replaced := false
			for i in list.size():
				if str(list[i].get("id", "")) == str(item.id):
					list[i] = item
					replaced = true
			if not replaced:
				list.append(item)
		server._save_json(file + ".json", list)
		server.refresh_all()
	return _json(200, {file: list, "now": _now()})


func _clean_event(b: Dictionary) -> Dictionary:
	var title := str(b.get("title", "")).strip_edges().left(48)
	if title == "":
		return {"error": "titre requis"}
	var mode := str(b.get("mode", ""))
	if not EVENT_MODES.has(mode):
		mode = ""
	return {"id": str(b.get("id", "")) if str(b.get("id", "")) != "" else _random_code(8), "title": title,
		"message": str(b.get("message", "")).left(240), "color": str(b.get("color", "blue")).left(12),
		"starts": int(b.get("starts", _now())), "ends": int(b.get("ends", _now() + 86400)),
		"gold_percent": clampi(int(b.get("gold_percent", 100)), 0, 10000),
		"cards_percent": clampi(int(b.get("cards_percent", 100)), 0, 10000),
		"mode": mode, "team": "2v2" if str(b.get("team", "1v1")) == "2v2" else "1v1",
		"trophies": bool(b.get("trophies", false)), "chests": bool(b.get("chests", false))}


func _clean_offer(b: Dictionary) -> Dictionary:
	var title := str(b.get("title", "")).strip_edges().left(48)
	if title == "":
		return {"error": "titre requis"}
	var items := []
	for it in b.get("items", []):
		if it is Dictionary and str(it.get("kind", "")) in ["gold", "gems", "card", "chest"]:
			items.append({"kind": str(it.kind), "id": str(it.get("id", "")), "n": clampi(int(it.get("n", 1)), 1, 1000000)})
	if items.is_empty():
		return {"error": "au moins un élément"}
	return {"id": str(b.get("id", "")) if str(b.get("id", "")) != "" else _random_code(8), "title": title,
		"items": items, "price": clampi(int(b.get("price", 0)), 0, 1000000),
		"currency": "gold" if str(b.get("currency", "gems")) == "gold" else "gems",
		"starts": int(b.get("starts", _now())), "ends": int(b.get("ends", 0)), "limit": clampi(int(b.get("limit", 1)), 0, 1000)}


func _clean_news(b: Dictionary) -> Dictionary:
	var title := str(b.get("title", "")).strip_edges().left(64)
	if title == "":
		return {"error": "titre requis"}
	return {"id": str(b.get("id", "")) if str(b.get("id", "")) != "" else _random_code(8), "title": title,
		"text": str(b.get("text", "")).left(1000), "at": int(b.get("at", _now()))}


static func _active(list: Array) -> Array:
	var now := _now()
	return list.filter(func(e: Dictionary) -> bool:
		return int(e.get("starts", 0)) <= now and (int(e.get("ends", 0)) == 0 or now < int(e.ends)))


# --- Invitations -------------------------------------------------------------------------------------

func _invite_usable(i: Dictionary) -> bool:
	return not i.get("revoked", false) and int(i.get("uses", 0)) < int(i.get("max_uses", 1)) \
		and (int(i.get("expires", 0)) == 0 or _now() < int(i.expires))


## Crée une invitation (`by` : id du joueur, 0 = admin).
func create_invite(by: int, note := "", max_uses := 1) -> Dictionary:
	var days := int(server._progress.settings.get("invite_days", 14))
	var inv := {"code": _random_code(8), "by": by, "note": note.left(60), "max_uses": clampi(max_uses, 1, 1000),
		"uses": 0, "used_by": [], "created": _now(), "expires": _now() + days * 86400 if days > 0 else 0, "revoked": false}
	invites.append(inv)
	server._save_json("invites.json", invites)
	return inv


## Utilise une invitation pour un nouveau compte : renvoie l'id de l'auteur (0 = admin, -1 = refusée).
func consume_invite(code: String, account_id: int) -> int:
	code = code.strip_edges().to_upper()
	for i in invites:
		if str(i.code) == code and _invite_usable(i):
			i.uses = int(i.uses) + 1
			i.used_by.append(account_id)
			server._save_json("invites.json", invites)
			return int(i.by)
	return -1


func invite_valid(code: String) -> bool:
	code = code.strip_edges().to_upper()
	for i in invites:
		if str(i.code) == code and _invite_usable(i):
			return true
	return false


## Invitations d'un joueur (vue de l'appli).
func player_invites(id: int) -> Array:
	var by_id := server._accounts_by_id()
	return invites.filter(func(i: Dictionary) -> bool: return int(i.by) == id).map(func(i: Dictionary) -> Dictionary:
		return {"code": i.code, "usable": _invite_usable(i), "used_by": i.used_by.map(func(u) -> String:
			return by_id.get(int(u), {}).get("name", "?")), "expires": i.expires})


func _invites_api(parts: Array, method: String, body: Dictionary) -> Dictionary:
	if method == "POST":
		if parts.size() >= 3 and parts[2] == "revoke":
			for i in invites:
				if str(i.code) == parts[1]:
					i.revoked = true
		else:
			create_invite(0, str(body.get("note", "")), int(body.get("max_uses", 1)))
		server._save_json("invites.json", invites)
	var by_id := server._accounts_by_id()
	var out := invites.map(func(i: Dictionary) -> Dictionary:
		var v := i.duplicate()
		v.by_name = "admin" if int(i.by) == 0 else by_id.get(int(i.by), {}).get("name", "?")
		v.used_names = i.used_by.map(func(u) -> String: return by_id.get(int(u), {}).get("name", "?"))
		v.usable = _invite_usable(i)
		return v)
	out.reverse()
	return _json(200, {"invites": out, "access_mode": server._progress.settings.get("access_mode", "invite")})


# --- Clans ---------------------------------------------------------------------------------------------

func _clans_api(parts: Array, method: String, body: Dictionary) -> Dictionary:
	var clans: Dictionary = server._clans.clans
	if method == "POST" and parts.size() >= 3:
		var c: Dictionary = clans.get(parts[1], {})
		if not c.is_empty():
			match parts[2]:
				"delete":
					var by_id := server._accounts_by_id()
					for mid in c.members:
						var a: Dictionary = by_id.get(int(mid), {})
						if not a.is_empty():
							a.clan = ""
					clans.erase(parts[1])
				"rename":
					var name := str(body.get("name", "")).strip_edges().left(20)
					if name.length() >= 3:
						c.name = name
			server._dirty = true
			server.refresh_all()
	var by_id := server._accounts_by_id()
	var out := []
	for id in clans:
		var c: Dictionary = clans[id]
		out.append({"id": id, "name": c.name, "members": c.members.map(func(m) -> String: return by_id.get(int(m), {}).get("name", "?")),
			"leader": by_id.get(int(c.leader), {}).get("name", "?")})
	return _json(200, {"clans": out})
