class_name ScreenLayout
extends RefCounted
## Marges de l'écran (encoche, caméra, barre de gestes) en unités du canevas, d'après la zone sûre
## d'Android / iOS. Test sur ordinateur : --safe-top=N --safe-bottom=N.

const ROUNDED := 24.0               # coins arrondis des téléphones récents : marge minimale


static func size() -> Vector2:
	return (Engine.get_main_loop() as SceneTree).root.get_visible_rect().size


static func top() -> float:
	return maxf(ROUNDED, _margin(true))


static func bottom() -> float:
	return maxf(ROUNDED * 0.5, _margin(false))


static func _margin(is_top: bool) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--safe-top=") and is_top or arg.begins_with("--safe-bottom=") and not is_top:
			return float(arg.get_slice("=", 1))
	if not OS.has_feature("mobile"):
		return 0.0
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.y <= 0:
		return 0.0
	var k := size().y / float(screen.y)
	return (safe.position.y if is_top else screen.y - safe.end.y) * k
