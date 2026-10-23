@icon("res://addons/frame_trace/icon.svg")
class_name FrameTraceRecorder
extends Node
## Find what makes a Godot game stutter. An FPS counter averages away the slow
## frames you're looking for; FrameTrace records the real time between every
## frame and how long your own named jobs took inside it, then writes a report
## that lists the slowest frames and which job was busy in each.
##
##   FrameTrace.begin(&"pathfinding")
##   ... the work ...
##   FrameTrace.end(&"pathfinding")
##
## Add it as an autoload named FrameTrace (the plugin does this), press F8 in
## the running game to start a 30-second capture, and read the JSON it writes.
## From Mytheria (cobomakesgames.com/blog/godot-stutter-frame-trace/).

## Emitted when a capture ends, with the report and where it was saved ("" if not saved).
signal finished(report: Dictionary, path: String)

## Seconds recorded after the warm-up.
@export_range(1.0, 600.0, 1.0) var duration_seconds: float = 30.0
## Seconds ignored at the start, so loading and the first frames don't count.
@export_range(0.0, 30.0, 0.5) var warmup_seconds: float = 2.0
## A frame slower than this counts as a hitch (25 ms is one you can feel at 60 fps).
@export_range(1.0, 1000.0, 0.5) var hitch_ms: float = 25.0
## The key that starts and stops a capture. KEY_NONE turns the shortcut off.
@export var toggle_key: Key = KEY_F8
## Where reports are written.
@export var output_directory: String = "user://frame_traces"
## How many of the slowest frames the report lists with their jobs.
@export_range(1, 200) var worst_frames: int = 20
@export var max_samples: int = 72000

var recording: bool = false
var last_report_path: String = ""

var _started_us: int = 0
var _measured_us: int = 0
var _previous_us: int = 0
var _samples: Array[Dictionary] = []
var _sections: Dictionary = {}
var _open: Dictionary = {}
var _section_names: Dictionary = {}


func _ready() -> void:
	process_priority = -1000000  # run first each frame, so a frame's gap is measured before your code runs
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if toggle_key == KEY_NONE or not event is InputEventKey or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == toggle_key:
		if recording:
			stop("stopped by key")
		else:
			start()
		get_viewport().set_input_as_handled()


## Starts a capture. Returns false if one is already running.
func start() -> bool:
	if recording:
		return false
	_samples.clear()
	_sections.clear()
	_open.clear()
	_section_names.clear()
	_started_us = Time.get_ticks_usec()
	_measured_us = 0
	_previous_us = 0
	recording = true
	set_process(true)
	print("FrameTrace: recording %d s after %d s of warm-up" % [duration_seconds, warmup_seconds])
	return true


## Times a named job inside the current frame. Calls of the same name add up.
func begin(section: StringName) -> void:
	if recording:
		_open[section] = Time.get_ticks_usec()


func end(section: StringName) -> void:
	if not recording or not _open.has(section):
		return
	_sections[section] = int(_sections.get(section, 0)) + Time.get_ticks_usec() - int(_open[section])
	_section_names[section] = true
	_open.erase(section)


## Times a callable as a named job and returns its result.
func measure(section: StringName, work: Callable) -> Variant:
	begin(section)
	var result: Variant = work.call()
	end(section)
	return result


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if now - _started_us < int(warmup_seconds * 1000000.0):
		_sections.clear()
		return
	if _measured_us == 0:
		_measured_us = now
		_previous_us = now
		_sections.clear()
		return
	var jobs: Dictionary = {}
	for section: StringName in _sections:
		jobs[str(section)] = snappedf(float(_sections[section]) / 1000.0, 0.001)
	_samples.append({
		"t_ms": snappedf(float(now - _measured_us) / 1000.0, 0.001),
		"gap_ms": snappedf(float(now - _previous_us) / 1000.0, 0.001),
		"delta_ms": snappedf(delta * 1000.0, 0.001),
		"jobs": jobs,
	})
	_sections.clear()
	_previous_us = now
	if now - _measured_us >= int(duration_seconds * 1000000.0):
		stop("complete")
	elif _samples.size() >= max_samples:
		stop("sample limit")


## Ends the capture, writes the report and returns it. `save` false keeps it in memory only.
func stop(reason: String = "stopped", save: bool = true) -> Dictionary:
	if not recording:
		return {}
	recording = false
	set_process(false)
	var report: Dictionary = build_report(reason)
	var path: String = ""
	if save:
		path = _write(report)
	finished.emit(report, path)
	print("FrameTrace: %d frames, %d over %.1f ms, worst %.1f ms%s" % [report.frames, report.hitches, hitch_ms, report.gap_ms.get("max", 0.0), (" -> " + ProjectSettings.globalize_path(path)) if not path.is_empty() else ""])
	return report


## The report for the frames recorded so far.
func build_report(reason: String = "") -> Dictionary:
	var gaps: Array[float] = []
	for sample: Dictionary in _samples:
		gaps.append(float(sample.gap_ms))
	var jobs: Dictionary = {}
	for section: StringName in _section_names:
		var values: Array[float] = []
		for sample: Dictionary in _samples:
			values.append(float(sample.jobs.get(str(section), 0.0)))
		jobs[str(section)] = statistics(values)
	var hitches: int = 0
	for gap: float in gaps:
		if gap > hitch_ms:
			hitches += 1
	var worst: Array[Dictionary] = _samples.duplicate()
	worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gap_ms > b.gap_ms)
	worst = worst.slice(0, worst_frames)
	for frame: Dictionary in worst:
		var busiest: String = ""
		var most: float = 0.0
		for job: String in frame.jobs:
			if float(frame.jobs[job]) > most:
				most = float(frame.jobs[job])
				busiest = job
		frame["busiest_job"] = busiest
	return {
		"format": "frame-trace-1",
		"reason": reason,
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"debug_build": OS.is_debug_build(),
		"max_fps": Engine.max_fps,
		"physics_hz": Engine.physics_ticks_per_second,
		"frames": _samples.size(),
		"seconds": float(_samples[-1].t_ms) / 1000.0 if not _samples.is_empty() else 0.0,
		"hitch_ms": hitch_ms,
		"hitches": hitches,
		"gap_ms": statistics(gaps),
		"jobs_ms": jobs,
		"worst_frames": worst,
		"samples": _samples,
	}


## count, mean, p50, p95, p99 and max of a list of numbers.
static func statistics(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	var at: Callable = func(q: float) -> float: return sorted[maxi(0, ceili(sorted.size() * q) - 1)]
	return {"count": sorted.size(), "mean": snappedf(total / sorted.size(), 0.001), "p50": at.call(0.5), "p95": at.call(0.95), "p99": at.call(0.99), "max": sorted[-1]}


func _write(report: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		push_warning("FrameTrace: can't create %s" % output_directory)
		return ""
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = output_directory.path_join("frame-trace-%s.json" % stamp)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("FrameTrace: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return ""
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	last_report_path = path
	return path


func _exit_tree() -> void:
	if recording:
		stop("exit")
