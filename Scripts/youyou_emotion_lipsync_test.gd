extends Node3D

const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")
const ActionTimeline := preload("res://Scripts/youyou_action_lipsync_timeline.gd")

const MODEL_PATH := "res://柚柚.glb"
const IDLE_SCENE_PATH := "res://待机Animation/Basic_Idle.glb"
const IDLE_ANIM := "Basic_Idle"
const PATCH_BIN_PATH := "res://youyou_assets/expressions_split/youyou_blendshapes.bin"
const VOICE_DIR := "res://配音"
const FACE_MESH_NAMES: PackedStringArray = [
	"人体_001", "眉毛", "眼睛左", "眼睛右", "睫毛", "上牙", "下牙", "舌头",
]
const FACE_SHAPE_PROBE: PackedStringArray = [
	"smile", "Eyes_smile", "Mouth_smile", "A", "E", "i", "o", "u",
]

var _model: Node3D
var _player: AnimationPlayer = null
var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _mixer: Node

var _patch_loaded := false
var _patch_apply_result: Dictionary = {}
var _patch_summary_printed := false

var _ui_layer: CanvasLayer
var _debug_label: Label
var _note_label: Label
var _patch_label: Label
var _slider_mouth: HSlider
var _slider_viseme: HSlider
var _slider_blend: HSlider
var _slider_hold: HSlider

var _auto_playing := false
var _auto_token := 0

var _timeline: Node
var _timeline_status_label: Label
var _timeline_action_option: OptionButton
var _timeline_catalog_filter: OptionButton
var _timeline_resource_label: Label
var _timeline_audio_option: OptionButton
var _timeline_audio_label: Label
var _voice_mp3_paths: PackedStringArray = []
var _timeline_accept_option: OptionButton
var _timeline_emotion_option: OptionButton
var _slider_audio_speed: HSlider
var _slider_action_speed: HSlider
var _slider_audio_offset: HSlider
var _slider_emotion_lead: HSlider
var _slider_emotion_blend: HSlider
var _slider_mouth_release: HSlider
var _slider_idle_return: HSlider
var _slider_pre_idle: HSlider
var _slider_post_idle: HSlider
var _timeline_notes: LineEdit

func _ready() -> void:
	if not _load_model():
		return
	var args := OS.get_cmdline_user_args()
	if "--face-baseline-all" in args:
		await _run_face_baseline_sequence()
		get_tree().quit()
		return
	var baseline := _parse_face_baseline_arg(args)
	if baseline != "":
		await _run_face_baseline(baseline)
		get_tree().quit()
		return
	if "--split-patch-check" in args:
		_apply_split_patch()
		await _run_patch_only_check()
		get_tree().quit()
		return
	if "--emotion-lipsync-check" in args:
		_apply_split_patch()
		_capture_defaults_baseline()
		_mixer = FacePresenter.new()
		add_child(_mixer)
		_mixer.setup(_meshes, _default_shapes)
		_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
		_mixer.apply_approved_coefficients()
		await _run_automation_check()
		get_tree().quit()
		return
	if "--action-lipsync-timeline-check" in args:
		_apply_split_patch()
		_load_idle_clip()
		_capture_defaults_baseline()
		_mixer = FacePresenter.new()
		add_child(_mixer)
		_mixer.setup(_meshes, _default_shapes)
		_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
		_mixer.apply_approved_coefficients()
		_init_action_timeline()
		await _run_action_timeline_check()
		get_tree().quit()
		return
	if "--event-clip-compat-check" in args:
		_apply_split_patch()
		_load_idle_clip()
		_capture_defaults_baseline()
		_mixer = FacePresenter.new()
		add_child(_mixer)
		_mixer.setup(_meshes, _default_shapes)
		_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
		_mixer.apply_approved_coefficients()
		_init_action_timeline()
		await _run_event_clip_compat_check()
		get_tree().quit()
		return
	if "--event-catalog-check" in args:
		await _run_event_catalog_registry_check()
		get_tree().quit()
		return
	_apply_split_patch()
	_load_idle_clip()
	_capture_defaults_baseline()
	_mixer = FacePresenter.new()
	_mixer.name = "YouyouFacePresenter"
	add_child(_mixer)
	_mixer.setup(_meshes, _default_shapes)
	_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
	_mixer.apply_approved_coefficients()
	if _mixer.is_emotion_available("smile"):
		_mixer.set_emotion("smile", 0.0)
	_init_action_timeline()
	_build_ui()
	_update_patch_ui()
	_sync_timeline_from_ui()
	if _player != null and _player.has_animation(IDLE_ANIM):
		_player.play(IDLE_ANIM)


func _process(_delta: float) -> void:
	if _mixer == null or _debug_label == null:
		return
	var lines: PackedStringArray = []
	if _patch_label != null:
		lines.append(_patch_label.text)
	if _timeline != null and _timeline_status_label != null:
		_timeline_status_label.text = "\n".join(_timeline.call("build_status_lines"))
	lines.append_array(_mixer.call("sample_debug_lines", 10))
	_debug_label.text = "\n".join(lines)


func _parse_face_baseline_arg(args: PackedStringArray) -> String:
	for arg in args:
		var text := String(arg)
		if text.begins_with("--face-baseline="):
			return text.substr("--face-baseline=".length()).strip_edges().to_upper()
	return ""


func _run_face_baseline_sequence() -> void:
	await _run_face_baseline("A")
	_apply_split_patch()
	_zero_all_blend_shapes()
	await _run_face_baseline("B")
	_zero_all_blend_shapes()
	_set_shape_all_meshes("Eyes_smile", 1.0)
	await _run_face_baseline("C")
	_zero_all_blend_shapes()
	_set_shape_all_meshes("Mouth_smile", 1.0)
	await _run_face_baseline("D")
	_zero_all_blend_shapes()
	_capture_defaults_baseline()
	_mixer = FacePresenter.new()
	add_child(_mixer)
	_mixer.setup(_meshes, _default_shapes)
	_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
	_mixer.set_emotion("smile", 0.0)
	await _run_face_baseline("E")


