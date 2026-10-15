extends Node

const Business := preload("res://Scripts/business/claw_business.gd")
const ShowPort := preload("res://Scripts/business/claw_show_port.gd")
const MinigamePort := preload("res://Scripts/business/claw_minigame_port.gd")
const CtrlKeys := preload("res://Scripts/business/claw_ctrl_keys.gd")

## 用来走一遍业务流程。按钮代表以后的真机事件，不直接指挥柚柚做动作。

var _show
var _minigame
var _business
var _keys
var _stage_label: Label
var _explain_label: Label
var _note_label: Label


func _ready() -> void:
	_show = ShowPort.new()
	_minigame = MinigamePort.new()
	_business = Business.new()
	add_child(_show)
	add_child(_minigame)
	add_child(_business)
	_business.bind(_show, _minigame)
	_keys = CtrlKeys.new()
	_keys.setup(_business)
	add_child(_keys)
	_business.situation_changed.connect(_refresh)
	_build_ui()
	_refresh()
	if "--business-check" in OS.get_cmdline_user_args():
		_show.pause_before_done = 0.12
		_run_check()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.16, 0.17, 0.19)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	layer.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "娃娃机现在进行到哪一步"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	_stage_label = Label.new()
	_stage_label.add_theme_font_size_override("font_size", 40)
	root.add_child(_stage_label)

	_explain_label = Label.new()
	_explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_explain_label)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.add_theme_color_override("font_color", Color(1, 0.86, 0.45))
	root.add_child(_note_label)

	var hint := Label.new()
	hint.text = "先用鼠标点一下游戏画面，再按 Ctrl 加字母。这些键只模拟玩家的事，不指挥柚柚做动作。没按 Ctrl 的字母键仍然留给原来的动作调试。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84))
	root.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)

	_add_button(grid, "有人走过来    Ctrl+E", Business.PLAYER_ENTERED, {})
	_add_button(grid, "人走开了    Ctrl+L", Business.PLAYER_LEFT, {})
	_add_button(grid, "投币    Ctrl+T", Business.COIN_ACCEPTED, {})
	_add_button(grid, "操作爪子    Ctrl+O", Business.PLAYER_OPERATING, {})
	_add_button(grid, "按下抓取    Ctrl+G", Business.GRAB_PRESSED, {})
	_add_button(grid, "抓到了    Ctrl+K", Business.GRAB_SUCCEEDED, {})
	_add_button(grid, "没抓到    Ctrl+F", Business.GRAB_FAILED, {})
	_add_button(grid, "没抓到，再给一次抓    Ctrl+R", Business.GRAB_FAILED, {"next": "retry"})
	_add_button(grid, "小游戏打完了    Ctrl+M", Business.MINIGAME_FINISHED, {"another_grab": false})
	_add_button(grid, "小游戏打完，再给一次抓    Ctrl+N", Business.MINIGAME_FINISHED, {"another_grab": true})


func _add_button(parent: GridContainer, caption: String, event_id: String, extra: Dictionary) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(460, 46)
	button.pressed.connect(func() -> void:
		_business.submit(event_id, extra)
	)
	parent.add_child(button)


func _refresh() -> void:
	if _stage_label == null:
		return
	_stage_label.text = _business.stage_name()
	_explain_label.text = _business.explain()
	_note_label.text = "刚才：" + _business.last_note


