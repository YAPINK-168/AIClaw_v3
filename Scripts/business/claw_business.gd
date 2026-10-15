extends Node
class_name ClawBusiness

const ShowPort := preload("res://Scripts/business/claw_show_port.gd")

## 娃娃机业务流程。只回答两件事：现在在哪一步，以及这一步允许什么发生。
## 不播放柚柚的动作和语音，只通过表现接口提出请求。

signal situation_changed

const PLAYER_ENTERED := "player_entered"
const PLAYER_LEFT := "player_left"
const COIN_ACCEPTED := "coin_accepted"
const PLAYER_OPERATING := "player_operating"
const GRAB_PRESSED := "grab_pressed"
const GRAB_SUCCEEDED := "grab_succeeded"
const GRAB_FAILED := "grab_failed"
const MINIGAME_FINISHED := "minigame_finished"

enum Stage { STANDBY, WAIT_START, OPERATE, GRABBING, RESULT, MINIGAME }

var _stage := Stage.STANDBY
var _visitor := false
var _token := 0
var _wait_show := false
var _success := false
var _after_result := "over"
var _result_phase := ""
var _show
var _minigame
var last_note := ""


func bind(show_port, minigame_port) -> void:
	_show = show_port
	_minigame = minigame_port
	if not _show.show_finished.is_connected(_on_show_finished):
		_show.show_finished.connect(_on_show_finished)
	if not _minigame.finished.is_connected(_on_minigame_port_finished):
		_minigame.finished.connect(_on_minigame_port_finished)
	_enter_standby(false)


func current_stage() -> Stage:
	return _stage


func has_visitor() -> bool:
	return _visitor


func stage_name() -> String:
	match _stage:
		Stage.STANDBY:
			return "待机"
		Stage.WAIT_START:
			return "等待开始"
		Stage.OPERATE:
			return "玩家操作"
		Stage.GRABBING:
			return "正在抓"
		Stage.RESULT:
			return "结果"
		Stage.MINIGAME:
			return "小游戏"
	return ""


func explain() -> String:
	match _stage:
		Stage.STANDBY:
			if _visitor:
				return "有人在机器前，柚柚在招揽。还没投币，不能抓。"
			return "机器前没人，柚柚做基础待机。"
		Stage.WAIT_START:
			return "币已经收下，正在开场。开场没完不能抓。"
		Stage.OPERATE:
			return "现在可以操作爪子。只有按下抓取，才会真的去抓。"
		Stage.GRABBING:
			return "正在抓。这一下还没出结果之前，再投币、再按抓取，都不算。"
		Stage.RESULT:
			if _result_phase == "feedback":
				if _success:
					return "抓到了。先把这个结果演完，再决定接下来去哪。"
				return "没抓到。先把这个结果演完，再决定接下来去哪。"
			match _after_result:
				"minigame":
					return "结果演完了，正在邀请去小游戏。"
				"retry":
					return "结果演完了。再给一次抓，不用重新投币。"
				_:
					return "这一轮要结束了，正在收尾。"
		Stage.MINIGAME:
			return "小游戏进行中。抓娃娃先等着，打完再决定要不要回来再抓。"
	return ""


func submit(event_id: String, extra: Dictionary = {}) -> Dictionary:
	match event_id:
		PLAYER_ENTERED:
			return _on_player_entered()
		PLAYER_LEFT:
			return _on_player_left()
		COIN_ACCEPTED:
			return _on_coin()
		PLAYER_OPERATING:
			return _on_player_operating()
		GRAB_PRESSED:
			return _on_grab_pressed()
		GRAB_SUCCEEDED:
			return _on_grab_result(true, String(extra.get("next", "")))
		GRAB_FAILED:
			return _on_grab_result(false, String(extra.get("next", "")))
		MINIGAME_FINISHED:
			return _on_minigame_finished(bool(extra.get("another_grab", false)))
		_:
			return _reject("这件事先不处理。")


func _on_player_entered() -> Dictionary:
	if _stage != Stage.STANDBY:
		return _reject("这轮已经开始了。")
	if _visitor:
		return _reject("人已经在机器前了。")
	_visitor = true
	_play(ShowPort.ACTION_ATTRACT, ShowPort.SPEECH_ATTRACT, false)
	_announce("有人走过来，开始招揽。")
	return _accept("有人走过来，开始招揽。")


func _on_player_left() -> Dictionary:
	if _stage != Stage.STANDBY:
		return _reject("币已经投了，人走开这轮也不中断。")
	if not _visitor:
		return _reject("机器前本来就没人。")
	_visitor = false
	_play(ShowPort.ACTION_STANDBY, "", false)
	_announce("人走开了，当前动作做完再回待机。")
	return _accept("人走开了，当前动作做完再回待机。")


func _on_coin() -> Dictionary:
	if _stage != Stage.STANDBY:
		return _reject("这轮已经收过币了，不能把投币和抓取混在一起。")
	_visitor = true
	_stage = Stage.WAIT_START
	_play(ShowPort.ACTION_OPENING, ShowPort.SPEECH_COIN, true)
	_announce("收币成功，进入开场。")
	return _accept("收币成功，进入开场。")


