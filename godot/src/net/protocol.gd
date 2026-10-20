class_name Protocol
extends RefCounted
## Protocole du jeu en ligne : ENet (UDP), messages = dictionnaires encodés par var_to_bytes
## (jamais d'objets à la lecture). Canal 0 fiable et ordonné (tout le jeu), canal 1 non fiable
## (horloge : ping / pong).
##
## Combats : chaque client pose ses cartes tout de suite (tick suivant) et les envoie ; le serveur
## les relaie dès réception, sans regroupement. Il simule le combat MAX_LATE ticks derrière l'heure
## réelle : une pose reçue avec jusqu'à MAX_LATE ticks de retard garde son tick (les autres clients
## reviennent en arrière et recalculent), au-delà elle est décalée au tick du serveur.

const PORT := 19340
const VERSION := 1
const CHANNEL_GAME := 0
const CHANNEL_CLOCK := 1
const CHANNELS := 2
const MAX_LATE := 6                 # ticks (300 ms) de retard acceptés sans décaler une pose
const MAX_AHEAD := 20               # une pose ne peut pas viser plus d'1 s dans le futur
const INPUT_DELAY := 1              # tick visé par une pose locale : le suivant
const START_DELAY_MS := 3500        # entre l'appariement et le premier tick (intro « VS »)
const SUM_EVERY := 20               # empreinte de la simulation envoyée toutes les secondes


static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


static func decode(data: PackedByteArray) -> Dictionary:
	var v = bytes_to_var(data)
	return v if v is Dictionary else {}