func _run_face_baseline(mode: String) -> void:
	for _i in 2:
		await get_tree().process_frame
	print("===== face_baseline_%s =====" % mode)
	match mode:
		"A":
			pass
		"B":
			_apply_split_patch()
			_zero_all_blend_shapes()
		"C":
			_apply_split_patch()
			_zero_all_blend_shapes()
			_set_shape_all_meshes("Eyes_smile", 1.0)
		"D":
			_apply_split_patch()
			_zero_all_blend_shapes()
			_set_shape_all_meshes("Mouth_smile", 1.0)
		"E":
			_apply_split_patch()
			_capture_defaults_baseline()
			_mixer = FacePresenter.new()
			add_child(_mixer)
			_mixer.setup(_meshes, _default_shapes)
			_mixer.call("configure_patch_readiness", _patch_apply_result.get("diagnostics", []))
			_mixer.set_emotion("smile", 0.0)
		_:
			push_error("未知 face baseline 模式：" + mode)
			return
	for mesh_name in FACE_MESH_NAMES:
		var mesh := _find_mesh_by_name(mesh_name)
		if mesh == null:
			print("  mesh_missing name=%s" % mesh_name)
			continue
		_print_mesh_baseline_line(mode, mesh)
	print("=== face_baseline_%s_done ===" % mode)


func _find_mesh_by_name(mesh_name: String) -> MeshInstance3D:
	for mesh in _meshes:
		if mesh.name == mesh_name:
			return mesh
	return null


func _zero_all_blend_shapes() -> void:
	for mesh in _meshes:
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_blend_shape_count():
			mesh.set_blend_shape_value(i, 0.0)


func _set_shape_all_meshes(shape_name: String, value: float) -> void:
	for mesh in _meshes:
		var idx := mesh.find_blend_shape_by_name(shape_name)
		if idx >= 0:
			mesh.set_blend_shape_value(idx, value)


