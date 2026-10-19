extends Node
# Added by every rendering test (see tools/run_test.sh): the window takes no
# focus, lets every click through and sits off-screen, so tests never take the
# user's mouse or keyboard.

func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]))
	var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(scr.position + scr.size - Vector2i(24, 24))
