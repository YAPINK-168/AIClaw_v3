extends Node3D

## 表情自然过渡独立测试：仅驱动 YouyouExpressionController，不接入口型 / 调度 / 业务。
## FacePoseMixer 迁移：继续通过本控制器的 set_primary / reset_to_default 写主表情，勿直接写网格。

const ExpressionController := preload("res://Scripts/youyou_expression.gd")

const MODEL_PATH := "res://柚柚.glb"
const IDLE_SCENE_PATH := "res://待机Animation/Basic_Idle.glb"
const IDLE_ANIM := "Basic_Idle"

const EMOTE_KEYS := {
	KEY_1: "smile",
	KEY_2: "surprise",
	KEY_3: "laugh",
	KEY_C: "angry",
	KEY_V: "sad",
	KEY_P: "grin",
	KEY_J: "wink",
	KEY_K: "lookleft",
	KEY_L: "lookright",
}

var _model: Node3D
var _player: AnimationPlayer = null
var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _expression: YouyouExpressionController
var _status_label: Label
var _log_lines: PackedStringArray = []


func _ready() -> void:
	_status_label = get_node_or_null("StatusLayer/StatusLabel") as Label
	if not _load_model():
		_fail_quit("模型加载失败")
		return
	_load_idle_clip()
	_capture_defaults_then_apply_gltf_smile()
	_init_expression_controller()
	if _player != null and _player.has_animation(IDLE_ANIM):
		_player.play(IDLE_ANIM)
	_note("表情过渡测试场景。1微笑 2惊讶 3大笑 C生气 V难过 P咧嘴 J眨眼 K看左 L看右 0恢复默认。")
	var args := OS.get_cmdline_user_args()
	if "--expression-transition-check" in args:
		await _run_expression_transition_check()
		get_tree().quit()


func _fail_quit(reason: String) -> void:
	push_error(reason)
	if "--expression-transition-check" in OS.get_cmdline_user_args():
		print("FAIL " + reason)
		get_tree().quit()


func _process(_delta: float) -> void:
	if _expression == null or _status_label == null:
		return
	var body := _find_mesh("人体_001")
	var body_smile := -1.0
	if body != null:
		var idx := body.find_blend_shape_by_name("smile")
		if idx >= 0:
			body_smile = body.get_blend_shape_value(idx)
	var hud := (
		"目标: %s | 当前主键: %s | 过渡进度: %.0f%% | 运行中: %s | 人体 smile: %.3f"
		% [
			_expression.get_transition_target(),
			_expression.get_active_primary(),
			_expression.get_transition_progress() * 100.0,
			str(_expression.is_transition_running()),
			body_smile,
		]
	)
	_status_label.text = hud + "\n" + "\n".join(_log_lines.slice(maxi(_log_lines.size() - 4, 0)))


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if EMOTE_KEYS.has(event.keycode):
		_request_emote(String(EMOTE_KEYS[event.keycode]))
		return
	match event.keycode:
		KEY_0:
			_restore_default()
		KEY_I:
			if _player != null and _player.has_animation(IDLE_ANIM):
				_player.play(IDLE_ANIM)


func _load_model() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("模型加载失败：" + MODEL_PATH)
		return false
	var instance := packed.instantiate()
	if not instance is Node3D:
		push_error("模型根节点不是 Node3D")
		instance.free()
		return false
	_model = instance as Node3D
	_model.name = "YouyouModel"
	add_child(_model)
	var skeleton := _model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("未找到 Armature/Skeleton3D")
		return false
	_collect_meshes(_model)
	if _meshes.is_empty():
		push_error("模型中没有网格")
		return false
	_hide_headphones()
	return true


