extends Node
class_name YouyouActionLipsyncTimeline

## 独立测试场景：动作 + 绑定配音 + 表情/口型时间轴（代际 token 防过期回调）。

const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")
const VisemeDriver := preload("res://Scripts/youyou_test_audio_viseme_driver.gd")
const DEFAULT_PRE_POST_IDLE := 1.667
const Approved := preload("res://Scripts/youyou_action_lipsync_approved.gd")
const EventCatalog := preload("res://Scripts/youyou_action_event_catalog.gd")

enum Phase { STOPPED, PRE_IDLE, MAIN, POST, FINISHED }

const CATALOG_FILTER_ALL := "all"
const CATALOG_FILTER_APPROVED := "approved"
const CATALOG_FILTER_EVENT := "event"
const RESOURCE_KIND_APPROVED := "approved_catalog"
const RESOURCE_KIND_EVENT := "event_catalog"

## 与美术表一致：仅收录已交付且工程内存在配音 mp3 的动作。
const ACTION_CATALOG: Array[Dictionary] = [
	{
		"action_id": "youyou_Basic_Idle01",
		"scene": "res://待机Animation/youyou_Basic_Idle01.001.glb",
		"source_anim": "youyou_Basic_Idle01_001",
		"default_audio": "res://配音/操作2-这个角度.mp3",
		"default_emotion": "smile",
	},
	{
		"action_id": "youyou_Basic_Idle02",
		"scene": "res://待机Animation/youyou_Basic_Idle02.glb",
		"source_anim": "youyou_Basic_Idle02",
		"default_audio": "res://配音/轻待机5-吃什么.mp3",
		"default_emotion": "smile",
	},
	{
		"action_id": "youyou_Basic_Idle03",
		"scene": "res://待机Animation/youyou_Basic_Idle03.glb",
		"source_anim": "youyou_Basic_Idle03",
		"default_audio": "res://配音/轻待机3-数手指.mp3",
		"default_emotion": "smile",
	},
	{
		"action_id": "youyou_Basic_Idle04",
		"scene": "res://待机Animation/youyou_Basic_Idle04.glb",
		"source_anim": "youyou_Basic_Idle04",
		"default_audio": "res://配音/轻待机5-看看什么有意思.mp3",
		"default_emotion": "smile",
	},
	{
		"action_id": "youyou_Basic_Idle05",
		"scene": "res://待机Animation/youyou_Basic_Idle05.glb",
		"source_anim": "youyou_Basic_Idle05",
		"default_audio": "res://配音/操作3-稳住节奏（修）.mp3",
		"default_emotion": "smile",
	},
	{
		"action_id": "youyou_Hello_Idle01",
		"scene": "res://待机Animation/youyou_Hello_Idle01.glb",
		"source_anim": "youyou_Hello_Idle01",
		"default_audio": "res://配音/招揽1-小惊喜.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle02",
		"scene": "res://待机Animation/youyou_Hello_Idle02.glb",
		"source_anim": "youyou_Hello_Idle02",
		"default_audio": "res://配音/招揽4-穿搭.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle03",
		"scene": "res://待机Animation/youyou_Hello_Idle03.glb",
		"source_anim": "youyou_Hello_Idle03",
		"default_audio": "res://配音/招揽7-有意思的事.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle05",
		"scene": "res://待机Animation/youyou_Hello_Idle05.glb",
		"source_anim": "youyou_Hello_Idle05",
		"default_audio": "res://配音/招揽3-心跳加速.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle06",
		"scene": "res://待机Animation/youyou_Hello_Idle06.glb",
		"source_anim": "youyou_Hello_Idle06",
		"default_audio": "res://配音/招揽9-诶诶诶.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle07",
		"scene": "res://待机Animation/youyou_Hello_Idle07.glb",
		"source_anim": "youyou_Hello_Idle07",
		"default_audio": "res://配音/招揽8-大胆上手抓.mp3",
		"default_emotion": "laugh",
	},
	{
		"action_id": "youyou_Hello_Idle08",
		"scene": "res://待机Animation/youyou_Hello_Idle08.glb",
		"source_anim": "youyou_Hello_Idle08",
		"default_audio": "res://配音/招揽6-摇杆左右扭.mp3",
		"default_emotion": "laugh",
	},
]

