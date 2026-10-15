extends Node3D

const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")
const PerformancePoseController := preload("res://Scripts/youyou_performance_pose.gd")
const Approved := preload("res://Scripts/youyou_action_lipsync_approved.gd")
const ApprovedPerformance := preload("res://Scripts/youyou_approved_action_performance.gd")
const GazeController := preload("res://Scripts/youyou_eye_gaze_controller.gd")
const HeadFollow := preload("res://Scripts/youyou_head_follow_controller.gd")
const IdleLife := preload("res://Scripts/youyou_idle_life_controller.gd")
const EventActionPerformance := preload("res://Scripts/youyou_event_action_performance.gd")
const ClawShowAdapter := preload("res://Scripts/youyou_claw_show_adapter.gd")
const EventCatalog := preload("res://Scripts/youyou_action_event_catalog.gd")

const MODEL_PATH := "res://柚柚.glb"
const IDLE_SCENE_PATH := "res://待机Animation/Basic_Idle.glb"
const HELLO_SCENE_PATH := "res://待机Animation/youyou_Hello_Idle01.glb"
const IDLE_ANIM := "Basic_Idle"
const HELLO_ANIM := "youyou_Hello_Idle01"
const BLEND_BASE_TO_LIGHT := 0.25
const BLEND_LIGHT_TO_BASE := 0.30
const BLEND_BASE_TO_ATTRACT := 0.25
const BLEND_LIGHT_TO_ATTRACT := 0.20
const BLEND_ATTRACT_TO_BASE := 0.30
const BLEND_MANUAL := 0.25
## 口型测试键（A/E 已被待机动画占用）：[ ] ; ' /
const VISEME_KEYS := {
	KEY_BRACKETLEFT: "a",
	KEY_BRACKETRIGHT: "e",
	KEY_SEMICOLON: "i",
	KEY_APOSTROPHE: "o",
	KEY_SLASH: "u",
}
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
const BATCH_ONESHOTS := {
	KEY_4: "hello01",
	KEY_5: "Hand Wave_rig_01",
	KEY_6: "youyou_Hello_Idle02",
	KEY_7: "youyou_Hello_Idle03",
	KEY_8: "youyou_Hello_Idle06",
	KEY_9: "youyou_Hello_Idle07",
	KEY_B: "youyou_Hello_Idle08",
	KEY_N: "youyou_Hello_Idle09",
}
const PREVIEW_EVENT_KEYS := {
	KEY_F1: "youyou_coin01",
	KEY_F2: "youyou_fail01",
	KEY_F3: "youyou_victory01",
	KEY_F4: "youyou_claw crane01_01",
}
const IDLE_VARIANTS := {
	KEY_Q: "Basic_Idle01",
	KEY_W: "Basic_Idle02",
	KEY_E: "Basic_Idle03",
	KEY_T: "Basic_Idle04",
	KEY_A: "Basic_Idle05",
	KEY_X: "youyou_Basic_Idle01",
	KEY_S: "youyou_Basic_Idle02",
	KEY_D: "youyou_Basic_Idle03",
	KEY_F: "youyou_Basic_Idle04",
	KEY_G: "youyou_Basic_Idle05",
	KEY_Z: "youyou_Basic_Idle06",
}
const CLIP_ALIASES := {
	"youyou_Basic_Idle01": {
		"scene": "res://待机Animation/youyou_Basic_Idle01.001.glb",
		"source": "youyou_Basic_Idle01_001",
	},
}
const NEW_CLIP_NAMES: PackedStringArray = [
	"youyou_Basic_Idle01",
	"youyou_Hello_Idle02",
	"youyou_Hello_Idle03",
	"youyou_Hello_Idle06",
	"youyou_Hello_Idle07",
	"youyou_Hello_Idle08",
	"youyou_Hello_Idle09",
]
enum ScheduleMode { BASE_IDLE, LIGHT_IDLE, ATTRACT, MANUAL_TEST }

var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _hello_active := false
var _oneshot_name := ""
var _status_label: Label
var _log_lines: PackedStringArray = []
var _reference_bones: Dictionary = {}
var _compat_lines: PackedStringArray = []
var _mode := ScheduleMode.MANUAL_TEST
var _schedule_enabled := false
var _wait_timer: Timer
var _light_pool: PackedStringArray = []
var _attract_pool: PackedStringArray = []
var _last_light := ""
var _last_attract := ""
var _active_finish_anim := ""
var _planned_wait := 0.0
var _wait_armed_msec := 0
var _auto_return_count := 0
var _last_blend := 0.0
var _pending_attract_request := false
var _basic_idle_prev_pos := -1.0
var _face: FacePresenter
var _patch_apply_result: Dictionary = {}
var _emotion_restore_primary := "smile"
var _viseme_clear_busy := false
var _performance_pose: Node
var _hello_perf_gen := 0
var _auto_perf_gen := 0
var _manual_perf_gen := 0
var _approved_perf: Node
var _event_perf: YouyouEventActionPerformance
var _show_adapter: YouyouClawShowAdapter
var _event_playing := false
var _saved_mode_before_event := ScheduleMode.BASE_IDLE
var _resume_schedule_after_event := false
var _event_play_token := 0
var _idle_life: Node
var _presence_camera: Camera3D


func _ready() -> void:
	_status_label = get_node_or_null("StatusLayer/StatusLabel") as Label
	_ensure_wait_timer()
	if not _load_model():
		return
	if not _load_clips():
		return
	_patch_apply_result = FacePresenter.apply_split_patch_to_model(_model)
	if not bool(_patch_apply_result.get("ok", false)):
		_note("拆分补丁部分成功 %d/%d（舌头未匹配，口型仍用原 GLB）。" % [
			int(_patch_apply_result.get("success_count", 0)),
			int(_patch_apply_result.get("total_count", 0)),
		])
	_default_shapes = FacePresenter.capture_zero_baseline(_meshes)
	_init_face_presenter()
	_init_performance_pose_controller()
	_init_approved_performance()
	_init_event_action_performance()
	_init_idle_presence()
	_start_idle(true)
	_note("场景已启动。I 基础待机，H 招揽01，Q/W/E/T/A 为 Basic_Idle01-05，X 为 youyou_Basic_Idle01，S/D/F/G/Z 为 youyou_Basic_Idle02-06。")
	_note("4 hello01，5 挥手，6/7 招揽02/03，8/9 招揽06/07，B/N 招揽08/09。M 模拟玩家经过。")
	_note("表情 1微笑 2惊讶 3大笑 0默认；C生气 V难过 P咧嘴 J眨眼 K看左 L看右。口型 [A ]E ;I 'O /U，Backspace 清口型。U/Y 错误测试。R 只重置镜头。")
	_note("事件动作 F1投币 F2失败 F3成功 F4抓取01（catalog 参数，非招揽池）。")
	var args := OS.get_cmdline_user_args()
	if "--phase-a-check" in args:
		_run_phase_a_check()
	elif "--batch-check" in args:
		_run_batch_check()
	elif "--idle-check" in args:
		_run_idle_check()
	elif "--new-anim-check" in args:
		_run_new_anim_check()
	elif "--approved-pool-check" in args:
		_run_approved_pool_check()
	elif "--schedule-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_schedule_check()
	elif "--blend-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_blend_check()
	elif "--pending-attract-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_pending_attract_check()
	elif "--expression-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_expression_check()
	elif "--expression-isolation-check" in args:
		_run_expression_isolation_check()
	elif "--viseme-check" in args:
		_run_viseme_check()
	elif "--viseme-diagnose" in args:
		_run_viseme_diagnose()
	elif "--viseme-coord-check" in args:
		_run_viseme_coord_check()
	elif "--performance-expression-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_performance_expression_check()
	elif "--idle-presence-check" in args:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		_run_idle_presence_check()
	elif "--preview-event-check" in args:
		_run_preview_event_check()
	else:
		_schedule_enabled = true
		_mode = ScheduleMode.BASE_IDLE
		_arm_wait()
		if _idle_life != null:
			_idle_life.set_process(true)
			_sync_idle_presence()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if IDLE_VARIANTS.has(event.keycode):
		_play_idle_variant(String(IDLE_VARIANTS[event.keycode]))
		return
	if BATCH_ONESHOTS.has(event.keycode):
		_play_batch_oneshot(String(BATCH_ONESHOTS[event.keycode]))
		return
	if EMOTE_KEYS.has(event.keycode):
		_apply_emote(String(EMOTE_KEYS[event.keycode]))
		return
	if VISEME_KEYS.has(event.keycode):
		_apply_viseme(String(VISEME_KEYS[event.keycode]))
		return
	if PREVIEW_EVENT_KEYS.has(event.keycode):
		_event_play_token += 1
		_play_preview_event(String(PREVIEW_EVENT_KEYS[event.keycode]), _event_play_token)
		return
	match event.keycode:
		KEY_BACKSPACE:
			_clear_viseme()
			return
		KEY_I:
			if _schedule_enabled:
				_resume_auto_from_i()
			else:
				_start_idle(false)
		KEY_M:
			if _schedule_enabled:
				_on_player_passed()
		KEY_H:
			_start_hello()
		KEY_0:
			_restore_default_expression()
		KEY_U:
			_request_missing_animation()
		KEY_Y:
			_apply_emote("missing_expression_probe")
		KEY_F12:
			if event.shift_pressed:
				_run_viseme_diagnose()


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _event_playing:
		_sync_idle_presence()
		return
	if _schedule_enabled:
		_poll_pending_attract_on_basic_idle_cycle()
	if _schedule_enabled and (_mode == ScheduleMode.LIGHT_IDLE or _mode == ScheduleMode.ATTRACT):
		if _active_finish_anim != "" and _player.assigned_animation == _active_finish_anim and not _player.is_playing():
			_on_auto_performance_finished()
		_sync_idle_presence()
		return
	if _hello_active and _player.assigned_animation == HELLO_ANIM and not _player.is_playing():
		if _performance_pose.consume_hello_end(_hello_perf_gen):
			_note("招揽播放结束，表现层回到待机。")
			_hello_active = false
			_start_idle(true)
		_sync_idle_presence()
		return
	if _oneshot_name != "" and _player.assigned_animation == _oneshot_name and not _player.is_playing():
		_note("单次动画结束，表现层回到待机：" + _oneshot_name)
		_start_idle(true)
	_sync_idle_presence()


func _load_model() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("模型加载失败：" + MODEL_PATH)
		return false
	var instance := packed.instantiate()
	if not instance is Node3D:
		_fail("模型根节点不是 Node3D：" + MODEL_PATH)
		instance.free()
		return false
	_model = instance as Node3D
	_model.name = "YouyouModel"
	add_child(_model)
	_skeleton = _model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if _skeleton == null:
		_fail("未找到骨架 Armature/Skeleton3D。")
		return false
	if _skeleton.find_bone("mixamorig_Hips") < 0:
		_fail("骨架中没有 mixamorig_Hips，动画轨道无法对应。")
		return false
	_collect_meshes(_model)
	if _meshes.is_empty():
		_fail("模型中没有网格，无法设置表情。")
		return false
	_hide_headphones()
	return true


func _load_clips() -> bool:
	if not Approved.load_config():
		_fail("无法加载已验收动作配置。")
		return false
	var idle_clip := _take_clip(IDLE_SCENE_PATH, IDLE_ANIM)
	if idle_clip == null:
		return false
	idle_clip.loop_mode = Animation.LOOP_LINEAR
	_reference_bones = _bones_in_clip(idle_clip)
	_player = AnimationPlayer.new()
	_player.name = "PreviewAnimationPlayer"
	_player.playback_default_blend_time = 0.0
	_model.add_child(_player)
	var library := AnimationLibrary.new()
	library.add_animation(IDLE_ANIM, idle_clip)
	for action_id in Approved.all_whitelisted_action_ids():
		if not _add_approved_clip(library, action_id):
			push_error("已验收动作 clip 接入失败，跳过：" + action_id)
	_player.add_animation_library(&"", library)
	_player.animation_finished.connect(_on_animation_finished)
	_build_schedule_pools()
	if not _player.has_animation(HELLO_ANIM):
		_note("键盘 H 使用已验收招揽：" + HELLO_ANIM + "（需成功接入动画库）。")
	return _light_pool.size() > 0 and _attract_pool.size() > 0


func _take_clip(scene_path: String, anim_name: String) -> Animation:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_fail("动画场景加载失败：" + scene_path)
		return null
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(anim_name):
		var available := ""
		if source != null:
			available = ",".join(source.get_animation_list())
		_fail("动画不存在：" + anim_name + "，文件：" + scene_path + "，实际列表：" + available)
		instance.free()
		return null
	var clip := (source.get_animation(anim_name) as Animation).duplicate(true) as Animation
	instance.free()
	return clip


func _clip_location(display_name: String) -> Dictionary:
	if CLIP_ALIASES.has(display_name):
		return CLIP_ALIASES[display_name]
	return {
		"scene": "res://待机Animation/%s.glb" % display_name,
		"source": display_name,
	}


