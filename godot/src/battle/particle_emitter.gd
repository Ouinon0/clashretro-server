class_name ParticleEmitter
extends Node2D
## Émetteur de particules de la 16.4 (legacy_vfx/emitters.json, via GameDB), simplifié :
## l'émetteur vit MinLife–MaxLife ms et lâche une particule toutes les ParticleMin/MaxInterval ms
## (au plus ParticleCount). Chaque particule (ParticleResource / ParticleExportName) part dans une
## direction au sol (angle, vitesse), avec une hauteur (StartZ, VelocityZ, Gravity), grossit de
## StartScale à EndScale, apparaît et s'efface (FadeIn/FadeOut), et peut tourner sur elle-même.
## Purement visuel (hasard non déterministe) : n'influe jamais sur la simulation.

const MAX_LIVE_PARTICLES := 160          # plafond global, pour les téléphones modestes
const SPEED_SCALE := 2.0                 # distances et vitesses au sol du CSV → pixels de la vue
const Z_SCALE := 0.6                     # hauteur, vitesse verticale et gravité

static var _live := 0

var row: Dictionary
var delay := 0.0                          # attente avant la première particule (Time de l'effet)
var _left := 0.0                          # durée de vie restante de l'émetteur (s)
var _next := 0.0
var _emitted := 0
var _particles: Array = []
var looping := false                      # émetteurs d'effets en boucle : vivent jusqu'au retrait
var trail := false                        # traînée : les particules restent où elles sont nées
var _resource := ""                       # particule imposée par l'effet (sinon celle du CSV)
var _export := ""


func override_particle(resource: String, export_name: String) -> void:
	_resource = resource
	_export = export_name


static func create(emitter_name: String) -> ParticleEmitter:
	var r := GameDB.emitter(emitter_name)
	if r.is_empty():
		return null
	var e := ParticleEmitter.new()
	e.row = r
	return e


func _ready() -> void:
	_left = randf_range(_n("MinLife", 100), maxf(_n("MinLife", 100), _n("MaxLife", 100))) / 1000.0


func _n(key: String, fallback := 0.0) -> float:
	var v = row.get(key)
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	return fallback


func _flag(key: String) -> bool:
	return row.get(key, false) == true


func _process(delta: float) -> void:
	if delay > 0.0:
		delay -= delta
		return
	var count := int(_n("ParticleCount", 1))
	# Le premier lot part toujours, même pour un émetteur qui ne vit qu'une milliseconde
	# (éclair de la Foudre, arc du Zap).
	if (_left > 0.0 or looping or _emitted == 0) and (_emitted < count or looping):
		_next -= delta
		while _next <= 0.0 and (_emitted < count or looping):
			_spawn()
			_next += _interval(count)
			if _next <= 0.0 and _n("ParticleMaxInterval") <= 0.0:
				_next = 0.0
				if _emitted >= count:
					break
	_left -= delta
	for p in _particles.duplicate():
		_update(p, delta)
	if _particles.is_empty() and (_left <= 0.0 and not looping) and _emitted > 0:
		queue_free()
	elif _particles.is_empty() and _emitted == 0 and _left <= -1.0:
		queue_free()


## Intervalle entre deux particules (s). Sans intervalle, un émetteur long (nuage de la Tornade,
## fumée du Cimetière) répartit ses particules sur sa vie au lieu de tout lâcher d'un coup.
func _interval(count: int) -> float:
	var lo := _n("ParticleMinInterval")
	var hi := maxf(lo, _n("ParticleMaxInterval"))
	if hi <= 0.0 and _n("MaxLife", 100) >= 1000.0 and count > 1:
		return _n("MaxLife", 100) / 1000.0 / count
	return randf_range(lo, hi) / 1000.0