const CLIP_ALIASES: Dictionary = {
	"youyou_Basic_Idle01": {
		"scene": "res://待机Animation/youyou_Basic_Idle01.001.glb",
		"source": "youyou_Basic_Idle01_001",
	},
}

var _host: Node
var _player: AnimationPlayer
var _idle_anim := "Basic_Idle"
var _face: FacePresenter
var _audio: AudioStreamPlayer
var _viseme_driver: VisemeDriver

var _session_gen := 0
var _phase := Phase.STOPPED
var _action_id := ""
var _clip_total := 0.0
var _loaded_clips: Dictionary = {}

var _pre_idle_duration := DEFAULT_PRE_POST_IDLE
var _post_idle_duration := DEFAULT_PRE_POST_IDLE
var _main_action_duration := 0.0
var _main_end_time := 0.0

var _audio_path := ""
var _audio_source_duration := 0.0
var _audio_start_offset := DEFAULT_PRE_POST_IDLE
var _audio_speed := 1.0
var _action_speed := 1.0
var _audio_started := false
var _audio_finished := false

var _target_emotion := "laugh"
var _emotion_lead_time := 0.35
var _emotion_blend_duration := 0.40
var _mouth_release_duration := 0.15
var _idle_return_duration := 0.50
var _base_idle_emotion := "smile"

var _emotion_scheduled := false
var _emotion_applied := false
var _idle_return_started := false

var _manual_acceptance_status := "draft"
var _notes := ""
var _resource_kind := RESOURCE_KIND_APPROVED
var _category := ""
var _package_finish_emitted := false

## 动作进入 FINISHED 且（无配音或配音已结束）时发出，供正式场景事件表现层使用。
signal package_finished(session_gen: int, action_id: String)

func setup(host: Node, anim_player: AnimationPlayer, face: FacePresenter, idle_anim_name: String) -> void:
	_host = host
	_player = anim_player
	_face = face
	_idle_anim = idle_anim_name
	_audio = AudioStreamPlayer.new()
	_audio.name = "ActionTimelineAudio"
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)
	_viseme_driver = VisemeDriver.new()
	_viseme_driver.name = "ActionTimelineVisemeDriver"
	add_child(_viseme_driver)
	_viseme_driver.setup(_face, _audio)
	EventCatalog.ensure_loaded()
	if not ACTION_CATALOG.is_empty():
		select_action(String(ACTION_CATALOG[0].get("action_id", "")))


func get_approved_catalog() -> Array[Dictionary]:
	return ACTION_CATALOG.duplicate()


func get_event_catalog() -> Array[Dictionary]:
	return EventCatalog.get_entries()


func get_catalog() -> Array[Dictionary]:
	return get_approved_catalog()


func get_action_ids(catalog_filter: String = CATALOG_FILTER_ALL) -> PackedStringArray:
	var ids: PackedStringArray = []
	if catalog_filter == CATALOG_FILTER_ALL or catalog_filter == CATALOG_FILTER_APPROVED:
		for entry in ACTION_CATALOG:
			ids.append(String(entry.get("action_id", "")))
	if catalog_filter == CATALOG_FILTER_ALL or catalog_filter == CATALOG_FILTER_EVENT:
		for entry in EventCatalog.get_entries():
			ids.append(String(entry.get("action_id", "")))
	return ids


func get_resource_kind(action_id: String) -> String:
	if find_catalog_entry(action_id) != {}:
		return RESOURCE_KIND_APPROVED
	if EventCatalog.find_entry(action_id) != {}:
		return RESOURCE_KIND_EVENT
	return ""


func get_resource_kind_label(action_id: String = "") -> String:
	var aid := action_id if action_id != "" else _action_id
	match get_resource_kind(aid):
		RESOURCE_KIND_APPROVED:
			return "已验收资源（轻待机/招揽调试目录）"
		RESOURCE_KIND_EVENT:
			return "事件测试资源（未入正式池）"
		_:
			return "未知资源"


func find_catalog_entry(action_id: String) -> Dictionary:
	for entry in ACTION_CATALOG:
		if String(entry.get("action_id", "")) == action_id:
			return entry
	return {}


func find_event_entry(action_id: String) -> Dictionary:
	return EventCatalog.find_entry(action_id)


