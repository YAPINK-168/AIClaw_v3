extends Node3D

const GazeController := preload("res://Scripts/youyou_eye_gaze_controller.gd")
const HeadFollow := preload("res://Scripts/youyou_head_follow_controller.gd")
const IdleLife := preload("res://Scripts/youyou_idle_life_controller.gd")
const Approved := preload("res://Scripts/youyou_action_lipsync_approved.gd")

const MODEL_PATH := "res://柚柚.glb"
const IDLE_SCENE_PATH := "res://待机Animation/Basic_Idle.glb"
const IDLE_ANIM := "Basic_Idle"
const DEMO_PERFORMANCE_ACTION := "youyou_Hello_Idle01"

var _model: Node3D
var _camera: Camera3D
var _player: AnimationPlayer
var _gaze: Node
var _head: Node
var _idle_life: Node
var _status: Label
var _blink_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_camera = get_node_or_null("ObservePivot/Camera3D") as Camera3D
	_status = get_node_or_null("StatusLayer/StatusLabel") as Label
	_blink_btn = get_node_or_null("StatusLayer/BlinkTestButton") as Button
	if _blink_btn != null:
		_blink_btn.pressed.connect(_on_blink_test_pressed)
	if not _load_model():
		return
	if not _load_idle_clip():
		return
	_gaze = GazeController.new()
	_gaze.name = "EyeGazeController"
	add_child(_gaze)
	_gaze.setup(_model, _camera)
	_head = HeadFollow.new()
	_head.name = "HeadFollowController"
	_head.process_priority = 100
	add_child(_head)
	_head.setup(_model)
	_idle_life = IdleLife.new()
	_idle_life.name = "IdleLifeController"
	add_child(_idle_life)
	_idle_life.setup(_gaze, _head)
	_player.play(IDLE_ANIM)
	_idle_life.set_performance_state(IdleLife.PerfState.BASE_IDLE)
	call_deferred("_grab_game_focus")
	var args := OS.get_cmdline_user_args()
	if "--eye-gaze-check" in args:
		set_process(false)
		await _run_eye_gaze_check()
		get_tree().quit()
		return
	if "--idle-life-check" in args:
		set_process(false)
		await _run_idle_life_check()
		get_tree().quit()
		return
	if "--idle-life-runtime-check" in args:
		set_process(false)
		await _run_idle_life_runtime_check()
		get_tree().quit()


func _grab_game_focus() -> void:
	get_viewport().grab_focus()


