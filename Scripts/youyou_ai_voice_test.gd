extends Node3D

const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")
const ObserveCamera := preload("res://Scripts/youyou_observe_camera.gd")

const AliyunNlsConfigScript := preload("res://Scripts/voice/aliyun_nls_config.gd")
const NlsTokenProviderScript := preload("res://Scripts/voice/nls_token_provider.gd")
const SpeechInputScript := preload("res://Scripts/voice/speech_input.gd")
const MoonshotLlmClientScript := preload("res://Scripts/voice/moonshot_llm_client.gd")
const YouyouDialogueClientScript := preload("res://Scripts/voice/youyou_dialogue_client.gd")
const VoiceOutputScript := preload("res://Scripts/voice/voice_output.gd")
const VisemeProceduralDriverScript := preload("res://Scripts/voice/viseme_procedural_driver.gd")
const VoiceInteractionControllerScript := preload("res://Scripts/voice/voice_interaction_controller.gd")
const YouyouVoiceSecretsScript := preload("res://Scripts/voice/youyou_voice_secrets.gd")
const BailianTtsConfigScript := preload("res://Scripts/voice/bailian_tts_config.gd")
const AudioBytesUtilScript := preload("res://Scripts/voice/audio_bytes_util.gd")
const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

const MODEL_PATH := "res://柚柚.glb"
const IDLE_SCENE_PATH := "res://待机Animation/Basic_Idle.glb"
const IDLE_ANIM := "Basic_Idle"

var _model: Node3D
var _player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _face: FacePresenter

var _nls_config: AliyunNlsConfigScript
var _token_provider: NlsTokenProviderScript
var _speech_input: SpeechInputScript
var _moonshot: MoonshotLlmClientScript
var _dialogue: YouyouDialogueClientScript
var _voice_output: VoiceOutputScript
var _tts_player: AudioStreamPlayer
var _viseme_driver: VisemeProceduralDriverScript
var _voice: VoiceInteractionControllerScript
var _bailian_tts: BailianTtsConfigScript

var _status_bar: Label
var _tts_state_label: Label
var _latency_label: Label
var _latency_tracker: VoiceTurnLatencyScript
var _error_label: Label
var _debug_log: RichTextLabel
var _debug_panel: PanelContainer
var _text_submit: LineEdit
var _tts_text: LineEdit
var _btn_tts_play: Button
var _btn_tts_stop: Button
var _hold_ptt := false
var _tts_busy := false
var _observe_pivot: Node3D
var _last_full_cfg_err := ""
var _last_tts_err := ""