func get_bound_audio_path(action_id: String) -> String:
	if get_resource_kind(action_id) == RESOURCE_KIND_EVENT:
		var event_entry := EventCatalog.find_entry(action_id)
		return String(event_entry.get("default_audio", ""))
	var approved := get_approved_params(action_id)
	if approved.has("audio_path"):
		return String(approved["audio_path"])
	var entry := find_catalog_entry(action_id)
	return String(entry.get("default_audio", ""))


func get_approved_params(action_id: String) -> Dictionary:
	return Approved.get_params(action_id)


func has_approved_preset(action_id: String) -> bool:
	if get_resource_kind(action_id) != RESOURCE_KIND_APPROVED:
		return false
	return bool(Approved.validate_entry(action_id).get("ok", false))


func select_action(action_id: String) -> bool:
	for entry in ACTION_CATALOG:
		if String(entry.get("action_id", "")) == action_id:
			_resource_kind = RESOURCE_KIND_APPROVED
			_category = ""
			_action_id = action_id
			_audio_path = String(entry.get("default_audio", ""))
			_target_emotion = String(entry.get("default_emotion", "smile"))
			_load_action_clip(entry)
			_apply_approved_preset(action_id)
			_probe_audio_duration()
			_recompute_main_duration()
			return true
	var event_entry := EventCatalog.find_entry(action_id)
	if not event_entry.is_empty():
		_resource_kind = RESOURCE_KIND_EVENT
		_category = String(event_entry.get("category", ""))
		_action_id = action_id
		_audio_path = String(event_entry.get("default_audio", ""))
		_target_emotion = String(event_entry.get("default_emotion", "smile"))
		_manual_acceptance_status = String(event_entry.get("manual_acceptance_status", "draft"))
		_notes = String(event_entry.get("notes", ""))
		_apply_event_catalog_preset(event_entry)
		_load_action_clip(event_entry)
		_probe_audio_duration()
		_recompute_main_duration()
		return true
	return false


func _apply_event_debug_defaults() -> void:
	_audio_start_offset = DEFAULT_PRE_POST_IDLE
	_audio_speed = 1.0
	_action_speed = 1.0
	_emotion_lead_time = 0.35
	_emotion_blend_duration = 0.40
	_mouth_release_duration = 0.15
	_idle_return_duration = 0.50
	set_pre_post_idle(DEFAULT_PRE_POST_IDLE, DEFAULT_PRE_POST_IDLE)
	if _face != null:
		_face.set_coefficients(
			FacePresenter.APPROVED_MOUTH_EMOTION_COEF,
			FacePresenter.APPROVED_VISEME_COEF,
			_emotion_blend_duration,
		)
	_viseme_driver.configure_viseme_blend(_mouth_release_duration)


func _apply_event_catalog_preset(entry: Dictionary) -> void:
	_apply_event_debug_defaults()
	if entry.is_empty():
		return
	set_pre_post_idle(
		float(entry.get("pre_idle_duration", _pre_idle_duration)),
		float(entry.get("post_idle_duration", _post_idle_duration)),
	)
	var tune := {}
	if entry.has("audio_start_offset"):
		tune["audio_start_offset"] = entry["audio_start_offset"]
	if entry.has("audio_speed"):
		tune["audio_speed"] = entry["audio_speed"]
	if entry.has("action_speed"):
		tune["action_speed"] = entry["action_speed"]
	if entry.has("default_emotion"):
		tune["emotion_id"] = entry["default_emotion"]
	if entry.has("emotion_lead_time"):
		tune["emotion_lead_time"] = entry["emotion_lead_time"]
	if entry.has("emotion_blend_duration"):
		tune["emotion_blend_duration"] = entry["emotion_blend_duration"]
	if entry.has("mouth_release_duration"):
		tune["mouth_release_duration"] = entry["mouth_release_duration"]
	if entry.has("idle_expression_return_duration"):
		tune["idle_expression_return_duration"] = entry["idle_expression_return_duration"]
	if entry.has("mouth_emotion_weight") and entry.has("viseme_weight"):
		tune["mouth_emotion_weight"] = entry["mouth_emotion_weight"]
		tune["viseme_weight"] = entry["viseme_weight"]
	if entry.has("manual_acceptance_status"):
		tune["manual_acceptance_status"] = entry["manual_acceptance_status"]
	if entry.has("notes"):
		tune["notes"] = entry["notes"]
	if not tune.is_empty():
		set_timeline_params(tune)


