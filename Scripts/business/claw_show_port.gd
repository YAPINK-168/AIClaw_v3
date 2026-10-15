extends Node
class_name ClawShowPort

## 给柚柚表现用的接口。业务只说「现在演哪一段」，不直接播动画、不直接放语音。
## 动作和语音以后接到 play() 里即可。演完必须发出 show_finished，并带回当时的 token。

signal show_finished(token: int)

const ACTION_STANDBY := "idle_base"
const ACTION_ATTRACT := "attract"
const ACTION_OPENING := "opening"
const ACTION_OPERATING := "operating"
const ACTION_GRABBING := "grabbing"
const ACTION_SUCCESS := "result_success"
const ACTION_FAIL := "result_fail"
const ACTION_INVITE_MINIGAME := "invite_minigame"
const ACTION_INVITE_RETRY := "invite_retry"
const ACTION_ROUND_OVER := "round_over"

const SPEECH_ATTRACT := "attract"
const SPEECH_COIN := "coin_feedback"
const SPEECH_CONTROL := "control_ready"
const SPEECH_GRAB := "grab_running"
const SPEECH_SUCCESS := "grab_success"
const SPEECH_FAIL := "grab_fail"
const SPEECH_MINIGAME := "minigame_invite"
const SPEECH_RETRY := "retry_invite"
const SPEECH_ROUND_OVER := "round_over"

## 需要等演完再往下走的段落，停这么久。接上真演出以后，改为真的播完再通知。
var pause_before_done := 0.9

var last_action := ""
var last_speech := ""


func play(action_id: String, speech_id: String, token: int, wait_for_it: bool = false) -> void:
	last_action = action_id
	last_speech = speech_id
	if not wait_for_it:
		call_deferred("_emit_done", token)
		return
	var timer := get_tree().create_timer(pause_before_done)
	timer.timeout.connect(_emit_done.bind(token))


func play_action(action_id: String, token: int) -> void:
	play(action_id, "", token, false)


func play_speech(speech_id: String, token: int) -> void:
	play("", speech_id, token, false)


func _emit_done(token: int) -> void:
	if not is_inside_tree():
		return
	show_finished.emit(token)