func _ready() -> void:
	_setup_world_light()
	_build_ui()
	if not _load_model():
		_set_error("模型加载失败")
		return
	_apply_split_patch()
	_load_idle_clip()
	_default_shapes = FacePresenter.capture_zero_baseline(_meshes)
	_setup_face()
	_setup_camera()
	_bailian_tts = BailianTtsConfigScript.new()
	_bailian_tts.apply_fixed_defaults()
	_setup_voice_services()
	var cfg_err := YouyouVoiceSecretsScript.load_into(_nls_config, _moonshot, _bailian_tts)
	var tts_err := YouyouVoiceSecretsScript.validate_tts_only(_bailian_tts)
	_last_full_cfg_err = cfg_err
	_last_tts_err = tts_err
	_refresh_config_status(_last_full_cfg_err, _last_tts_err)
	_log_line(YouyouVoiceSecretsScript.config_status_line(_bailian_tts))
	if cfg_err == "":
		_log_line(_speech_input.get_mic_status_text())
	_log_line("按住 空格：录音+全链路 | Esc：取消 | 中键：旋转视角 | R：复位视角")
	if tts_err != "":
		_log_line("TTS: " + tts_err)
		_log_line("可在 config/youyou_voice_secrets.cfg 设置 api_key=\"...\"（双引号），或启动前设置 DASHSCOPE_API_KEY。")
	elif not _bailian_tts.is_api_key_configured():
		_log_line("当前进程未读取到 TTS Key（编辑器启动通常不带系统环境变量）。")
	var args := OS.get_cmdline_user_args()
	if "--voice-config-check" in args:
		print("voice_config_ok=", cfg_err.is_empty())
		print("bailian_tts_config_ok=", YouyouVoiceSecretsScript.validate_tts_only(_bailian_tts).is_empty())
		print("tts_effective_model=", _bailian_tts.model)
		print("tts_effective_voice=", _bailian_tts.voice)
		print("tts_endpoint_url=", _bailian_tts.get_request_url())
		print("tts_endpoint_kind=", _bailian_tts.endpoint_kind_name())
		get_tree().quit()
		return
	if "--tts-text" in args:
		var tidx := args.find("--tts-text")
		if tidx >= 0 and tidx + 1 < args.size():
			var cli_tts_err := YouyouVoiceSecretsScript.validate_tts_only(_bailian_tts)
			if not cli_tts_err.is_empty():
				push_error(cli_tts_err)
				print("tts_test_ok=false")
			else:
				await get_tree().process_frame
				print(
					"tts_test_model=%s voice=%s url=%s"
					% [
						_bailian_tts.model,
						_bailian_tts.voice,
						_bailian_tts.get_request_url(),
					]
				)
				var ok_tts: bool = await _run_tts_plain(String(args[tidx + 1]), args)
				print("tts_test_ok=", ok_tts)
		get_tree().quit()
		return
	if "--voice-text" in args:
		var idx := args.find("--voice-text")
		if idx >= 0 and idx + 1 < args.size():
			await get_tree().process_frame
			if "--voice-latency" in args and _latency_tracker != null:
				_latency_tracker.enabled = true
				print("voice_latency_coverage=text_submit+llm+tts (无 ASR)")
			await _voice.submit_text(String(args[idx + 1]))
			if _latency_tracker != null and _latency_tracker.enabled:
				VoiceTurnLatencyScript.print_aggregate()
		get_tree().quit()
		return
	if "--voice-latency-bench" in args:
		if cfg_err != "":
			push_error("voice_latency_bench 需要完整 voice 配置: " + cfg_err)
			print("voice_latency_bench_ok=false")
			get_tree().quit()
			return
		var rounds := 1
		var ridx := args.find("--voice-latency-rounds")
		if ridx >= 0 and ridx + 1 < args.size():
			rounds = maxi(1, int(args[ridx + 1]))
		var bench_text := "你好，请用一句话回复。"
		var tidx := args.find("--voice-latency-text")
		if tidx >= 0 and tidx + 1 < args.size():
			bench_text = String(args[tidx + 1])
		await get_tree().process_frame
		var tracker := VoiceTurnLatencyScript.new()
		tracker.enabled = true
		VoiceTurnLatencyScript.clear_history()
		_voice.bind_latency_tracker(tracker)
		print(
			"voice_latency_bench rounds=",
			rounds,
			" coverage=text+llm+tts (无 ASR) paid_api_rounds=",
			rounds,
		)
		for _i in range(rounds):
			await _voice.submit_text(bench_text)
			await get_tree().process_frame
		VoiceTurnLatencyScript.print_aggregate()
		print("voice_latency_bench_ok=true")
		get_tree().quit()
		return
	if "--voice-smoke" in args:
		await get_tree().process_frame
		var SmokeRunner := preload("res://Scripts/voice/voice_interaction_smoke_runner.gd")
		var runner := SmokeRunner.new()
		add_child(runner)
		var smoke_ok: bool = await runner.run(_voice, _voice_output, _face, _viseme_driver)
		print("voice_smoke_ok=", smoke_ok)
		get_tree().quit()
		return


var _default_shapes: Dictionary = {}


func _setup_world_light() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.86, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.96, 0.98)
	env.ambient_light_energy = 0.55
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-20.0, -120.0, 0.0)
	add_child(fill)