func _apply_approved_preset(action_id: String) -> void:
	var preset := Approved.get_params(action_id)
	if preset.is_empty():
		return
	if preset.has("audio_path"):
		_audio_path = String(preset["audio_path"])
	set_pre_post_idle(
		float(preset.get("pre_idle_duration", _pre_idle_duration)),
		float(preset.get("post_idle_duration", _post_idle_duration)),
	)
	var tune := preset.duplicate()
	tune.erase("pre_idle_duration")
	tune.erase("post_idle_duration")
	set_timeline_params(tune)


func set_audio_resource(path: String) -> void:
	_audio_path = path
	_probe_audio_duration()


func set_pre_post_idle(pre: float, post: float) -> void:
	_pre_idle_duration = maxf(pre, 0.0)
	_post_idle_duration = maxf(post, 0.0)
	_recompute_main_duration()


func set_main_action_duration(seconds: float) -> void:
	if seconds > 0.0:
		_main_action_duration = seconds
		_main_end_time = _pre_idle_duration + _main_action_duration
	else:
		_recompute_main_duration()


func set_timeline_params(params: Dictionary) -> void:
	if params.has("audio_start_offset"):
		_audio_start_offset = maxf(float(params["audio_start_offset"]), 0.0)
	if params.has("audio_speed"):
		_audio_speed = clampf(float(params["audio_speed"]), 0.5, 2.0)
	if params.has("action_speed"):
		_action_speed = clampf(float(params["action_speed"]), 0.5, 2.0)
		_apply_action_playback_speed()
	if params.has("emotion_id"):
		_target_emotion = String(params["emotion_id"])
	if params.has("emotion_lead_time"):
		_emotion_lead_time = maxf(float(params["emotion_lead_time"]), 0.0)
	if params.has("emotion_blend_duration"):
		_emotion_blend_duration = maxf(float(params["emotion_blend_duration"]), 0.0)
	if params.has("mouth_release_duration"):
		_mouth_release_duration = maxf(float(params["mouth_release_duration"]), 0.0)
	if params.has("idle_expression_return_duration"):
		_idle_return_duration = maxf(float(params["idle_expression_return_duration"]), 0.0)
	if params.has("manual_acceptance_status"):
		_manual_acceptance_status = String(params["manual_acceptance_status"])
	if params.has("notes"):
		_notes = String(params["notes"])
	if _face != null and params.has("mouth_emotion_weight") and params.has("viseme_weight"):
		var blend := float(params.get("emotion_blend_duration", _face.get_coefficients().z))
		_face.set_coefficients(
			float(params["mouth_emotion_weight"]),
			float(params["viseme_weight"]),
			blend,
		)
	_viseme_driver.configure_viseme_blend(_mouth_release_duration)


func get_timeline_params() -> Dictionary:
	var coef := Vector3.ZERO
	if _face != null:
		coef = _face.get_coefficients()
	return {
		"action_id": _action_id,
		"resource_kind": _resource_kind,
		"category": _category,
		"audio_id": _audio_path.get_file().get_basename() if _audio_path != "" else "",
		"audio_path": _audio_path,
		"pre_idle_duration": _pre_idle_duration,
		"main_action_duration": _main_action_duration,
		"post_idle_duration": _post_idle_duration,
		"clip_total_duration": _clip_total,
		"audio_start_offset": _audio_start_offset,
		"audio_speed": _audio_speed,
		"action_speed": _action_speed,
		"emotion_id": _target_emotion,
		"emotion_lead_time": _emotion_lead_time,
		"emotion_blend_duration": _emotion_blend_duration,
		"mouth_emotion_weight": coef.x,
		"viseme_weight": coef.y,
		"mouth_release_duration": _mouth_release_duration,
		"idle_expression_return_duration": _idle_return_duration,
		"manual_acceptance_status": _manual_acceptance_status,
		"notes": _notes,
	}


func play_voice_with_viseme() -> void:
	if _audio_path == "":
		push_warning("未选择配音：请在下拉框中选择 res://配音 下的 mp3")
		return
	stop(false)
	_session_gen += 1
	var gen := _session_gen
	_reset_flags()
	if _face != null:
		_face.configure_performance_blend(_emotion_blend_duration)
		_face.set_emotion(_target_emotion, _emotion_blend_duration)
	_start_audio(gen)


