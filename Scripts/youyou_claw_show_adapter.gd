extends Node
class_name YouyouClawShowAdapter

## 业务 ShowPort 语义 → 正式场景事件表现（不直接加载 GLB/MP3）。

signal show_finished(token: int)

const MAP_PATH := "res://config/youyou_claw_show_map.json"

var _event_perf: YouyouEventActionPerformance
var _wait_token := -1
var _last_action := ""
var _last_speech := ""


func setup(event_performance: YouyouEventActionPerformance) -> void:
	_event_perf = event_performance
	if not _event_perf.performance_finished.is_connected(_on_performance_finished):
		_event_perf.performance_finished.connect(_on_performance_finished)
	if not _event_perf.performance_failed.is_connected(_on_performance_failed):
		_event_perf.performance_failed.connect(_on_performance_failed)


func play(action_id: String, speech_id: String, token: int, wait_for_it: bool = false) -> void:
	_last_action = action_id
	_last_speech = speech_id
	var mapping := _resolve_mapping(action_id, speech_id)
	if mapping.is_empty():
		push_warning("Show 映射缺失：action=%s speech=%s" % [action_id, speech_id])
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	var event_id := String(mapping.get("event_action_id", ""))
	var status := String(mapping.get("binding_status", ""))
	if event_id == "":
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if status == "playback_only" and (action_id != "" or speech_id != ""):
		push_warning("事件 %s 仅测试场/显式 action_id 播放，忽略业务组合 %s|%s" % [
			event_id, action_id, speech_id,
		])
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if _event_perf == null:
		push_error("事件表现节点未 setup")
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if not _event_perf.play_event(event_id, token):
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if wait_for_it:
		_wait_token = token
	else:
		call_deferred("_emit_done", token)


func play_action(action_id: String, token: int) -> void:
	play(action_id, "", token, false)


func play_speech(speech_id: String, token: int) -> void:
	play("", speech_id, token, false)


func play_event_by_id(event_action_id: String, token: int, wait_for_it: bool = false) -> void:
	_last_action = ""
	_last_speech = ""
	if _event_perf == null:
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if not _event_perf.play_event(event_action_id, token):
		if wait_for_it:
			call_deferred("_emit_done", token)
		return
	if wait_for_it:
		_wait_token = token
	else:
		call_deferred("_emit_done", token)


func _on_performance_finished(token: int, _action_id: String, _reason: String) -> void:
	if _wait_token >= 0 and token == _wait_token:
		var t := _wait_token
		_wait_token = -1
		show_finished.emit(t)


func _on_performance_failed(token: int, action_id: String, code: String, message: String) -> void:
	push_warning("Show 事件播放失败 %s [%s]: %s" % [action_id, code, message])
	if _wait_token >= 0 and token == _wait_token:
		var t := _wait_token
		_wait_token = -1
		show_finished.emit(t)


func _emit_done(token: int) -> void:
	if is_inside_tree():
		show_finished.emit(token)


func _resolve_mapping(action_id: String, speech_id: String) -> Dictionary:
	var mappings := _load_mappings()
	for item in mappings:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = item
		if String(m.get("business_action", "")) != action_id:
			continue
		if String(m.get("business_speech", "")) != speech_id:
			continue
		return m
	return {}


func _load_mappings() -> Array:
	if not FileAccess.file_exists(MAP_PATH):
		push_error("Show 映射缺失：" + MAP_PATH)
		return []
	var file := FileAccess.open(MAP_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var raw: Variant = parsed.get("mappings", [])
	if typeof(raw) != TYPE_ARRAY:
		return []
	return raw