func _print_mesh_baseline_line(mode: String, mesh: MeshInstance3D) -> void:
	var am := mesh.mesh as ArrayMesh
	var weights := {}
	for shape_name in FACE_SHAPE_PROBE:
		var idx := mesh.find_blend_shape_by_name(shape_name)
		if idx >= 0:
			weights[shape_name] = mesh.get_blend_shape_value(idx)
	var surf0 := am.surface_get_arrays(0) if am.get_surface_count() > 0 else []
	var vert_n := 0
	var idx_n := 0
	var bone_n := 0
	if not surf0.is_empty():
		if surf0[Mesh.ARRAY_VERTEX] != null:
			vert_n = (surf0[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if surf0[Mesh.ARRAY_INDEX] != null:
			idx_n = (surf0[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
		if surf0[Mesh.ARRAY_BONES] != null:
			var bones_arr: Variant = surf0[Mesh.ARRAY_BONES]
			if bones_arr is PackedByteArray:
				bone_n = (bones_arr as PackedByteArray).size()
			elif bones_arr is PackedInt32Array:
				bone_n = (bones_arr as PackedInt32Array).size()
	print(
		"  mode=%s node=%s path=%s type=%s surfaces=%d verts=%d idx=%d bones_bytes=%d shapes=%d skin=%s weights=%s"
		% [
			mode,
			mesh.name,
			str(mesh.get_path()),
			am.get_class(),
			am.get_surface_count(),
			vert_n,
			idx_n,
			bone_n,
			am.get_blend_shape_count(),
			mesh.skin != null,
			var_to_str(weights),
		]
	)


func _apply_split_patch() -> bool:
	_patch_loaded = FileAccess.file_exists(PATCH_BIN_PATH)
	_patch_apply_result = FacePresenter.apply_split_patch_to_model(_model)
	if not _patch_summary_printed:
		print("[split-patch]\n", String(_patch_apply_result.get("summary", "")))
		for entry in _patch_apply_result.get("diagnostics", []):
			print(_format_diagnostic_line(entry))
		_patch_summary_printed = true
	return bool(_patch_apply_result.get("ok", false))


func _format_diagnostic_line(entry: Variant) -> String:
	if not (entry is Dictionary):
		return str(entry)
	var d: Dictionary = entry
	return (
		"  mesh=%s found=%s node=%s method=%s patch_v=%s godot_v=%s unique_v=%s "
		+ "mode=%s matched=%s/%s ratio=%.1f%% avg_err=%.5f max_err=%.5f added=%s pass=%s | %s"
	) % [
		d.get("patch_name", "?"),
		d.get("found", false),
		d.get("node_name", ""),
		d.get("match_method", ""),
		d.get("patch_vertex_count", 0),
		d.get("godot_surface_vertex_count", 0),
		d.get("godot_unique_vertex_count", 0),
		d.get("space_mode", ""),
		d.get("matched_vertices", 0),
		d.get("total_vertices", 0),
		float(d.get("match_ratio", 0.0)) * 100.0,
		float(d.get("avg_position_error", -1.0)),
		float(d.get("max_position_error", -1.0)),
		d.get("shapes_added", 0),
		d.get("passed", false),
		d.get("result_message", d.get("failure_reason", "")),
	]


func _update_patch_ui() -> void:
	if _patch_label == null:
		return
	var ok := bool(_patch_apply_result.get("ok", false))
	var sc := int(_patch_apply_result.get("success_count", 0))
	var tc := int(_patch_apply_result.get("total_count", 0))
	var status := "完整接入" if ok else ("部分成功" if sc > 0 else "失败")
	_patch_label.text = "补丁: %s | 网格 %d/%d | bin=%s" % [
		status, sc, tc, "已加载" if _patch_loaded else "缺失"
	]
	if _note_label != null:
		_note_label.text = (
			"拆分表情 + 口型测试 | Eyes_*/Mouth_* 与 A/E/I/O/U 叠加 | "
			+ ("补丁就绪" if ok else "补丁未完整就绪，部分情绪不可用")
		)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "TestUI"
	add_child(_ui_layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	_ui_layer.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 720)
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.text = "情绪+口型组合测试"
	root.add_child(_note_label)

	_patch_label = Label.new()
	_patch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_patch_label)

	var emo_row := HBoxContainer.new()
	emo_row.add_theme_constant_override("separation", 4)
	var emo_title := Label.new()
	emo_title.text = "情绪"
	root.add_child(emo_title)
	root.add_child(emo_row)

	if _mixer != null:
		for eid in _mixer.get_emotion_ids():
			var btn := Button.new()
			var ready_tag := "" if _mixer.is_emotion_available(eid) else " [未就绪]"
			btn.text = _mixer.get_emotion_label(eid) + ready_tag
			btn.disabled = not _mixer.is_emotion_available(eid)
			btn.pressed.connect(_on_emotion_pressed.bind(eid))
			emo_row.add_child(btn)

	var vis_row := HBoxContainer.new()
	vis_row.add_theme_constant_override("separation", 4)
	var vis_label := Label.new()
	vis_label.text = "口型"
	root.add_child(vis_label)
	root.add_child(vis_row)
	for vid in ["a", "e", "i", "o", "u"]:
		var btn := Button.new()
		btn.text = vid.to_upper()
		btn.pressed.connect(_on_viseme_pressed.bind(vid))
		vis_row.add_child(btn)
	var clear_btn := Button.new()
	clear_btn.text = "清除口型"
	clear_btn.pressed.connect(_on_clear_viseme)
	vis_row.add_child(clear_btn)

	var seq_row := HBoxContainer.new()
	seq_row.add_theme_constant_override("separation", 4)
	var play_btn := Button.new()
	play_btn.text = "播放 A→E→I→O→U"
	play_btn.pressed.connect(_on_play_sequence)
	seq_row.add_child(play_btn)
	var stop_btn := Button.new()
	stop_btn.text = "停止播放"
	stop_btn.pressed.connect(_on_stop_sequence)
	seq_row.add_child(stop_btn)
	var reset_btn := Button.new()
	reset_btn.text = "重置表情"
	reset_btn.pressed.connect(_on_reset)
	seq_row.add_child(reset_btn)
	root.add_child(seq_row)

	if _mixer != null:
		_slider_mouth = _add_slider(root, "情绪嘴形系数", 0.0, 1.0, FacePresenter.APPROVED_MOUTH_EMOTION_COEF, _on_coef_changed)
		_slider_viseme = _add_slider(root, "口型系数", 0.0, 1.0, FacePresenter.APPROVED_VISEME_COEF, _on_coef_changed)
		_slider_blend = _add_slider(root, "过渡(秒)", 0.0, 1.0, FacePresenter.APPROVED_BLEND_TIME, _on_coef_changed)
	_slider_hold = _add_slider(root, "自动播放保持(秒)", 0.1, 2.0, 0.6, func(_v): pass)

	_build_action_timeline_ui(root)

	_debug_label = Label.new()
	_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_debug_label)


func _add_slider(parent: VBoxContainer, title: String, min_v: float, max_v: float, default_v: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 140
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = default_v
	slider.value_changed.connect(cb)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _sync_coefficients_from_sliders() -> void:
	if _mixer == null:
		return
	_mixer.set_coefficients(_slider_mouth.value, _slider_viseme.value, _slider_blend.value)


func _on_coef_changed(_v: float) -> void:
	if _mixer == null:
		return
	_sync_coefficients_from_sliders()
	if _mixer.get_active_viseme() != "":
		_mixer.set_viseme(_mixer.get_active_viseme())
	else:
		_mixer.set_emotion(_mixer.get_active_emotion())


func _on_emotion_pressed(eid: String) -> void:
	if _mixer == null:
		return
	_stop_sequence()
	_sync_coefficients_from_sliders()
	_mixer.clear_viseme(0.0)
	_mixer.set_emotion(eid)


func _on_viseme_pressed(vid: String) -> void:
	if _mixer == null:
		return
	_sync_coefficients_from_sliders()
	_mixer.set_viseme(vid)


func _on_clear_viseme() -> void:
	if _mixer == null:
		return
	_sync_coefficients_from_sliders()
	_mixer.clear_viseme()


func _on_reset() -> void:
	if _mixer == null:
		return
	_stop_sequence()
	_sync_coefficients_from_sliders()
	_mixer.reset_all()


func _on_play_sequence() -> void:
	if _mixer == null:
		return
	_sync_coefficients_from_sliders()
	_auto_token += 1
	var token := _auto_token
	_auto_playing = true
	_run_sequence(token)


func _on_stop_sequence() -> void:
	_auto_playing = false
	_auto_token += 1


func _stop_sequence() -> void:
	_auto_playing = false
	_auto_token += 1


func _run_sequence(token: int) -> void:
	await _sequence_worker(token)


func _sequence_worker(token: int) -> void:
	for vid in ["a", "e", "i", "o", "u"]:
		if token != _auto_token or not _auto_playing:
			return
		_mixer.set_viseme(vid)
		await get_tree().create_timer(_slider_hold.value).timeout
	if token != _auto_token:
		return
	_mixer.clear_viseme()
	_auto_playing = false


func _load_model() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("模型加载失败")
		return false
	var instance := packed.instantiate() as Node3D
	_model = instance
	_model.name = "YouyouModel"
	add_child(_model)
	_collect_meshes(_model)
	if _meshes.is_empty():
		return false
	for mesh in _meshes:
		if mesh.name == "耳机":
			mesh.visible = false
	return true


func _load_idle_clip() -> void:
	var packed := load(IDLE_SCENE_PATH) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(IDLE_ANIM):
		instance.free()
		return
	var clip := (source.get_animation(IDLE_ANIM) as Animation).duplicate(true) as Animation
	clip.loop_mode = Animation.LOOP_LINEAR
	instance.free()
	_player = AnimationPlayer.new()
	_model.add_child(_player)
	var lib := AnimationLibrary.new()
	lib.add_animation(IDLE_ANIM, clip)
	_player.add_animation_library(&"", lib)
	if not _player.animation_finished.is_connected(_on_test_animation_finished):
		_player.animation_finished.connect(_on_test_animation_finished)


func _init_action_timeline() -> void:
	if _player == null or _mixer == null:
		return
	if _timeline != null:
		return
	_timeline = ActionTimeline.new()
	_timeline.name = "ActionLipsyncTimeline"
	add_child(_timeline)
	_timeline.call("setup", self, _player, _mixer, IDLE_ANIM)


func _on_test_animation_finished(anim_name: StringName) -> void:
	if _timeline != null:
		_timeline.call("notify_animation_finished", anim_name)


func _build_action_timeline_ui(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "动作 + 绑定配音 + 表情时间轴（已验收目录 + 事件测试登记）"
	parent.add_child(title)

	_timeline_resource_label = Label.new()
	_timeline_resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_timeline_resource_label)

	_timeline_status_label = Label.new()
	_timeline_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_timeline_status_label)

	var filter_row := HBoxContainer.new()
	var filter_lbl := Label.new()
	filter_lbl.text = "目录筛选"
	filter_lbl.custom_minimum_size.x = 80
	filter_row.add_child(filter_lbl)
	_timeline_catalog_filter = OptionButton.new()
	_timeline_catalog_filter.add_item("全部（已验收 + 事件）", 0)
	_timeline_catalog_filter.set_item_metadata(0, ActionTimeline.CATALOG_FILTER_ALL)
	_timeline_catalog_filter.add_item("已验收轻待机/招揽", 1)
	_timeline_catalog_filter.set_item_metadata(1, ActionTimeline.CATALOG_FILTER_APPROVED)
	_timeline_catalog_filter.add_item("事件测试资源", 2)
	_timeline_catalog_filter.set_item_metadata(2, ActionTimeline.CATALOG_FILTER_EVENT)
	filter_row.add_child(_timeline_catalog_filter)
	parent.add_child(filter_row)

	var action_row := HBoxContainer.new()
	var action_lbl := Label.new()
	action_lbl.text = "动作"
	action_lbl.custom_minimum_size.x = 80
	action_row.add_child(action_lbl)
	_timeline_action_option = OptionButton.new()
	_rebuild_timeline_action_options()
	action_row.add_child(_timeline_action_option)
	parent.add_child(action_row)

	_voice_mp3_paths = _list_voice_mp3_paths()
	var audio_row := HBoxContainer.new()
	var audio_lbl := Label.new()
	audio_lbl.text = "选择配音"
	audio_lbl.custom_minimum_size.x = 80
	audio_row.add_child(audio_lbl)
	_timeline_audio_option = OptionButton.new()
	_timeline_audio_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_audio_option.add_item("（不选配音 / 仅动作）")
	_timeline_audio_option.set_item_metadata(0, "")
	for vpath in _voice_mp3_paths:
		_timeline_audio_option.add_item(vpath.get_file())
		_timeline_audio_option.set_item_metadata(_timeline_audio_option.item_count - 1, vpath)
	audio_row.add_child(_timeline_audio_option)
	parent.add_child(audio_row)

	_timeline_audio_label = Label.new()
	_timeline_audio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_timeline_audio_label)

	var emo_tl_row := HBoxContainer.new()
	var emo_tl_lbl := Label.new()
	emo_tl_lbl.text = "目标情绪"
	emo_tl_lbl.custom_minimum_size.x = 80
	emo_tl_row.add_child(emo_tl_lbl)
	_timeline_emotion_option = OptionButton.new()
	if _mixer != null:
		for eid in _mixer.get_emotion_ids():
			if _mixer.is_emotion_available(eid):
				_timeline_emotion_option.add_item(_mixer.get_emotion_label(eid))
				_timeline_emotion_option.set_item_metadata(
					_timeline_emotion_option.item_count - 1,
					eid,
				)
		for i in _timeline_emotion_option.item_count:
			if String(_timeline_emotion_option.get_item_metadata(i)) == "laugh":
				_timeline_emotion_option.select(i)
				break
	emo_tl_row.add_child(_timeline_emotion_option)
	parent.add_child(emo_tl_row)

	var ctrl_row := HBoxContainer.new()
	var tl_play := Button.new()
	tl_play.text = "播放动作轴"
	tl_play.pressed.connect(_on_timeline_play)
	ctrl_row.add_child(tl_play)
	var tl_stop := Button.new()
	tl_stop.text = "停止"
	tl_stop.pressed.connect(_on_timeline_stop)
	ctrl_row.add_child(tl_stop)
	var tl_replay := Button.new()
	tl_replay.text = "重播"
	tl_replay.pressed.connect(_on_timeline_replay)
	ctrl_row.add_child(tl_replay)
	var tl_voice := Button.new()
	tl_voice.text = "播配音对口型"
	tl_voice.pressed.connect(_on_timeline_play_voice)
	ctrl_row.add_child(tl_voice)
	parent.add_child(ctrl_row)

	_slider_pre_idle = _add_slider(parent, "前置待机(秒)", 0.0, 3.0, ActionTimeline.DEFAULT_PRE_POST_IDLE, _on_timeline_param_changed)
	_slider_post_idle = _add_slider(parent, "后置待机(秒)", 0.0, 3.0, ActionTimeline.DEFAULT_PRE_POST_IDLE, _on_timeline_param_changed)
	_slider_audio_offset = _add_slider(parent, "配音启动偏移(秒)", 0.0, 6.0, ActionTimeline.DEFAULT_PRE_POST_IDLE, _on_timeline_param_changed)
	_slider_audio_speed = _add_slider(parent, "配音速率", 0.85, 1.15, 1.0, _on_timeline_param_changed)
	_slider_action_speed = _add_slider(parent, "动作速率", 0.85, 1.15, 1.0, _on_timeline_param_changed)
	_slider_emotion_lead = _add_slider(parent, "表情提前量(秒)", 0.0, 2.0, 0.35, _on_timeline_param_changed)
	_slider_emotion_blend = _add_slider(parent, "表情渐变(秒)", 0.05, 2.0, 0.40, _on_timeline_param_changed)
	_slider_mouth_release = _add_slider(parent, "口型退出(秒)", 0.0, 1.0, 0.15, _on_timeline_param_changed)
	_slider_idle_return = _add_slider(parent, "待机表情恢复(秒)", 0.05, 2.0, 0.50, _on_timeline_param_changed)

	var accept_row := HBoxContainer.new()
	var accept_lbl := Label.new()
	accept_lbl.text = "验收状态"
	accept_lbl.custom_minimum_size.x = 80
	accept_row.add_child(accept_lbl)
	_timeline_accept_option = OptionButton.new()
	_timeline_accept_option.add_item("draft")
	_timeline_accept_option.add_item("pending")
	_timeline_accept_option.add_item("approved")
	_timeline_accept_option.add_item("rejected")
	accept_row.add_child(_timeline_accept_option)
	parent.add_child(accept_row)

	_timeline_notes = LineEdit.new()
	_timeline_notes.placeholder_text = "备注（人工验收说明）"
	parent.add_child(_timeline_notes)

	var save_row := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "保存 JSON (user://)"
	save_btn.pressed.connect(_on_timeline_save)
	save_row.add_child(save_btn)
	var export_btn := Button.new()
	export_btn.text = "导出 JSON 到剪贴板"
	export_btn.pressed.connect(_on_timeline_export_clipboard)
	save_row.add_child(export_btn)
	var csv_btn := Button.new()
	csv_btn.text = "导出 CSV 到剪贴板"
	csv_btn.pressed.connect(_on_timeline_export_csv)
	save_row.add_child(csv_btn)
	parent.add_child(save_row)

	if _timeline_catalog_filter != null:
		_timeline_catalog_filter.item_selected.connect(func(_i: int) -> void:
			_rebuild_timeline_action_options()
			_sync_timeline_from_ui()
		)
	if _timeline_action_option.item_count > 0:
		_timeline_action_option.item_selected.connect(_on_timeline_action_selected)
	if _timeline_audio_option != null:
		_timeline_audio_option.item_selected.connect(_on_timeline_audio_selected)
	if _timeline_emotion_option != null:
		_timeline_emotion_option.item_selected.connect(func(_i: int) -> void: _push_timeline_params())


func _list_voice_mp3_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	for fn in DirAccess.get_files_at(VOICE_DIR):
		if fn.ends_with(".mp3"):
			paths.append(VOICE_DIR.path_join(fn))
	paths.sort()
	return paths


func _timeline_catalog_filter_id() -> String:
	if _timeline_catalog_filter == null or _timeline_catalog_filter.item_count == 0:
		return ActionTimeline.CATALOG_FILTER_ALL
	return String(_timeline_catalog_filter.get_item_metadata(_timeline_catalog_filter.selected))


func _rebuild_timeline_action_options() -> void:
	if _timeline_action_option == null or _timeline == null:
		return
	var prev := ""
	if _timeline_action_option.item_count > 0:
		prev = _timeline_action_option.get_item_text(_timeline_action_option.selected)
	_timeline_action_option.clear()
	var filter_id := _timeline_catalog_filter_id()
	for aid in _timeline.call("get_action_ids", filter_id):
		_timeline_action_option.add_item(String(aid))
	if _timeline_action_option.item_count == 0:
		return
	var pick := 0
	if prev != "":
		for i in _timeline_action_option.item_count:
			if _timeline_action_option.get_item_text(i) == prev:
				pick = i
				break
	_timeline_action_option.select(pick)


func _refresh_timeline_resource_label() -> void:
	if _timeline_resource_label == null or _timeline == null:
		return
	var idx := _timeline_action_option.selected if _timeline_action_option != null else 0
	if _timeline_action_option == null or _timeline_action_option.item_count == 0:
		_timeline_resource_label.text = "—"
		return
	var aid := _timeline_action_option.get_item_text(idx)
	_timeline_resource_label.text = String(_timeline.call("get_resource_kind_label", aid))


func _sync_timeline_from_ui() -> void:
	if _timeline == null:
		return
	var idx := _timeline_action_option.selected if _timeline_action_option != null else 0
	if _timeline_action_option != null and _timeline_action_option.item_count > 0:
		var aid := _timeline_action_option.get_item_text(idx)
		_timeline.call("select_action", aid)
		_pull_timeline_params_to_ui()
	_refresh_timeline_resource_label()
	_refresh_timeline_audio_label()
	_update_accept_option_for_current_resource()


func _pull_timeline_params_to_ui() -> void:
	if _timeline == null:
		return
	var p: Dictionary = _timeline.call("get_timeline_params")
	if _slider_pre_idle:
		_slider_pre_idle.value = float(p.get("pre_idle_duration", ActionTimeline.DEFAULT_PRE_POST_IDLE))
	if _slider_post_idle:
		_slider_post_idle.value = float(p.get("post_idle_duration", ActionTimeline.DEFAULT_PRE_POST_IDLE))
	if _slider_audio_offset:
		_slider_audio_offset.value = float(p.get("audio_start_offset", ActionTimeline.DEFAULT_PRE_POST_IDLE))
	if _slider_audio_speed:
		_slider_audio_speed.value = float(p.get("audio_speed", 1.0))
	if _slider_action_speed:
		_slider_action_speed.value = float(p.get("action_speed", 1.0))
	if _slider_emotion_lead:
		_slider_emotion_lead.value = float(p.get("emotion_lead_time", 0.35))
	if _slider_emotion_blend:
		_slider_emotion_blend.value = float(p.get("emotion_blend_duration", 0.40))
	if _slider_mouth_release:
		_slider_mouth_release.value = float(p.get("mouth_release_duration", 0.15))
	if _slider_idle_return:
		_slider_idle_return.value = float(p.get("idle_expression_return_duration", 0.50))
	if _slider_mouth:
		_slider_mouth.value = float(p.get("mouth_emotion_weight", FacePresenter.APPROVED_MOUTH_EMOTION_COEF))
	if _slider_viseme:
		_slider_viseme.value = float(p.get("viseme_weight", FacePresenter.APPROVED_VISEME_COEF))
	if _timeline_emotion_option != null:
		var eid := String(p.get("emotion_id", "smile"))
		for i in _timeline_emotion_option.item_count:
			if String(_timeline_emotion_option.get_item_metadata(i)) == eid:
				_timeline_emotion_option.select(i)
				break
	if _timeline_accept_option != null:
		var status := String(p.get("manual_acceptance_status", "draft"))
		for i in _timeline_accept_option.item_count:
			if _timeline_accept_option.get_item_text(i) == status:
				_timeline_accept_option.select(i)
				break
	if _timeline_notes:
		_timeline_notes.text = String(p.get("notes", ""))
	_sync_coefficients_from_sliders()
	_sync_audio_option_from_timeline()
	_update_accept_option_for_current_resource()


func _apply_timeline_audio_from_option() -> void:
	if _timeline == null or _timeline_audio_option == null:
		return
	var path := String(_timeline_audio_option.get_item_metadata(_timeline_audio_option.selected))
	_timeline.call("set_audio_resource", path)


func _sync_audio_option_from_timeline() -> void:
	if _timeline_audio_option == null or _timeline == null:
		return
	var path := String(_timeline.call("get_timeline_params").get("audio_path", ""))
	var pick := 0
	for i in _timeline_audio_option.item_count:
		if String(_timeline_audio_option.get_item_metadata(i)) == path:
			pick = i
			break
	_timeline_audio_option.set_block_signals(true)
	_timeline_audio_option.select(pick)
	_timeline_audio_option.set_block_signals(false)


func _on_timeline_audio_selected(_idx: int) -> void:
	_apply_timeline_audio_from_option()
	_push_timeline_params()
	_refresh_timeline_audio_label()


func _update_accept_option_for_current_resource() -> void:
	if _timeline == null or _timeline_accept_option == null or _timeline_action_option == null:
		return
	if _timeline_action_option.item_count == 0:
		return
	var aid := _timeline_action_option.get_item_text(_timeline_action_option.selected)
	var is_event := String(_timeline.call("get_resource_kind", aid)) == ActionTimeline.RESOURCE_KIND_EVENT
	for i in _timeline_accept_option.item_count:
		var txt := _timeline_accept_option.get_item_text(i)
		var disabled := is_event and (txt == "approved" or txt == "rejected")
		_timeline_accept_option.set_item_disabled(i, disabled)
	if is_event:
		var cur := _timeline_accept_option.get_item_text(_timeline_accept_option.selected)
		if cur == "approved" or cur == "rejected":
			for i in _timeline_accept_option.item_count:
				if _timeline_accept_option.get_item_text(i) == "draft":
					_timeline_accept_option.select(i)
					break


func _refresh_timeline_audio_label() -> void:
	if _timeline_audio_label == null or _timeline == null:
		return
	var path := String(_timeline.call("get_timeline_params").get("audio_path", ""))
	if path == "":
		_timeline_audio_label.text = "当前未选配音：可下拉选择 mp3；「播放动作轴」按偏移同步口型，或点「播配音对口型」立即动嘴"
		return
	var exists := FileAccess.file_exists(path)
	var dur := float(_timeline.call("get_audio_source_duration"))
	_timeline_audio_label.text = "当前: %s%s | 原长 %.2fs | 播放时将驱动口型（测试场专用轮换 viseme）" % [
		path,
		" [文件缺失]" if not exists else "",
		dur,
	]


func _push_timeline_params() -> void:
	if _timeline == null:
		return
	var status := "draft"
	if _timeline_accept_option != null:
		status = _timeline_accept_option.get_item_text(_timeline_accept_option.selected)
	if _timeline_action_option != null and _timeline_action_option.item_count > 0:
		var aid := _timeline_action_option.get_item_text(_timeline_action_option.selected)
		if String(_timeline.call("get_resource_kind", aid)) == ActionTimeline.RESOURCE_KIND_EVENT:
			if status != "draft" and status != "pending":
				status = "draft"
	_timeline.call(
		"set_pre_post_idle",
		_slider_pre_idle.value if _slider_pre_idle else ActionTimeline.DEFAULT_PRE_POST_IDLE,
		_slider_post_idle.value if _slider_post_idle else ActionTimeline.DEFAULT_PRE_POST_IDLE,
	)
	var emotion_id := "laugh"
	if _timeline_emotion_option != null and _timeline_emotion_option.item_count > 0:
		emotion_id = String(_timeline_emotion_option.get_item_metadata(_timeline_emotion_option.selected))
	_timeline.call(
		"set_timeline_params",
		{
			"emotion_id": emotion_id,
			"audio_start_offset": _slider_audio_offset.value if _slider_audio_offset else ActionTimeline.DEFAULT_PRE_POST_IDLE,
			"audio_speed": _slider_audio_speed.value if _slider_audio_speed else 1.0,
			"action_speed": _slider_action_speed.value if _slider_action_speed else 1.0,
			"emotion_lead_time": _slider_emotion_lead.value if _slider_emotion_lead else 0.35,
			"emotion_blend_duration": _slider_emotion_blend.value if _slider_emotion_blend else 0.40,
			"mouth_release_duration": _slider_mouth_release.value if _slider_mouth_release else 0.15,
			"idle_expression_return_duration": _slider_idle_return.value if _slider_idle_return else 0.50,
			"mouth_emotion_weight": _slider_mouth.value if _slider_mouth else FacePresenter.APPROVED_MOUTH_EMOTION_COEF,
			"viseme_weight": _slider_viseme.value if _slider_viseme else FacePresenter.APPROVED_VISEME_COEF,
			"manual_acceptance_status": status,
			"notes": _timeline_notes.text if _timeline_notes else "",
		},
	)


func _on_timeline_param_changed(_v: float) -> void:
	_sync_coefficients_from_sliders()
	_push_timeline_params()


func _on_timeline_action_selected(_idx: int) -> void:
	_sync_timeline_from_ui()


func _on_timeline_play() -> void:
	_stop_sequence()
	_apply_timeline_audio_from_option()
	_push_timeline_params()
	if _timeline != null:
		_timeline.call("play")


func _on_timeline_play_voice() -> void:
	_stop_sequence()
	_apply_timeline_audio_from_option()
	_push_timeline_params()
	if _timeline != null:
		_timeline.call("play_voice_with_viseme")


func _on_timeline_stop() -> void:
	if _timeline != null:
		_timeline.call("stop")


func _on_timeline_replay() -> void:
	_on_timeline_play()


func _on_timeline_save() -> void:
	if _timeline == null:
		return
	_push_timeline_params()
	var prefix := "youyou_action_lipsync"
	if _timeline_action_option != null and _timeline_action_option.item_count > 0:
		var aid := _timeline_action_option.get_item_text(_timeline_action_option.selected)
		if String(_timeline.call("get_resource_kind", aid)) == ActionTimeline.RESOURCE_KIND_EVENT:
			prefix = "youyou_event_action_lipsync_draft"
	var path := "user://%s_%s.json" % [prefix, Time.get_unix_time_from_system()]
	var err: Error = _timeline.call("save_params_to_path", path)
	if err == OK:
		print("action_lipsync_saved path=%s" % path)
	else:
		push_error("保存失败 err=%s" % str(err))


func _on_timeline_export_clipboard() -> void:
	if _timeline == null:
		return
	_push_timeline_params()
	DisplayServer.clipboard_set(_timeline.call("export_params_json"))


func _on_timeline_export_csv() -> void:
	if _timeline == null:
		return
	_push_timeline_params()
	var p: Dictionary = _timeline.call("get_timeline_params")
	var keys := p.keys()
	keys.sort()
	var header := ",".join(keys)
	var values: PackedStringArray = []
	for k in keys:
		values.append(str(p[k]))
	DisplayServer.clipboard_set(header + "\n" + ",".join(values))


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _capture_defaults_baseline() -> void:
	_default_shapes = FacePresenter.capture_zero_baseline(_meshes)


func _run_patch_only_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	lines.append("patch_ok=%s" % str(_patch_apply_result.get("ok", false)))
	lines.append("patch_meshes=%d/%d" % [
		int(_patch_apply_result.get("success_count", 0)),
		int(_patch_apply_result.get("total_count", 0)),
	])
	for entry in _patch_apply_result.get("diagnostics", []):
		lines.append(_format_diagnostic_line(entry))
	lines.append("=== split_patch_check_pass=%s ===" % str(_patch_apply_result.get("ok", false)))
	print("\n".join(lines))


func _run_automation_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	var patch_ok := bool(_patch_apply_result.get("ok", false))
	lines.append("patch_ok=%s meshes=%d/%d" % [
		patch_ok,
		int(_patch_apply_result.get("success_count", 0)),
		int(_patch_apply_result.get("total_count", 0)),
	])

	_mixer.set_emotion("smile")
	await get_tree().create_timer(0.25).timeout
	var eyes_smile: float = _mixer.call("read_shape_on_body", "Eyes_smile")
	var mouth_smile: float = _mixer.call("read_shape_on_body", "Mouth_smile")
	var legacy_smile: float = _mixer.call("read_shape_on_body", "smile")

	_mixer.call("set_viseme", "a")
	await get_tree().create_timer(0.25).timeout
	var a_w: float = _mixer.call("read_shape_on_body", "A")
	var eyes_during: float = _mixer.call("read_shape_on_body", "Eyes_smile")
	var mouth_during: float = _mixer.call("read_shape_on_body", "Mouth_smile")

	_mixer.call("clear_viseme")
	await get_tree().create_timer(0.25).timeout
	var mouth_after: float = _mixer.call("read_shape_on_body", "Mouth_smile")
	var a_after: float = _mixer.call("read_shape_on_body", "A")

	lines.append("smile split eyes=%.3f mouth=%.3f legacy=%.3f" % [eyes_smile, mouth_smile, legacy_smile])
	lines.append("viseme_a=%.3f eyes_during=%.3f mouth_during=%.3f" % [a_w, eyes_during, mouth_during])
	lines.append("after_clear mouth=%.3f a=%.3f" % [mouth_after, a_after])

	var viseme_min := FacePresenter.APPROVED_VISEME_COEF * 0.92
	var ok := eyes_smile > 0.85 and mouth_smile > 0.85 and legacy_smile < 0.05
	ok = ok and a_w > viseme_min and eyes_during > 0.85 and mouth_during < mouth_smile
	ok = ok and mouth_after > 0.85 and a_after < 0.05
	lines.append("patch_full_8of8=%s" % str(patch_ok))
	lines.append("=== emotion_lipsync_check_pass=%s ===" % str(ok))
	print("\n".join(lines))


func _run_action_timeline_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	var ok := _timeline != null and _player != null
	var pass_n := 0
	var total_n := 0
	if ok:
		var ids: PackedStringArray = _timeline.call("get_action_ids", ActionTimeline.CATALOG_FILTER_APPROVED)
		total_n = ids.size()
		for aid in ids:
			var entry_ok := true
			_timeline.call("select_action", aid)
			entry_ok = entry_ok and bool(_timeline.call("has_approved_preset", aid))
			var apath := String(_timeline.call("get_bound_audio_path", aid))
			var clip_len := float(_timeline.call("get_clip_total_duration"))
			var main_len := float(_timeline.call("get_main_action_duration_value"))
			var audio_len := float(_timeline.call("get_audio_source_duration"))
			entry_ok = entry_ok and _player.has_animation(aid)
			entry_ok = entry_ok and FileAccess.file_exists(apath)
			entry_ok = entry_ok and clip_len > ActionTimeline.DEFAULT_PRE_POST_IDLE * 2.0 + 0.05
			entry_ok = entry_ok and main_len > 0.05
			entry_ok = entry_ok and audio_len > 0.05
			lines.append(
				"catalog id=%s clip=%.2f main=%.2f audio=%.2f ok=%s"
				% [aid, clip_len, main_len, audio_len, str(entry_ok)]
			)
			if entry_ok:
				pass_n += 1
			else:
				ok = false
		_timeline.call("select_action", "youyou_Hello_Idle01")
		var ref_audio := float(_timeline.call("get_audio_source_duration"))
		_timeline.call("set_timeline_params", {"audio_speed": 1.1})
		var eff_len := float(_timeline.call("get_audio_effective_duration"))
		var speed_ok := absf(eff_len - ref_audio / 1.1) < 0.08
		lines.append("speed_check eff=%.3f ok=%s" % [eff_len, str(speed_ok)])
		ok = ok and speed_ok
		_timeline.call("play")
		await get_tree().create_timer(0.15).timeout
		ok = ok and int(_timeline.call("get_phase")) != ActionTimeline.Phase.STOPPED
		_timeline.call("stop")
		await get_tree().create_timer(0.1).timeout
	else:
		ok = false
	lines.append("approved_catalog_pass=%d/%d" % [pass_n, total_n])
	lines.append("=== action_lipsync_timeline_check_pass=%s ===" % str(ok))
	print("\n".join(lines))


func _run_event_catalog_registry_check() -> void:
	for _i in 2:
		await get_tree().process_frame
	const EventCatalog := preload("res://Scripts/youyou_action_event_catalog.gd")
	var reg := EventCatalog.validate_registry()
	var lines: PackedStringArray = []
	lines.append("event_catalog_count=%d" % int(reg.get("count", 0)))
	lines.append("catalog_notes=%s" % EventCatalog.get_catalog_notes())
	for issue in reg.get("issues", []):
		lines.append("issue=%s" % String(issue))
	lines.append("=== event_catalog_check_pass=%s ===" % str(bool(reg.get("ok", false))))
	print("\n".join(lines))


func _run_event_clip_compat_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	const EventCatalog := preload("res://Scripts/youyou_action_event_catalog.gd")
	EventCatalog.ensure_loaded()
	var lines: PackedStringArray = []
	var ok := true
	var pass_n := 0
	var total_n := 0
	lines.append("headless_note=仅验证资源可加载、AnimationPlayer 内目标动画存在且轨道非空；骨架与运行时口型/表情融合需在编辑器测试场人工确认")
	lines.append("missing_glb=youyou_Speak_Idle03（未登记于 event catalog）")
	if _timeline == null:
		ok = false
		lines.append("timeline_missing=true")
	else:
		var ids: PackedStringArray = _timeline.call("get_action_ids", ActionTimeline.CATALOG_FILTER_EVENT)
		total_n = ids.size()
		for aid in ids:
			var probe: Dictionary = _timeline.call("probe_action_clip", aid)
			var entry_ok := bool(probe.get("ok", false))
			lines.append(
				"event id=%s scene=%s anim=%s len=%.2f ok=%s reason=%s"
				% [
					aid,
					String(probe.get("scene_path", "")),
					String(probe.get("source_anim", "")),
					float(probe.get("clip_length", 0.0)),
					str(entry_ok),
					String(probe.get("reason", "")),
				]
			)
			if entry_ok:
				pass_n += 1
				_timeline.call("select_action", aid)
				entry_ok = entry_ok and _player != null and _player.has_animation(aid)
				if not entry_ok:
					lines.append("  player_register_fail id=%s" % aid)
					ok = false
				else:
					var clip_len := float(_timeline.call("get_clip_total_duration"))
					if clip_len <= 0.05:
						ok = false
						lines.append("  clip_duration_fail id=%s" % aid)
			else:
				ok = false
	lines.append("event_compat_pass=%d/%d" % [pass_n, total_n])
	lines.append("=== event_clip_compat_check_pass=%s ===" % str(ok and pass_n == total_n and total_n > 0))
	print("\n".join(lines))
