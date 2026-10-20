class_name AdminHttp
extends RefCounted
## Petit serveur HTTP/1.1 (TCP, sans dépendance) pour l'admin web du serveur de jeu. Il est servi
## depuis le fil réseau du serveur (poll() à chaque tour de boucle) : les requêtes lisent et
## modifient les comptes sans verrou. Une requête par connexion (Connection: close).
##
## `handler.call(request)` reçoit {method, path, query, headers, body, json} et renvoie
## {status, type, body (String ou PackedByteArray), headers?} ; ou {file: chemin, type} pour un gros
## fichier envoyé par morceaux (l'APK à télécharger).

const MAX_BODY := 1 << 20
const MAX_CLIENTS := 32
const TIMEOUT_MS := 10000

var handler: Callable
var _server := TCPServer.new()
var _clients: Array = []            # {peer, buf, since, file?}


func listen(port: int, bind := "*") -> Error:
	return _server.listen(port, bind)


func is_listening() -> bool:
	return _server.is_listening()


func poll() -> void:
	while _server.is_connection_available() and _clients.size() < MAX_CLIENTS:
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - c.since > TIMEOUT_MS:
			peer.disconnect_from_host()
			_clients.erase(c)
			continue
		if c.has("out"):
			_flush(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_partial_data(mini(n, 65536))
			if got[0] == OK:
				c.buf.append_array(got[1])
		var request := _parse(c.buf)
		if request.is_empty():
			if c.buf.size() > MAX_BODY + 16384:
				_reply(c, {"status": 413, "type": "text/plain", "body": "trop gros"})
			continue
		var response: Dictionary
		if handler.is_valid():
			response = handler.call(request)
		else:
			response = {"status": 500, "type": "text/plain", "body": "pas de gestionnaire"}
		_reply(c, response)


## Requête complète (en-têtes + corps selon Content-Length), sinon {}.
func _parse(buf: PackedByteArray) -> Dictionary:
	var text_end := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			text_end = i
			break
	if text_end < 0:
		return {}
	var head := buf.slice(0, text_end).get_string_from_utf8()
	var lines := head.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "/", "query": {}, "headers": {}, "body": "", "json": null}
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at > 0:
			headers[lines[i].left(at).strip_edges().to_lower()] = lines[i].substr(at + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if length > MAX_BODY:
		length = MAX_BODY
	if buf.size() < text_end + 4 + length:
		return {}
	var body := buf.slice(text_end + 4, text_end + 4 + length).get_string_from_utf8()
	var target := first[1]
	var path := target.get_slice("?", 0).uri_decode()
	var query := {}
	if "?" in target:
		for pair in target.get_slice("?", 1).split("&"):
			if pair != "":
				query[pair.get_slice("=", 0).uri_decode()] = pair.get_slice("=", 1).replace("+", " ").uri_decode()
	var json = null
	if body != "" and headers.get("content-type", "").begins_with("application/json"):
		json = JSON.parse_string(body)
	return {"method": first[0], "path": path, "query": query, "headers": headers, "body": body, "json": json}


func _reply(c: Dictionary, r: Dictionary) -> void:
	var body = r.get("body", "")
	var bytes: PackedByteArray = body if body is PackedByteArray else str(body).to_utf8_buffer()
	var status := int(r.get("status", 200))
	var length := bytes.size()
	if r.has("file"):
		var f := FileAccess.open(str(r.file), FileAccess.READ)
		if f == null:
			_reply(c, {"status": 404, "body": "introuvable"})
			return
		c.file = f
		length = f.get_length()
		bytes = PackedByteArray()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n" % [
		status, _reason(status), r.get("type", "text/plain; charset=utf-8"), length]
	head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\n"
	for k in r.get("headers", {}):
		head += "%s: %s\r\n" % [k, r.headers[k]]
	var out := (head + "\r\n").to_utf8_buffer()
	out.append_array(bytes)
	c.out = out
	c.since = Time.get_ticks_msec()
	_flush(c)


func _flush(c: Dictionary) -> void:
	var peer: StreamPeerTCP = c.peer
	var out: PackedByteArray = c.out
	if out.is_empty() and c.has("file"):
		var f: FileAccess = c.file
		if f.get_position() < f.get_length():
			out = f.get_buffer(262144)
		else:
			c.erase("file")
	if out.is_empty():
		peer.disconnect_from_host()
		_clients.erase(c)
		return
	var sent := peer.put_partial_data(out)
	if sent[0] != OK:
		peer.disconnect_from_host()
		_clients.erase(c)
		return
	if int(sent[1]) > 0:
		c.since = Time.get_ticks_msec()
	c.out = out.slice(int(sent[1]))


static func _reason(status: int) -> String:
	return {200: "OK", 204: "No Content", 302: "Found", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
		404: "Not Found", 413: "Payload Too Large", 429: "Too Many Requests", 500: "Internal Server Error"}.get(status, "OK")
