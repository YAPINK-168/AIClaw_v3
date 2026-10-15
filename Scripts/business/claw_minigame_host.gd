extends Node2D
## 抓失败后的小游戏层：转盘固定深海寻宝，然后进入那一局。

const CtrlKeys := preload("res://Scripts/business/claw_ctrl_keys.gd")
const RouletteScript := preload("res://Scripts/business/claw_roulette.gd")

const INNER_SCENE_PATH := "res://miner/scenes/main.tscn"
const RETURN_SEC := 15.0

enum Phase { HIDDEN, SPIN, WAIT_LAUNCH, PLAY, SETTLED }

var _port
var _phase := Phase.HIDDEN
var _open := false
var _inner: Node2D
var _bg_video: CanvasLayer
var _roulette: Control
var _hint: Label
var _return_left := 0.0


func _ready() -> void:
	visible = false
	z_index = 100
	_build_blocker()
	_build_roulette()
	_build_hint()
	_ensure_input_actions()
	set_process(false)


func setup(port) -> void:
	_port = port


func covers_screen() -> bool:
	return _open


func open_round(_token: int = 0) -> void:
	_open = true
	visible = true
	_return_left = 0.0
	_hint.visible = false
	_free_inner()
	_phase = Phase.SPIN
	set_process(true)
	_roulette.visible = true
	_roulette.start_spin()


func close_round() -> void:
	if not _open and _phase == Phase.HIDDEN:
		return
	_open = false
	_phase = Phase.HIDDEN
	_return_left = 0.0
	set_process(false)
	_free_inner()
	_hide_bg_video()
	if _roulette != null:
		_roulette.stop_audio()
		_roulette.visible = false
	if _hint != null:
		_hint.visible = false
	visible = false


func replay_round() -> void:
	if not _open:
		return
	_phase = Phase.PLAY
	_return_left = 0.0
	_hint.visible = false
	_spawn_inner()


func miner_steer_axis() -> float:
	return 0.0


func obtain_bg_video() -> CanvasLayer:
	var scr = load("res://miner/scripts/miner_bg_video.gd")
	var orphan := get_tree().root.get_node_or_null("BackgroundVideo")
	if orphan != null and orphan != _bg_video:
		orphan.queue_free()
	var fresh := _bg_video == null or not is_instance_valid(_bg_video)
	if fresh:
		_bg_video = scr.new()
		_bg_video.name = "BackgroundVideo"
		add_child(_bg_video)
	move_child(_bg_video, 0)
	_bg_video.visible = true
	if not fresh and _bg_video.has_method("restart_for_round"):
		_bg_video.restart_for_round()
	return _bg_video


func _process(delta: float) -> void:
	if _phase != Phase.SETTLED:
		return
	_return_left -= delta
	var left := maxi(0, ceili(_return_left))
	_hint.text = "还剩 %d 秒回到娃娃机。Ctrl+N 再抓一次，Ctrl+M 直接结束。" % left
	if _return_left <= 0.0:
		_finish_round()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if _phase == Phase.WAIT_LAUNCH and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_launch_game()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if _phase == Phase.SPIN and _is_ctrl_g(key):
		get_viewport().set_input_as_handled()
	elif _phase == Phase.WAIT_LAUNCH and _is_start_key(key):
		_launch_game()
		get_viewport().set_input_as_handled()
	elif (_phase == Phase.PLAY or _phase == Phase.SETTLED) and _is_ctrl_g(key):
		if _inner != null and _inner.has_method("press_fire"):
			_inner.press_fire()
		get_viewport().set_input_as_handled()


func _build_blocker() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -5
	layer.name = "MouseBlock"
	var block := Control.new()
	block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(block)
	add_child(layer)


func _build_roulette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "RouletteLayer"
	_roulette = RouletteScript.new()
	_roulette.name = "Roulette"
	_roulette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roulette.visible = false
	_roulette.spin_finished.connect(_on_spin_finished)
	layer.add_child(_roulette)
	add_child(layer)


func _build_hint() -> void:
	var layer := _roulette.get_parent() as CanvasLayer
	_hint = Label.new()
	_hint.name = "ReturnHint"
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -64.0
	_hint.offset_bottom = -16.0
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color("FFE8C8"))
	layer.add_child(_hint)


func _on_spin_finished(game_id: String) -> void:
	if not _open or game_id != "miner":
		return
	_phase = Phase.WAIT_LAUNCH


func _launch_game() -> void:
	if _phase != Phase.WAIT_LAUNCH:
		return
	_phase = Phase.PLAY
	_roulette.stop_audio()
	_roulette.visible = false
	_spawn_inner()


func _spawn_inner() -> void:
	_free_inner()
	var packed := load(INNER_SCENE_PATH) as PackedScene
	if packed == null:
		push_error("深海寻宝场景加载失败。")
		_finish_round()
		return
	var node := packed.instantiate()
	if not node is Node2D:
		node.free()
		push_error("深海寻宝场景根节点不是画面。")
		_finish_round()
		return
	_inner = node as Node2D
	_inner.name = "SeabedMiner"
	add_child(_inner)
	if _inner.has_signal("settled"):
		_inner.settled.connect(_on_inner_settled)
	if _inner.has_method("_on_viewport_resized"):
		_inner.call_deferred("_on_viewport_resized")
	if _inner.has_method("_post_layout_sync"):
		_inner.call_deferred("_post_layout_sync")


func _on_inner_settled(_score: int) -> void:
	if _phase != Phase.PLAY:
		return
	_phase = Phase.SETTLED
	_return_left = RETURN_SEC
	_hint.visible = true
	_hint.text = "还剩 %d 秒回到娃娃机。Ctrl+N 再抓一次，Ctrl+M 直接结束。" % int(RETURN_SEC)


func _finish_round() -> void:
	if not _open:
		return
	var port = _port
	close_round()
	if port != null and port.has_method("notify_finished"):
		port.notify_finished(false)


func _free_inner() -> void:
	if _inner != null and is_instance_valid(_inner):
		_inner.queue_free()
	_inner = null


func _hide_bg_video() -> void:
	if _bg_video == null or not is_instance_valid(_bg_video):
		return
	if _bg_video.has_method("stop_playback"):
		_bg_video.stop_playback()
	_bg_video.visible = false


func _is_start_key(key: InputEventKey) -> bool:
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_SPACE or code == KEY_ENTER or code == KEY_KP_ENTER:
		return true
	return _is_ctrl_g(key)


func _is_ctrl_g(key: InputEventKey) -> bool:
	if not CtrlKeys.is_ctrl_combo(key):
		return false
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	return code == KEY_G


func _ensure_input_actions() -> void:
	_ensure_action("move_left")
	_ensure_action("move_right")
	_ensure_action("fire")
	_add_keys("move_left", [KEY_LEFT, KEY_A, KEY_KP_4])
	_add_keys("move_right", [KEY_RIGHT, KEY_D, KEY_KP_6])
	_add_keys("fire", [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z, KEY_J])


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _add_keys(action: String, keys: Array) -> void:
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		ev.keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