func _add_approved_clip(library: AnimationLibrary, action_id: String) -> bool:
	var check: Dictionary = Approved.validate_entry(action_id)
	if not bool(check.get("ok", false)):
		for err in check.get("errors", []):
			push_error("%s: %s" % [action_id, str(err)])
		return false
	var clip := Approved.take_animation_clip(action_id)
	if clip == null:
		push_error("clip 提取失败：" + action_id)
		return false
	clip.loop_mode = Animation.LOOP_NONE
	library.add_animation(action_id, clip)
	var reg: Dictionary = Approved.get_clip_registry(action_id)
	_report_track_compatibility(action_id, clip, String(reg.get("source_anim", action_id)))
	return true


func _add_mapped_clip(library: AnimationLibrary, display_name: String, loop_mode: Animation.LoopMode) -> void:
	var location := _clip_location(display_name)
	var clip := _take_clip(String(location["scene"]), String(location["source"]))
	if clip == null:
		return
	clip.loop_mode = loop_mode
	library.add_animation(display_name, clip)
	if display_name in NEW_CLIP_NAMES:
		_report_track_compatibility(display_name, clip, String(location["source"]))


func _bones_in_clip(clip: Animation) -> Dictionary:
	var bones := {}
	for index in clip.get_track_count():
		var bone := String(clip.track_get_path(index).get_concatenated_subnames())
		if bone != "":
			bones[bone] = true
	return bones


func _report_track_compatibility(display_name: String, clip: Animation, source_name: String) -> void:
	var bones := _bones_in_clip(clip)
	var missing: PackedStringArray = []
	var extra: PackedStringArray = []
	for bone_name in bones.keys():
		var bone := String(bone_name)
		if _skeleton.find_bone(bone) < 0:
			missing.append(bone)
		elif not _reference_bones.has(bone):
			extra.append(bone)
	var hips := bones.has("mixamorig_Hips")
	var summary := "%s source=%s tracks=%d bones=%d hips=%s missing=%d extra=%d" % [
		display_name, source_name, clip.get_track_count(), bones.size(), hips, missing.size(), extra.size()
	]
	if missing.size() > 0:
		summary += " missing_bones=" + ",".join(missing.slice(0, 8))
	if extra.size() > 0:
		summary += " extra_bones=" + ",".join(extra.slice(0, 8))
	_compat_lines.append(summary)
	if not hips:
		_fail(display_name + " 没有 mixamorig_Hips 轨道，不能确认它驱动当前骨架。")
	elif missing.size() > 0:
		_fail(display_name + " 有轨道指向当前骨架不存在的骨骼：" + ",".join(missing.slice(0, 8)))
	else:
		_note(display_name + " 轨道与当前骨架兼容，展示名已映射，源动画名 " + source_name + "。")


func _hide_headphones() -> void:
	var hidden := 0
	for mesh in _meshes:
		if String(mesh.name) == "耳机":
			mesh.visible = false
			hidden += 1
	if hidden == 0:
		_fail("未找到耳机网格，无法隐藏。")


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _init_face_presenter() -> void:
	_face = FacePresenter.new()
	_face.name = "YouyouFacePresenter"
	add_child(_face)
	_face.setup(_meshes, _default_shapes)
	_face.configure_patch_readiness(_patch_apply_result.get("diagnostics", []))
	_face.apply_approved_coefficients()
	_face.configure_performance_blend(FacePresenter.TRANSITION_BLEND_TIME_DEFAULT)
	if _face.is_emotion_available("smile"):
		_face.set_emotion("smile", 0.0)
	_note("面部表现：拆分 Eyes_*/Mouth_*，默认微笑，复合主键保持 0。")


func _init_approved_performance() -> void:
	_approved_perf = ApprovedPerformance.new()
	_approved_perf.name = "ApprovedActionPerformance"
	add_child(_approved_perf)
	_approved_perf.call("setup", self, _player, _face)


func _init_event_action_performance() -> void:
	_event_perf = EventActionPerformance.new()
	_event_perf.name = "EventActionPerformance"
	add_child(_event_perf)
	_event_perf.setup(self, _player, _face, IDLE_ANIM)
	if not _event_perf.performance_finished.is_connected(_on_event_performance_finished):
		_event_perf.performance_finished.connect(_on_event_performance_finished)
	if not _event_perf.performance_failed.is_connected(_on_event_performance_failed):
		_event_perf.performance_failed.connect(_on_event_performance_failed)
	_show_adapter = ClawShowAdapter.new()
	_show_adapter.name = "ClawShowAdapter"
	add_child(_show_adapter)
	_show_adapter.setup(_event_perf)


func _play_preview_event(action_id: String, token: int) -> void:
	if _event_perf == null:
		_fail("事件表现未初始化。")
		return
	if not _event_playing:
		_saved_mode_before_event = _mode
		_resume_schedule_after_event = _schedule_enabled
	_enter_manual()
	_event_playing = true
	_note("请求事件动作 %s（token=%d）。" % [action_id, token])
	if not _event_perf.play_event(action_id, token):
		_event_playing = false
		_restore_schedule_after_event()


func _on_event_performance_finished(token: int, action_id: String, reason: String) -> void:
	if not _event_playing:
		return
	_event_playing = false
	_note("事件动作完成 %s token=%d（%s）。" % [action_id, token, reason])
	_restore_schedule_after_event()


func _on_event_performance_failed(token: int, action_id: String, code: String, message: String) -> void:
	if _event_playing:
		_event_playing = false
	_fail("事件动作失败 %s token=%d [%s]: %s" % [action_id, token, code, message])
	_restore_schedule_after_event()


func get_claw_show_adapter() -> YouyouClawShowAdapter:
	return _show_adapter


func get_event_action_performance() -> YouyouEventActionPerformance:
	return _event_perf


func _restore_schedule_after_event() -> void:
	_sync_performance_base_idle()
	if _resume_schedule_after_event and _saved_mode_before_event != ScheduleMode.MANUAL_TEST:
		_mode = _saved_mode_before_event
		if _schedule_enabled:
			_arm_wait()
	else:
		_mode = ScheduleMode.MANUAL_TEST


func _init_performance_pose_controller() -> void:
	_performance_pose = PerformancePoseController.new()
	_performance_pose.name = "YouyouPerformancePoseController"
	add_child(_performance_pose)
	_performance_pose.setup(
		_face,
		func() -> bool:
			return _face != null and _face.get_active_viseme() != ""
	)
	_performance_pose.apply_pose(PerformancePoseController.POSE_BASE_IDLE, true)
	_emotion_restore_primary = "smile"


func _sync_performance_base_idle() -> void:
	if _performance_pose == null:
		return
	if _performance_pose.apply_pose(PerformancePoseController.POSE_BASE_IDLE):
		_emotion_restore_primary = _performance_pose.sync_emotion_restore_primary()


func _apply_viseme(viseme_id: String) -> void:
	if _face == null:
		_fail("面部控制器未初始化。")
		return
	if _face.get_active_viseme() == "":
		_emotion_restore_primary = _face.get_emotion_restore_primary()
	if not _face.set_viseme(viseme_id):
		_fail("口型不存在或不受支持：" + viseme_id)
		return
	_note("口型 %s，强度 1.0，过渡 %.2f 秒。" % [viseme_id, FacePresenter.VISEME_BLEND_TIME])


func _clear_viseme() -> void:
	if _face == null or _viseme_clear_busy:
		return
	_viseme_clear_busy = true
	_run_clear_viseme_coordinator()


func _run_clear_viseme_coordinator() -> void:
	var blend := FacePresenter.VISEME_BLEND_TIME
	_face.clear_viseme(blend)
	await get_tree().create_timer(blend + 0.08).timeout
	if not _face.all_visemes_near_zero(0.03):
		_face.clear_viseme(0.0)
		_note("口型二次清零。")
	else:
		_note("已清除口型，情绪由面部模块恢复：" + _face.get_active_emotion())
	_viseme_clear_busy = false


func _is_gaze_emote(shape_name: String) -> bool:
	return shape_name in FacePresenter.GAZE_KEYS


func _is_split_emote(shape_name: String) -> bool:
	return shape_name in FacePresenter.SPLIT_EMOTION_IDS


func _start_idle(from_hello_end: bool) -> void:
	_stop_approved_performance()
	_hello_active = false
	_oneshot_name = ""
	if _player == null or not _player.has_animation(IDLE_ANIM):
		_fail("无法播放待机，动画不存在：" + IDLE_ANIM)
		return
	if not from_hello_end and _player.assigned_animation == IDLE_ANIM and _player.is_playing():
		_note("待机已在播放，忽略重复请求。")
		return
	if not from_hello_end:
		_performance_pose.invalidate_hello()
	var blend := _blend_into_idle()
	_play_clip(IDLE_ANIM, blend)
	_sync_performance_base_idle()
	_note("播放待机 %s，混合 %.2f 秒，循环。" % [IDLE_ANIM, blend])


func _start_hello() -> void:
	_enter_manual()
	_oneshot_name = ""
	if _player == null or not _player.has_animation(HELLO_ANIM):
		_fail("无法播放招揽，动画不存在：" + HELLO_ANIM)
		_start_idle(true)
		return
	var restarting := _player.assigned_animation == HELLO_ANIM and _player.is_playing()
	_hello_perf_gen = _performance_pose.begin_hello_performance(false)
	_hello_active = true
	_play_clip(HELLO_ANIM, BLEND_MANUAL)
	_start_approved_performance(HELLO_ANIM, _hello_perf_gen)
	_emotion_restore_primary = String(
		Approved.get_params(HELLO_ANIM).get("emotion_id", _performance_pose.sync_emotion_restore_primary())
	)
	if restarting:
		_note("招揽尚未结束，已从头混合重播。")
	else:
		_note("播放招揽 %s，混合 %.2f 秒，单次。结束后只恢复表现。" % [HELLO_ANIM, BLEND_MANUAL])


func _play_idle_variant(anim_name: String) -> void:
	_enter_manual()
	if not _is_approved_action(anim_name):
		_fail("未验收待机动作，正式场景拒绝播放：" + anim_name)
		return
	if _player == null or not _player.has_animation(anim_name):
		_fail("无法播放待机变体，动画不存在：" + anim_name)
		return
	var restarting := _player.assigned_animation == anim_name and _player.is_playing()
	_hello_active = false
	_oneshot_name = ""
	_manual_perf_gen = _performance_pose.bump_auto_session()
	_play_clip(anim_name, BLEND_MANUAL)
	_start_approved_performance(anim_name, _manual_perf_gen)
	if restarting:
		_note("待机变体已从头混合重播：" + anim_name)
	else:
		_note("播放 %s，混合 %.2f 秒，副本循环。按 I 回到 Basic_Idle。" % [anim_name, BLEND_MANUAL])


func _play_batch_oneshot(anim_name: String) -> void:
	_enter_manual()
	if not _is_approved_action(anim_name):
		_fail("未验收招揽/单次动作，正式场景拒绝播放：" + anim_name)
		return
	if _player == null or not _player.has_animation(anim_name):
		_fail("无法播放单次动画，动画不存在：" + anim_name)
		_start_idle(true)
		return
	var restarting := _player.assigned_animation == anim_name and _player.is_playing()
	_hello_active = false
	_oneshot_name = anim_name
	_manual_perf_gen = _performance_pose.bump_auto_session()
	_play_clip(anim_name, BLEND_MANUAL)
	_start_approved_performance(anim_name, _manual_perf_gen)
	if restarting:
		_note("单次动画尚未结束，已从头混合重播：" + anim_name)
	else:
		_note("播放单次动画 %s，混合 %.2f 秒。结束后回到待机。" % [anim_name, BLEND_MANUAL])


func _on_animation_finished(anim_name: StringName) -> void:
	var finished := String(anim_name)
	if _event_playing and _event_perf != null:
		_event_perf.notify_animation_finished(anim_name)
	if _schedule_enabled and (_mode == ScheduleMode.LIGHT_IDLE or _mode == ScheduleMode.ATTRACT):
		if anim_name != StringName(_active_finish_anim):
			return
		if not _performance_pose.auto_finish_may_run(_auto_perf_gen):
			return
		if _approved_perf != null:
			_approved_perf.call("on_action_animation_finished", finished, _auto_perf_gen)
		_on_auto_performance_finished()
		return
	if anim_name == HELLO_ANIM and _hello_active:
		if not _performance_pose.consume_hello_end(_hello_perf_gen):
			return
		if _approved_perf != null:
			_approved_perf.call("on_action_animation_finished", finished, _hello_perf_gen)
		_note("收到招揽结束信号，表现层回到待机。")
		_hello_active = false
		_start_idle(true)
		return
	if _oneshot_name != "" and anim_name == StringName(_oneshot_name):
		if _approved_perf != null:
			_approved_perf.call("on_action_animation_finished", finished, _manual_perf_gen)
		_note("收到单次动画结束信号，表现层回到待机：" + _oneshot_name)
		_start_idle(true)


func _apply_emote(shape_name: String) -> void:
	if _face == null:
		_fail("面部控制器未初始化。")
		return
	var ok := false
	if _is_gaze_emote(shape_name):
		ok = _face.set_gaze(shape_name)
	elif _is_split_emote(shape_name):
		ok = _face.set_emotion(shape_name)
	else:
		_fail("表情形态键不存在或不受支持：" + shape_name)
		return
	if not ok:
		_fail("表情形态键不存在或不受支持：" + shape_name)
		return
	_emotion_restore_primary = _face.get_emotion_restore_primary()
	_note("表情切换到 " + shape_name + "，过渡 " + str(FacePresenter.VISEME_BLEND_TIME) + " 秒。")


