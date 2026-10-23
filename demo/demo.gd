extends Control
## Frame Trace demo: a fake "pathfinding" job stalls for 40 ms every second.
## Press F8 (or Start) to record 10 seconds, then read which job owned the slow frames.

@onready var status: Label = $Box/Status
var frame: int = 0


func _ready() -> void:
	FrameTrace.duration_seconds = 10.0
	FrameTrace.finished.connect(_show)
	$Box/Start.pressed.connect(func() -> void:
		if FrameTrace.start():
			status.text = "Recording 10 seconds after a 2-second warm-up…")


func _process(_delta: float) -> void:
	frame += 1
	FrameTrace.begin(&"pathfinding")
	OS.delay_msec(40 if frame % 60 == 0 and $Box/Stall.button_pressed else 0)
	FrameTrace.end(&"pathfinding")


func _show(report: Dictionary, path: String) -> void:
	var worst: Dictionary = report.worst_frames[0] if not report.worst_frames.is_empty() else {}
	status.text = "%d frames, %d slower than %.0f ms.\nWorst frame: %.1f ms, busiest job: %s.\nReport: %s" % [
		report.frames, report.hitches, report.hitch_ms, worst.get("gap_ms", 0.0), worst.get("busiest_job", "-"), ProjectSettings.globalize_path(path)]