func _setup_camera() -> void:
	_observe_pivot = Node3D.new()
	_observe_pivot.name = "ObservePivot"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 38.0
	_observe_pivot.add_child(cam)
	_observe_pivot.set_script(ObserveCamera)
	add_child(_observe_pivot)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TestUiLayer"
	add_child(layer)

	var top := _make_bar_panel()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 44.0
	layer.add_child(top)
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_margin.add_theme_constant_override("margin_left", 10)
	top_margin.add_theme_constant_override("margin_right", 10)
	top_margin.add_theme_constant_override("margin_top", 6)
	top_margin.add_theme_constant_override("margin_bottom", 4)
	top.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_margin.add_child(top_row)
	_status_bar = Label.new()
	_status_bar.text = "初始化…"
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.clip_text = true
	top_row.add_child(_status_bar)
	var dbg_toggle := Button.new()
	dbg_toggle.text = "日志"
	dbg_toggle.pressed.connect(_on_toggle_debug)
	top_row.add_child(dbg_toggle)

	_debug_panel = _make_bar_panel()
	_debug_panel.visible = false
	_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_debug_panel.offset_top = 48.0
	_debug_panel.offset_bottom = 220.0
	layer.add_child(_debug_panel)
	var dbg_margin := MarginContainer.new()
	dbg_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dbg_margin.add_theme_constant_override("margin_left", 10)
	dbg_margin.add_theme_constant_override("margin_right", 10)
	dbg_margin.add_theme_constant_override("margin_top", 4)
	dbg_margin.add_theme_constant_override("margin_bottom", 4)
	_debug_panel.add_child(dbg_margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbg_margin.add_child(scroll)
	_debug_log = RichTextLabel.new()
	_debug_log.fit_content = true
	_debug_log.scroll_active = false
	_debug_log.bbcode_enabled = false
	_debug_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_debug_log)

	var bottom := _make_bar_panel()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -228.0
	layer.add_child(bottom)
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom_margin.add_theme_constant_override("margin_left", 10)
	bottom_margin.add_theme_constant_override("margin_right", 10)
	bottom_margin.add_theme_constant_override("margin_top", 8)
	bottom_margin.add_theme_constant_override("margin_bottom", 8)
	bottom.add_child(bottom_margin)
	var bottom_v := VBoxContainer.new()
	bottom_v.add_theme_constant_override("separation", 8)
	bottom_margin.add_child(bottom_v)

	_tts_state_label = Label.new()
	_tts_state_label.text = "TTS：待机"
	bottom_v.add_child(_tts_state_label)

	_latency_label = Label.new()
	_latency_label.text = "耗时：待机（最近 5 轮平均在轮次结束后更新）"
	_latency_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_latency_label.modulate = Color(0.78, 0.86, 0.95)
	bottom_v.add_child(_latency_label)

	var tts_row := HBoxContainer.new()
	tts_row.add_theme_constant_override("separation", 8)
	bottom_v.add_child(tts_row)
	var tts_lbl := Label.new()
	tts_lbl.text = "TTS 台词"
	tts_row.add_child(tts_lbl)
	_tts_text = LineEdit.new()
	_tts_text.text = "你好，我是柚柚。"
	_tts_text.placeholder_text = "百炼 SpeechSynthesizer 测试台词"
	_tts_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tts_row.add_child(_tts_text)
	_btn_tts_play = Button.new()
	_btn_tts_play.text = "生成并播放"
	_btn_tts_play.pressed.connect(_on_tts_play_pressed)
	tts_row.add_child(_btn_tts_play)
	_btn_tts_stop = Button.new()
	_btn_tts_stop.text = "停止播放"
	_btn_tts_stop.pressed.connect(_on_tts_stop_pressed)
	tts_row.add_child(_btn_tts_stop)

	var llm_row := HBoxContainer.new()
	llm_row.add_theme_constant_override("separation", 8)
	bottom_v.add_child(llm_row)
	var llm_lbl := Label.new()
	llm_lbl.text = "LLM 文本"
	llm_row.add_child(llm_lbl)
	_text_submit = LineEdit.new()
	_text_submit.placeholder_text = "跳过录音，直连 LLM+TTS 全链路"
	_text_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	llm_row.add_child(_text_submit)
	var btn_send := Button.new()
	btn_send.text = "发送"
	btn_send.pressed.connect(_on_text_send)
	llm_row.add_child(btn_send)

	var hint := Label.new()
	hint.text = "按住 空格 录音 · Esc 取消 · 口型为 A/E/I/O/U 规则轮换（非音素对齐）"
	hint.modulate = Color(0.85, 0.88, 0.92)
	bottom_v.add_child(hint)

	_error_label = Label.new()
	_error_label.modulate = Color(1.0, 0.55, 0.5)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom_v.add_child(_error_label)


