@tool
extends EditorPlugin
## Registers the FrameTrace autoload, so FrameTrace.begin()/end() work anywhere.

const NAME: String = "FrameTrace"


func _enable_plugin() -> void:
	add_autoload_singleton(NAME, "res://addons/frame_trace/frame_trace.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(NAME)
