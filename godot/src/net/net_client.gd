extends Node
## Connexion au serveur de jeu (autoload Net) : ENet, messages Protocol, horloge du serveur.
##
## L'horloge est estimée par des pings non fiables (toutes les 0,5 s, et souvent au début) : on
## garde l'échantillon au plus court aller-retour, le moins faussé par la file d'attente du réseau.

signal connected
signal disconnected
signal message(msg: Dictionary)

const PING_EVERY_MS := 500

var host_name := "127.0.0.1"
var port := Protocol.PORT
var rtt_ms := 0
var _host: ENetConnection
var _peer: ENetPacketPeer
var _connected := false
var _offset := 0.0                   # heure serveur − heure locale (ms)
var _best_rtt := 1 << 30
var _samples := 0
var _last_ping := 0


func connect_to(host: String, server_port := Protocol.PORT) -> void:
	close()
	host_name = host
	port = server_port
	_host = ENetConnection.new()
	_host.create_host(1, Protocol.CHANNELS)
	_host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	_peer = _host.connect_to_host(host, port, Protocol.CHANNELS)
	_best_rtt = 1 << 30
	_samples = 0


func close() -> void:
	if _peer:
		_peer.peer_disconnect_now()
	if _host:
		_host.destroy()
	_peer = null
	_host = null
	if _connected:
		_connected = false
		disconnected.emit()


func is_online() -> bool:
	return _connected


func send(msg: Dictionary) -> void:
	if _connected:
		_peer.send(Protocol.CHANNEL_GAME, Protocol.encode(msg), ENetPacketPeer.FLAG_RELIABLE)


## Heure du serveur (ms, son horloge monotone), estimée.
func server_now() -> float:
	return Time.get_ticks_msec() + _offset


func _process(_delta: float) -> void:
	poll()


## Lit tout ce qui est arrivé (appelé chaque image, et par le combat avant de simuler).
func poll() -> void:
	if _host == null:
		return
	var event := _host.service(0)
	while event[0] != ENetConnection.EVENT_NONE:
		match event[0]:
			ENetConnection.EVENT_CONNECT:
				_connected = true
				_peer.set_timeout(0, 5000, 10000)
				connected.emit()
			ENetConnection.EVENT_DISCONNECT:
				_connected = false
				_host = null
				_peer = null
				disconnected.emit()
				return
			ENetConnection.EVENT_RECEIVE:
				var msg := Protocol.decode(event[1].get_packet())
				if msg.get("t", "") == "pong":
					_on_pong(msg)
				elif not msg.is_empty():
					message.emit(msg)
		if _host == null:
			return
		event = _host.service(0)
	var now := Time.get_ticks_msec()
	var every := 100 if _samples < 10 else PING_EVERY_MS
	if _connected and now - _last_ping >= every:
		_last_ping = now
		_peer.send(Protocol.CHANNEL_CLOCK, Protocol.encode({"t": "ping", "c": now}), ENetPacketPeer.FLAG_UNSEQUENCED)


func _on_pong(msg: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var rtt: int = now - int(msg.c)
	_samples += 1
	rtt_ms = rtt if _samples == 1 else int(lerpf(rtt_ms, rtt, 0.2))
	# Le meilleur aller-retour vieillit doucement, pour suivre un changement de réseau.
	_best_rtt += 1
	if rtt <= _best_rtt:
		_best_rtt = rtt
		_offset = float(msg.s) - (float(msg.c) + rtt / 2.0)
