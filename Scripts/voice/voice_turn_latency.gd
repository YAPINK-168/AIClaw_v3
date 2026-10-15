class_name VoiceTurnLatency
extends RefCounted

## 全链路耗时（Time.get_ticks_usec 单调时钟）。未发生的阶段在报告中为 null，不用 0 冒充。

const HISTORY_MAX := 32

var enabled: bool = false

var turn_id: int = 0
var _path: String = ""
var _outcome: String = "idle"
var _marks: Dictionary = {}
var _tts_segments: Array[Dictionary] = []
var _current_tts_chunk: int = -1

static var _seq: int = 0
static var _history: Array[Dictionary] = []


func start_turn(path: String) -> void:
	if not enabled:
		return
	_seq += 1
	turn_id = _seq
	_path = path
	_outcome = "running"
	_marks.clear()
	_tts_segments.clear()
	_current_tts_chunk = -1


func mark_once(event: String) -> void:
	if not enabled:
		return
	if _marks.has(event):
		return
	_marks[event] = Time.get_ticks_usec()


func mark_end(event: String) -> void:
	if not enabled:
		return
	_marks[event] = Time.get_ticks_usec()


func has_mark(event: String) -> bool:
	return _marks.has(event)


func set_tts_chunk_index(index: int) -> void:
	if not enabled:
		return
	_current_tts_chunk = index


func notify_tts_http_span(http_ms: float) -> void:
	if not enabled or _current_tts_chunk < 0:
		return
	_ensure_segment(_current_tts_chunk)
	var seg: Dictionary = _tts_segments[_current_tts_chunk]
	seg["http_ms"] = http_ms


func notify_tts_segment_bytes(byte_size: int) -> void:
	if not enabled or _current_tts_chunk < 0:
		return
	_ensure_segment(_current_tts_chunk)
	var seg: Dictionary = _tts_segments[_current_tts_chunk]
	seg["bytes"] = byte_size


func close_open_stages() -> void:
	if not enabled:
		return
	if has_mark("asr_start") and not has_mark("asr_end"):
		mark_end("asr_end")
	if has_mark("llm_start") and not has_mark("llm_end"):
		mark_end("llm_end")
	if has_mark("tts_start") and not has_mark("tts_all_ready"):
		mark_end("tts_all_ready")


func finish(outcome: String) -> void:
	if not enabled:
		return
	close_open_stages()
	_outcome = outcome
	mark_end("turn_end")
	var report := build_report()
	_history.append(report)
	while _history.size() > HISTORY_MAX:
		_history.pop_front()
	_print_round(report)


func build_report() -> Dictionary:
	var input_end := _pick_input_end_event()
	var r := {
		"turn_id": turn_id,
		"path": _path,
		"outcome": _outcome,
		"events": _marks.duplicate(),
		"tts_segments": _tts_segments.duplicate(true),
	}
	r["asr_ms"] = _delta("asr_start", "asr_end")
	r["llm_ms"] = _delta("llm_start", "llm_end")
	r["tts_first_http_ms"] = _delta("tts_http_start", "tts_http_done")
	r["tts_first_download_ms"] = _delta("tts_download_start", "tts_first_audio_ready")
	r["tts_first_ready_ms"] = _delta("tts_start", "tts_first_audio_ready")
	r["decode_to_play_ms"] = _delta("tts_decode_start", "playback_start")
	r["ptt_end_to_play_ms"] = _delta(input_end, "playback_start")
	r["ptt_end_to_playback_end_ms"] = _delta(input_end, "playback_end")
	r["turn_total_ms"] = _delta(_turn_start_event(), "turn_end")
	r["tts_all_synth_ms"] = _delta("tts_start", "tts_all_ready")
	r["asr_token_ms"] = _delta("asr_token_start", "asr_start")
	# 兼容旧字段名
	r["release_to_play_ms"] = r["ptt_end_to_play_ms"]
	r["tts_first_chunk_ms"] = r["tts_first_ready_ms"]
	r["tts_http_ms"] = r["tts_first_http_ms"]
	r["tts_download_ms"] = r["tts_first_download_ms"]
	return r


static func get_history() -> Array[Dictionary]:
	return _history.duplicate(true)