func _spawn() -> void:
	_emitted += 1
	if _live >= MAX_LIVE_PARTICLES:
		return
	# Ressource et export : une valeur ou une liste (une particule tirée au hasard parmi elles).
	var resources = row.get("ParticleResource", "sc/effects.sc")
	var exports = row.get("ParticleExportName", "")
	var pick := randi() % maxi(1, exports.size()) if exports is Array else 0
	var file := _resource if _resource != "" else str(resources[mini(pick, resources.size() - 1)] if resources is Array else resources).get_file().get_basename()
	var export_name := _export if _export != "" else str(exports[pick] if exports is Array else exports)
	if not ResourceLoader.exists(ScLibrary.DATA_DIR + file + ".json"):
		return
	var lib := ScLibrary.get_library(file)
	if not lib.has_export(export_name):
		return
	var node := lib.create_export(export_name)
	if node is ScMovieClip:
		node.loop = _flag("LoopParticleClip")
		node.play()
	add_child(node)
	_live += 1
	var angle := deg_to_rad(randf_range(_n("ParticleMinAngle"), maxf(_n("ParticleMinAngle"), _n("ParticleMaxAngle"))))
	if _flag("ParticleRandomAngle"):
		angle = randf() * TAU
	var speed := randf_range(_n("ParticleMinSpeed"), maxf(_n("ParticleMinSpeed"), _n("ParticleMaxSpeed"))) * SPEED_SCALE
	var area := _n("ParticleStartXYAreaRadius") * SPEED_SCALE
	var start := Vector2(randf_range(-area, area), randf_range(-area, area) * 0.8) if area > 0 else Vector2.ZERO
	var radius := randf_range(_n("ParticleMinRadius"), maxf(_n("ParticleMinRadius"), _n("ParticleMaxRadius"))) * SPEED_SCALE
	start += Vector2(cos(angle), sin(angle)) * radius
	var random_scale := _n("RandomScale")
	var p := {
		"node": node, "pos": start, "vel": Vector2(cos(angle), sin(angle) * 0.8) * speed,
		"z": _n("ParticleStartZ") * Z_SCALE, "vz": randf_range(_n("ParticleMinVelocityZ"), maxf(_n("ParticleMinVelocityZ"), _n("ParticleMaxVelocityZ"))) * Z_SCALE,
		"life": randf_range(_n("ParticleMinLife", 500), maxf(_n("ParticleMinLife", 500), _n("ParticleMaxLife", 500))) / 1000.0,
		"age": 0.0, "spin": deg_to_rad(_n("AngularSpeed")) * (1 if randf() < 0.5 else -1),
		"scale_k": 1.0 + randf_range(-random_scale, random_scale) / 100.0, "origin": position,
	}
	_particles.append(p)
	_update(p, 0.0)


func _update(p: Dictionary, delta: float) -> void:
	p.age += delta
	var node: Node2D = p.node
	if p.age >= p.life or not is_instance_valid(node):
		_particles.erase(p)
		if is_instance_valid(node):
			node.queue_free()
		_live -= 1
		return
	var inertia := clampf(_n("Inertia") / 100.0, 0.0, 0.99)
	if inertia > 0:
		p.vel *= pow(1.0 - inertia, delta * 4.0)
	p.pos += p.vel * delta
	p.vz += _n("ParticleGravity") * Z_SCALE * delta
	p.z = maxf(0.0, p.z + p.vz * delta)
	node.position = p.pos - Vector2(0, p.z)
	if trail:
		node.position += (p.origin - position) / maxf(0.01, self.scale.x)
	var t: float = p.age / p.life
	var scale: float = lerpf(_n("StartScale", 100), _n("EndScale", _n("StartScale", 100)), t) / 100.0 * p.scale_k
	node.scale = Vector2(scale, scale)
	var fade_in := _n("FadeInDuration") / 1000.0
	var fade_out := _n("FadeOutDuration") / 1000.0
	var alpha := 1.0
	if fade_in > 0 and p.age < fade_in:
		alpha = p.age / fade_in
	if fade_out > 0 and p.life - p.age < fade_out:
		alpha = minf(alpha, (p.life - p.age) / fade_out)
	node.modulate.a = alpha
	if _flag("RotateToDirection") and p.vel.length() > 1.0:
		node.rotation = p.vel.angle() + PI / 2
	else:
		node.rotation += p.spin * delta


## Fin d'une traînée (projectile arrivé) : plus d'émission, l'émetteur part avec ses particules.
func finish() -> void:
	looping = false
	_left = 0.0
	if _emitted == 0:
		_emitted = 1


func _exit_tree() -> void:
	for p in _particles:
		if is_instance_valid(p.node):
			_live -= 1
	_particles.clear()