func _make_bar_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.14, 0.72)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _on_toggle_debug() -> void:
	if _debug_panel != null:
		_debug_panel.visible = not _debug_panel.visible


func _refresh_config_status(full_cfg_err: String, tts_err: String) -> void:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(_bailian_tts.api_key_status_text())
	parts.append("model=" + _bailian_tts.model)
	if tts_err.is_empty():
		parts.append("TTS就绪")
	else:
		parts.append("TTS未就绪")
	if full_cfg_err.is_empty():
		parts.append("ASR/LLM就绪")
	else:
		parts.append("ASR/LLM未齐")
	_status_bar.text = " | ".join(parts)
	_btn_tts_play.disabled = not tts_err.is_empty() or _tts_busy


func _set_tts_state(text: String) -> void:
	if _tts_state_label != null:
		_tts_state_label.text = "TTS：" + text


func _on_tts_play_pressed() -> void:
	if _tts_busy or _voice_output == null:
		return
	var tts_err := YouyouVoiceSecretsScript.validate_tts_only(_bailian_tts)
	if not tts_err.is_empty():
		_set_tts_state("失败")
		_set_error(tts_err)
		return
	var line := _tts_text.text.strip_edges()
	if line.is_empty():
		_set_error("TTS 台词为空")
		return
	_run_tts_only(line)


func _on_tts_stop_pressed() -> void:
	_stop_tts_playback("已停止")


func _run_tts_plain(text: String, args: PackedStringArray) -> bool:
	var dump_path := ""
	if "--tts-dump-wav" in args:
		var didx := args.find("--tts-dump-wav")
		if didx >= 0 and didx + 1 < args.size():
			dump_path = String(args[didx + 1])
	if dump_path.is_empty():
		return await _voice_output.speak(text, "", 0.0)
	var client := _voice_output.bailian_client
	if client == null:
		return await _voice_output.speak(text, "", 0.0)
	var result: Dictionary = await client.synthesize_text(text, "", 0)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "TTS 失败")))
		return false
	var audio: PackedByteArray = result.get("audio", PackedByteArray())
	if audio.is_empty():
		return false
	var abs := ProjectSettings.globalize_path(dump_path) if dump_path.begins_with("user://") or dump_path.begins_with("res://") else dump_path
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 WAV: " + abs)
		return false
	f.store_buffer(audio)
	f.close()
	print("tts_dump_wav=", abs, " bytes=", audio.size(), " request_id=", result.get("request_id", ""))
	var stream := AudioBytesUtilScript.stream_from_bytes(audio)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		print("tts_dump_decode mix_rate=", wav.mix_rate, " stereo=", wav.stereo, " pcm_bytes=", wav.data.size())
	if _tts_player != null and stream != null:
		_tts_player.stream = stream
		_tts_player.play()
		var seconds: float = AudioBytesUtilScript.estimate_duration_sec(stream)
		var elapsed := 0.0
		while _tts_player.playing and elapsed < seconds + 0.5:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
	return true