func _process(_delta: float) -> void:
	if _gaze == null or _idle_life == null:
		return
	if _status != null:
		var d: Dictionary = _idle_life.get_debug_snapshot()
		var kind_names: PackedStringArray = ["无", "眨眼", "转眼"]
		var kind_i: int = int(d.get("autonomous_kind", 0)) if typeof(d.get("autonomous_kind", 0)) == TYPE_INT else 0
		var auto_g: Vector2 = d.get("autonomous_gaze", Vector2.ZERO)
		var disp_g: Vector2 = d.get("display_gaze", Vector2.ZERO)
		_status.text = (
			"状态=%s | 自主许可=%s | 行为=%s | 阶段=%s | 下次≈%.1fs\n"
			+ "自主目标(%+.2f,%+.2f) | 注视(%+.2f,%+.2f) | 眨眼=%.2f | eyeLook峰值=%.2f\n"
			+ "头部 yaw=%.2f°/目标%.2f° pitch=%.2f° | 手动冷却=%.2fs | B/按钮=测试眨眼 | P=招揽"
			% [
				"基础待机" if d.get("base_idle", false) else "表演中",
				"是" if d.get("autonomous_allowed", false) else "否",
				kind_names[clampi(kind_i, 0, 2)],
				String(d.get("blink_phase", "idle")),
				float(d.get("next_timer_sec", 0.0)),
				auto_g.x, auto_g.y,
				disp_g.x, disp_g.y,
				float(d.get("blink_weight", 0.0)),
				float(d.get("look_peak", 0.0)),
				float(d.get("head_yaw_deg", 0.0)),
				float(d.get("head_target_yaw_deg", 0.0)),
				float(d.get("head_pitch_deg", 0.0)),
				float(d.get("seconds_since_manual", 0.0)),
			]
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_toggle_performance_demo()
		elif event.keycode == KEY_B:
			_on_blink_test_pressed()


func _on_blink_test_pressed() -> void:
	if _idle_life == null:
		return
	var ok: bool = _idle_life.call("trigger_test_blink")
	if _blink_btn != null:
		_blink_btn.text = "眨眼已触发…" if ok else "眨眼忙/非待机"
		if ok:
			get_tree().create_timer(1.2).timeout.connect(func() -> void:
				if _blink_btn != null:
					_blink_btn.text = "测试眨眼 (B)"
			)


func _toggle_performance_demo() -> void:
	if _idle_life.get_performance_state() == IdleLife.PerfState.BASE_IDLE:
		_idle_life.set_performance_state(IdleLife.PerfState.PERFORMANCE)
		if _player.has_animation(DEMO_PERFORMANCE_ACTION):
			_player.play(DEMO_PERFORMANCE_ACTION)
		_player.animation_finished.connect(_on_performance_finished, CONNECT_ONE_SHOT)
	else:
		_return_to_base_idle()


func _on_performance_finished(_anim: StringName) -> void:
	_return_to_base_idle()


func _return_to_base_idle() -> void:
	_player.play(IDLE_ANIM)
	_idle_life.set_performance_state(IdleLife.PerfState.BASE_IDLE)


func _load_model() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("模型加载失败")
		return false
	_model = packed.instantiate() as Node3D
	_model.name = "YouyouModel"
	add_child(_model)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) == "耳机":
			mesh.visible = false
	return true


func _load_idle_clip() -> bool:
	Approved.load_config()
	var packed := load(IDLE_SCENE_PATH) as PackedScene
	if packed == null:
		return false
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(IDLE_ANIM):
		instance.free()
		return false
	var idle_clip := (source.get_animation(IDLE_ANIM) as Animation).duplicate(true) as Animation
	idle_clip.loop_mode = Animation.LOOP_LINEAR
	instance.free()
	_player = AnimationPlayer.new()
	_player.name = "TestAnimationPlayer"
	_player.process_priority = 0
	_model.add_child(_player)
	var lib := AnimationLibrary.new()
	lib.add_animation(IDLE_ANIM, idle_clip)
	if Approved.validate_entry(DEMO_PERFORMANCE_ACTION).get("ok", false):
		var perf := Approved.take_animation_clip(DEMO_PERFORMANCE_ACTION)
		if perf != null:
			perf.loop_mode = Animation.LOOP_NONE
			lib.add_animation(DEMO_PERFORMANCE_ACTION, perf)
	_player.add_animation_library(&"", lib)
	return true


func _run_eye_gaze_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	var ok := _gaze != null
	if ok:
		if _idle_life != null:
			_idle_life.set_process(false)
			_idle_life.set_performance_state(IdleLife.PerfState.PERFORMANCE)
		_gaze.call("set_gaze_immediate", Vector2(-0.5, 0.0))
		await get_tree().process_frame
		var in_l: float = _gaze.call("read_shape_weight", "eyeLookInLeft", "眼睛左")
		var out_r: float = _gaze.call("read_shape_weight", "eyeLookOutRight", "眼睛右")
		ok = ok and in_l > 0.18 and out_r > 0.18
		lines.append("look_left in_l=%.3f out_r=%.3f" % [in_l, out_r])
		_gaze.call("set_gaze_immediate", Vector2(0.5, 0.0))
		await get_tree().process_frame
		var out_l: float = _gaze.call("read_shape_weight", "eyeLookOutLeft", "眼睛左")
		var in_r: float = _gaze.call("read_shape_weight", "eyeLookInRight", "眼睛右")
		ok = ok and out_l > 0.18 and in_r > 0.18
		lines.append("look_right out_l=%.3f in_r=%.3f" % [out_l, in_r])
		_gaze.call("set_gaze_immediate", Vector2.ZERO)
		await get_tree().process_frame
		ok = ok and _gaze.call("read_shape_weight", "eyeLookOutLeft", "眼睛左") < 0.05
	lines.append("=== eye_gaze_check_pass=%s ===" % str(ok))
	print("\n".join(lines))