func _run_check() -> void:
	var lines: PackedStringArray = []
	var ok := true
	_expect(lines, _business.stage_name() == "待机", "开场应是待机")
	var too_early: Dictionary = _business.submit(Business.GRAB_PRESSED)
	_expect(lines, too_early["ok"] == false, "没投币不能抓")
	_business.submit(Business.PLAYER_ENTERED)
	_expect(lines, _business.explain().contains("招揽"), "有人走近进入招揽")
	_business.submit(Business.PLAYER_LEFT)
	_expect(lines, not _business.explain().contains("招揽"), "人走开回到空闲")
	_business.submit(Business.COIN_ACCEPTED)
	_expect(lines, _business.stage_name() == "等待开始", "投币后等待开始")
	var grab_while_opening: Dictionary = _business.submit(Business.GRAB_PRESSED)
	_expect(lines, grab_while_opening["ok"] == false, "开场时不能抓")
	var too_soon: Dictionary = _business.submit(Business.PLAYER_OPERATING)
	_expect(lines, too_soon["ok"] == false, "开场时不能操作爪子")
	var coin_again: Dictionary = _business.submit(Business.COIN_ACCEPTED)
	_expect(lines, coin_again["ok"] == false, "不能连续投币")
	ok = await _wait_until("玩家操作", 2.0) and ok
	_expect(lines, _business.stage_name() == "玩家操作", "开场结束才能操作")
	_push_ctrl(KEY_O)
	await get_tree().process_frame
	_expect(lines, _business.stage_name() == "玩家操作" and _business.last_note.contains("操作爪子"), "按住Ctrl再按O只表示在操作爪子")
	_business.submit(Business.GRAB_PRESSED)
	_expect(lines, _business.stage_name() == "正在抓", "按下抓取后进入抓取")
	var second_grab: Dictionary = _business.submit(Business.GRAB_PRESSED)
	_expect(lines, second_grab["ok"] == false and _business.stage_name() == "正在抓", "抓取中不能再抓")
	var coin_while_grab: Dictionary = _business.submit(Business.COIN_ACCEPTED)
	_expect(lines, coin_while_grab["ok"] == false, "抓取中不能投币")
	_show.show_finished.emit(1)
	_expect(lines, _business.stage_name() == "正在抓", "旧的演完通知不能打断抓取")
	_business.submit(Business.GRAB_FAILED)
	ok = await _wait_until("小游戏", 2.0) and ok
	_expect(lines, _business.stage_name() == "小游戏", "没抓到后进入小游戏")
	var grab_in_game: Dictionary = _business.submit(Business.GRAB_PRESSED)
	_expect(lines, grab_in_game["ok"] == false, "小游戏里不能抓")
	_business.submit(Business.MINIGAME_FINISHED, {"another_grab": true})
	_expect(lines, _business.stage_name() == "玩家操作", "小游戏可再给一次抓且不用投币")
	_business.submit(Business.GRAB_PRESSED)
	_business.submit(Business.GRAB_FAILED, {"next": "retry"})
	ok = await _wait_until("玩家操作", 2.0) and ok
	_expect(lines, _business.stage_name() == "玩家操作", "再给一次抓会回到操作")
	_business.submit(Business.GRAB_PRESSED)
	_business.submit(Business.GRAB_SUCCEEDED)
	ok = await _wait_until("待机", 2.0) and ok
	_expect(lines, _business.stage_name() == "待机", "抓到后本轮结束并回到待机")
	_expect(lines, _business.explain().contains("招揽"), "人还在，回到招揽")
	for line in lines:
		if line.begins_with("失败"):
			ok = false
		print(line)
	print("BUSINESS_CHECK_OK" if ok else "BUSINESS_CHECK_FAIL")
	get_tree().quit(0 if ok else 1)


func _push_ctrl(keycode: Key) -> void:
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.physical_keycode = KEY_CTRL
	ctrl.pressed = true
	ctrl.echo = false
	_keys._input(ctrl)
	# 按住 Ctrl 时，字母这一下经常不带 Ctrl 标记，只带物理按键。
	var event := InputEventKey.new()
	event.keycode = KEY_NONE
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = false
	event.ctrl_pressed = false
	_keys._unhandled_input(event)


func _expect(lines: PackedStringArray, passed: bool, label: String) -> void:
	lines.append(("通过 " if passed else "失败 ") + label)


func _wait_until(stage_name: String, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		if _business.stage_name() == stage_name:
			return true
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("超时，停在：" + _business.stage_name() + " / " + _business.explain())
	return false
