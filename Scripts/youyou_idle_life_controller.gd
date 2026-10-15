extends Node
class_name YouyouIdleLifeController

## 基础待机生命感：随机眨眼、自主转眼、输入打断与状态许可。

const HeadFollowScript := preload("res://Scripts/youyou_head_follow_controller.gd")

enum PerfState { BASE_IDLE, PERFORMANCE }
enum AutonomousKind { NONE, BLINK, GLANCE }

@export var blink_interval_min: float = 1.6
@export var blink_interval_max: float = 4.2
@export var blink_close_speed: float = 16.0
@export var blink_open_speed: float = 12.0
@export var blink_hold_sec: float = 0.04

@export var glance_interval_min: float = 1.5
@export var glance_interval_max: float = 4.0
@export var glance_hold_min: float = 0.4
@export var glance_hold_max: float = 1.05
@export var glance_chance: float = 0.9
@export var glance_magnitude: float = 0.38
@export var glance_smooth: float = 5.2
@export var input_cooldown_sec: float = 0.85

@export var mouse_move_threshold_px: float = 8.0

var _gaze: Node
var _head: HeadFollowScript
var _state := PerfState.BASE_IDLE

var _blink_timer := 0.0
var _blink_phase := "idle"
var _blink_weight := 0.0
var _blink_hold_left := 0.0

var _glance_timer := 0.0
var _glance_hold := 0.0
var _glance_target := Vector2.ZERO
var _glance_display := Vector2.ZERO
var _glance_active := false

var _seconds_since_manual_input := 999.0
var _autonomous_kind := AutonomousKind.NONE
var _blink_channel := true
var _gaze_channel := true
var _head_channel := true
var _blink_masked := false
var _manual_input_enabled := true
var _blink_released := false
var _gaze_released := false
var _head_released := false


func setup(gaze: Node, head: HeadFollowScript) -> void:
	_gaze = gaze
	_head = head
	_schedule_blink()
	_schedule_glance()
	process_priority = 100
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if not _manual_input_enabled or _state != PerfState.BASE_IDLE:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.relative.length_squared() >= 0.25:
			_note_manual_input()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W, KEY_A, KEY_S, KEY_D:
				_note_manual_input()


func _process(delta: float) -> void:
	process_life(delta, get_viewport())


func set_performance_state(state: PerfState) -> void:
	if _state == state:
		return
	_state = state
	if state != PerfState.BASE_IDLE:
		_cancel_autonomous()
	else:
		_schedule_blink()
		_schedule_glance()
		_seconds_since_manual_input = input_cooldown_sec


func get_performance_state() -> PerfState:
	return _state


func trigger_test_blink() -> bool:
	if _state != PerfState.BASE_IDLE:
		return false
	if _blink_phase != "idle":
		return false
	_blink_phase = "closing"
	return true


func is_base_idle_allowed() -> bool:
	return _state == PerfState.BASE_IDLE


func set_blink_channel(enabled: bool) -> void:
	_blink_channel = enabled


func set_blink_masked(masked: bool) -> void:
	_blink_masked = masked


func is_blink_masked() -> bool:
	return _blink_masked


func set_gaze_channel(enabled: bool) -> void:
	_gaze_channel = enabled


func set_head_channel(enabled: bool) -> void:
	_head_channel = enabled


func set_manual_input_enabled(enabled: bool) -> void:
	_manual_input_enabled = enabled
	if _gaze != null:
		_gaze.call("set_manual_input_enabled", enabled)
	if not enabled:
		_seconds_since_manual_input = input_cooldown_sec


func is_blink_channel_enabled() -> bool:
	return _blink_channel


func is_gaze_channel_enabled() -> bool:
	return _gaze_channel


func is_head_channel_enabled() -> bool:
	return _head_channel


func is_manual_input_enabled() -> bool:
	return _manual_input_enabled


func is_autonomous_allowed() -> bool:
	return _state == PerfState.BASE_IDLE and not _is_manual_gaze_override()