func _run_tts_only(text: String) -> void:
	_tts_busy = true
	_btn_tts_play.disabled = true
	_set_error("")
	_set_tts_state("请求中…")
	if _face != null and _face.is_emotion_available("smile"):
		_face.set_emotion("smile")
	if _viseme_driver != null:
		_viseme_driver.start()
	_log_line("TTS 请求: " + text)
	_set_tts_state("播放中…")
	# TTS 专项测试：不传 LLM 情绪 instruction，避免「情绪：开心」改写演绎风格、与控制台试听不一致。
	var ok: bool = await _voice_output.speak(text, "", 0.0)
	if _viseme_driver != null:
		_viseme_driver.stop()
	if _face != null:
		_face.reset_to_default()
	_tts_busy = false
	_last_tts_err = YouyouVoiceSecretsScript.validate_tts_only(_bailian_tts)
	_refresh_config_status(_last_full_cfg_err, _last_tts_err)
	if ok:
		_set_tts_state("播放结束")
		_log_line("TTS 播放完成")
	else:
		_set_tts_state("失败")
		_set_error("TTS 合成或播放失败（见日志/控制台）")


func _stop_tts_playback(state_text: String) -> void:
	if _voice_output != null:
		_voice_output.stop()
	if _viseme_driver != null:
		_viseme_driver.stop()
	if _face != null:
		_face.reset_to_default()
	_tts_busy = false
	_set_tts_state(state_text)
	_refresh_config_status(_last_full_cfg_err, _last_tts_err)


func _setup_face() -> void:
	_face = FacePresenter.new()
	_face.name = "YouyouFacePresenter"
	add_child(_face)
	_face.setup(_meshes, _default_shapes)
	_face.apply_approved_coefficients()
	if _face.is_emotion_available("smile"):
		_face.set_emotion("smile", 0.0)


func _setup_voice_services() -> void:
	var services := Node.new()
	services.name = "VoiceServices"
	add_child(services)

	_nls_config = AliyunNlsConfigScript.new()
	_nls_config.name = "AliyunNlsConfig"
	services.add_child(_nls_config)

	_token_provider = NlsTokenProviderScript.new()
	_token_provider.name = "NlsTokenProvider"
	services.add_child(_token_provider)
	_token_provider.setup(_nls_config)

	_speech_input = SpeechInputScript.new()
	_speech_input.name = "SpeechInput"
	services.add_child(_speech_input)
	_speech_input.setup(_nls_config, _token_provider)

	_moonshot = MoonshotLlmClientScript.new()
	_moonshot.name = "MoonshotLlmClient"
	services.add_child(_moonshot)

	_dialogue = YouyouDialogueClientScript.new()
	_dialogue.name = "YouyouDialogueClient"
	services.add_child(_dialogue)
	_dialogue.setup(_moonshot)

	_tts_player = AudioStreamPlayer.new()
	_tts_player.name = "TtsAudioPlayer"
	add_child(_tts_player)

	_voice_output = VoiceOutputScript.new()
	_voice_output.name = "VoiceOutput"
	services.add_child(_voice_output)
	_voice_output.setup(_nls_config, _token_provider, _tts_player, _bailian_tts)

	_viseme_driver = VisemeProceduralDriverScript.new()
	_viseme_driver.name = "VisemeProceduralDriver"
	add_child(_viseme_driver)
	_viseme_driver.setup(_face, _tts_player)

	_voice = VoiceInteractionControllerScript.new()
	_voice.name = "VoiceInteractionController"
	add_child(_voice)
	_voice.setup(_speech_input, _dialogue, _voice_output, _face, _viseme_driver)
	_voice.moonshot_client = _moonshot
	_latency_tracker = VoiceTurnLatencyScript.new()
	_latency_tracker.enabled = true
	_voice.bind_latency_tracker(_latency_tracker)
	_voice_output.set_playback_started_hook(_voice.notify_tts_playback_started)
	_voice.turn_finished.connect(_on_turn_finished_latency)
	_voice.status_message.connect(_on_voice_status)
	_voice.user_text_ready.connect(_on_user_text)
	_voice.assistant_text_ready.connect(_on_assistant_text)
	_voice.state_changed.connect(_on_state_changed)


