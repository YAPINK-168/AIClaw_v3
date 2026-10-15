extends Node
class_name YouyouApprovedActionPerformance

## 正式场景：已验收动作的配音、口型、表情与动作速率（代际防串台）。

const Approved := preload("res://Scripts/youyou_action_lipsync_approved.gd")
const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")
const VisemeDriver := preload("res://Scripts/youyou_test_audio_viseme_driver.gd")

var _host: Node
var _player: AnimationPlayer
var _face: FacePresenter
var _audio: AudioStreamPlayer
var _viseme: VisemeDriver

var _session_gen := 0
var _action_id := ""
var _params: Dictionary = {}
var _base_idle_emotion := "smile"


func setup(host: Node, anim_player: AnimationPlayer, face: FacePresenter) -> void:
	_host = host
	_player = anim_player
	_face = face
	_audio = AudioStreamPlayer.new()
	_audio.name = "ApprovedActionAudio"
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)
	_viseme = VisemeDriver.new()
	_viseme.name = "ApprovedActionViseme"
	add_child(_viseme)
	_viseme.setup(_face, _audio)


func get_active_action_id() -> String:
	return _action_id


func start(action_id: String, session_gen: int) -> bool:
	stop(false)
	var check: Dictionary = Approved.validate_entry(action_id)
	if not bool(check.get("ok", false)):
		for err in check.get("errors", []):
			push_error("已验收动作无效 %s: %s" % [action_id, str(err)])
		return false
	_params = check.get("params", {}) as Dictionary
	_action_id = action_id
	_session_gen = session_gen
	_apply_face_coefficients()
	var speed := float(_params.get("action_speed", 1.0))
	if _player != null and String(_player.assigned_animation) == action_id:
		_player.speed_scale = speed
	_schedule(action_id, session_gen)
	return true


func stop(invalidate: bool = true) -> void:
	if invalidate:
		_session_gen += 1
	if _audio.playing:
		_audio.stop()
	var release := float(_params.get("mouth_release_duration", 0.15))
	if _viseme != null:
		_viseme.stop(release)
	_action_id = ""
	_params = {}
	if _player != null:
		_player.speed_scale = 1.0


func on_action_animation_finished(action_id: String, session_gen: int) -> void:
	if action_id != _action_id or session_gen != _session_gen:
		return
	var return_d := float(_params.get("idle_expression_return_duration", 0.5))
	if _face != null:
		_face.configure_performance_blend(return_d)
		_face.set_emotion(_base_idle_emotion, return_d)
	stop(false)


func _apply_face_coefficients() -> void:
	if _face == null:
		return
	_face.set_coefficients(
		float(_params.get("mouth_emotion_weight", FacePresenter.APPROVED_MOUTH_EMOTION_COEF)),
		float(_params.get("viseme_weight", FacePresenter.APPROVED_VISEME_COEF)),
		float(_params.get("emotion_blend_duration", FacePresenter.APPROVED_BLEND_TIME)),
	)
	_viseme.configure_viseme_blend(float(_params.get("mouth_release_duration", 0.15)))


func _wall_delay(anim_seconds: float) -> float:
	var speed := maxf(float(_params.get("action_speed", 1.0)), 0.01)
	return maxf(anim_seconds, 0.0) / speed


func _schedule(action_id: String, gen: int) -> void:
	if _host == null:
		return
	var offset := float(_params.get("audio_start_offset", 1.667))
	var lead := float(_params.get("emotion_lead_time", 0.35))
	var emo_at := _wall_delay(maxf(offset - lead, 0.0))
	var audio_at := _wall_delay(offset)
	if emo_at > 0.0:
		_host.get_tree().create_timer(emo_at).timeout.connect(
			func() -> void:
				_on_emotion(gen, action_id),
			CONNECT_ONE_SHOT,
		)
	else:
		_on_emotion(gen, action_id)
	if audio_at > 0.0:
		_host.get_tree().create_timer(audio_at).timeout.connect(
			func() -> void:
				_on_audio(gen, action_id),
			CONNECT_ONE_SHOT,
		)
	else:
		_on_audio(gen, action_id)


func _on_emotion(gen: int, action_id: String) -> void:
	if gen != _session_gen or action_id != _action_id or _face == null:
		return
	var emo := String(_params.get("emotion_id", "smile"))
	var blend := float(_params.get("emotion_blend_duration", 0.4))
	_face.configure_performance_blend(blend)
	_face.set_emotion(emo, blend)


func _on_audio(gen: int, action_id: String) -> void:
	if gen != _session_gen or action_id != _action_id:
		return
	var path := String(_params.get("audio_path", ""))
	if path == "":
		push_error("配音路径为空：" + action_id)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("配音加载失败：" + path)
		return
	_audio.stream = stream
	_audio.pitch_scale = float(_params.get("audio_speed", 1.0))
	_audio.play()
	_viseme.start()


func _on_audio_finished() -> void:
	var release := float(_params.get("mouth_release_duration", 0.15))
	_viseme.stop(release)