func play() -> void:
	if _player == null or _action_id == "":
		return
	stop(false)
	_session_gen += 1
	var gen := _session_gen
	_reset_flags()
	if not _player.has_animation(_action_id):
		push_error("动作 clip 未加载：" + _action_id)
		return
	_player.speed_scale = _action_speed
	_player.play(_action_id, -1, 1.0, false)
	_phase = Phase.PRE_IDLE
	_schedule_async(gen)


func replay() -> void:
	play()


func stop(invalidate: bool = true) -> void:
	if invalidate:
		_session_gen += 1
	_stop_audio_and_viseme()
	if _player != null and _player.is_playing() and _player.current_animation == _action_id:
		_player.stop()
	if _player != null:
		_player.speed_scale = 1.0
	_phase = Phase.STOPPED
	_reset_flags()


func get_phase() -> Phase:
	return _phase


func get_phase_label() -> String:
	match _phase:
		Phase.PRE_IDLE:
			return "前置待机"
		Phase.MAIN:
			return "主动作"
		Phase.POST:
			return "后置待机"
		Phase.FINISHED:
			return "已结束"
		_:
			return "已停止"


func get_anim_time() -> float:
	if _player == null:
		return 0.0
	if _player.current_animation != _action_id:
		return 0.0
	return _player.current_animation_position


func get_main_remaining() -> float:
	return maxf(_main_end_time - get_anim_time(), 0.0)


func get_audio_playback_time() -> float:
	if _audio == null or not _audio.playing:
		return 0.0
	return _audio.get_playback_position()


func get_audio_effective_duration() -> float:
	if _audio_source_duration <= 0.0:
		return 0.0
	return _audio_source_duration / maxf(_audio_speed, 0.01)


func get_audio_remaining() -> float:
	return maxf(get_audio_effective_duration() - get_audio_playback_time(), 0.0)


func get_clip_total_duration() -> float:
	return _clip_total


func get_main_action_duration_value() -> float:
	return _main_action_duration


func get_audio_source_duration() -> float:
	return _audio_source_duration


func build_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("资源: %s | 分类: %s | 验收: %s" % [
		get_resource_kind_label(),
		_category if _category != "" else "—",
		_manual_acceptance_status,
	])
	if _resource_kind == RESOURCE_KIND_EVENT and _audio_path == "":
		lines.append("配音: 未绑定（事件资源仅动作/兼容性调试，不代表口型组合已验收）")
	lines.append(
		"阶段: %s | 动作 t=%.2fs / 总长 %.2fs | 主动作 %.2fs 剩 %.2fs | 动作速率 ×%.2f"
		% [
			get_phase_label(),
			get_anim_time(),
			_clip_total,
			_main_action_duration,
			get_main_remaining(),
			_action_speed,
		]
	)
	if not (_resource_kind == RESOURCE_KIND_EVENT and _audio_path == ""):
		lines.append(
			"配音: 原长 %.2fs ×%.2f → 实际 %.2fs | 播放 %.2fs 剩 %.2fs | 偏移 %.2fs | %s"
			% [
				_audio_source_duration,
				_audio_speed,
				get_audio_effective_duration(),
				get_audio_playback_time(),
				get_audio_remaining(),
				_audio_start_offset,
				"播放中" if _audio.playing else ("已播完" if _audio_finished else "未启动"),
			]
		)
	var emo_state := "未触发"
	if _emotion_applied:
		emo_state = "已到目标"
	elif _emotion_scheduled:
		emo_state = "渐变中/已排程"
	lines.append(
		"目标情绪: %s | 表情 %s | 提前 %.2fs 渐变 %.2fs"
		% [_target_emotion, emo_state, _emotion_lead_time, _emotion_blend_duration]
	)
	if _face != null:
		lines.append(
			"口型: %s | 嘴情 %.2f 口型系数 %.2f | 口型退出 %.2fs"
			% [
				_face.get_active_viseme() if _face.get_active_viseme() != "" else "—",
				_face.get_coefficients().x,
				_face.get_coefficients().y,
				_mouth_release_duration,
			]
		)
	return lines


