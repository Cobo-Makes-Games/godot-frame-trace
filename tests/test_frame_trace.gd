extends SceneTree
## Headless checks: godot --headless --path . --script tests/test_frame_trace.gd
## A fake "pathfinding" job stalls 40 ms every 10th frame; the trace must find
## those frames as hitches and name the job.

var failures: int = 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	var trace: FrameTraceRecorder = FrameTraceRecorder.new()
	trace.warmup_seconds = 0.2
	trace.duration_seconds = 1.5
	trace.output_directory = "user://frame_trace_test"
	root.add_child(trace)
	await process_frame
	var reports: Array[Dictionary] = []
	var paths: Array[String] = []
	trace.finished.connect(func(report: Dictionary, path: String) -> void:
		reports.append(report)
		paths.append(path))
	check(trace.start(), "a capture starts")
	check(not trace.start(), "a second start while recording is refused")
	var frame: int = 0
	while trace.recording:
		frame += 1
		trace.begin(&"pathfinding")
		OS.delay_msec(40 if frame % 10 == 0 else 1)
		trace.end(&"pathfinding")
		trace.measure(&"ui", func() -> int: return 1)
		await process_frame
	check(reports.size() == 1, "finished fires once")
	var report: Dictionary = reports[0]
	check(report.frames > 20, "recorded %d frames" % report.frames)
	check(report.hitches >= 3, "found the stalled frames as hitches (%d)" % report.hitches)
	check(report.gap_ms.max >= 40.0, "the worst gap includes the 40 ms stall (%.1f ms)" % report.gap_ms.max)
	check(report.worst_frames[0].busiest_job == "pathfinding", "the slowest frame names pathfinding as its busiest job")
	check(report.jobs_ms.has("pathfinding") and report.jobs_ms.has("ui"), "every named job gets statistics")
	check(report.jobs_ms.pathfinding.max >= 40.0, "pathfinding's worst time is the stall (%.1f ms)" % report.jobs_ms.pathfinding.max)
	check(not paths[0].is_empty() and FileAccess.file_exists(paths[0]), "the report was written to %s" % paths[0])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	check(parsed is Dictionary and parsed.format == "frame-trace-1", "the file is the same report as JSON")
	DirAccess.remove_absolute(paths[0])
	var stats: Dictionary = FrameTraceRecorder.statistics([1.0, 2.0, 3.0, 4.0, 100.0])
	check(stats.p50 == 3.0 and stats.max == 100.0 and stats.count == 5, "statistics: median 3, max 100")
	trace.queue_free()
	await process_frame
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