func _restore_default_expression() -> void:
	if _face == null:
		return
	if _face.get_active_viseme() != "":
		_emotion_restore_primary = "smile"
		_clear_viseme()
		return
	_face.reset_all(FacePresenter.VISEME_BLEND_TIME)
	_performance_pose.note_pose(PerformancePoseController.POSE_BASE_IDLE)
	_emotion_restore_primary = "smile"
	_note("已恢复默认微笑（Eyes_smile/Mouth_smile，复合主键归零）。")


func _request_missing_animation() -> void:
	_enter_manual()
	var missing_name := "missing_animation_probe"
	if _player != null and _player.has_animation(missing_name):
		_play_clip(missing_name, 0.0)
		return
	_fail("请求了不存在的动画：" + missing_name)
	if _player == null or not _player.is_playing():
		_start_idle(true)


func _ensure_wait_timer() -> void:
	_wait_timer = Timer.new()
	_wait_timer.name = "LightIdleWait"
	_wait_timer.one_shot = true
	_wait_timer.timeout.connect(_on_light_wait_timeout)
	add_child(_wait_timer)


func _build_schedule_pools() -> void:
	_light_pool = _build_validated_pool(Approved.get_light_idle_whitelist(), "轻待机")
	_attract_pool = _build_validated_pool(Approved.get_attract_whitelist(), "招揽")


func _build_validated_pool(whitelist: PackedStringArray, label: String) -> PackedStringArray:
	var found := PackedStringArray()
	for action_id in whitelist:
		var check: Dictionary = Approved.validate_entry(action_id)
		if not bool(check.get("ok", false)):
			for err in check.get("errors", []):
				push_error("%s池跳过 %s: %s" % [label, action_id, str(err)])
			continue
		if _player == null or not _player.has_animation(action_id):
			push_error("%s池跳过 %s: 动画未接入" % [label, action_id])
			continue
		found.append(action_id)
	if found.is_empty():
		_fail("%s池为空：无有效已验收动作。" % label)
	return found


func _is_approved_action(anim_name: String) -> bool:
	return Approved.is_whitelisted(anim_name) and bool(
		Approved.validate_entry(anim_name).get("ok", false)
	)


func _stop_approved_performance() -> void:
	if _approved_perf != null:
		_approved_perf.call("stop")


func _start_approved_performance(anim_name: String, session_gen: int) -> void:
	if _approved_perf == null:
		return
	if not _is_approved_action(anim_name):
		push_error("拒绝播放未验收动作：" + anim_name)
		return
	if not bool(_approved_perf.call("start", anim_name, session_gen)):
		push_error("已验收表演启动失败：" + anim_name)


func _enter_manual() -> void:
	_stop_approved_performance()
	if _wait_timer != null:
		_wait_timer.stop()
	_clear_pending_attract()
	_restore_light_loops()
	_active_finish_anim = ""
	_mode = ScheduleMode.MANUAL_TEST
	_hello_active = false
	_oneshot_name = ""
	if _performance_pose != null:
		_performance_pose.invalidate_hello()
		_performance_pose.invalidate_auto()


func _resume_auto_from_i() -> void:
	var already_waiting := _mode == ScheduleMode.BASE_IDLE and _wait_timer != null and not _wait_timer.is_stopped() and _player != null and _player.assigned_animation == IDLE_ANIM and _player.is_playing()
	if already_waiting:
		_note("自动待机已在进行。")
		return
	if _wait_timer != null:
		_wait_timer.stop()
	_clear_pending_attract()
	_restore_light_loops()
	_active_finish_anim = ""
	_mode = ScheduleMode.BASE_IDLE
	_start_idle(false)
	if _player == null or _player.assigned_animation != IDLE_ANIM or not _player.is_playing():
		_mode = ScheduleMode.MANUAL_TEST
		return
	_arm_wait()


func _on_player_passed() -> void:
	_queue_pending_attract()


func _queue_pending_attract() -> void:
	if _mode == ScheduleMode.ATTRACT or _mode == ScheduleMode.MANUAL_TEST:
		_note("当前不能插入招揽，忽略 M。")
		return
	if _mode != ScheduleMode.BASE_IDLE and _mode != ScheduleMode.LIGHT_IDLE:
		return
	if _pending_attract_request:
		_note("已有待处理招揽，忽略 M。")
		return
	_pending_attract_request = true
	if _wait_timer != null:
		_wait_timer.stop()
	if _mode == ScheduleMode.BASE_IDLE and _player.assigned_animation == IDLE_ANIM:
		_basic_idle_prev_pos = _player.current_animation_position
	else:
		_basic_idle_prev_pos = -1.0
	_note("已记录玩家经过，当前动作自然结束后再播放招揽。")


func _clear_pending_attract() -> void:
	_pending_attract_request = false
	_basic_idle_prev_pos = -1.0


func _poll_pending_attract_on_basic_idle_cycle() -> void:
	if not _pending_attract_request or _mode != ScheduleMode.BASE_IDLE:
		_basic_idle_prev_pos = -1.0
		return
	if _player.assigned_animation != IDLE_ANIM or not _player.is_playing():
		return
	var pos := _player.current_animation_position
	var length := _player.current_animation_length
	if length <= 0.0:
		return
	if _basic_idle_prev_pos >= 0.0 and _basic_idle_prev_pos >= length * 0.70 and pos <= length * 0.30:
		_clear_pending_attract()
		_play_auto_attract()
		return
	_basic_idle_prev_pos = pos


func _on_auto_performance_finished() -> void:
	if _mode == ScheduleMode.LIGHT_IDLE and _pending_attract_request:
		_clear_pending_attract()
		_play_auto_attract()
		return
	_return_auto_base()


func _arm_wait() -> void:
	if not _schedule_enabled or _mode != ScheduleMode.BASE_IDLE or _wait_timer == null:
		return
	if _pending_attract_request:
		return
	_wait_timer.stop()
	_planned_wait = randf_range(2.0, 4.0)
	_wait_armed_msec = Time.get_ticks_msec()
	_wait_timer.start(_planned_wait)
	_note("基础待机，%.2f 秒后播放轻待机。" % _planned_wait)


func _on_light_wait_timeout() -> void:
	if not _schedule_enabled or _mode != ScheduleMode.BASE_IDLE:
		return
	if _pending_attract_request:
		return
	if _player == null or _player.assigned_animation != IDLE_ANIM or not _player.is_playing():
		return
	_play_auto_light()


func _play_auto_light() -> void:
	var anim_name := _pick_name(_light_pool, _last_light)
	if anim_name == "":
		_fail("没有可播放的轻待机。")
		return
	_last_light = anim_name
	if _wait_timer != null:
		_wait_timer.stop()
	_restore_light_loops()
	_hello_active = false
	_oneshot_name = ""
	_mode = ScheduleMode.LIGHT_IDLE
	_active_finish_anim = anim_name
	_auto_perf_gen = _performance_pose.bump_auto_session()
	var clip := _player.get_animation(anim_name)
	clip.loop_mode = Animation.LOOP_NONE
	_play_clip(anim_name, BLEND_BASE_TO_LIGHT)
	_start_approved_performance(anim_name, _auto_perf_gen)
	_note("自动轻待机 %s，混合 %.2f 秒，单次。" % [anim_name, BLEND_BASE_TO_LIGHT])


func _play_auto_attract() -> void:
	_clear_pending_attract()
	var anim_name := _pick_name(_attract_pool, _last_attract)
	if anim_name == "":
		_fail("没有可播放的轻招揽。")
		return
	_last_attract = anim_name
	var from_light := _mode == ScheduleMode.LIGHT_IDLE
	var blend := BLEND_LIGHT_TO_ATTRACT if from_light else BLEND_BASE_TO_ATTRACT
	var outgoing := String(_player.assigned_animation) if from_light else ""
	if _wait_timer != null:
		_wait_timer.stop()
	_restore_light_loops(outgoing)
	_hello_active = false
	_oneshot_name = ""
	_mode = ScheduleMode.ATTRACT
	_active_finish_anim = anim_name
	_auto_perf_gen = _performance_pose.begin_auto_attract_performance(false)
	_play_clip(anim_name, blend)
	_start_approved_performance(anim_name, _auto_perf_gen)
	_emotion_restore_primary = String(
		Approved.get_params(anim_name).get("emotion_id", "smile")
	)
	_note("自动轻招揽 %s，混合 %.2f 秒，单次。" % [anim_name, blend])


func _return_auto_base() -> void:
	if _mode != ScheduleMode.LIGHT_IDLE and _mode != ScheduleMode.ATTRACT:
		return
	if not _performance_pose.auto_finish_may_run(_auto_perf_gen):
		return
	_performance_pose.consume_auto_finish(_auto_perf_gen)
	var finished := _active_finish_anim
	_auto_return_count += 1
	_mode = ScheduleMode.BASE_IDLE
	_active_finish_anim = ""
	_restore_light_loops()
	_hello_active = false
	_oneshot_name = ""
	_start_idle(true)
	_note("自动表演结束，回到基础待机：" + finished)
	_arm_wait()


func _restore_light_loops(except_name: String = "") -> void:
	if _player == null:
		return
	for anim_name in _light_pool:
		if anim_name == except_name:
			continue
		if _player.has_animation(anim_name):
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func _play_clip(anim_name: String, blend: float) -> void:
	var same := _player.assigned_animation == anim_name and _player.is_playing()
	var hold_pose := blend > 0.0 and not _player.is_playing() and String(_player.assigned_animation) != ""
	_last_blend = blend
	if _is_approved_action(anim_name):
		var p: Dictionary = Approved.get_params(anim_name)
		_player.speed_scale = float(p.get("action_speed", 1.0))
	elif anim_name == IDLE_ANIM:
		_player.speed_scale = 1.0
	if hold_pose:
		# Godot 4.7：capture 第一个参数是动画名，第二个是过渡时长；不能写成 capture(blend)。
		_player.play_with_capture(anim_name, blend, blend)
	elif same:
		_player.play(anim_name, blend)
		_player.seek(0.0, false)
	else:
		_player.play(anim_name, blend)


func _blend_into_idle() -> float:
	if _player == null:
		return 0.0
	var current := String(_player.assigned_animation)
	if current == "" or current == IDLE_ANIM:
		return 0.0
	if current in _light_pool:
		return BLEND_LIGHT_TO_BASE
	if current in _attract_pool or current == HELLO_ANIM:
		return BLEND_ATTRACT_TO_BASE
	return BLEND_MANUAL


func _pick_name(pool: PackedStringArray, previous: String) -> String:
	if pool.is_empty():
		return ""
	if pool.size() < 2:
		return pool[0]
	var choices := PackedStringArray()
	for anim_name in pool:
		if anim_name != previous:
			choices.append(anim_name)
	if choices.is_empty():
		choices = pool
	return choices[randi() % choices.size()]


