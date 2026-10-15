class_name VoiceInteractionController
extends Node

const SpeechInputScript := preload("res://Scripts/voice/speech_input.gd")
const YouyouDialogueClientScript := preload("res://Scripts/voice/youyou_dialogue_client.gd")
const VoiceOutputScript := preload("res://Scripts/voice/voice_output.gd")
const FacePresenterScript := preload("res://Scripts/youyou_face_presenter.gd")
const VisemeProceduralDriverScript := preload("res://Scripts/voice/viseme_procedural_driver.gd")
const LlmResponseScript := preload("res://Scripts/voice/llm_response.gd")
const MoonshotLlmClientScript := preload("res://Scripts/voice/moonshot_llm_client.gd")
const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

enum State {
	IDLE,
	LISTENING,
	RECOGNIZING,
	THINKING,
	SYNTHESIZING,
	SPEAKING,
	CANCELLED,
	ERROR,
}

signal state_changed(old_state: State, new_state: State)
signal status_message(text: String)
signal user_text_ready(text: String)
signal assistant_text_ready(text: String, emotion: String)
signal turn_finished(reason: String)

var speech_input: SpeechInputScript
var dialogue: YouyouDialogueClientScript
var voice_output: VoiceOutputScript
var face: FacePresenterScript
var viseme_driver: VisemeProceduralDriverScript
## 可选：用于 cancel 时中止 LLM HTTP。
var moonshot_client: MoonshotLlmClientScript
var latency: VoiceTurnLatencyScript

var _state: State = State.IDLE
var _session_gen := 0
var _last_error := ""
var _listen_release_pending := false


func setup(
	input: SpeechInputScript,
	dialogue_client: YouyouDialogueClientScript,
	output: VoiceOutputScript,
	face_presenter: FacePresenterScript,
	viseme: VisemeProceduralDriverScript,
) -> void:
	speech_input = input
	dialogue = dialogue_client
	voice_output = output
	face = face_presenter
	viseme_driver = viseme


func bind_latency_tracker(tracker: VoiceTurnLatencyScript) -> void:
	latency = tracker
	if speech_input != null:
		speech_input.latency = tracker
	if voice_output != null:
		voice_output.latency = tracker
		if voice_output.bailian_client != null:
			voice_output.bailian_client.latency = tracker
	if moonshot_client != null:
		moonshot_client.latency = tracker


func get_state() -> State:
	return _state


func get_state_name() -> String:
	match _state:
		State.IDLE:
			return "idle"
		State.LISTENING:
			return "listening"
		State.RECOGNIZING:
			return "recognizing"
		State.THINKING:
			return "thinking"
		State.SYNTHESIZING:
			return "synthesizing"
		State.SPEAKING:
			return "speaking"
		State.CANCELLED:
			return "cancelled"
		State.ERROR:
			return "error"
		_:
			return "unknown"


func get_last_error() -> String:
	return _last_error


func is_busy() -> bool:
	return _state in [
		State.LISTENING,
		State.RECOGNIZING,
		State.THINKING,
		State.SYNTHESIZING,
		State.SPEAKING,
	]


func begin_listen() -> void:
	if _state == State.LISTENING:
		return
	if is_busy():
		return
	_listen_release_pending = false
	_set_state(State.LISTENING)
	if latency != null and latency.enabled:
		latency.start_turn("ptt")
		latency.mark_once("ptt_start")
	speech_input.start_hold()
	_emit_status("录音中… 松开提交")


func end_listen() -> void:
	if _state != State.LISTENING:
		return
	if _listen_release_pending:
		return
	_listen_release_pending = true
	_session_gen += 1
	var gen := _session_gen
	_set_state(State.RECOGNIZING)
	_emit_status("识别中…")
	if latency != null and latency.enabled:
		latency.mark_once("ptt_end")
	var text: String = await speech_input.end_hold_and_recognize()
	_listen_release_pending = false
	if gen != _session_gen:
		return
	if text.is_empty():
		var msg := speech_input.last_error if speech_input.last_error != "" else "识别结果为空"
		_fail(msg, gen)
		return
	user_text_ready.emit(text)
	await _run_dialogue_pipeline(text, gen)


func submit_text(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if is_busy():
		await cancel_turn()
	_session_gen += 1
	var gen := _session_gen
	if latency != null and latency.enabled:
		latency.start_turn("text")
		latency.mark_once("text_submit")
	user_text_ready.emit(trimmed)
	await _run_dialogue_pipeline(trimmed, gen)


func cancel_turn() -> void:
	_session_gen += 1
	_listen_release_pending = false
	if speech_input != null:
		speech_input.cancel()
	if moonshot_client != null:
		moonshot_client.cancel_inflight()
	if dialogue != null:
		dialogue.rollback_pending_user_turn()
	if voice_output != null:
		voice_output.stop()
	_reset_presentation()
	_set_state(State.CANCELLED)
	_emit_status("已取消")
	await get_tree().process_frame
	_set_state(State.IDLE)
	_emit_status("待机")
	if latency != null and latency.enabled:
		latency.finish("cancelled")
	turn_finished.emit("cancelled")


func _run_dialogue_pipeline(user_text: String, gen: int) -> void:
	if gen != _session_gen:
		return
	_set_state(State.THINKING)
	_emit_status("思考中…")
	var llm: LlmResponseScript = await dialogue.ask(user_text)
	if gen != _session_gen:
		return
	if llm == null or not llm.ok or llm.reply.is_empty():
		_fail("LLM 无有效回复", gen)
		return
	var face_emotion := YouyouEmotionMap.to_face_emotion(llm.emotion)
	assistant_text_ready.emit(llm.reply, face_emotion)
	if face != null:
		face.set_emotion(face_emotion)
	_set_state(State.SYNTHESIZING)
	_emit_status("生成语音中…")
	if viseme_driver != null:
		viseme_driver.start()
	var ok: bool = await voice_output.speak(llm.reply, llm.emotion, llm.intensity)
	if gen != _session_gen:
		return
	if viseme_driver != null:
		viseme_driver.stop()
	_reset_presentation()
	if not ok:
		_fail("TTS 合成或播放失败", gen)
		return
	_set_state(State.IDLE)
	_emit_status("待机")
	if latency != null and latency.enabled:
		latency.finish("completed")
	turn_finished.emit("completed")


func _fail(message: String, gen: int = -1) -> void:
	if gen >= 0 and gen != _session_gen:
		return
	_last_error = message
	push_error(message)
	_reset_presentation()
	if voice_output != null and voice_output.is_speaking():
		voice_output.stop()
	_set_state(State.ERROR)
	_emit_status("失败: " + message)
	for _i in 3:
		await get_tree().process_frame
		if gen >= 0 and gen != _session_gen:
			return
	_set_state(State.IDLE)
	_emit_status("待机")
	if latency != null and latency.enabled:
		latency.finish("error")
	turn_finished.emit("error")


func _reset_presentation() -> void:
	if viseme_driver != null:
		viseme_driver.stop()
	if face != null:
		face.reset_to_default()


func _set_state(next: State) -> void:
	if _state == next:
		return
	var old := _state
	_state = next
	state_changed.emit(old, next)
	if next == State.SPEAKING:
		_emit_status("播放中…")


func _emit_status(text: String) -> void:
	status_message.emit(text)


## 供 VoiceOutput 在首帧音频开始播放时上报（可选）。
func notify_tts_playback_started() -> void:
	if _state == State.SYNTHESIZING:
		_set_state(State.SPEAKING)