func get_debug_snapshot() -> Dictionary:
	var gaze_auto := Vector2.ZERO
	var gaze_display := Vector2.ZERO
	var blink := 0.0
	var look_peak := 0.0
	if _gaze != null:
		gaze_auto = _gaze.call("get_autonomous_gaze")
		gaze_display = _gaze.call("get_display_gaze")
		blink = _gaze.call("get_blink_weight")
		look_peak = _gaze.call("get_peak_look_weight")
	var next_timer := _blink_timer if _blink_phase == "idle" else _glance_timer
	if _blink_phase in ["closing", "hold", "opening"]:
		next_timer = 0.0
	elif _glance_active:
		next_timer = _glance_hold
	return {
		"state": _state,
		"base_idle": _state == PerfState.BASE_IDLE,
		"autonomous_allowed": is_autonomous_allowed(),
		"manual_gaze_override": _is_manual_gaze_override(),
		"autonomous_kind": int(_autonomous_kind),
		"blink_phase": _blink_phase,
		"next_timer_sec": next_timer,
		"autonomous_gaze": gaze_auto,
		"display_gaze": gaze_display,
		"blink_weight": blink,
		"look_peak": look_peak,
		"seconds_since_manual": _seconds_since_manual_input,
		"head_enabled": _head.is_enabled() if _head != null else false,
		"head_yaw_deg": _head.get_current_yaw_deg() if _head != null else 0.0,
		"head_pitch_deg": _head.get_current_pitch_deg() if _head != null else 0.0,
		"head_target_yaw_deg": _head.get_target_yaw_deg() if _head != null else 0.0,
	}


func process_life(delta: float, viewport: Viewport) -> void:
	if _gaze == null:
		return
	if _manual_input_enabled:
		_update_manual_input_clock(delta)
	var base_idle := _state == PerfState.BASE_IDLE
	var blink_on := _blink_channel and base_idle
	var gaze_on := _gaze_channel and base_idle
	var head_on := _head_channel and base_idle
	var autonomous := gaze_on and not _is_manual_gaze_override()
	_gaze.call("set_autonomous_active", autonomous)
	_gaze.call("set_manual_gaze_override", _manual_input_enabled and _is_manual_gaze_override())
	if blink_on:
		_blink_released = false
		if _blink_masked:
			_blink_weight = lerpf(_blink_weight, 0.0, clampf(blink_open_speed * delta, 0.0, 1.0))
			_gaze.call("set_blink_weight", _blink_weight)
			_gaze.call("apply_blink_weight", _blink_weight)
		else:
			_process_blink(delta)
	else:
		_release_blink_edge()
	if gaze_on:
		_gaze_released = false
		if autonomous:
			_process_glance(delta)
		else:
			_fade_autonomous_glance(delta)
		_gaze.call("process_gaze", delta, viewport)
	else:
		_release_gaze_edge()
		if blink_on:
			_gaze.call("apply_blink_weight", _blink_weight)
	if _head != null:
		if head_on:
			_head_released = false
			_head.set_enabled(true)
			var g: Vector2 = _gaze.call("get_display_gaze")
			_head.set_follow_gaze(g)
			var wasd: bool = _manual_input_enabled and _gaze.call("is_wasd_active")
			_head.set_smooth_speed(_head.keyboard_smooth_speed if wasd else 5.0)
			_head.process_follow(delta)
		else:
			_release_head_edge()
	_update_autonomous_kind()


func _release_blink_edge() -> void:
	if _blink_released:
		return
	_blink_phase = "idle"
	_blink_weight = 0.0
	_blink_hold_left = 0.0
	_gaze.call("set_blink_weight", 0.0)
	_gaze.call("apply_blink_weight", 0.0)
	_schedule_blink()
	_blink_released = true


func _release_gaze_edge() -> void:
	if _gaze_released:
		return
	_glance_active = false
	_glance_target = Vector2.ZERO
	_glance_display = Vector2.ZERO
	_gaze.call("set_autonomous_gaze", Vector2.ZERO)
	_gaze.call("set_autonomous_active", false)
	_gaze.call("release_look_shapes")
	_schedule_glance()
	_gaze_released = true


func _release_head_edge() -> void:
	if _head_released or _head == null:
		return
	_head.relinquish()
	_head_released = true


func _cancel_autonomous() -> void:
	_glance_active = false
	_glance_target = Vector2.ZERO
	_glance_display = Vector2.ZERO
	_blink_phase = "idle"
	_blink_weight = 0.0
	_gaze.call("set_autonomous_gaze", Vector2.ZERO)
	_gaze.call("set_autonomous_active", false)
	_gaze.call("set_blink_weight", 0.0)
	_autonomous_kind = AutonomousKind.NONE
	if _head != null:
		_head.set_enabled(false)