func save_params_to_path(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var payload := {
		"schema": "youyou_action_lipsync_tuning_v1",
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"params": get_timeline_params(),
	}
	file.store_string(JSON.stringify(payload, "\t"))
	return OK


func export_params_json() -> String:
	var payload := {
		"schema": "youyou_action_lipsync_tuning_v1",
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"params": get_timeline_params(),
	}
	return JSON.stringify(payload, "\t")


func apply_params_from_dict(params: Dictionary) -> void:
	if params.has("action_id"):
		select_action(String(params["action_id"]))
	if params.has("audio_path"):
		set_audio_resource(String(params["audio_path"]))
	elif params.has("audio_id"):
		var aid := String(params["audio_id"])
		if aid != "":
			set_audio_resource("res://配音/%s.mp3" % aid)
	set_pre_post_idle(
		float(params.get("pre_idle_duration", _pre_idle_duration)),
		float(params.get("post_idle_duration", _post_idle_duration)),
	)
	if params.has("main_action_duration"):
		set_main_action_duration(float(params["main_action_duration"]))
	set_timeline_params(params)


func _reset_flags() -> void:
	_emotion_scheduled = false
	_emotion_applied = false
	_audio_started = false
	_audio_finished = false
	_idle_return_started = false
	_package_finish_emitted = false


func is_audio_finished() -> bool:
	return _audio_finished


func is_audio_playing() -> bool:
	return _audio != null and _audio.playing


func get_current_action_id() -> String:
	return _action_id


func get_session_gen() -> int:
	return _session_gen


func _check_package_finished(gen: int) -> void:
	if gen != _session_gen or _package_finish_emitted or _action_id == "":
		return
	if _phase != Phase.FINISHED:
		return
	if _audio_path != "":
		if _audio_started and (_audio.playing or not _audio_finished):
			return
		if not _audio_started and FileAccess.file_exists(_audio_path) and _audio_source_duration > 0.0:
			return
	_package_finish_emitted = true
	package_finished.emit(gen, _action_id)


func _recompute_main_duration() -> void:
	if _clip_total <= _pre_idle_duration + _post_idle_duration:
		_main_action_duration = maxf(_clip_total - _pre_idle_duration - _post_idle_duration, 0.0)
	else:
		_main_action_duration = _clip_total - _pre_idle_duration - _post_idle_duration
	_main_end_time = _pre_idle_duration + _main_action_duration


func _clip_location(display_name: String) -> Dictionary:
	if CLIP_ALIASES.has(display_name):
		return CLIP_ALIASES[display_name]
	return {"scene": "res://待机Animation/%s.glb" % display_name, "source": display_name}


func probe_action_clip(action_id: String) -> Dictionary:
	var entry := find_catalog_entry(action_id)
	if entry.is_empty():
		entry = EventCatalog.find_entry(action_id)
	if entry.is_empty():
		return {"ok": false, "reason": "未登记 action_id", "action_id": action_id}
	var scene_path := String(entry.get("scene", ""))
	var source_anim := String(entry.get("source_anim", action_id))
	if scene_path == "" and get_resource_kind(action_id) == RESOURCE_KIND_APPROVED:
		var mapped := _clip_location(action_id)
		scene_path = String(mapped.get("scene", ""))
		if source_anim == action_id and CLIP_ALIASES.has(action_id):
			source_anim = String(CLIP_ALIASES[action_id].get("source", action_id))
	var probe := EventCatalog.probe_animation_clip(scene_path, source_anim)
	probe["action_id"] = action_id
	return probe


func _load_action_clip(entry: Dictionary) -> void:
	var action_id := String(entry.get("action_id", ""))
	if _loaded_clips.has(action_id):
		_clip_total = float(_loaded_clips[action_id])
		return
	var scene_path := String(entry.get("scene", ""))
	if scene_path == "":
		var mapped := _clip_location(action_id)
		scene_path = String(mapped.get("scene", ""))
	var source_anim := String(entry.get("source_anim", action_id))
	if source_anim == action_id and CLIP_ALIASES.has(action_id):
		source_anim = String(CLIP_ALIASES[action_id].get("source", action_id))
	var clip := _take_clip(scene_path, source_anim)
	if clip == null:
		return
	clip.loop_mode = Animation.LOOP_NONE
	_clip_total = clip.length
	_loaded_clips[action_id] = _clip_total
	if _player == null:
		return
	var lib := _player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		_player.add_animation_library("", lib)
	lib.add_animation(action_id, clip)


func _take_clip(scene_path: String, anim_name: String) -> Animation:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("动画场景加载失败：" + scene_path)
		return null
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(anim_name):
		instance.free()
		push_error("动画不存在：" + anim_name + " @ " + scene_path)
		return null
	var clip := (source.get_animation(anim_name) as Animation).duplicate(true) as Animation
	instance.free()
	return clip


func _probe_audio_duration() -> void:
	_audio_source_duration = 0.0
	if _audio_path == "" or not FileAccess.file_exists(_audio_path):
		return
	var stream := load(_audio_path) as AudioStream
	if stream == null:
		return
	if stream.has_method("get_length"):
		var len: float = stream.get_length()
		if len > 0.0:
			_audio_source_duration = len


func _wall_delay_for_anim_time(anim_seconds: float) -> float:
	var speed := maxf(_action_speed, 0.01)
	return maxf(anim_seconds, 0.0) / speed


func _apply_action_playback_speed() -> void:
	if _player == null:
		return
	if String(_player.current_animation) != _action_id:
		return
	if _phase == Phase.STOPPED or _phase == Phase.FINISHED:
		return
	_player.speed_scale = _action_speed


func _schedule_async(gen: int) -> void:
	if _host == null:
		return
	var emotion_anim_t := maxf(_audio_start_offset - _emotion_lead_time, 0.0)
	var emotion_at := _wall_delay_for_anim_time(emotion_anim_t)
	if emotion_at > 0.0:
		_host.get_tree().create_timer(emotion_at).timeout.connect(
			func() -> void:
				_on_emotion_timer(gen),
			CONNECT_ONE_SHOT,
		)
	else:
		_on_emotion_timer(gen)
	var audio_wall := _wall_delay_for_anim_time(_audio_start_offset)
	if audio_wall > 0.0:
		_host.get_tree().create_timer(audio_wall).timeout.connect(
			func() -> void:
				_on_audio_start_timer(gen),
			CONNECT_ONE_SHOT,
		)
	else:
		_on_audio_start_timer(gen)


func _on_emotion_timer(gen: int) -> void:
	if gen != _session_gen or _face == null:
		return
	_emotion_scheduled = true
	_face.configure_performance_blend(_emotion_blend_duration)
	_face.set_emotion(_target_emotion, _emotion_blend_duration)
	_emotion_applied = true


func _on_audio_start_timer(gen: int) -> void:
	if gen != _session_gen:
		return
	_start_audio(gen)


func _start_audio(gen: int) -> void:
	if gen != _session_gen or _audio_path == "":
		return
	var stream := load(_audio_path) as AudioStream
	if stream == null:
		push_error("配音加载失败：" + _audio_path)
		return
	_audio.stream = stream
	_audio.pitch_scale = _audio_speed
	_audio.play()
	_audio_started = true
	_viseme_driver.configure_viseme_blend(_mouth_release_duration)
	_viseme_driver.start()


func _on_audio_finished() -> void:
	var gen := _session_gen
	if not _audio_started:
		return
	_audio_finished = true
	_viseme_driver.stop(_mouth_release_duration)
	_check_package_finished(gen)
	# 口型结束后保持眼眉情绪，仅释放嘴部口型权重。


func _stop_audio_and_viseme() -> void:
	if _audio.playing:
		_audio.stop()
	_viseme_driver.stop(_mouth_release_duration)


func _process(_delta: float) -> void:
	if _player == null or _phase == Phase.STOPPED or _phase == Phase.FINISHED:
		return
	if _player.current_animation != _action_id:
		return
	var t := get_anim_time()
	if t < _pre_idle_duration:
		_phase = Phase.PRE_IDLE
	elif t < _main_end_time:
		_phase = Phase.MAIN
	elif t < _clip_total - 0.02:
		_phase = Phase.POST
	else:
		_on_action_end()


func _on_action_end() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	var gen := _session_gen
	if not _idle_return_started and _face != null:
		_idle_return_started = true
		_face.configure_performance_blend(_idle_return_duration)
		_face.set_emotion(_base_idle_emotion, _idle_return_duration)
	if _player != null and _player.has_animation(_idle_anim):
		_player.speed_scale = 1.0
		_player.play(_idle_anim)
	_check_package_finished(gen)


func notify_animation_finished(anim_name: StringName) -> void:
	if String(anim_name) != _action_id:
		return
	if _phase != Phase.FINISHED:
		_on_action_end()