func _on_player_operating() -> Dictionary:
	if _stage != Stage.OPERATE:
		return _reject("现在还不能操作爪子。")
	_play(ShowPort.ACTION_OPERATING, "", false)
	_announce("玩家正在操作爪子。")
	return _accept("玩家正在操作爪子。")


func _on_grab_pressed() -> Dictionary:
	if _stage != Stage.OPERATE:
		if _stage == Stage.GRABBING:
			return _reject("正在抓，不能再抓一次。")
		return _reject("现在还不能抓。")
	_stage = Stage.GRABBING
	_play(ShowPort.ACTION_GRABBING, ShowPort.SPEECH_GRAB, false)
	_announce("开始抓取。")
	return _accept("开始抓取。")


func _on_grab_result(success: bool, requested_next: String) -> Dictionary:
	if _stage != Stage.GRABBING:
		return _reject("现在没有一轮抓取在进行。")
	_success = success
	_after_result = _normalize_next(requested_next, success)
	_result_phase = "feedback"
	_stage = Stage.RESULT
	if success:
		_play(ShowPort.ACTION_SUCCESS, ShowPort.SPEECH_SUCCESS, true)
		_announce("抓到了。")
		return _accept("抓到了。")
	_play(ShowPort.ACTION_FAIL, ShowPort.SPEECH_FAIL, true)
	_announce("没抓到。")
	return _accept("没抓到。")


func _on_minigame_finished(another_grab: bool) -> Dictionary:
	if _stage != Stage.MINIGAME:
		return _reject("现在不在小游戏里。")
	if another_grab:
		_enter_operate("小游戏结束，再给一次抓。")
		return _accept("小游戏结束，再给一次抓。")
	_enter_standby_after_round("小游戏结束，这一轮到此为止。")
	return _accept("小游戏结束，这一轮到此为止。")


func _on_minigame_port_finished(token: int, another_grab: bool) -> void:
	if token != _token or _stage != Stage.MINIGAME:
		return
	_on_minigame_finished(another_grab)


func _on_show_finished(token: int) -> void:
	if token != _token or not _wait_show:
		return
	_wait_show = false
	match _stage:
		Stage.WAIT_START:
			_enter_operate("开场结束，可以把控制权交给玩家了。")
		Stage.RESULT:
			_advance_result()


func _advance_result() -> void:
	if _result_phase == "feedback":
		_result_phase = "guide"
		match _after_result:
			"minigame":
				_play(ShowPort.ACTION_INVITE_MINIGAME, ShowPort.SPEECH_MINIGAME, true)
				_announce("邀请去小游戏。")
			"retry":
				_play(ShowPort.ACTION_INVITE_RETRY, ShowPort.SPEECH_RETRY, true)
				_announce("再给一次抓。")
			_:
				_play(ShowPort.ACTION_ROUND_OVER, ShowPort.SPEECH_ROUND_OVER, true)
				_announce("这一轮收尾。")
		return
	match _after_result:
		"minigame":
			_enter_minigame()
		"retry":
			_enter_operate("可以再抓一次，不用重新投币。")
		_:
			_enter_standby_after_round("这一轮结束。人还在的话，继续招揽。")


func _enter_operate(note: String) -> void:
	_stage = Stage.OPERATE
	_result_phase = ""
	_play(ShowPort.ACTION_OPERATING, ShowPort.SPEECH_CONTROL, false)
	_announce(note)


func _enter_minigame() -> void:
	_stage = Stage.MINIGAME
	_result_phase = ""
	_token = _next_token()
	_wait_show = false
	_minigame.open_minigame(_token)
	_announce("进入小游戏。")


func _enter_standby_after_round(note: String) -> void:
	_stage = Stage.STANDBY
	_result_phase = ""
	_success = false
	_after_result = "over"
	if _visitor:
		_play(ShowPort.ACTION_ATTRACT, ShowPort.SPEECH_ATTRACT, false)
	else:
		_play(ShowPort.ACTION_STANDBY, "", false)
	_announce(note)


func _enter_standby(visitor: bool) -> void:
	_stage = Stage.STANDBY
	_visitor = visitor
	_result_phase = ""
	_play(ShowPort.ACTION_STANDBY, "", false)
	_announce("机器空着，基础待机。")


func _play(action_id: String, speech_id: String, wait_for_it: bool) -> void:
	_token = _next_token()
	_wait_show = wait_for_it
	_show.play(action_id, speech_id, _token, wait_for_it)


func _next_token() -> int:
	_token += 1
	return _token


func _normalize_next(requested_next: String, success: bool) -> String:
	if requested_next == "minigame" or requested_next == "retry" or requested_next == "over":
		return requested_next
	if success:
		return "over"
	return "minigame"


func _announce(note: String) -> void:
	last_note = note
	situation_changed.emit()


func _accept(note: String) -> Dictionary:
	return {"ok": true, "note": note}


func _reject(note: String) -> Dictionary:
	last_note = note
	situation_changed.emit()
	return {"ok": false, "note": note}
