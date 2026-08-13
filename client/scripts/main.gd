extends Control
## Phase 0.1 client skeleton entry point.
## Later phases add: mic capture + VAD streaming (§9.1), camera interface with
## CameraFeed/replay backends (§5.1 development workflow), avatar, WebSocket transport (§16).


func _ready() -> void:
	print("Echo Companion client started, Godot ", Engine.get_version_info().string)
