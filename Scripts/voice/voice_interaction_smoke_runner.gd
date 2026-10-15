extends Node

## 控制器逻辑 smoke（桩模块，不调用真实 ASR/LLM/TTS API）。

const SpeechInputScript := preload("res://Scripts/voice/speech_input.gd")
const YouyouDialogueClientScript := preload("res://Scripts/voice/youyou_dialogue_client.gd")
const VoiceOutputScript := preload("res://Scripts/voice/voice_output.gd")
const VoiceInteractionControllerScript := preload("res://Scripts/voice/voice_interaction_controller.gd")
const LlmResponseScript := preload("res://Scripts/voice/llm_response.gd")
const FacePresenterScript := preload("res://Scripts/youyou_face_presenter.gd")
const VisemeProceduralDriverScript := preload("res://Scripts/voice/viseme_procedural_driver.gd")


class StubSpeech extends SpeechInputScript:
	var script_text: String = ""
	var cancel_count := 0

	func _ready() -> void:
		pass

	func start_hold() -> void:
		pass

	func cancel() -> void:
		cancel_count += 1

	func end_hold_and_recognize() -> String:
		await get_tree().process_frame
		return script_text


class StubDialogue extends YouyouDialogueClientScript:
	var next_response: LlmResponseScript = LlmResponseScript.failure()
	var ask_count := 0

	func ask(_player_text: String) -> LlmResponseScript:
		ask_count += 1
		await get_tree().process_frame
		return next_response


class StubVoiceOutput extends VoiceOutputScript:
	var should_fail := false
	var speak_count := 0
	var stop_count := 0
	var _stub_speaking := false

	func _ready() -> void:
		pass

	func stop(invalidate_inflight: bool = true) -> void:
		stop_count += 1
		_stub_speaking = false

	func is_speaking() -> bool:
		return _stub_speaking

	func speak(_text: String, _emotion: String = "", _intensity: float = 0.0) -> bool:
		speak_count += 1
		_stub_speaking = true
		for _i in 8:
			await get_tree().process_frame
			if not _stub_speaking:
				return false
		_stub_speaking = false
		return not should_fail


func run(
	_production_voice: VoiceInteractionControllerScript,
	_production_output: Node,
	_production_face: FacePresenterScript,
	_production_viseme: VisemeProceduralDriverScript,
) -> bool:
	var ok := true
	ok = ok and await _case_asr_empty()
	ok = ok and await _case_llm_failure()
	ok = ok and await _case_tts_failure()
	ok = ok and await _case_happy_turn()
	ok = ok and await _case_cancel_during_speak()
	ok = ok and await _case_cancel_then_new_turn()
	ok = ok and await _case_double_begin_listen()
	ok = ok and await _case_busy_blocks_listen()
	print("voice_smoke_cases_passed=", ok)
	return ok


func _make_controller() -> Dictionary:
	var speech := StubSpeech.new()
	speech.name = "StubSpeech"
	add_child(speech)
	var dialogue := StubDialogue.new()
	dialogue.name = "StubDialogue"
	add_child(dialogue)
	var output := StubVoiceOutput.new()
	output.name = "StubOutput"
	add_child(output)
	var face := FacePresenterScript.new()
	face.name = "StubFace"
	add_child(face)
	var viseme := VisemeProceduralDriverScript.new()
	viseme.name = "StubViseme"
	add_child(viseme)
	var ctrl := VoiceInteractionControllerScript.new()
	ctrl.name = "CtrlUnderTest"
	add_child(ctrl)
	ctrl.setup(speech, dialogue, output, face, viseme)
	return {
		"ctrl": ctrl,
		"speech": speech,
		"dialogue": dialogue,
		"output": output,
	}


func _cleanup(pack: Dictionary) -> void:
	for k in pack.keys():
		var n: Node = pack[k]
		if n != null and is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame


func _case_asr_empty() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	var dialogue: StubDialogue = p.dialogue
	p.speech.script_text = ""
	p.speech.last_error = "识别结果为空"
	ctrl.begin_listen()
	await ctrl.end_listen()
	for _i in 4:
		await get_tree().process_frame
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and dialogue.ask_count == 0
	print("smoke_asr_empty=", pass_, " state=", ctrl.get_state_name(), " ask=", dialogue.ask_count)
	await _cleanup(p)
	return pass_


func _case_llm_failure() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	var output: StubVoiceOutput = p.output
	p.speech.script_text = "你好"
	p.dialogue.next_response = LlmResponseScript.failure()
	ctrl.begin_listen()
	await ctrl.end_listen()
	for _i in 4:
		await get_tree().process_frame
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and output.speak_count == 0
	print(
		"smoke_llm_fail=",
		pass_,
		" state=",
		ctrl.get_state_name(),
		" speak=",
		output.speak_count,
	)
	await _cleanup(p)
	return pass_


func _case_tts_failure() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	p.speech.script_text = "你好"
	var llm := LlmResponseScript.fallback("测试回复")
	llm.ok = true
	p.dialogue.next_response = llm
	p.output.should_fail = true
	ctrl.begin_listen()
	await ctrl.end_listen()
	for _i in 4:
		await get_tree().process_frame
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and p.output.speak_count == 1
	print(
		"smoke_tts_fail=",
		pass_,
		" state=",
		ctrl.get_state_name(),
		" speak=",
		p.output.speak_count,
	)
	await _cleanup(p)
	return pass_


func _case_happy_turn() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	p.speech.script_text = "第一轮"
	var llm := LlmResponseScript.fallback("好的呀")
	llm.emotion = "happy"
	p.dialogue.next_response = llm
	ctrl.begin_listen()
	await ctrl.end_listen()
	await get_tree().process_frame
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and p.output.speak_count == 1
	print("smoke_happy_turn=", pass_)
	await _cleanup(p)
	return pass_


func _case_cancel_during_speak() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	p.dialogue.next_response = LlmResponseScript.fallback("长回复")
	ctrl.submit_text("取消测试")
	await get_tree().process_frame
	await get_tree().process_frame
	ctrl.cancel_turn()
	for _i in 12:
		await get_tree().process_frame
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and p.output.stop_count >= 1
	print("smoke_cancel_speak=", pass_)
	await _cleanup(p)
	return pass_


func _case_cancel_then_new_turn() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	p.dialogue.next_response = LlmResponseScript.fallback("a")
	ctrl.submit_text("x")
	await get_tree().process_frame
	ctrl.cancel_turn()
	for _i in 6:
		await get_tree().process_frame
	p.dialogue.next_response = LlmResponseScript.fallback("b")
	await ctrl.submit_text("第二轮")
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE
	pass_ = pass_ and p.dialogue.ask_count >= 1
	print("smoke_cancel_new_turn=", pass_)
	await _cleanup(p)
	return pass_


func _case_double_begin_listen() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	ctrl.begin_listen()
	ctrl.begin_listen()
	var pass_ := ctrl.get_state() == VoiceInteractionControllerScript.State.LISTENING
	print("smoke_double_begin=", pass_)
	ctrl.cancel_turn()
	await _cleanup(p)
	return pass_


func _case_busy_blocks_listen() -> bool:
	var p := _make_controller()
	var ctrl: VoiceInteractionControllerScript = p.ctrl
	p.dialogue.next_response = LlmResponseScript.fallback("回复")
	ctrl.submit_text("busy")
	await get_tree().process_frame
	ctrl.begin_listen()
	var blocked := ctrl.get_state() != VoiceInteractionControllerScript.State.LISTENING
	for _i in 20:
		await get_tree().process_frame
		if ctrl.get_state() == VoiceInteractionControllerScript.State.IDLE:
			break
	print("smoke_busy_blocks_listen=", blocked)
	await _cleanup(p)
	return blocked