func _on_voice_status(text: String) -> void:
	if _status_bar != null:
		var base := _bailian_tts.api_key_status_text() if _bailian_tts != null else ""
		_status_bar.text = base + " | 全链路: " + text


func _on_user_text(text: String) -> void:
	_append_detail("你说: " + text)


func _on_assistant_text(text: String, emotion: String) -> void:
	_append_detail("柚柚(%s): %s" % [emotion, text])


func _on_turn_finished_latency(_reason: String) -> void:
	_refresh_latency_ui()


func _refresh_latency_ui() -> void:
	if _latency_label == null:
		return
	var hist := VoiceTurnLatencyScript.get_history()
	if hist.is_empty():
		_latency_label.text = "耗时：尚无记录"
		return
	var last: Dictionary = hist[hist.size() - 1]
	var avg := VoiceTurnLatencyScript.get_recent_averages(5)
	var avg_play: Variant = avg.get("ptt_end_to_play_ms")
	var avg_llm: Variant = avg.get("llm_ms")
	var avg_tts: Variant = avg.get("tts_first_ready_ms")
	var avg_asr: Variant = avg.get("asr_ms")
	var avg_line := ""
	if avg_play != null:
		avg_line = " | 近5轮均: 开播=%.0fms" % float(avg_play)
		if avg_llm != null:
			avg_line += " LLM=%.0fms" % float(avg_llm)
		if avg_tts != null:
			avg_line += " TTS首包=%.0fms" % float(avg_tts)
		if avg_asr != null:
			avg_line += " ASR=%.0fms" % float(avg_asr)
	_latency_label.text = "本轮: " + VoiceTurnLatencyScript.format_summary_line(last) + avg_line
	_log_line("latency " + VoiceTurnLatencyScript.format_summary_line(last))


func _on_state_changed(_old: int, new_state: int) -> void:
	match new_state:
		VoiceInteractionControllerScript.State.IDLE:
			_set_error("")
		VoiceInteractionControllerScript.State.ERROR:
			_set_error(_voice.get_last_error())
	if _tts_state_label != null and _voice != null:
		var busy := _voice.is_busy()
		if not busy and new_state != VoiceInteractionControllerScript.State.ERROR:
			if not _tts_busy:
				_tts_state_label.text = "交互：" + _voice.get_state_name()


func _on_text_send() -> void:
	_voice.submit_text(_text_submit.text)
	_text_submit.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_V:
				if not _hold_ptt:
					_hold_ptt = true
					_voice.begin_listen()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_voice.cancel_turn()
				_stop_tts_playback("已取消")
				get_viewport().set_input_as_handled()
	if event is InputEventKey and not event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_V] and _hold_ptt:
			_hold_ptt = false
			_voice.end_listen()
			get_viewport().set_input_as_handled()


func _load_model() -> bool:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return false
	_model = packed.instantiate() as Node3D
	_model.name = "YouyouModel"
	add_child(_model)
	_collect_meshes(_model)
	for mesh in _meshes:
		if mesh.name == "耳机":
			mesh.visible = false
	return not _meshes.is_empty()


func _apply_split_patch() -> void:
	var result: Dictionary = FacePresenter.apply_split_patch_to_model(_model)
	if not bool(result.get("ok", false)):
		_log_line("拆分补丁 %d/%d（舌头未匹配，面部/口型仍可用）" % [
			int(result.get("success_count", 0)), int(result.get("total_count", 0)),
		])


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
	_player.play(IDLE_ANIM)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _log_line(text: String) -> void:
	print(text)
	_append_detail(text)


func _append_detail(text: String) -> void:
	if _debug_log == null:
		return
	if _debug_log.text.is_empty():
		_debug_log.text = text
	else:
		_debug_log.text += "\n" + text


func _set_error(text: String) -> void:
	if _error_label != null:
		_error_label.text = text if text != "" else ""
