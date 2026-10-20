class_name Effects
extends RefCounted
## Effets de la 16.4 (legacy_vfx/effects.json, via GameDB) : chaque effet liste des composants
## « SWF » (clip .sc joué une fois), « Effect » (autre effet), « ParticleEmitter » (émetteur) sur
## une couche (Ground, Base, Shadow : au sol sous les unités ; le reste au-dessus), avec un son.
## Version ennemie (EnemyVersion) pour l'équipe adverse. Positions dans le repère .sc des calques
## d'effets de BattleView.

const MAX_DEPTH := 4
const GROUND_LAYERS := ["Ground", "Base", "Shadow"]


## Joue un effet ; renvoie ce qui reste (effets en boucle) pour que l'appelant le retire.
static func play(effect_name: String, view: BattleView, position: Vector2, enemy := false, depth := 0,
		scale := 1.0) -> Array:
	var kept: Array = []
	if effect_name == "" or depth > MAX_DEPTH or view == null:
		return kept
	var row := GameDB.effect(effect_name)
	if row.is_empty():
		return kept
	if enemy and str(row.get("EnemyVersion", "")) != "":
		return play(row.EnemyVersion, view, position, false, depth + 1, scale)
	var looping: bool = row.get("Loop", false) == true
	var k := scale * float(row.get("Scale", 100)) / 100.0
	if row.has("ShakeScreen"):
		view.shake(float(row.ShakeScreen))
	for entry: Dictionary in row.get("RenderableComponents", []):
		if entry.has("Sound"):
			Sounds.play_event(entry.Sound)
		var target := view.fx_ground if entry.get("Layer", "") in GROUND_LAYERS else view.fx_top
		var entry_k := k * float(entry.get("RenderableScale", 100)) / 100.0
		match entry.get("Type", ""):
			"SWF":
				var file := str(entry.get("FileName", "")).get_file().get_basename()
				if file != "" and entry.has("ExportName"):
					var clip := _play_clip(file, entry.ExportName, target, position, looping, entry_k)
					if clip:
						kept.append(clip)
			"ParticleEmitter":
				var emitter := ParticleEmitter.create(str(entry.get("ParticleEmitterName", "")))
				if emitter:
					emitter.scale = Vector2.ONE * entry_k
					emitter.position = position
					emitter.looping = looping
					var delay := float(entry.get("Time", 0)) / 1000.0
					if delay > 0.0:
						emitter.delay = delay
					target.add_child(emitter)
					if looping:
						kept.append(emitter)
			"Effect":
				kept.append_array(play(str(entry.get("Effect", "")), view, position, enemy, depth + 1, scale))
	return kept


static func _play_clip(file: String, export_name: String, parent: Node2D, position: Vector2, looping: bool,
		scale: float) -> Node2D:
	if not ResourceLoader.exists(ScLibrary.DATA_DIR + file + ".json"):
		return null
	var lib := ScLibrary.get_library(file)
	if not lib.has_export(export_name):
		return null
	var clip := lib.create_export(export_name)
	clip.position = position
	clip.scale = Vector2.ONE * scale
	parent.add_child(clip)
	if looping:
		if clip is ScMovieClip:
			clip.loop = true
			clip.play()
		return clip
	if clip is ScMovieClip and clip.frames.size() > 1:
		clip.loop = false
		clip.play()
		clip.finished.connect(clip.queue_free)
	else:
		parent.get_tree().create_timer(0.6).timeout.connect(clip.queue_free)
	return null