func _is_manual_gaze_override() -> bool:
	if _gaze != null and _gaze.call("is_wasd_active"):
		return true
	return _seconds_since_manual_input < input_cooldown_sec


func _note_manual_input() -> void:
	_seconds_since_manual_input = 0.0


func _update_manual_input_clock(delta: float) -> void:
	if _gaze != null and _gaze.call("is_wasd_active"):
		_seconds_since_manual_input = 0.0
	else:
		_seconds_since_manual_input += delta


func _schedule_blink() -> void:
	_blink_timer = randf_range(blink_interval_min, blink_interval_max)


func _schedule_glance() -> void:
	_glance_timer = randf_range(glance_interval_min, glance_interval_max)


func _process_blink(delta: float) -> void:
	if _blink_phase == "idle":
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_phase = "closing"
		_blink_weight = lerpf(_blink_weight, 0.0, clampf(blink_open_speed * delta, 0.0, 1.0))
	elif _blink_phase == "closing":
		_blink_weight = move_toward(_blink_weight, 1.0, blink_close_speed * delta)
		if _blink_weight >= 0.98:
			_blink_phase = "hold"
			_blink_hold_left = blink_hold_sec
	elif _blink_phase == "hold":
		_blink_hold_left -= delta
		_blink_weight = 1.0
		if _blink_hold_left <= 0.0:
			_blink_phase = "opening"
	elif _blink_phase == "opening":
		_blink_weight = move_toward(_blink_weight, 0.0, blink_open_speed * delta)
		if _blink_weight <= 0.02:
			_blink_phase = "idle"
			_schedule_blink()
	_gaze.call("set_blink_weight", _blink_weight)


func _fade_blink_and_glance(delta: float) -> void:
	_blink_phase = "idle"
	_blink_weight = lerpf(_blink_weight, 0.0, clampf(blink_open_speed * delta, 0.0, 1.0))
	_gaze.call("set_blink_weight", _blink_weight)
	_fade_autonomous_glance(delta)


func _fade_autonomous_glance(delta: float) -> void:
	_glance_active = false
	_glance_display = _glance_display.lerp(Vector2.ZERO, clampf(glance_smooth * delta, 0.0, 1.0))
	_gaze.call("set_autonomous_gaze", _glance_display)


func _process_glance(delta: float) -> void:
	if not _glance_active:
		_glance_timer -= delta
		if _glance_timer <= 0.0:
			if randf() <= glance_chance:
				_glance_target = _random_glance_target()
				_glance_hold = randf_range(glance_hold_min, glance_hold_max)
				_glance_active = true
			_schedule_glance()
	_glance_display = _glance_display.lerp(
		_glance_target if _glance_active else Vector2.ZERO,
		clampf(glance_smooth * delta, 0.0, 1.0),
	)
	if _glance_active:
		_glance_hold -= delta
		if _glance_hold <= 0.0:
			_glance_active = false
			_glance_target = Vector2.ZERO
	_gaze.call("set_autonomous_gaze", _glance_display)


func _random_glance_target() -> Vector2:
	var dirs: Array[Vector2] = [
		Vector2(-1, 0), Vector2(1, 0), Vector2(0, -0.65), Vector2(0, 0.55),
		Vector2(-0.65, -0.35), Vector2(0.65, -0.35), Vector2(-0.55, 0.35), Vector2(0.55, 0.35),
	]
	var pick: Vector2 = dirs[randi() % dirs.size()]
	var mag := randf_range(0.28, 0.82) * glance_magnitude
	return Vector2(
		pick.x * _gaze.call("get_max_horizontal") * mag,
		pick.y * _gaze.call("get_max_vertical") * mag,
	)


func _update_autonomous_kind() -> void:
	if _state != PerfState.BASE_IDLE:
		_autonomous_kind = AutonomousKind.NONE
		return
	if _blink_phase in ["closing", "hold", "opening"]:
		_autonomous_kind = AutonomousKind.BLINK
	elif _glance_active or _glance_display.length_squared() > 0.0004:
		_autonomous_kind = AutonomousKind.GLANCE
	else:
		_autonomous_kind = AutonomousKind.NONE