static func get_recent_averages(last_n: int = 5) -> Dictionary:
	var n := mini(maxi(last_n, 1), _history.size())
	if n == 0:
		return {}
	var start := _history.size() - n
	var keys := [
		"asr_ms",
		"llm_ms",
		"tts_first_ready_ms",
		"ptt_end_to_play_ms",
		"ptt_end_to_playback_end_ms",
	]
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for k in keys:
		sums[k] = 0.0
		counts[k] = 0
	for i in range(start, _history.size()):
		var row: Dictionary = _history[i]
		for k in keys:
			var v: Variant = row.get(k)
			if v == null:
				continue
			var f := float(v)
			if f >= 0.0:
				sums[k] += f
				counts[k] += 1
	var avg: Dictionary = {}
	for k in keys:
		var c: int = int(counts[k])
		if c > 0:
			avg[k] = float(sums[k]) / float(c)
	return avg


static func clear_history() -> void:
	_history.clear()


static func format_summary_line(report: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("id=%d" % int(report.get("turn_id", 0)))
	parts.append(str(report.get("path", "")))
	parts.append(str(report.get("outcome", "")))
	for key in ["ptt_end_to_play_ms", "asr_ms", "llm_ms", "tts_first_ready_ms", "turn_total_ms"]:
		var v: Variant = report.get(key)
		if v == null:
			parts.append("%s=—" % key)
		else:
			var f := float(v)
			if f >= 0.0:
				parts.append("%s=%.0fms" % [key, f])
			else:
				parts.append("%s=—" % key)
	return " ".join(parts)


static func print_aggregate() -> void:
	if _history.is_empty():
		print("voice_latency_aggregate rounds=0")
		return
	var avg := get_recent_averages(_history.size())
	print("voice_latency_aggregate rounds=", _history.size())
	for k in avg.keys():
		print("  avg_%s=%.1fms" % [k, float(avg[k])])
	for row in _history:
		print("  ", format_summary_line(row))


func _turn_start_event() -> String:
	if _path == "ptt":
		return "ptt_start" if _marks.has("ptt_start") else "ptt_end"
	return "text_submit"


func _pick_input_end_event() -> String:
	if _marks.has("ptt_end"):
		return "ptt_end"
	if _marks.has("text_submit"):
		return "text_submit"
	return ""


func _delta(from_event: String, to_event: String) -> Variant:
	if from_event.is_empty() or not _marks.has(from_event) or not _marks.has(to_event):
		return null
	return float(int(_marks[to_event]) - int(_marks[from_event])) / 1000.0


func _ensure_segment(index: int) -> void:
	while _tts_segments.size() <= index:
		_tts_segments.append({"index": _tts_segments.size(), "http_ms": null, "bytes": 0})


func _print_round(r: Dictionary) -> void:
	print(
		"voice_latency_round turn_id=%d path=%s outcome=%s"
		% [r.get("turn_id", 0), r.get("path", ""), r.get("outcome", "")]
	)
	var line := static_format_metrics(r)
	if not line.is_empty():
		print("  ", line)
	var segs: Variant = r.get("tts_segments", [])
	if typeof(segs) == TYPE_ARRAY and (segs as Array).size() > 1:
		print("  tts_segments=", segs)


static func static_format_metrics(r: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key in [
		"ptt_end_to_play_ms",
		"asr_ms",
		"llm_ms",
		"tts_first_ready_ms",
		"tts_first_http_ms",
		"tts_first_download_ms",
		"decode_to_play_ms",
		"ptt_end_to_playback_end_ms",
		"turn_total_ms",
	]:
		var v: Variant = r.get(key)
		if v == null:
			continue
		var f := float(v)
		if f >= 0.0:
			parts.append("%s=%.1fms" % [key, f])
	return " | ".join(parts)


## 兼容旧调用
func begin_turn(path: String) -> void:
	start_turn(path)
	if path == "text":
		mark_once("text_submit")
	elif path == "ptt":
		mark_once("ptt_end")


func mark(event: String) -> void:
	match event:
		"asr_done":
			mark_end("asr_end")
		"llm_done":
			mark_end("llm_end")
		"tts_playback_start":
			mark_once("playback_start")
		"release_submit":
			mark_once("text_submit")
		_:
			mark_once(event)
