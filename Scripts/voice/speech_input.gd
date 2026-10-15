class_name SpeechInput
extends Node

## Push-to-talk 录音 → 16-bit LE mono PCM @ 16kHz（与 AIClaw_v2 VoiceInput 按住模式一致，无邀请/VAD）。

const AudioPcmUtil := preload("res://Scripts/voice/audio_pcm_util.gd")
const AliyunNlsConfigScript := preload("res://Scripts/voice/aliyun_nls_config.gd")
const NlsTokenProviderScript := preload("res://Scripts/voice/nls_token_provider.gd")
const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

var config: AliyunNlsConfigScript
var latency: VoiceTurnLatencyScript
var token_provider: NlsTokenProviderScript

var last_error: String = ""

var _http: HTTPRequest
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _recording := false
var _samples: PackedFloat32Array = PackedFloat32Array()
var _mix_rate: int = 48000
var _recognize_gen: int = 0


func setup(nls_config: AliyunNlsConfigScript, tokens: NlsTokenProviderScript) -> void:
	config = nls_config
	token_provider = tokens


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 45.0
	add_child(_http)
	_ensure_record_bus()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Record"
	add_child(_mic_player)
	_mix_rate = int(AudioServer.get_mix_rate())
	var enabled: bool = bool(ProjectSettings.get_setting("audio/driver/enable_input", false))
	if not enabled:
		push_warning("请在 Project Settings → Audio → Driver → Enable Input 开启麦克风。")


func get_mic_status_text() -> String:
	if AudioServer.get_input_device_list().is_empty():
		return "未检测到麦克风"
	return "麦克风: %s" % AudioServer.input_device


func start_hold() -> void:
	if _recording:
		return
	last_error = ""
	if _capture != null:
		_capture.clear_buffer()
	_samples = PackedFloat32Array()
	_recording = true
	_start_mic()


func cancel() -> void:
	_recognize_gen += 1
	_recording = false
	_stop_mic()
	_samples = PackedFloat32Array()
	if _http != null:
		_http.cancel_request()


func end_hold_and_recognize() -> String:
	if _recording:
		_recording = false
		if _capture != null:
			_flush_capture()
		_stop_mic()
	elif _samples.is_empty():
		last_error = "没有开始录音。"
		return ""

	var duration := float(_samples.size()) / float(maxi(_mix_rate, 1))
	var peak := 0.0
	for i in _samples.size():
		peak = maxf(peak, absf(_samples[i]))
	if _samples.is_empty() or duration < 0.2:
		last_error = "录音太短（%.2f 秒）。" % duration
		return ""
	if peak < 0.01:
		last_error = "音量过低，请检查麦克风。"
		return ""

	var sample_rate := config.sample_rate if config != null and config.sample_rate > 0 else 16000
	var pcm := AudioPcmUtil.floats_to_pcm16_mono(_samples, _mix_rate, sample_rate)
	_samples = PackedFloat32Array()
	_recognize_gen += 1
	var gen := _recognize_gen
	var text := await _recognize_pcm(pcm, sample_rate, gen)
	if gen != _recognize_gen:
		return ""
	return text


func _process(_delta: float) -> void:
	if _recording:
		_flush_capture()
	else:
		_discard_capture()


func _start_mic() -> void:
	_set_capture_enabled(true)
	if _mic_player != null and not _mic_player.playing:
		_mic_player.play()
	if _capture != null:
		_capture.clear_buffer()


func _stop_mic() -> void:
	if _mic_player != null and _mic_player.playing:
		_mic_player.stop()
	_discard_capture()
	_set_capture_enabled(false)


func _flush_capture() -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buf: PackedVector2Array = _capture.get_buffer(frames)
	if buf.is_empty():
		return
	var start := _samples.size()
	_samples.resize(start + buf.size())
	for i in buf.size():
		_samples[start + i] = (buf[i].x + buf[i].y) * 0.5


func _discard_capture() -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames > 0:
		_capture.get_buffer(frames)


func _recognize_pcm(pcm: PackedByteArray, sample_rate: int, gen: int) -> String:
	if config == null or config.app_key.is_empty():
		last_error = "缺少阿里云 app_key 配置"
		return ""
	if latency != null and latency.enabled:
		latency.mark_once("asr_token_start")
	var token: String = await token_provider.get_token()
	if token.is_empty():
		last_error = "获取 NLS Token 失败"
		_close_asr_timing()
		return ""
	if latency != null and latency.enabled:
		latency.mark_once("asr_start")
	var url := "%s?appkey=%s&format=pcm&sample_rate=%d&enable_punctuation_prediction=true&enable_inverse_text_normalization=true" % [
		config.get_asr_endpoint(),
		config.app_key.uri_encode(),
		sample_rate,
	]
	var headers := PackedStringArray([
		"X-NLS-Token: %s" % token,
		"Content-Type: application/octet-stream",
	])
	var err := _http.request_raw(url, headers, HTTPClient.METHOD_POST, pcm)
	if err != OK:
		last_error = "ASR 请求发起失败: %s" % err
		_close_asr_timing()
		return ""
	var completed: Array = await _http.request_completed
	if gen != _recognize_gen:
		_close_asr_timing()
		return ""
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		last_error = "ASR 网络失败 HTTP=%s" % str(completed[1])
		_close_asr_timing()
		return ""
	var text: String = (completed[3] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "ASR 响应无法解析"
		_close_asr_timing()
		return ""
	var d: Dictionary = parsed
	if int(d.get("status", 0)) != 20000000:
		last_error = "ASR 失败: %s" % str(d.get("message", text))
		_close_asr_timing()
		return ""
	var result: String = str(d.get("result", "")).strip_edges()
	if result.is_empty():
		last_error = "识别结果为空"
	_close_asr_timing()
	return result


func _close_asr_timing() -> void:
	if latency != null and latency.enabled and latency.has_mark("asr_start"):
		latency.mark_end("asr_end")


func _ensure_record_bus() -> void:
	var idx := AudioServer.get_bus_index("Record")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Record")
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_mute(idx, true)
	var capture_i := -1
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			capture_i = i
			break
	if capture_i < 0:
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
		capture_i = AudioServer.get_bus_effect_count(idx) - 1
	_capture = AudioServer.get_bus_effect(idx, capture_i) as AudioEffectCapture
	AudioServer.set_bus_effect_enabled(idx, capture_i, false)


func _set_capture_enabled(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Record")
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			AudioServer.set_bus_effect_enabled(idx, i, on)
			break