func _run_idle_life_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	var ok := true
	_idle_life.set_process(false)
	_idle_life.set_performance_state(IdleLife.PerfState.BASE_IDLE)
	_gaze.call("apply_blink_weight", 1.0)
	var blink: float = _gaze.call("read_shape_weight", "eyeBlinkLeft", "眼睛左")
	ok = ok and blink > 0.95
	lines.append("blink_weight=%.3f" % blink)
	_gaze.call("set_blink_weight", 0.0)
	_gaze.call("process_gaze", 0.0, get_viewport())
	_idle_life.set_performance_state(IdleLife.PerfState.PERFORMANCE)
	for _i in 5:
		_idle_life.call("process_life", 0.05, get_viewport())
	var blink_off: float = _gaze.call("read_shape_weight", "eyeBlinkLeft", "眼睛左")
	ok = ok and blink_off < 0.05
	lines.append("performance_blink_off=%.3f" % blink_off)
	ok = ok and _idle_life.get_performance_state() == IdleLife.PerfState.PERFORMANCE
	_idle_life.set_process(false)
	_idle_life.set_performance_state(IdleLife.PerfState.BASE_IDLE)
	_gaze.call("set_gaze_immediate", Vector2.ZERO)
	_gaze.call("set_autonomous_gaze", Vector2(0.35, 0.0))
	_gaze.call("set_autonomous_active", true)
	_gaze.call("set_manual_gaze_override", false)
	for _f in 10:
		_gaze.call("process_gaze", 0.05, get_viewport())
	var gx: float = (_gaze.call("get_display_gaze") as Vector2).x
	ok = ok and gx > 0.12
	lines.append("autonomous_gaze_x=%.3f" % gx)
	_head.set_enabled(true)
	_head.set_follow_gaze(Vector2(0.35, 0.0))
	_head.process_follow(0.1)
	ok = ok and absf(_head.get_current_yaw_deg()) > 0.2
	lines.append("head_yaw_deg=%.3f" % _head.get_current_yaw_deg())
	lines.append("=== idle_life_check_pass=%s ===" % str(ok))
	print("\n".join(lines))


func _run_idle_life_runtime_check() -> void:
	seed(90210)
	for _i in 3:
		await get_tree().process_frame
	_idle_life.set_process(false)
	_idle_life.set_performance_state(IdleLife.PerfState.BASE_IDLE)
	set_process(false)
	var vp := get_viewport()
	var blink_peaks := 0
	var glance_peaks := 0
	var head_peaks := 0
	var max_head_motion := 0.0
	for _step in 900:
		_idle_life.call("process_life", 0.02, vp)
		var snap: Dictionary = _idle_life.get_debug_snapshot()
		if float(snap.get("blink_weight", 0.0)) > 0.65:
			blink_peaks += 1
		if float(snap.get("look_peak", 0.0)) > 0.12:
			glance_peaks += 1
		var head_motion := maxf(
			absf(float(snap.get("head_yaw_deg", 0.0))),
			absf(float(snap.get("head_pitch_deg", 0.0))),
		)
		max_head_motion = maxf(max_head_motion, head_motion)
		if head_motion > 0.03:
			head_peaks += 1
	var ok := blink_peaks > 3 and glance_peaks > 5 and head_peaks > 3 and max_head_motion > 0.06
	print(
		"runtime_blink_frames=%d runtime_glance_frames=%d runtime_head_frames=%d max_head_motion=%.3f\n=== idle_life_runtime_check_pass=%s ==="
		% [blink_peaks, glance_peaks, head_peaks, max_head_motion, str(ok)]
	)