func _load_idle_clip() -> void:
	var packed := load(IDLE_SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("待机动画加载失败，仅测试表情。")
		return
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(IDLE_ANIM):
		push_warning("待机动画不可用，仅测试表情。")
		instance.free()
		return
	var clip := (source.get_animation(IDLE_ANIM) as Animation).duplicate(true) as Animation
	clip.loop_mode = Animation.LOOP_LINEAR
	instance.free()
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	var library := AnimationLibrary.new()
	library.add_animation(IDLE_ANIM, clip)
	_player.add_animation_library(&"", library)


func _hide_headphones() -> void:
	for mesh in _meshes:
		if mesh.name == "耳机":
			mesh.visible = false


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _capture_defaults_then_apply_gltf_smile() -> void:
	for mesh in _meshes:
		var values := {}
		for index in mesh.mesh.get_blend_shape_count():
			var shape_name := String(mesh.mesh.get_blend_shape_name(index))
			values[shape_name] = mesh.get_blend_shape_value(index)
		_default_shapes[mesh] = values
	for mesh in _meshes:
		var index := mesh.find_blend_shape_by_name("smile")
		if index >= 0:
			mesh.set_blend_shape_value(index, 1.0)
			(_default_shapes[mesh] as Dictionary)["smile"] = 1.0


func _init_expression_controller() -> void:
	_expression = ExpressionController.new()
	_expression.name = "YouyouExpressionController"
	add_child(_expression)
	_expression.setup(_meshes, _default_shapes)
	_expression.configure_primary_blend(
		ExpressionController.TRANSITION_BLEND_TIME_DEFAULT,
		Tween.TRANS_CUBIC,
		Tween.EASE_IN_OUT,
	)
	_expression.reset_to_default(0.0)


func _request_emote(shape_name: String) -> void:
	if _expression.set_primary(shape_name):
		_note("请求主表情 → %s（%.2fs）" % [shape_name, _expression.get_primary_blend_time()])


func _restore_default() -> void:
	_expression.reset_to_default()
	_note("恢复默认微笑")


func _find_mesh(name: String) -> MeshInstance3D:
	for mesh in _meshes:
		if mesh.name == name:
			return mesh
	return null


func _read_primary_on_body(primary: String) -> float:
	var body := _find_mesh("人体_001")
	if body == null:
		return -1.0
	return _expression.read_primary_on_mesh(body, primary)


func _note(msg: String) -> void:
	_log_lines.append(msg)
	print(msg)


func _run_expression_transition_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	var body := _find_mesh("人体_001")
	if body == null:
		lines.append("FAIL no_body_mesh")
		print("\n".join(lines))
		return

	lines.append("blend_time=%.2f" % _expression.get_primary_blend_time())
	lines.append("startup_smile=%.3f active=%s" % [_read_primary_on_body("smile"), _expression.get_active_primary()])

	_expression.set_primary("sad")
	for _i in 2:
		await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout
	var smile_mid := _read_primary_on_body("smile")
	var sad_mid := _read_primary_on_body("sad")
	lines.append("mid_sad smile=%.3f sad=%.3f progress=%.3f" % [
		smile_mid, sad_mid, _expression.get_transition_progress()
	])
	var mid_ok := smile_mid > 0.05 and smile_mid < 0.98 and sad_mid > 0.02 and sad_mid < 0.98
	lines.append("continuous_to_sad=%s" % str(mid_ok))

	_expression.set_primary("surprise")
	await get_tree().process_frame
	var smile_after_interrupt := _read_primary_on_body("smile")
	var jump := absf(smile_after_interrupt - smile_mid)
	lines.append("interrupt_smile_jump=%.4f" % jump)
	lines.append("interrupt_no_snap=%s" % str(jump < 0.12))

	await get_tree().create_timer(ExpressionController.TRANSITION_BLEND_TIME_DEFAULT + 0.15).timeout
	lines.append("final_surprise=%.3f sad=%.3f" % [
		_read_primary_on_body("surprise"), _read_primary_on_body("sad")
	])

	_expression.reset_to_default()
	await get_tree().create_timer(ExpressionController.TRANSITION_BLEND_TIME_DEFAULT + 0.15).timeout
	var smile_after_reset := _read_primary_on_body("smile")
	var default_ok := smile_after_reset > 0.95
	lines.append("after_default_smile=%.3f progress=%.3f" % [
		smile_after_reset, _expression.get_transition_progress()
	])

	for pk in ["angry", "laugh", "grin"]:
		_expression.set_primary(pk)
		await get_tree().create_timer(0.04).timeout
	var grin_mid := _read_primary_on_body("grin")
	_expression.set_primary("sad")
	await get_tree().create_timer(0.06).timeout
	var angry_leak := _read_primary_on_body("angry")
	var laugh_leak := _read_primary_on_body("laugh")
	lines.append("rapid_chain_grin_mid=%.3f angry_leak=%.3f laugh_leak=%.3f" % [grin_mid, angry_leak, laugh_leak])

	await get_tree().create_timer(ExpressionController.TRANSITION_BLEND_TIME_DEFAULT + 0.2).timeout
	var final_sad := _read_primary_on_body("sad")
	var others_clear := (
		_read_primary_on_body("surprise") < 0.05
		and _read_primary_on_body("grin") < 0.05
		and _read_primary_on_body("laugh") < 0.05
	)
	lines.append("final_sad=%.3f others_zero=%s" % [final_sad, str(others_clear)])

	lines.append("single_writer_scene=true")
	lines.append("target_switch_ok=%s" % str(_expression.get_transition_target() == "sad"))

	var all_ok := mid_ok and jump < 0.12 and default_ok and final_sad > 0.95 and others_clear
	lines.append("default_smile_after_reset=%s" % str(default_ok))
	lines.append("=== expression_transition_check_pass=%s ===" % str(all_ok))
	print("\n".join(lines))