func _run_phase_a_check() -> void:
	var lines: PackedStringArray = []
	lines.append("players=" + str(_count_players(_model)))
	lines.append("idle_loop=" + str(_player.get_animation(IDLE_ANIM).loop_mode))
	lines.append("hello_loop=" + str(_player.get_animation(HELLO_ANIM).loop_mode))
	lines.append("idle_length=" + str(_player.get_animation(IDLE_ANIM).length))
	lines.append("hello_length=" + str(_player.get_animation(HELLO_ANIM).length))
	lines.append("blend=" + str(_player.playback_default_blend_time))
	lines.append("startup=" + _player.assigned_animation + " playing=" + str(_player.is_playing()))
	_start_idle(false)
	lines.append("repeat_idle_ignored=" + str("忽略重复请求" in _log_lines[_log_lines.size() - 1]))
	_player.seek(_player.current_animation_length - 0.05, true)
	_player.advance(0.2)
	lines.append("idle_after_wrap=" + _player.assigned_animation + " playing=" + str(_player.is_playing()) + " pos=" + str(_player.current_animation_position))
	var hips := _skeleton.find_bone("mixamorig_Hips")
	var pose_before := _skeleton.get_bone_pose_rotation(hips)
	_start_hello()
	_player.seek(2.0, true)
	_player.advance(0.0)
	var pose_after := _skeleton.get_bone_pose_rotation(hips)
	lines.append("hello_current=" + _player.assigned_animation)
	lines.append("hello_pose_changed=" + str(not pose_before.is_equal_approx(pose_after)))
	_player.seek(3.0, true)
	_start_hello()
	lines.append("hello_restart_pos=" + str(_player.current_animation_position))
	_apply_emote("surprise")
	var body := _find_mesh("人体_001")
	var laugh_index := body.find_blend_shape_by_name("laugh") if body != null else -1
	var surprise_index := body.find_blend_shape_by_name("surprise") if body != null else -1
	var surprise_before := body.get_blend_shape_value(surprise_index) if surprise_index >= 0 else -1.0
	_start_hello()
	_player.seek(1.5, true)
	_player.advance(0.0)
	var laugh_during := body.get_blend_shape_value(laugh_index) if laugh_index >= 0 else -1.0
	_player.speed_scale = 40.0
	_start_hello()
	await get_tree().create_timer(0.45).timeout
	_player.speed_scale = 1.0
	var laugh_after_hello := body.get_blend_shape_value(laugh_index) if laugh_index >= 0 else -1.0
	lines.append("surprise_before_manual=" + str(surprise_before))
	lines.append("laugh_during_hello=" + str(laugh_during))
	lines.append("laugh_after_hello=" + str(laugh_after_hello))
	lines.append("hello_overrides_manual_emote=" + str(laugh_during > 0.5))
	lines.append("after_hello=" + _player.assigned_animation + " playing=" + str(_player.is_playing()))
	_start_hello()
	_start_idle(false)
	_start_hello()
	_start_idle(true)
	lines.append("alternate_final=" + _player.assigned_animation)
	lines.append("players_after=" + str(_count_players(_model)))
	_request_missing_animation()
	_apply_emote("missing_expression_probe")
	var joined := "\n".join(_log_lines)
	lines.append("missing_anim_visible=" + str("missing_animation_probe" in joined))
	lines.append("missing_expr_visible=" + str("missing_expression_probe" in joined))
	lines.append("missing_still=" + _player.assigned_animation + " playing=" + str(_player.is_playing()))
	var output := "\n".join(lines)
	print(output)
	var file := FileAccess.open("user://phase_a_check.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(output)
		file.close()
	get_tree().quit()


func _run_batch_check() -> void:
	var lines: PackedStringArray = []
	for anim_name in ["hello01", "Hand Wave_rig_01"]:
		var hips := _skeleton.find_bone("mixamorig_Hips")
		var before := _skeleton.get_bone_pose_rotation(hips)
		_play_batch_oneshot(anim_name)
		var shot_time := minf(4.0, _player.get_animation(anim_name).length * 0.45)
		_player.seek(shot_time, true)
		_player.advance(0.0)
		var during := _skeleton.get_bone_pose_rotation(hips)
		lines.append(anim_name + "_playing=" + _player.assigned_animation)
		lines.append(anim_name + "_pose_changed=" + str(not before.is_equal_approx(during)))
		lines.append(anim_name + "_loop=" + str(_player.get_animation(anim_name).loop_mode))
		await _save_check_png("C:/Users/29385/AppData/Local/Temp/youyou_batch_%s.png" % anim_name.replace(" ", "_"))
		_player.speed_scale = 40.0
		var finished := false
		var waited := 0.0
		while waited < 1.2:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if _player.assigned_animation == IDLE_ANIM and _player.is_playing() and _oneshot_name == "":
				finished = true
				break
		_player.speed_scale = 1.0
		lines.append(anim_name + "_returned=" + str(finished) + " anim=" + _player.assigned_animation)
	_apply_emote("surprise")
	_play_batch_oneshot("hello01")
	var body := _find_mesh("人体_001")
	var surprise_index := body.find_blend_shape_by_name("surprise")
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("interrupt_anim=" + _player.assigned_animation)
	lines.append("interrupt_oneshot=" + _oneshot_name)
	lines.append("surprise_after_interrupt=" + str(body.get_blend_shape_value(surprise_index)))
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key4=" + _player.assigned_animation)
	_push_key(KEY_5)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key5=" + _player.assigned_animation)
	_start_hello()
	lines.append("hello_still=" + _player.assigned_animation + " active=" + str(_hello_active))
	print("\n".join(lines))
	get_tree().quit()


func _run_idle_check() -> void:
	var lines: PackedStringArray = []
	var hips := _skeleton.find_bone("mixamorig_Hips")
	for keycode in IDLE_VARIANTS.keys():
		var anim_name := String(IDLE_VARIANTS[keycode])
		_play_idle_variant(anim_name)
		var anim := _player.get_animation(anim_name)
		_player.seek(0.0, true)
		var start_pose := _skeleton.get_bone_pose_rotation(hips)
		_player.seek(anim.length * 0.4, true)
		_player.advance(0.0)
		var mid_pose := _skeleton.get_bone_pose_rotation(hips)
		lines.append("%s loop=%s len=%.3f moved=%s" % [anim_name, anim.loop_mode, anim.length, not start_pose.is_equal_approx(mid_pose)])
		await _save_check_png("C:/Users/29385/AppData/Local/Temp/youyou_idle_%s.png" % anim_name)
		_player.seek(maxf(anim.length - 0.05, 0.0), true)
		_player.advance(0.2)
		var wrapped := _player.assigned_animation == anim_name and _player.is_playing() and _player.current_animation_position < 0.5
		lines.append("%s wrapped=%s pos=%.3f" % [anim_name, wrapped, _player.current_animation_position])
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("after_i=" + _player.assigned_animation)
	_push_key(KEY_Q)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_q=" + _player.assigned_animation)
	_push_key(KEY_Z)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_z=" + _player.assigned_animation)
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_4=" + _player.assigned_animation + " oneshot=" + _oneshot_name)
	print("\n".join(lines))
	get_tree().quit()


func _run_new_anim_check() -> void:
	for _i in 5:
		await get_tree().process_frame
	var pivot := get_node("ObservePivot") as Node3D
	var camera := pivot.get_node("Camera3D") as Camera3D
	var pivot_before := pivot.global_transform
	var camera_before := camera.global_transform
	var body := _find_mesh("人体_001")
	var surprise_index := body.find_blend_shape_by_name("surprise")
	_apply_emote("surprise")
	var lines: PackedStringArray = []
	lines.append_array(_compat_lines)
	lines.append("alias=youyou_Basic_Idle01<=youyou_Basic_Idle01_001")
	lines.append("source_name_hidden=" + str(not _player.has_animation("youyou_Basic_Idle01_001")))
	lines.append("skipped_04=" + str(not _player.has_animation("youyou_Hello_Idle04")))
	lines.append("skipped_05=" + str(not _player.has_animation("youyou_Hello_Idle05")))
	lines.append("kept_hello01=" + str(_player.has_animation(HELLO_ANIM)))
	lines.append("kept_hello=" + str(_player.has_animation("hello01")))
	lines.append("kept_wave=" + str(_player.has_animation("Hand Wave_rig_01")))
	var hips := _skeleton.find_bone("mixamorig_Hips")
	var idle_name := "youyou_Basic_Idle01"
	var idle_clip := _player.get_animation(idle_name)
	_play_idle_variant(idle_name)
	_player.seek(0.0, true)
	_player.advance(0.0)
	var idle_start := _skeleton.get_bone_pose_rotation(hips)
	_player.seek(idle_clip.length * 0.4, true)
	_player.advance(0.0)
	var idle_mid := _skeleton.get_bone_pose_rotation(hips)
	lines.append("youyou_Basic_Idle01_loop=%s len=%.3f moved=%s playing=%s" % [
		idle_clip.loop_mode, idle_clip.length, not idle_start.is_equal_approx(idle_mid), _player.assigned_animation
	])
	await _save_check_png("C:/Users/29385/AppData/Local/Temp/youyou_new_youyou_Basic_Idle01.png")
	_player.seek(maxf(idle_clip.length - 0.05, 0.0), true)
	_player.advance(0.2)
	var wrapped := _player.assigned_animation == idle_name and _player.is_playing() and _player.current_animation_position < 0.5
	lines.append("youyou_Basic_Idle01_wrapped=%s pos=%.3f" % [wrapped, _player.current_animation_position])
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("youyou_Basic_Idle01_after_i=%s surprise=%.1f" % [
		_player.assigned_animation, body.get_blend_shape_value(surprise_index)
	])
	var attract_names: PackedStringArray = Approved.get_attract_whitelist()
	attract_names.erase("youyou_Hello_Idle01")
	for anim_name in attract_names:
		var clip := _player.get_animation(anim_name)
		var before := _skeleton.get_bone_pose_rotation(hips)
		_play_batch_oneshot(anim_name)
		_player.seek(minf(1.2, clip.length * 0.35), true)
		_player.advance(0.0)
		var during := _skeleton.get_bone_pose_rotation(hips)
		lines.append("%s loop=%s len=%.3f moved=%s playing=%s" % [
			anim_name, clip.loop_mode, clip.length, not before.is_equal_approx(during), _player.assigned_animation
		])
		await _save_check_png("C:/Users/29385/AppData/Local/Temp/youyou_new_%s.png" % anim_name)
		_player.speed_scale = 40.0
		var finished := false
		var waited := 0.0
		while waited < 2.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
			if _player.assigned_animation == IDLE_ANIM and _player.is_playing() and _oneshot_name == "" and not _hello_active:
				finished = true
				break
		_player.speed_scale = 1.0
		lines.append("%s returned=%s anim=%s surprise=%.1f" % [
			anim_name, finished, _player.assigned_animation, body.get_blend_shape_value(surprise_index)
		])
	_play_batch_oneshot("youyou_Hello_Idle02")
	_player.seek(0.8, true)
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("interrupt_i=%s oneshot=%s hello=%s surprise=%.1f" % [
		_player.assigned_animation, _oneshot_name, _hello_active, body.get_blend_shape_value(surprise_index)
	])
	_play_batch_oneshot("youyou_Hello_Idle03")
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("interrupt_h=%s hello_active=%s" % [_player.assigned_animation, _hello_active])
	_play_batch_oneshot("youyou_Hello_Idle06")
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("interrupt_4=%s oneshot=%s" % [_player.assigned_animation, _oneshot_name])
	var key_to_name := {
		KEY_X: "youyou_Basic_Idle01",
		KEY_6: "youyou_Hello_Idle02",
		KEY_7: "youyou_Hello_Idle03",
		KEY_8: "youyou_Hello_Idle06",
		KEY_9: "youyou_Hello_Idle07",
		KEY_B: "youyou_Hello_Idle08",
		KEY_N: "youyou_Hello_Idle09",
		KEY_Q: "Basic_Idle01",
		KEY_4: "hello01",
		KEY_5: "Hand Wave_rig_01",
	}
	for keycode in key_to_name.keys():
		_push_key(keycode)
		await get_tree().process_frame
		await get_tree().process_frame
		lines.append("key_%s=%s" % [key_to_name[keycode], _player.assigned_animation])
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_H=%s" % _player.assigned_animation)
	lines.append("pivot_same=" + str(pivot.global_transform.is_equal_approx(pivot_before)))
	lines.append("camera_same=" + str(camera.global_transform.is_equal_approx(camera_before)))
	lines.append("surprise_final=%.1f" % body.get_blend_shape_value(surprise_index))
	print("\n".join(lines))
	get_tree().quit()


func _run_preview_event_check() -> void:
	var lines: PackedStringArray = []
	var ok := true
	EventCatalog.ensure_loaded()
	for action_id in EventActionPerformance.PREVIEW_EVENT_WHITELIST:
		var check: Dictionary = _event_perf.validate_event(action_id)
		var pass_entry := bool(check.get("ok", false))
		lines.append(
			"%s ok=%s scene=%s audio=%s errors=%s"
			% [
				action_id,
				str(pass_entry),
				String(check.get("scene", "")),
				String(check.get("audio", "")),
				",".join(check.get("errors", [])),
			]
		)
		ok = ok and pass_entry
	var coin_map := _show_adapter != null
	lines.append("show_adapter_ready=%s" % str(coin_map))
	lines.append("=== preview_event_check_pass=%s ===" % str(ok))
	var report := "\n".join(lines)
	print(report)
	get_tree().quit()


func _run_approved_pool_check() -> void:
	var lines: PackedStringArray = []
	lines.append("light_pool=" + ",".join(_light_pool))
	lines.append("attract_pool=" + ",".join(_attract_pool))
	var ok := _light_pool.size() == Approved.get_light_idle_whitelist().size()
	ok = ok and _attract_pool.size() == Approved.get_attract_whitelist().size()
	for action_id in ["hello01", "Hand Wave_rig_01", "youyou_Hello_Idle04", "youyou_Hello_Idle09", "youyou_Basic_Idle06", "Basic_Idle01"]:
		var absent := not _player.has_animation(action_id)
		lines.append("unapproved_absent_%s=%s" % [action_id, str(absent)])
		ok = ok and absent
	ok = ok and ("youyou_Hello_Idle05" in _attract_pool)
	ok = ok and _is_approved_action("youyou_Basic_Idle01")
	var sample: Dictionary = Approved.get_params("youyou_Hello_Idle08")
	ok = ok and float(sample.get("audio_start_offset", 0.0)) > 3.0
	lines.append("sample_hello08_offset=%.2f" % float(sample.get("audio_start_offset", 0.0)))
	lines.append("=== approved_pool_check_pass=%s ===" % str(ok))
	print("\n".join(lines))
	get_tree().quit()


func _run_schedule_check() -> void:
	for _frame in 4:
		await get_tree().process_frame
	var pivot := get_node("ObservePivot") as Node3D
	var camera := pivot.get_node("Camera3D") as Camera3D
	var pivot_before := pivot.global_transform
	var camera_before := camera.global_transform
	var lines: PackedStringArray = []
	var hips := _skeleton.find_bone("mixamorig_Hips")
	var body := _find_mesh("人体_001")
	var surprise_index := body.find_blend_shape_by_name("surprise")
	lines.append("light_pool=" + ",".join(_light_pool))
	lines.append("attract_pool=" + ",".join(_attract_pool))
	lines.append("timer_count=" + str(_count_timers(self)))
	lines.append("startup_anim=" + _player.assigned_animation)
	var light1 := await _await_auto_light(lines, "cycle1", hips)
	var light2 := await _await_auto_light(lines, "cycle2", hips)
	lines.append("light_not_repeat=" + str(light1 != "" and light2 != "" and light1 != light2))
	var attract1 := await _await_attract_from_base(lines, "pass1", hips)
	await _finish_auto_to_base(lines, "pass1")
	_player.seek(1.0, true)
	var held_anim := _player.assigned_animation
	var held_pos := _player.current_animation_position
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("m_during_attract_anim=" + _player.assigned_animation)
	lines.append("m_during_attract_same=" + str(_player.assigned_animation == held_anim and _player.current_animation_position > held_pos - 0.05))
	lines.append("m_during_attract_pending=" + str(_pending_attract_request))
	lines.append("m_during_attract_pos=" + str(snapped(_player.current_animation_position, 0.01)) + " from=" + str(snapped(held_pos, 0.01)))
	await _finish_auto_to_base(lines, "attract1")
	var attract2 := ""
	if _mode == ScheduleMode.BASE_IDLE:
		_push_key(KEY_M)
		await get_tree().process_frame
		await get_tree().process_frame
		attract2 = await _wait_for_attract_playing(3.0)
		lines.append("pass2_anim=" + attract2 + " mode=" + str(_mode) + " in_pool=" + str(attract2 in _attract_pool))
		lines.append("attract_not_repeat=" + str(attract1 != "" and attract2 != attract1))
		await _finish_auto_to_base(lines, "attract2")
	_wait_timer.stop()
	_on_light_wait_timeout()
	var interrupted_light := _player.assigned_animation
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("m_light_pending from=" + interrupted_light + " still=" + _player.assigned_animation + " pending=" + str(_pending_attract_request) + " mode=" + str(_mode))
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("manual_h=" + _player.assigned_animation + " mode=" + str(_mode) + " timer_stopped=" + str(_wait_timer.is_stopped()))
	_player.seek(1.0, true)
	var manual_anim := _player.assigned_animation
	var manual_pos := _player.current_animation_position
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("m_during_manual_same=" + str(_player.assigned_animation == manual_anim and absf(_player.current_animation_position - manual_pos) < 0.2))
	_player.speed_scale = 40.0
	var manual_returned := false
	var manual_waited := 0.0
	while manual_waited < 2.0:
		await get_tree().process_frame
		manual_waited += get_process_delta_time()
		if _player.assigned_animation == IDLE_ANIM and _player.is_playing() and _mode == ScheduleMode.MANUAL_TEST and _wait_timer.is_stopped():
			manual_returned = true
			break
	_player.speed_scale = 1.0
	lines.append("manual_end_no_auto=" + str(manual_returned) + " mode=" + str(_mode) + " timer_stopped=" + str(_wait_timer.is_stopped()))
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("after_i=%s mode=%s timer=%s wait=%.2f" % [_player.assigned_animation, _mode, not _wait_timer.is_stopped(), _planned_wait])
	_push_key(KEY_2)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("expr_anim=%s mode=%s timer=%s surprise=%.1f" % [
		_player.assigned_animation, _mode, not _wait_timer.is_stopped(), body.get_blend_shape_value(surprise_index)
	])
	_push_key(KEY_X)
	await get_tree().process_frame
	await get_tree().process_frame
	var x_loop := -1
	if _player.has_animation("youyou_Basic_Idle01"):
		x_loop = _player.get_animation("youyou_Basic_Idle01").loop_mode
	lines.append("key_x=%s loop=%s mode=%s timer_stopped=%s" % [
		_player.assigned_animation, x_loop, _mode, _wait_timer.is_stopped()
	])
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_4=" + _player.assigned_animation + " mode=" + str(_mode))
	_push_key(KEY_5)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_5=" + _player.assigned_animation)
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("i_restores=%s mode=%s timer=%s" % [_player.assigned_animation, _mode, not _wait_timer.is_stopped()])
	var previous := ""
	var adjacent := 0
	var seen := {}
	for _i in 40:
		var picked := _pick_name(_light_pool, previous)
		if picked == previous:
			adjacent += 1
		seen[picked] = true
		previous = picked
	lines.append("light_pick_adjacent=" + str(adjacent) + " unique=" + str(seen.size()) + " pool=" + str(_light_pool.size()))
	previous = ""
	adjacent = 0
	seen = {}
	for _i in 40:
		var picked := _pick_name(_attract_pool, previous)
		if picked == previous:
			adjacent += 1
		seen[picked] = true
		previous = picked
	lines.append("attract_pick_adjacent=" + str(adjacent) + " unique=" + str(seen.size()) + " pool=" + str(_attract_pool.size()))
	lines.append("excluded_04=" + str(not ("youyou_Hello_Idle04" in _attract_pool)))
	lines.append("included_05=" + str("youyou_Hello_Idle05" in _attract_pool))
	lines.append("excluded_09=" + str(not ("youyou_Hello_Idle09" in _attract_pool)))
	lines.append("excluded_youyou06=" + str(not ("youyou_Basic_Idle06" in _light_pool)))
	lines.append("excluded_hello01=" + str(not _player.has_animation("hello01")))
	lines.append("excluded_hand_wave=" + str(not _player.has_animation("Hand Wave_rig_01")))
	lines.append("pivot_same=" + str(pivot.global_transform.is_equal_approx(pivot_before)))
	lines.append("camera_same=" + str(camera.global_transform.is_equal_approx(camera_before)))
	_player.speed_scale = 1.0
	print("\n".join(lines))
	get_tree().quit()


func _await_auto_light(lines: PackedStringArray, label: String, hips: int) -> String:
	var started_msec := _wait_armed_msec
	var planned := _planned_wait
	var seen := ""
	var waited := 0.0
	while waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _mode == ScheduleMode.LIGHT_IDLE:
			seen = _player.assigned_animation
			break
	var elapsed := (Time.get_ticks_msec() - started_msec) / 1000.0
	var moved := false
	var loop_mode := -1
	if seen != "":
		var before := _skeleton.get_bone_pose_rotation(hips)
		_player.seek(minf(0.8, _player.get_animation(seen).length * 0.35), true)
		_player.advance(0.0)
		moved = not before.is_equal_approx(_skeleton.get_bone_pose_rotation(hips))
		loop_mode = _player.get_animation(seen).loop_mode
	lines.append("%s light=%s in_pool=%s loop=%s moved=%s planned=%.2f elapsed=%.2f" % [
		label, seen, seen in _light_pool, loop_mode, moved, planned, elapsed
	])
	await _finish_auto_to_base(lines, label)
	return seen


func _await_attract_from_base(lines: PackedStringArray, label: String, hips: int) -> String:
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	var queued := _pending_attract_request
	var still_idle := _player.assigned_animation == IDLE_ANIM and _mode == ScheduleMode.BASE_IDLE
	lines.append("%s queued=%s still_idle=%s timer_stopped=%s" % [label, queued, still_idle, _wait_timer.is_stopped()])
	var anim_name := await _wait_for_attract_playing(4.0)
	var before := _skeleton.get_bone_pose_rotation(hips)
	if _player.has_animation(anim_name):
		_player.seek(minf(0.8, _player.get_animation(anim_name).length * 0.25), true)
		_player.advance(0.0)
	var moved := not before.is_equal_approx(_skeleton.get_bone_pose_rotation(hips))
	var loop_mode := _player.get_animation(anim_name).loop_mode if _player.has_animation(anim_name) else -1
	lines.append("%s attract=%s mode=%s in_pool=%s loop=%s moved=%s" % [
		label, anim_name, _mode, anim_name in _attract_pool, loop_mode, moved
	])
	return anim_name


func _wait_for_attract_playing(limit: float) -> String:
	var length := _player.current_animation_length
	_player.seek(maxf(length - 0.04, 0.0), true)
	var waited := 0.0
	while waited < limit:
		await get_tree().process_frame
		waited += get_process_delta_time()
		_player.advance(get_process_delta_time())
		if _mode == ScheduleMode.ATTRACT and _player.assigned_animation in _attract_pool:
			return String(_player.assigned_animation)
	return String(_player.assigned_animation)


func _finish_auto_to_base(lines: PackedStringArray, label: String) -> void:
	_player.speed_scale = 40.0
	var returned := false
	var waited := 0.0
	while waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _mode == ScheduleMode.BASE_IDLE and _player.assigned_animation == IDLE_ANIM and _player.is_playing() and not _wait_timer.is_stopped():
			returned = true
			break
	_player.speed_scale = 1.0
	lines.append("%s returned=%s anim=%s mode=%s wait=%.2f timer=%s" % [
		label, returned, _player.assigned_animation, _mode, _planned_wait, not _wait_timer.is_stopped()
	])


func _count_timers(node: Node) -> int:
	var count := 1 if node is Timer else 0
	for child in node.get_children():
		count += _count_timers(child)
	return count


func _run_expression_check() -> void:
	for _frame in 3:
		await get_tree().process_frame
	var body := _find_mesh("人体_001")
	if body == null:
		body = _find_mesh("人体.001")
	var lines: PackedStringArray = []
	var smile_i := body.find_blend_shape_by_name("smile")
	lines.append("mesh_count=%d" % _meshes.size())
	lines.append("startup_active=" + _face.get_active_primary())
	lines.append("startup_legacy_smile=%.3f eyes_smile=%.3f mouth_smile=%.3f" % [
		body.get_blend_shape_value(smile_i) if smile_i >= 0 else -1.0,
		_face.read_shape_on_body("Eyes_smile"),
		_face.read_shape_on_body("Mouth_smile"),
	])
	_apply_emote("smile")
	await get_tree().create_timer(0.25).timeout
	lines.append("after_1_smile split=%.3f legacy=%.3f" % [
		_face.read_primary_on_mesh(body, "smile"), body.get_blend_shape_value(smile_i) if smile_i >= 0 else -1.0
	])
	_apply_emote("surprise")
	await get_tree().create_timer(0.25).timeout
	lines.append("after_2_surprise split=%.3f legacy=%.3f active=%s" % [
		_face.read_primary_on_mesh(body, "surprise"),
		_read_legacy_on_body(body, "surprise"),
		_face.get_active_primary(),
	])
	_apply_emote("sad")
	await get_tree().create_timer(0.25).timeout
	lines.append("after_v_sad split=%.3f" % [_face.read_primary_on_mesh(body, "sad")])
	_apply_emote("laugh")
	await get_tree().create_timer(0.25).timeout
	lines.append("chain_laugh split=%.3f" % [_face.read_primary_on_mesh(body, "laugh")])
	_apply_emote("laugh")
	await get_tree().process_frame
	_apply_emote("angry")
	await get_tree().create_timer(0.25).timeout
	lines.append("rapid_to_angry surprise_legacy=%.3f angry_split=%.3f active=%s" % [
		_read_legacy_on_body(body, "surprise"), _face.read_primary_on_mesh(body, "angry"), _face.get_active_primary()
	])
	var synced := 0
	var mesh_count := 0
	for mesh in _meshes:
		var ev := mesh.find_blend_shape_by_name("Eyes_angry")
		var mv := mesh.find_blend_shape_by_name("Mouth_angry")
		if ev < 0 and mv < 0:
			continue
		mesh_count += 1
		var peak := 0.0
		if ev >= 0:
			peak = maxf(peak, mesh.get_blend_shape_value(ev))
		if mv >= 0:
			peak = maxf(peak, mesh.get_blend_shape_value(mv))
		if peak > 0.5:
			synced += 1
	lines.append("angry_sync_meshes=%d/%d" % [synced, mesh_count])
	_push_key(KEY_J)
	await get_tree().create_timer(0.25).timeout
	var wink_i := body.find_blend_shape_by_name("wink")
	lines.append("after_j_wink composite=%.3f active=%s" % [
		body.get_blend_shape_value(wink_i) if wink_i >= 0 else -1.0, _face.get_active_primary()
	])
	_push_key(KEY_K)
	await get_tree().create_timer(0.25).timeout
	var look_i := body.find_blend_shape_by_name("lookleft")
	lines.append("after_k_lookleft composite=%.3f" % [body.get_blend_shape_value(look_i) if look_i >= 0 else -1.0])
	for keycode in [KEY_C, KEY_V, KEY_P, KEY_L]:
		_push_key(keycode)
		await get_tree().create_timer(0.22).timeout
	lines.append("after_cvpL_active=" + _face.get_active_primary())
	_push_key(KEY_0)
	await get_tree().create_timer(0.25).timeout
	lines.append("after_0_split_smile=%.3f legacy_smile=%.3f active=%s" % [
		_face.read_primary_on_mesh(body, "smile"),
		body.get_blend_shape_value(smile_i) if smile_i >= 0 else -1.0,
		_face.get_active_primary(),
	])
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key4_anim=%s face=%s" % [_player.assigned_animation, _face.get_active_primary()])
	_push_key(KEY_M)
	await get_tree().process_frame
	lines.append("m_pending=%s anim=%s face=%s" % [_pending_attract_request, _player.assigned_animation, _face.get_active_primary()])
	_apply_emote("missing_expression_probe")
	lines.append("missing_failed=" + str("missing_expression_probe" in "\n".join(_log_lines)))
	var ok: bool = (
		_face.read_shape_on_body("Eyes_smile") > 0.85
		and _read_legacy_on_body(body, "smile") < 0.05
		and synced >= maxi(mesh_count - 1, 1)
	)
	lines.append("=== face_expression_check_pass=%s ===" % str(ok))
	print("\n".join(lines))
	get_tree().quit()


func _read_legacy_on_body(body: MeshInstance3D, shape_name: String) -> float:
	var idx := body.find_blend_shape_by_name(shape_name)
	if idx < 0:
		return -1.0
	return body.get_blend_shape_value(idx)


func _run_viseme_coord_check() -> void:
	for _frame in 3:
		await get_tree().process_frame
	var body := _find_mesh("人体_001")
	if body == null:
		body = _find_mesh("人体.001")
	var lines: PackedStringArray = []
	_face.reset_all(0.0)
	await get_tree().process_frame
	_apply_emote("surprise")
	await get_tree().create_timer(0.25).timeout
	_apply_viseme("a")
	await get_tree().create_timer(0.25).timeout
	var a_body: float = _face.read_viseme_on_mesh(body, "a")
	var eyes_surprise_during: float = _face.read_shape_on_body("Eyes_surprise")
	lines.append("surprise_plus_a split_surprise=%.3f legacy_smile=%.3f A=%.3f mouth_surprise=%.3f eyes=%.3f" % [
		_face.read_primary_on_mesh(body, "surprise"),
		_read_legacy_on_body(body, "smile"),
		a_body,
		_face.read_shape_on_body("Mouth_surprise"),
		eyes_surprise_during,
	])
	var tooth := _find_mesh("上牙")
	var tongue := _find_mesh("舌头")
	lines.append("participants_a tooth=%.3f tongue=%.3f leak=%.4f" % [
		_face.read_viseme_on_mesh(tooth, "a"), _face.read_viseme_on_mesh(tongue, "a"),
		_face.max_viseme_weight_excluding("a", 0.03)
	])
	await _run_clear_viseme_coordinator()
	await get_tree().create_timer(0.3).timeout
	lines.append("after_clear_surprise split=%.3f all_zero=%s restore=%s" % [
		_face.read_primary_on_mesh(body, "surprise"), _face.all_visemes_near_zero(0.03),
		_face.get_active_primary()
	])
	_apply_viseme("u")
	await get_tree().process_frame
	_apply_emote("laugh")
	await get_tree().process_frame
	await _run_clear_viseme_coordinator()
	await get_tree().create_timer(0.3).timeout
	lines.append("defer_laugh split=%.3f u=%.3f" % [
		_face.read_primary_on_mesh(body, "laugh"), _face.read_viseme_on_mesh(body, "u")
	])
	_apply_emote("smile")
	await get_tree().create_timer(0.2).timeout
	_apply_viseme("o")
	await get_tree().process_frame
	_apply_viseme("e")
	await get_tree().process_frame
	_apply_viseme("i")
	await get_tree().create_timer(0.25).timeout
	lines.append("rapid_i leak=%.4f" % _face.max_viseme_weight_excluding("i", 0.03))
	await _run_clear_viseme_coordinator()
	await get_tree().create_timer(0.3).timeout
	lines.append("final_smile=%.3f visemes_zero=%s" % [
		_face.read_primary_on_mesh(body, "smile"), _face.all_visemes_near_zero(0.03)
	])
	_push_key(KEY_4)
	await get_tree().process_frame
	var viseme_min: float = FacePresenter.APPROVED_VISEME_COEF * 0.92
	var ok: bool = (
		a_body > viseme_min
		and eyes_surprise_during > 0.85
		and _face.read_primary_on_mesh(body, "smile") > 0.85
		and _face.all_visemes_near_zero(0.03)
	)
	lines.append("=== viseme_coord_check_pass=%s ===" % str(ok))
	lines.append("regression_anim=%s" % _player.assigned_animation)
	print("\n".join(lines))
	get_tree().quit()


func _run_viseme_check() -> void:
	for _frame in 3:
		await get_tree().process_frame
	var body := _find_mesh("人体_001")
	if body == null:
		body = _find_mesh("人体.001")
	var lines: PackedStringArray = []
	for vid in ["a", "e", "i", "o", "u"]:
		_apply_viseme(vid)
		await get_tree().create_timer(0.25).timeout
		lines.append("viseme_%s sample=%.3f" % [vid, _face.read_viseme_on_mesh(body, vid)])
	var synced := 0
	var mesh_count := 0
	for mesh in _meshes:
		if not _face.is_viseme_participant_mesh(mesh):
			continue
		var v: float = _face.read_viseme_on_mesh(mesh, "u")
		if v < 0.0:
			continue
		mesh_count += 1
		if v > 0.85:
			synced += 1
	lines.append("viseme_u_participant_sync=%d/%d" % [synced, mesh_count])
	_apply_viseme("o")
	await get_tree().create_timer(0.25).timeout
	var brow := _find_mesh("眉毛")
	var eye_r := _find_mesh("眼睛右")
	var brow_o: float = _face.read_viseme_on_mesh(brow, "o") if brow != null else -1.0
	var eye_o: float = _face.read_viseme_on_mesh(eye_r, "o") if eye_r != null else -1.0
	var body_o: float = _face.read_viseme_on_mesh(body, "o")
	lines.append("partition_brow_o=%.3f eye_r_o=%.3f body_o=%.3f" % [brow_o, eye_o, body_o])
	_apply_viseme("a")
	await get_tree().process_frame
	_apply_viseme("o")
	await get_tree().create_timer(0.25).timeout
	lines.append("switch_a_to_o a=%.3f o=%.3f" % [
		_face.read_viseme_on_mesh(body, "a"), _face.read_viseme_on_mesh(body, "o")
	])
	await _run_clear_viseme_coordinator()
	await get_tree().create_timer(0.08).timeout
	lines.append("after_clear active=%s o=%.3f" % [_face.get_active_viseme(), _face.read_viseme_on_mesh(body, "o")])
	_apply_emote("smile")
	_apply_viseme("a")
	await get_tree().create_timer(0.25).timeout
	lines.append("coexist_smile_a split=%.3f A=%.3f face=%s" % [
		_face.read_primary_on_mesh(body, "smile"), _face.read_viseme_on_mesh(body, "a"), _face.get_active_primary()
	])
	_apply_emote("surprise")
	_apply_viseme("u")
	await get_tree().create_timer(0.25).timeout
	lines.append("coexist_surprise_u split=%.3f u=%.3f" % [
		_face.read_primary_on_mesh(body, "surprise"), _face.read_viseme_on_mesh(body, "u")
	])
	_apply_viseme("e")
	await get_tree().process_frame
	_apply_viseme("i")
	await get_tree().process_frame
	_apply_viseme("e")
	await get_tree().create_timer(0.25).timeout
	lines.append("rapid_e_i_e e=%.3f i=%.3f" % [_face.read_viseme_on_mesh(body, "e"), _face.read_viseme_on_mesh(body, "i")])
	if not _face.set_viseme("invalid_viseme"):
		lines.append("missing_viseme_rejected=true")
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("regression_key4=%s face=%s viseme=%s" % [
		_player.assigned_animation, _face.get_active_primary(), _face.get_active_viseme()
	])
	print("\n".join(lines))
	get_tree().quit()


func _run_expression_isolation_check() -> void:
	for _frame in 3:
		await get_tree().process_frame
	var body := _find_mesh("人体_001")
	if body == null:
		body = _find_mesh("人体.001")
	var lines: PackedStringArray = []
	for primary in ["smile", "surprise", "laugh", "wink", "grin", "angry"]:
		_apply_emote(primary)
		await get_tree().create_timer(0.25).timeout
		var ok := false
		if primary in FacePresenter.GAZE_KEYS:
			var idx := body.find_blend_shape_by_name(primary)
			var v := body.get_blend_shape_value(idx) if idx >= 0 else -1.0
			ok = v > 0.85 and _read_legacy_on_body(body, "smile") < 0.05
			lines.append("isolated_%s composite=%.3f ok=%s" % [primary, v, str(ok)])
		else:
			var split_v: float = _face.read_primary_on_mesh(body, primary)
			var legacy_v := _read_legacy_on_body(body, primary)
			ok = split_v > 0.85 and legacy_v < 0.05
			lines.append("isolated_%s split=%.3f legacy=%.3f ok=%s" % [primary, split_v, legacy_v, str(ok)])
	print("\n".join(lines))
	get_tree().quit()


func _run_pending_attract_check() -> void:
	for _frame in 4:
		await get_tree().process_frame
	var lines: PackedStringArray = []
	_wait_timer.stop()
	_mode = ScheduleMode.BASE_IDLE
	_start_idle(true)
	lines.append("idle_len=%.3f" % _player.current_animation_length)
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("base_m queued=%s anim=%s mode=%s timer_stopped=%s" % [
		_pending_attract_request, _player.assigned_animation, _mode, _wait_timer.is_stopped()
	])
	_on_light_wait_timeout()
	lines.append("pending_blocks_light=%s" % str(_player.assigned_animation == IDLE_ANIM and _mode == ScheduleMode.BASE_IDLE))
	_push_key(KEY_M)
	await get_tree().process_frame
	lines.append("duplicate_m_ignored=%s" % str(_pending_attract_request))
	var attract_after_cycle := await _wait_for_attract_playing(4.0)
	lines.append("base_cycle_attract=%s mode=%s pending=%s" % [attract_after_cycle, _mode, _pending_attract_request])
	_player.speed_scale = 40.0
	await _finish_auto_to_base(lines, "attract_return")
	_player.speed_scale = 1.0
	_wait_timer.stop()
	_on_light_wait_timeout()
	var light_name := String(_player.assigned_animation)
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("light_m queued=%s still_light=%s anim=%s" % [
		_pending_attract_request, _player.assigned_animation == light_name and _mode == ScheduleMode.LIGHT_IDLE, _player.assigned_animation
	])
	_player.speed_scale = 40.0
	var waited := 0.0
	var direct_attract := ""
	while waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _mode == ScheduleMode.ATTRACT:
			direct_attract = String(_player.assigned_animation)
			break
	_player.speed_scale = 1.0
	lines.append("light_to_attract=%s skipped_base=%s" % [direct_attract, direct_attract != "" and direct_attract in _attract_pool])
	await _finish_auto_to_base(lines, "light_chain")
	_wait_timer.stop()
	_play_auto_attract()
	await get_tree().process_frame
	await get_tree().process_frame
	var during := String(_player.assigned_animation)
	var during_mode := _mode
	_push_key(KEY_M)
	await get_tree().process_frame
	_push_key(KEY_M)
	await get_tree().process_frame
	lines.append("attract_double_m pending=%s anim=%s mode=%s held=%s" % [
		_pending_attract_request, during, during_mode, _player.assigned_animation == during and _mode == ScheduleMode.ATTRACT
	])
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("manual_m_ignored pending=%s mode=%s" % [_pending_attract_request, _mode])
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("i_clears pending=%s timer=%s anim=%s" % [_pending_attract_request, not _wait_timer.is_stopped(), _player.assigned_animation])
	print("\n".join(lines))
	get_tree().quit()


func _run_blend_check() -> void:
	_wait_timer.stop()
	for _frame in 4:
		await get_tree().process_frame
	var pivot := get_node("ObservePivot") as Node3D
	var camera := pivot.get_node("Camera3D") as Camera3D
	var pivot_before := pivot.global_transform
	var camera_before := camera.global_transform
	var lines: PackedStringArray = []
	var body := _find_mesh("人体_001")
	var surprise_index := body.find_blend_shape_by_name("surprise")
	lines.append("default_blend=" + str(_player.playback_default_blend_time))
	var saved_rots: Dictionary = _snapshot_bone_rotations()
	var returns_before := _auto_return_count
	_play_auto_light()
	var light_name := String(_player.assigned_animation)
	var light_pos := _player.current_animation_position
	var gap := _largest_rotation_gap(saved_rots, light_name)
	var gap_bone := String(gap["bone"])
	var gap_amount := float(gap["gap"])
	var bone_index := _skeleton.find_bone(gap_bone)
	await get_tree().process_frame
	var early_delta := _rotation_delta(saved_rots, gap_bone)
	await get_tree().create_timer(0.12).timeout
	var mid_delta := _rotation_delta(saved_rots, gap_bone)
	await get_tree().create_timer(0.2).timeout
	var late_delta := _rotation_delta(saved_rots, gap_bone)
	var late_to_target := 0.0
	if bone_index >= 0:
		var target_now := _bone_rotation_at(light_name, gap_bone, _player.current_animation_position)
		late_to_target = _skeleton.get_bone_pose_rotation(bone_index).angle_to(target_now)
	var root_delta := _hips_position_at(IDLE_ANIM, 0.0).distance_to(_hips_position_at(light_name, 0.0))
	lines.append("base_to_light anim=%s loop=%s start_pos=%.3f blend=%.2f bone=%s gap=%.4f early=%.4f mid=%.4f late=%.4f late_to_target=%.4f root_delta=%.4f" % [
		light_name, _player.get_animation(light_name).loop_mode, light_pos, _last_blend, gap_bone, gap_amount, early_delta, mid_delta, late_delta, late_to_target, root_delta
	])
	lines.append("base_to_light_eased=" + str(gap_amount > 0.05 and early_delta < gap_amount * 0.45 and late_delta > early_delta))
	_player.seek(maxf(_player.current_animation_length - 0.04, 0.0), true)
	var end_pose := _snapshot_bone_rotations()
	var back_gap := _largest_rotation_gap(end_pose, IDLE_ANIM)
	var back_bone := String(back_gap["bone"])
	var back_amount := float(back_gap["gap"])
	var back_root := _skeleton.get_bone_pose_position(_skeleton.find_bone("mixamorig_Hips")).distance_to(_hips_position_at(IDLE_ANIM, 0.0))
	await get_tree().create_timer(0.08).timeout
	var back_early := _rotation_delta(end_pose, back_bone)
	await get_tree().create_timer(0.15).timeout
	var back_mid := _rotation_delta(end_pose, back_bone)
	await get_tree().create_timer(0.2).timeout
	var back_late := _rotation_delta(end_pose, back_bone)
	lines.append("light_to_base bone=%s gap=%.4f early=%.4f mid=%.4f late=%.4f blend=%.2f anim=%s root=%.4f" % [
		back_bone, back_amount, back_early, back_mid, back_late, _last_blend, _player.assigned_animation, back_root
	])
	lines.append("light_to_base_eased=" + str(back_amount > 0.15 and back_early < back_amount * 0.55 and back_late > back_early))
	_player.speed_scale = 40.0
	var light_returned := await _await_base_idle(2.0)
	_player.speed_scale = 1.0
	lines.append("light_returned=%s returns=%d anim=%s blend=%.2f timer=%s" % [
		light_returned, _auto_return_count - returns_before, _player.assigned_animation, _last_blend, not _wait_timer.is_stopped()
	])
	_wait_timer.stop()
	returns_before = _auto_return_count
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	var attract_name := String(_player.assigned_animation)
	await get_tree().create_timer(0.12).timeout
	lines.append("base_to_attract anim=%s blend=%.2f mode=%s still=%s timer_stopped=%s" % [
		attract_name, _last_blend, _mode, _player.assigned_animation == attract_name and _mode == ScheduleMode.ATTRACT, _wait_timer.is_stopped()
	])
	_player.speed_scale = 40.0
	var attract_returned := await _await_base_idle(2.0)
	_player.speed_scale = 1.0
	lines.append("attract_returned=%s returns=%d anim=%s blend=%.2f" % [
		attract_returned, _auto_return_count - returns_before, _player.assigned_animation, _last_blend
	])
	_wait_timer.stop()
	_play_auto_light()
	var interrupted := String(_player.assigned_animation)
	_player.seek(maxf(_player.current_animation_length - 0.05, 0.0), true)
	returns_before = _auto_return_count
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	var interrupt_blend := _last_blend
	var interrupt_anim := String(_player.assigned_animation)
	await get_tree().create_timer(0.45).timeout
	lines.append("m_interrupts from=%s to=%s blend=%.2f held=%s mode=%s returns=%d" % [
		interrupted, interrupt_anim, interrupt_blend, _player.assigned_animation == interrupt_anim and _mode == ScheduleMode.ATTRACT, _mode, _auto_return_count - returns_before
	])
	_player.seek(1.2, true)
	var held_pos := _player.current_animation_position
	_push_key(KEY_M)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("m_ignored anim=%s pos=%.2f" % [_player.assigned_animation, _player.current_animation_position])
	lines.append("m_ignored_held=" + str(_player.assigned_animation == interrupt_anim and _player.current_animation_position > held_pos - 0.05))
	_player.speed_scale = 40.0
	var interrupt_returned := await _await_base_idle(2.0)
	_player.speed_scale = 1.0
	lines.append("interrupt_returned=%s anim=%s" % [interrupt_returned, _player.assigned_animation])
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_h=%s mode=%s timer_stopped=%s" % [_player.assigned_animation, _mode, _wait_timer.is_stopped()])
	_player.seek(2.0, true)
	_push_key(KEY_H)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("hello_restart_pos=%.3f" % _player.current_animation_position)
	_push_key(KEY_4)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_4=" + _player.assigned_animation)
	_push_key(KEY_5)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_5=" + _player.assigned_animation)
	_push_key(KEY_X)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_x=%s loop=%s" % [_player.assigned_animation, _player.get_animation("youyou_Basic_Idle01").loop_mode])
	_push_key(KEY_6)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_6=" + _player.assigned_animation)
	_push_key(KEY_I)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("key_i=%s mode=%s timer=%s" % [_player.assigned_animation, _mode, not _wait_timer.is_stopped()])
	_push_key(KEY_2)
	await get_tree().process_frame
	await get_tree().process_frame
	lines.append("expr anim=%s timer=%s surprise=%.1f" % [
		_player.assigned_animation, not _wait_timer.is_stopped(), body.get_blend_shape_value(surprise_index)
	])
	lines.append("pivot_same=" + str(pivot.global_transform.is_equal_approx(pivot_before)))
	lines.append("camera_same=" + str(camera.global_transform.is_equal_approx(camera_before)))
	lines.append("default_blend_after=" + str(_player.playback_default_blend_time))
	_player.speed_scale = 1.0
	print("\n".join(lines))
	get_tree().quit()


func _await_base_idle(limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _mode == ScheduleMode.BASE_IDLE and _player.assigned_animation == IDLE_ANIM and _player.is_playing() and not _wait_timer.is_stopped():
			return true
	return false


func _snapshot_bone_rotations() -> Dictionary:
	var saved: Dictionary = {}
	for index in _skeleton.get_bone_count():
		saved[_skeleton.get_bone_name(index)] = _skeleton.get_bone_pose_rotation(index)
	return saved


func _largest_rotation_gap(saved: Dictionary, anim_name: String) -> Dictionary:
	var best_bone := ""
	var best_gap := 0.0
	var clip := _player.get_animation(anim_name)
	for index in clip.get_track_count():
		if clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := String(clip.track_get_path(index).get_concatenated_subnames())
		if not saved.has(bone_name) or _skeleton.find_bone(bone_name) < 0:
			continue
		var target := clip.rotation_track_interpolate(index, 0.0)
		var gap := (saved[bone_name] as Quaternion).angle_to(target)
		if gap > best_gap:
			best_gap = gap
			best_bone = bone_name
	return {"bone": best_bone, "gap": best_gap}


func _rotation_delta(saved: Dictionary, bone_name: String) -> float:
	var index := _skeleton.find_bone(bone_name)
	if index < 0 or not saved.has(bone_name):
		return 0.0
	return (saved[bone_name] as Quaternion).angle_to(_skeleton.get_bone_pose_rotation(index))


func _bone_rotation_at(anim_name: String, bone_name: String, time: float) -> Quaternion:
	var clip := _player.get_animation(anim_name)
	for index in clip.get_track_count():
		if clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
			continue
		if String(clip.track_get_path(index).get_concatenated_subnames()) != bone_name:
			continue
		return clip.rotation_track_interpolate(index, time)
	return Quaternion.IDENTITY


func _hips_rotation_at(anim_name: String, time: float) -> Quaternion:
	var track := _hips_track(anim_name, Animation.TYPE_ROTATION_3D)
	if track < 0:
		return Quaternion.IDENTITY
	return _player.get_animation(anim_name).rotation_track_interpolate(track, time)


func _hips_position_at(anim_name: String, time: float) -> Vector3:
	var track := _hips_track(anim_name, Animation.TYPE_POSITION_3D)
	if track < 0:
		return Vector3.ZERO
	return _player.get_animation(anim_name).position_track_interpolate(track, time)


func _hips_track(anim_name: String, track_type: Animation.TrackType) -> int:
	if _player == null or not _player.has_animation(anim_name):
		return -1
	var clip := _player.get_animation(anim_name)
	for index in clip.get_track_count():
		if clip.track_get_type(index) != track_type:
			continue
		if String(clip.track_get_path(index).get_concatenated_subnames()) == "mixamorig_Hips":
			return index
	return -1


func _save_check_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("png %s err=%s" % [path, err])


const VISEME_DIAG_WATCH: PackedStringArray = [
	"A", "E", "i", "o", "u",
	"smile", "surprise", "laugh",
	"jawOpen", "mouthSmileLeft", "mouthSmileRight",
	"noseSneerLeft", "noseSneerRight", "jawForward",
]


func _run_viseme_diagnose() -> void:
	_schedule_enabled = false
	if _wait_timer != null:
		_wait_timer.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	_diagnose_freeze_idle_pose()
	var lines: PackedStringArray = []
	lines.append("=== viseme_diagnose_begin ===")
	lines.append("face_meshes=" + _diagnose_face_mesh_catalog())
	lines.append("anim=" + str(_player.assigned_animation if _player else "") + " playing=" + str(_player.is_playing() if _player else false))
	for vid in ["a", "e", "i", "o", "u"]:
		for group in ["A", "B", "C", "D"]:
			await _diagnose_apply_group(group, vid)
			await get_tree().create_timer(FacePresenter.VISEME_BLEND_TIME + 0.15).timeout
			var leak := _diagnose_viseme_leak(vid)
			lines.append("--- viseme=%s group=%s leak_other_viseme_max=%.4f ---" % [vid, group, leak])
			for mesh in _diagnose_face_meshes():
				lines.append(_diagnose_mesh_row(group, vid, mesh))
			if group == "B" or group == "C" or group == "D":
				lines.append(_diagnose_body_summary(group, vid))
	_diagnose_restore_production_default()
	lines.append("restore smile=" + _diagnose_read_shape(_find_body_mesh(), "smile"))
	lines.append("restore viseme_active=" + str(_face.get_active_viseme()))
	lines.append("=== viseme_diagnose_end ===")
	print("\n".join(lines))
	get_tree().quit()


func _diagnose_freeze_idle_pose() -> void:
	if _player == null:
		return
	if _player.has_animation(IDLE_ANIM):
		_player.play(IDLE_ANIM, 0.0)
		_player.seek(0.0, true)
		_player.pause()


func _diagnose_face_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh in _meshes:
		if mesh.find_blend_shape_by_name("A") >= 0:
			out.append(mesh)
	return out


func _diagnose_viseme_participant_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _face == null:
		return out
	for mesh in _meshes:
		if _face.is_viseme_participant_mesh(mesh):
			out.append(mesh)
	return out


func _diagnose_face_mesh_catalog() -> String:
	var parts: PackedStringArray = []
	var idx := 0
	for mesh in _diagnose_face_meshes():
		parts.append("%d:%s" % [idx, mesh.name])
		idx += 1
	return "|".join(parts)


func _find_body_mesh() -> MeshInstance3D:
	var body := _find_mesh("人体_001")
	if body == null:
		body = _find_mesh("人体.001")
	if body == null and not _diagnose_face_meshes().is_empty():
		body = _diagnose_face_meshes()[0]
	return body


func _diagnose_restore_production_default() -> void:
	if _face != null:
		_face.reset_all(0.0)


func _diagnose_apply_group(group: String, viseme_id: String) -> void:
	match group:
		"A":
			_diagnose_restore_production_default()
		"B":
			_diagnose_restore_production_default()
			_face.set_emotion("smile", 0.0)
			_face.set_viseme(viseme_id, 0.0)
		"C":
			_diagnose_restore_production_default()
			_face.set_viseme(viseme_id, 0.0)
		"D":
			_diagnose_restore_production_default()
			_face.set_viseme(viseme_id, FacePresenter.VISEME_BLEND_TIME)
		_:
			pass


func _diagnose_set_all_primary_weights(_smile_weight: float) -> void:
	if _face != null:
		_face.set_emotion("smile", 0.0)


func _diagnose_reset_p1_micro_baseline() -> void:
	pass


func _diagnose_read_shape(mesh: MeshInstance3D, shape_name: String) -> String:
	if mesh == null:
		return "na"
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index < 0:
		return "miss"
	return "%.3f" % mesh.get_blend_shape_value(index)


func _diagnose_viseme_leak(active_vid: String) -> float:
	var shape_for: Dictionary = {"a": "A", "e": "E", "i": "i", "o": "o", "u": "u"}
	var active_shape := String(shape_for.get(active_vid, ""))
	var max_leak := 0.0
	for mesh in _diagnose_face_meshes():
		for vid in ["a", "e", "i", "o", "u"]:
			var sh := String(FacePresenter.VISEME_SHAPE_NAMES[vid])
			if sh == active_shape:
				continue
			var index := mesh.find_blend_shape_by_name(sh)
			if index >= 0:
				max_leak = maxf(max_leak, mesh.get_blend_shape_value(index))
	return max_leak


func _diagnose_mesh_row(group: String, viseme_id: String, mesh: MeshInstance3D) -> String:
	var cols: PackedStringArray = ["grp=%s" % group, "v=%s" % viseme_id, "mesh=%s" % mesh.name]
	for shape_name in VISEME_DIAG_WATCH:
		cols.append("%s=%s" % [shape_name, _diagnose_read_shape(mesh, shape_name)])
	return " ".join(cols)


func _diagnose_body_summary(group: String, viseme_id: String) -> String:
	var body := _find_body_mesh()
	var shape_name := String(FacePresenter.VISEME_SHAPE_NAMES.get(viseme_id, ""))
	return "summary grp=%s v=%s body_%s=%s smile=%s anim_track_probe=%s" % [
		group, viseme_id, shape_name, _diagnose_read_shape(body, shape_name),
		_diagnose_read_shape(body, "smile"),
		_diagnose_animation_blendshape_probe(body)
	]


func _diagnose_animation_blendshape_probe(body: MeshInstance3D) -> String:
	if _player == null or body == null:
		return "no_player"
	var anim := _player.get_animation(_player.assigned_animation)
	if anim == null:
		return "no_anim"
	var hits := 0
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_BLEND_SHAPE:
			continue
		var path := String(anim.track_get_path(i))
		if body.name in path or "smile" in path or "A" in path:
			hits += 1
	return "blend_shape_tracks=" + str(hits)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = false
	get_viewport().push_input(event)


func _find_mesh(mesh_name: String) -> MeshInstance3D:
	for mesh in _meshes:
		if mesh.name == mesh_name:
			return mesh
	return null


func _count_players(node: Node) -> int:
	var count := 1 if node is AnimationPlayer else 0
	for child in node.get_children():
		count += _count_players(child)
	return count


func _run_performance_expression_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	var body := _find_mesh("人体_001")
	var lines: PackedStringArray = []
	lines.append("startup_anim=%s face=%s pose=%s" % [
		_player.assigned_animation, _face.get_active_primary(), _performance_pose.get_current_pose()
	])
	lines.append("startup_smile=%.3f" % _face.read_primary_on_mesh(body, "smile"))

	var gen_before := _hello_perf_gen
	_start_hello()
	await get_tree().process_frame
	lines.append("hello_started laugh=%.3f gen=%s pose=%s" % [
		_face.read_primary_on_mesh(body, "laugh"), _hello_perf_gen, _performance_pose.get_current_pose()
	])
	await get_tree().create_timer(0.15).timeout
	var laugh_mid: float = _face.read_primary_on_mesh(body, "laugh")
	lines.append("hello_mid_laugh=%.3f progress=%.3f" % [laugh_mid, _face.get_transition_progress()])

	_play_batch_oneshot("hello01")
	await get_tree().process_frame
	lines.append("interrupt_oneshot anim=%s hello_active=%s" % [_player.assigned_animation, _hello_active])
	_player.speed_scale = 35.0
	var waited := 0.0
	while waited < 2.5:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _player.assigned_animation == IDLE_ANIM and _player.is_playing():
			break
	_player.speed_scale = 1.0
	await get_tree().create_timer(_performance_pose.performance_blend_duration() + 0.12).timeout
	var smile_after_oneshot: float = _face.read_primary_on_mesh(body, "smile")
	lines.append("after_oneshot_smile=%.3f" % smile_after_oneshot)

	_start_hello()
	var stale_gen := gen_before
	_play_batch_oneshot("Hand Wave_rig_01")
	await get_tree().process_frame
	lines.append("stale_hello_gen=%s current_gen=%s" % [stale_gen, _hello_perf_gen])
	if _performance_pose.hello_end_may_run(stale_gen):
		lines.append("stale_hello_leak=true")
	else:
		lines.append("stale_hello_blocked=true")

	_start_hello()
	await get_tree().process_frame
	_start_hello()
	await get_tree().process_frame
	lines.append("double_hello laugh=%.3f" % _face.read_primary_on_mesh(body, "laugh"))

	_wait_timer.stop()
	_mode = ScheduleMode.BASE_IDLE
	await get_tree().create_timer(0.12).timeout
	_apply_emote("sad")
	await get_tree().create_timer(0.08).timeout
	var sad_mid: float = _face.read_primary_on_mesh(body, "sad")
	_start_hello()
	await get_tree().process_frame
	lines.append("expr_interrupt sad_mid=%.3f laugh=%.3f" % [
		sad_mid, _face.read_primary_on_mesh(body, "laugh")
	])

	_enter_manual()
	_start_idle(true)
	await get_tree().create_timer(_performance_pose.performance_blend_duration() + 0.15).timeout
	lines.append("hello_end_smile=%.3f" % _face.read_primary_on_mesh(body, "smile"))

	_mode = ScheduleMode.BASE_IDLE
	_play_auto_attract()
	await get_tree().create_timer(0.15).timeout
	lines.append("auto_attract laugh=%.3f mode=%s" % [_face.read_primary_on_mesh(body, "laugh"), _mode])
	_enter_manual()
	_start_idle(true)
	await get_tree().create_timer(_performance_pose.performance_blend_duration() + 0.15).timeout
	lines.append("auto_attract_interrupt_smile=%.3f" % _face.read_primary_on_mesh(body, "smile"))

	var ok: bool = (
		lines.has("stale_hello_blocked=true")
		and laugh_mid > 0.05
		and smile_after_oneshot > 0.85
		and _face.read_primary_on_mesh(body, "smile") > 0.85
	)
	lines.append("=== performance_expression_check_pass=%s ===" % str(ok))
	print("\n".join(lines))
	get_tree().quit()


func _init_idle_presence() -> void:
	_presence_camera = get_node_or_null("ObservePivot/Camera3D") as Camera3D
	var gaze := GazeController.new()
	gaze.name = "EyeGazeController"
	add_child(gaze)
	gaze.setup(_model, _presence_camera)
	var head := HeadFollow.new()
	head.name = "HeadFollowController"
	add_child(head)
	head.setup(_model)
	_idle_life = IdleLife.new()
	_idle_life.name = "IdleLifeController"
	add_child(_idle_life)
	_idle_life.call("setup", gaze, head)
	_idle_life.call("set_manual_input_enabled", false)
	_idle_life.call("set_performance_state", IdleLife.PerfState.BASE_IDLE)
	_idle_life.set_process(false)


func _is_presence_base_idle() -> bool:
	return (
		_player != null
		and _mode == ScheduleMode.BASE_IDLE
		and not _hello_active
		and _oneshot_name == ""
		and _player.assigned_animation == IDLE_ANIM
		and _player.is_playing()
	)


func _sync_idle_presence() -> void:
	if _idle_life == null:
		return
	var on := _is_presence_base_idle()
	_idle_life.call("set_blink_channel", true)
	var wink_active := _face != null and _face.get_active_primary() == "wink"
	_idle_life.call("set_blink_masked", wink_active)
	_idle_life.call("set_gaze_channel", on)
	_idle_life.call("set_head_channel", on)


func _mesh_named(mesh_name: String) -> MeshInstance3D:
	for mesh in _meshes:
		if String(mesh.name) == mesh_name:
			return mesh
	return null


func _run_idle_presence_check() -> void:
	for _i in 3:
		await get_tree().process_frame
	if _idle_life != null:
		_idle_life.set_process(false)
	var lines: PackedStringArray = []
	var ok := _idle_life != null and _player != null
	ok = ok and not _idle_life.call("is_manual_input_enabled")
	_mode = ScheduleMode.BASE_IDLE
	_hello_active = false
	_oneshot_name = ""
	if _player.assigned_animation != IDLE_ANIM or not _player.is_playing():
		_start_idle(true)
	_sync_idle_presence()
	ok = ok and _is_presence_base_idle()
	ok = ok and _idle_life.call("is_blink_channel_enabled")
	ok = ok and _idle_life.call("is_gaze_channel_enabled")
	ok = ok and _idle_life.call("is_head_channel_enabled")
	seed(90210)
	var blink_peaks := 0
	var glance_peaks := 0
	var head_peaks := 0
	for _step in 900:
		_idle_life.call("process_life", 0.02, get_viewport())
		var snap: Dictionary = _idle_life.call("get_debug_snapshot")
		if float(snap.get("blink_weight", 0.0)) > 0.65:
			blink_peaks += 1
		if float(snap.get("look_peak", 0.0)) > 0.02:
			glance_peaks += 1
		var head_motion := maxf(
			absf(float(snap.get("head_yaw_deg", 0.0))),
			absf(float(snap.get("head_pitch_deg", 0.0))),
		)
		if head_motion > 0.03:
			head_peaks += 1
	ok = ok and blink_peaks > 3 and glance_peaks > 5 and head_peaks > 3
	lines.append("base_blink=%d base_glance=%d base_head=%d" % [blink_peaks, glance_peaks, head_peaks])
	var eye := _mesh_named("眼睛左")
	var body := _mesh_named("人体_001")
	var look_i := eye.find_blend_shape_by_name("eyeLookOutLeft") if eye != null else -1
	var mouth_i := body.find_blend_shape_by_name("A") if body != null else -1
	var head_idx := _skeleton.find_bone("mixamorig_Head") if _skeleton != null else -1
	_play_auto_light()
	_sync_idle_presence()
	var light_split: bool = (
		_idle_life.call("is_blink_channel_enabled")
		and not _idle_life.call("is_gaze_channel_enabled")
		and not _idle_life.call("is_head_channel_enabled")
	)
	ok = ok and light_split and _mode == ScheduleMode.LIGHT_IDLE
	_idle_life.call("process_life", 0.02, get_viewport())
	if look_i >= 0:
		eye.set_blend_shape_value(look_i, 0.41)
	if mouth_i >= 0:
		body.set_blend_shape_value(mouth_i, 0.66)
	var head_before := _skeleton.get_bone_pose_rotation(head_idx) if head_idx >= 0 else Quaternion.IDENTITY
	for _hold in 4:
		_idle_life.call("process_life", 0.02, get_viewport())
	var look_held := eye.get_blend_shape_value(look_i) if look_i >= 0 else -1.0
	var mouth_held := body.get_blend_shape_value(mouth_i) if mouth_i >= 0 else -1.0
	var head_after := _skeleton.get_bone_pose_rotation(head_idx) if head_idx >= 0 else Quaternion.IDENTITY
	ok = ok and absf(look_held - 0.41) < 0.02
	ok = ok and absf(mouth_held - 0.66) < 0.02
	ok = ok and head_before.is_equal_approx(head_after)
	lines.append("light_hold look=%.3f mouth=%.3f" % [look_held, mouth_held])
	var phase_before: String = String(_idle_life.call("get_debug_snapshot").get("blink_phase", ""))
	_play_auto_attract()
	_sync_idle_presence()
	var switched_clean: bool = (
		_mode == ScheduleMode.ATTRACT
		and not _is_presence_base_idle()
		and _idle_life.call("is_blink_channel_enabled")
		and not _idle_life.call("is_gaze_channel_enabled")
		and String(_idle_life.call("get_debug_snapshot").get("blink_phase", "")) == phase_before
	)
	ok = ok and switched_clean
	lines.append("light_to_attract_clean=%s" % str(switched_clean))
	var attract_blinks := 0
	for _step in 500:
		_idle_life.call("process_life", 0.02, get_viewport())
		if float(_idle_life.call("get_debug_snapshot").get("blink_weight", 0.0)) > 0.65:
			attract_blinks += 1
	ok = ok and attract_blinks > 3
	lines.append("attract_blink_frames=%d" % attract_blinks)
	_start_hello()
	_sync_idle_presence()
	ok = ok and _mode == ScheduleMode.MANUAL_TEST and not _idle_life.call("is_head_channel_enabled")
	lines.append("interrupt_manual=%s" % str(_mode == ScheduleMode.MANUAL_TEST))
	_hello_active = false
	_oneshot_name = ""
	_mode = ScheduleMode.BASE_IDLE
	_start_idle(true)
	_sync_idle_presence()
	ok = ok and _is_presence_base_idle() and _idle_life.call("is_blink_channel_enabled")
	if mouth_i >= 0:
		ok = ok and absf(body.get_blend_shape_value(mouth_i) - 0.66) < 0.02
	lines.append("restored_base=%s mouth_kept=%.3f" % [
		str(_is_presence_base_idle()),
		body.get_blend_shape_value(mouth_i) if mouth_i >= 0 else -1.0,
	])
	_face.set_gaze("wink", 0.0)
	_sync_idle_presence()
	var phase_wink: String = String(_idle_life.call("get_debug_snapshot").get("blink_phase", ""))
	for _mask in 12:
		_idle_life.call("process_life", 0.05, get_viewport())
	var snap_wink: Dictionary = _idle_life.call("get_debug_snapshot")
	var wink_ok: bool = (
		_idle_life.call("is_blink_masked")
		and String(snap_wink.get("blink_phase", "")) == phase_wink
		and float(snap_wink.get("blink_weight", 1.0)) < 0.08
	)
	ok = ok and wink_ok
	lines.append("wink_mask=%s phase=%s weight=%.3f" % [
		str(wink_ok), String(snap_wink.get("blink_phase", "")), float(snap_wink.get("blink_weight", -1.0))
	])
	_face.set_emotion("smile", 0.0)
	lines.append("=== idle_presence_check_pass=%s ===" % str(ok))
	print("\n".join(lines))
	get_tree().quit()


func _note(message: String) -> void:
	_log_lines.append(message)
	if _log_lines.size() > 8:
		_log_lines.remove_at(0)
	print(message)
	if _status_label != null:
		_status_label.text = "\n".join(_log_lines)


func _fail(message: String) -> void:
	push_error(message)
	_note("错误：" + message)
