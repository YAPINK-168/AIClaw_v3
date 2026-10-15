extends Node

const Business := preload("res://Scripts/business/claw_business.gd")

## 有些键盘按住 Ctrl 再按字母时，字母那一下不会带上 Ctrl 标记。
## 这里记住 Ctrl 本身有没有按着，不单看字母事件上的标记。

static var ctrl_latched := false

var business


static func note(key: InputEventKey) -> void:
	if key.keycode != KEY_CTRL and key.physical_keycode != KEY_CTRL:
		return
	if key.pressed:
		ctrl_latched = true
	else:
		ctrl_latched = Input.is_physical_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_CTRL)


static func is_ctrl_combo(key: InputEventKey) -> bool:
	if not key.pressed or key.echo:
		return false
	if key.shift_pressed or key.alt_pressed or key.meta_pressed:
		return false
	if key.keycode == KEY_CTRL or key.physical_keycode == KEY_CTRL:
		return false
	return key.ctrl_pressed or ctrl_latched or Input.is_physical_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_CTRL)


static func debug_should_skip(event: InputEvent) -> bool:
	return event is InputEventKey and is_ctrl_combo(event as InputEventKey)


func setup(business_node) -> void:
	business = business_node


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		note(event as InputEventKey)


func _unhandled_input(event: InputEvent) -> void:
	if business == null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not is_ctrl_combo(key):
		return
	var letter := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	var binding := _binding_for(letter)
	if binding.is_empty():
		return
	business.submit(String(binding["event"]), binding["extra"])
	get_viewport().set_input_as_handled()


func _binding_for(keycode: Key) -> Dictionary:
	match keycode:
		KEY_E:
			return {"event": Business.PLAYER_ENTERED, "extra": {}}
		KEY_L:
			return {"event": Business.PLAYER_LEFT, "extra": {}}
		KEY_T:
			return {"event": Business.COIN_ACCEPTED, "extra": {}}
		KEY_O:
			return {"event": Business.PLAYER_OPERATING, "extra": {}}
		KEY_G:
			return {"event": Business.GRAB_PRESSED, "extra": {}}
		KEY_K:
			return {"event": Business.GRAB_SUCCEEDED, "extra": {}}
		KEY_F:
			return {"event": Business.GRAB_FAILED, "extra": {}}
		KEY_R:
			return {"event": Business.GRAB_FAILED, "extra": {"next": "retry"}}
		KEY_M:
			return {"event": Business.MINIGAME_FINISHED, "extra": {"another_grab": false}}
		KEY_N:
			return {"event": Business.MINIGAME_FINISHED, "extra": {"another_grab": true}}
	return {}
