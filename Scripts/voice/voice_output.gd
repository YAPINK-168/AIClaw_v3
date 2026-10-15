class_name VoiceOutput
extends Node

## TTS：百炼 SpeechSynthesizer（与 AudioPanel qwen-audio-3.0-tts-plus 配置一致）。
## ASR 仍使用 NLS；本节点不再调用 NLS /stream/v1/tts。

const AliyunNlsConfigScript := preload("res://Scripts/voice/aliyun_nls_config.gd")
const NlsTokenProviderScript := preload("res://Scripts/voice/nls_token_provider.gd")
const BailianTtsConfigScript := preload("res://Scripts/voice/bailian_tts_config.gd")
const BailianTtsClientScript := preload("res://Scripts/voice/bailian_tts_client.gd")
const AudioBytesUtilScript := preload("res://Scripts/voice/audio_bytes_util.gd")
const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

var config: AliyunNlsConfigScript
var latency: VoiceTurnLatencyScript
var token_provider: NlsTokenProviderScript
var bailian_config: BailianTtsConfigScript
var bailian_client: BailianTtsClientScript
var audio_player: AudioStreamPlayer

## 首句 PCM 就绪即播放；关闭则恢复「全部分句合成完再播」。
## true 时：后台 _drain_playback_queue 与 for 分句合成并行——首句 await 合成入队后即播放，
## 后续分句在播放上一段期间继续串行 synthesize（不增并发 HTTP，仅重叠播放与合成）。
@export var stream_first_chunk: bool = true

@export_category("TTS Voice Settings")
@export_range(-500, 500, 1) var speech_rate: int = 0
@export_range(-500, 500, 1) var pitch_rate: int = 0

var _http: HTTPRequest
var _stop_requested: bool = false
var _speaking: bool = false
var _pcm_queue: Array = [] # PackedByteArray chunks waiting to play
var _synth_done: bool = true
var _playback_done: bool = true
var _speak_gen: int = 0
var _play_sample_rate: int = 16000
## Accumulated PCM duration (seconds) for the current speak() call — for lip sync.
var _speak_audio_seconds: float = 0.0
var _playback_started_hook: Callable = Callable()


func setup(
	nls_config: AliyunNlsConfigScript,
	tokens: NlsTokenProviderScript,
	player: AudioStreamPlayer,
	tts_config: BailianTtsConfigScript = null,
) -> void:
	config = nls_config
	token_provider = tokens
	audio_player = player
	bailian_config = tts_config
	if bailian_client == null:
		bailian_client = BailianTtsClientScript.new()
		bailian_client.name = "BailianTtsClient"
		add_child(bailian_client)
	bailian_client.setup(bailian_config)


func set_playback_started_hook(callable: Callable) -> void:
	_playback_started_hook = callable


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)


func is_speaking() -> bool:
	return _speaking


## Total synthesized audio seconds so far for the active speak (grows as chunks arrive).
func get_speak_audio_seconds() -> float:
	return _speak_audio_seconds


func stop(invalidate_inflight: bool = true) -> void:
	_stop_requested = true
	if invalidate_inflight:
		_speak_gen += 1
		if bailian_client != null:
			bailian_client.cancel_session()
	_pcm_queue.clear()
	_synth_done = true
	_speak_audio_seconds = 0.0
	if audio_player != null and audio_player.playing:
		audio_player.stop()
	_speaking = false


func speak(text: String, emotion: String = "", intensity: float = 0.0) -> bool:
	if text.strip_edges().is_empty():
		return true
	if bailian_config == null or bailian_client == null:
		push_error("TTS 缺少百炼配置或客户端")
		return false
	var tts_err := bailian_config.validate_for_tts()
	if not tts_err.is_empty():
		push_error("TTS 配置不完整: " + tts_err)
		return false

	stop(false)
	if bailian_client != null:
		bailian_client.cancel_session()
	_stop_requested = false
	_speaking = true
	_speak_gen += 1
	var gen := _speak_gen
	_speak_audio_seconds = 0.0

	var emotion_category := ""
	var llm_intensity := _sanitize_llm_intensity(intensity)
	var mapped_intensity := 0.01
	if not emotion.strip_edges().is_empty():
		emotion_category = _map_emotion_category(emotion)
		mapped_intensity = clampf(llm_intensity * 1.2, 0.01, 1.4)

	print("VoiceOutput: 百炼 TTS model=%s voice=%s emotion=%s"
		% [bailian_config.model, bailian_config.voice, emotion_category if not emotion_category.is_empty() else "(plain)"])
	print("VoiceOutput: 开始 TTS，文本长度=", text.length(),
		" stream_first_chunk=", stream_first_chunk)

	var rate := bailian_config.sample_rate if bailian_config.sample_rate > 0 else 24000
	if latency != null and latency.enabled:
		latency.mark_once("tts_start")
	var chunks := _split_for_tts(text)
	print("VoiceOutput: TTS 分句数=", chunks.size())
	if chunks.is_empty():
		_speaking = false
		return true

	if not stream_first_chunk:
		var ok_legacy := await _speak_legacy_buffer_all(
			chunks, rate, emotion_category, mapped_intensity, gen
		)
		return ok_legacy

	_pcm_queue.clear()
	_synth_done = false
	_playback_done = false
	_play_sample_rate = rate
	_drain_playback_queue(gen)

	for i in chunks.size():
		if _stop_requested or gen != _speak_gen:
			_synth_done = true
			if audio_player != null and audio_player.playing:
				audio_player.stop()
			while not _playback_done and gen == _speak_gen:
				await get_tree().process_frame
			_speaking = false
			return false
		if latency != null and latency.enabled:
			latency.set_tts_chunk_index(i)
		var piece: PackedByteArray = await _synthesize_chunk_bailian(
			chunks[i], emotion_category, mapped_intensity, gen
		)
		if _stop_requested or gen != _speak_gen:
			_synth_done = true
			_pcm_queue.clear()
			if audio_player != null and audio_player.playing:
				audio_player.stop()
			while not _playback_done and gen == _speak_gen:
				await get_tree().process_frame
			_speaking = false
			return false
		if piece.is_empty():
			push_error("VoiceOutput: 某一句 TTS 返回空音频")
			_synth_done = true
			_pcm_queue.clear()
			if audio_player != null and audio_player.playing:
				audio_player.stop()
			while not _playback_done and gen == _speak_gen:
				await get_tree().process_frame
			_speaking = false
			return false
		_note_audio_seconds(piece)
		_pcm_queue.append(piece)
		if i == 0:
			print("VoiceOutput: 首句就绪，开始播放 (bytes=%d, 剩余分句=%d)" % [
				piece.size(), chunks.size() - 1
			])

	_synth_done = true
	if latency != null and latency.enabled:
		latency.mark_end("tts_all_ready")
	while not _playback_done and gen == _speak_gen:
		if _stop_requested:
			break
		await get_tree().process_frame

	if audio_player != null and audio_player.playing:
		audio_player.stop()
	var ok := not _stop_requested and gen == _speak_gen
	_speaking = false
	if latency != null and latency.enabled and ok:
		latency.mark_end("playback_end")
	print("VoiceOutput: 播放结束 ok=", ok)
	return ok


func _speak_legacy_buffer_all(
	chunks: PackedStringArray,
	rate: int,
	emotion_category: String,
	mapped_intensity: float,
	gen: int
) -> bool:
	var pcm := PackedByteArray()
	for chunk_i in chunks.size():
		if _stop_requested or gen != _speak_gen:
			_speaking = false
			return false
		if latency != null and latency.enabled:
			latency.set_tts_chunk_index(chunk_i)
		var piece: PackedByteArray = await _synthesize_chunk_bailian(
			chunks[chunk_i], emotion_category, mapped_intensity, gen
		)
		if _stop_requested or gen != _speak_gen:
			_speaking = false
			return false
		if piece.is_empty():
			push_error("VoiceOutput: 某一句 TTS 返回空音频")
			_speaking = false
			return false
		pcm.append_array(piece)

	if pcm.size() < 2:
		push_error("TTS 返回空音频")
		_speaking = false
		return false

	_speak_audio_seconds = _estimate_bytes_duration(pcm)
	await _play_audio_bytes(pcm, gen)
	if audio_player != null and audio_player.playing:
		audio_player.stop()
	var ok := not _stop_requested and gen == _speak_gen
	_speaking = false
	print("VoiceOutput: 播放结束")
	return ok


func _note_audio_seconds(pcm: PackedByteArray) -> void:
	_speak_audio_seconds += _estimate_bytes_duration(pcm)


func _estimate_bytes_duration(pcm: PackedByteArray) -> float:
	var stream := AudioBytesUtilScript.stream_from_bytes(pcm)
	return AudioBytesUtilScript.estimate_duration_sec(stream)


func _drain_playback_queue(gen: int) -> void:
	while gen == _speak_gen:
		if _stop_requested:
			break
		if _pcm_queue.is_empty():
			if _synth_done:
				break
			await get_tree().process_frame
			continue
		var piece: PackedByteArray = _pcm_queue.pop_front()
		await _play_audio_bytes(piece, gen)
		if _stop_requested or gen != _speak_gen:
			break
	if gen == _speak_gen:
		_playback_done = true


func _play_audio_bytes(pcm: PackedByteArray, gen: int) -> void:
	if pcm.is_empty() or audio_player == null:
		return
	if _stop_requested or gen != _speak_gen:
		return

	if latency != null and latency.enabled:
		latency.mark_once("tts_decode_start")
	var stream := AudioBytesUtilScript.stream_from_bytes(pcm)
	if stream == null:
		push_error("VoiceOutput: 音频解码失败 (bytes=%d format=%s)" % [
			pcm.size(), AudioBytesUtilScript.detect_format(pcm),
		])
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		print(
			"VoiceOutput: 解码 WAV mix_rate=%d stereo=%s pcm_bytes=%d"
			% [wav.mix_rate, wav.stereo, wav.data.size()]
		)

	audio_player.stream = stream
	audio_player.bus = "Master"
	audio_player.play()
	if not audio_player.playing:
		push_error("VoiceOutput: AudioStreamPlayer 未能开始播放")
		return
	if latency != null and latency.enabled:
		latency.mark_once("playback_start")
	if _playback_started_hook.is_valid():
		_playback_started_hook.call()

	var seconds: float = AudioBytesUtilScript.estimate_duration_sec(stream)
	if seconds <= 0.0:
		seconds = 8.0
	print("VoiceOutput: 播放分片 %.2fs bytes=%d" % [seconds, pcm.size()])
	var elapsed := 0.0
	while audio_player.playing and elapsed < seconds + 0.5:
		if _stop_requested or gen != _speak_gen:
			audio_player.stop()
			break
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _synthesize_chunk_bailian(
	chunk: String,
	emotion_category: String,
	mapped_intensity: float,
	gen: int,
) -> PackedByteArray:
	var instruction := _build_bailian_instruction(emotion_category, mapped_intensity)
	var result: Dictionary = await bailian_client.synthesize_text(
		chunk, instruction, gen
	)
	if _stop_requested or gen != _speak_gen:
		return PackedByteArray()
	if not bool(result.get("ok", false)):
		var err_msg := str(result.get("error", "TTS 失败"))
		push_error(err_msg)
		return PackedByteArray()
	return result.get("audio", PackedByteArray()) as PackedByteArray


func _build_bailian_instruction(emotion_category: String, _intensity: float) -> String:
	## 与 AudioPanel `compose_instruction` 一致：情绪进 input.instruction，不改写 input.text。
	if bailian_config != null:
		var fixed := bailian_config.default_instruction.strip_edges()
		if not fixed.is_empty() and emotion_category.is_empty():
			return fixed
	var emotion_label := _emotion_label_for_instruction(emotion_category)
	var parts: PackedStringArray = PackedStringArray()
	if not emotion_label.is_empty():
		parts.append("情绪：" + emotion_label)
	if bailian_config != null:
		var fixed2 := bailian_config.default_instruction.strip_edges()
		if not fixed2.is_empty():
			parts.append(fixed2)
	return "；".join(parts)


func _emotion_label_for_instruction(emotion_category: String) -> String:
	match emotion_category:
		"happy":
			return "开心"
		"sad":
			return "悲伤"
		"angry":
			return "愤怒"
		"surprise":
			return "惊讶"
		"neutral":
			return ""
		_:
			return ""


## LLM intensity → 合法 0~1；非法默认 0.4；小于 0 按 0（映射后夹到 0.01）；大于 1 按 1.0。
func _sanitize_llm_intensity(intensity: float) -> float:
	if is_nan(intensity) or is_inf(intensity):
		return 0.4
	if intensity < 0.0:
		return 0.0
	if intensity > 1.0:
		return 1.0
	return intensity


## 仅允许阿里云 SSML 的 5 种 emotion；扩展情绪映射到最接近类别。
## surprised 兼容为 surprise。未知回退 neutral。不改变 TTS 管道本身。
func _map_emotion_category(emotion: String) -> String:
	match emotion.strip_edges().to_lower():
		"neutral":
			return "neutral"
		"happy", "shy", "playful", "proud", "curious":
			return "happy"
		"sad":
			return "sad"
		"angry":
			return "angry"
		"surprise", "surprised":
			return "surprise"
		"confused":
			return "neutral"
		_:
			return "neutral"


func _split_for_tts(text: String) -> PackedStringArray:
	var list: PackedStringArray = PackedStringArray()
	var sb := ""
	var on_android := OS.get_name() == "Android"
	var soft_limit := 48 if on_android else 80
	var hard_limit := 160 if on_android else 280
	for i in text.length():
		var c := text.substr(i, 1)
		sb += c
		var punct := c == "。" or c == "！" or c == "？" or c == "；" or c == "\n" \
			or c == "." or c == "!" or c == "?" or c == "，" or c == ","
		if (punct and sb.length() >= 8) or sb.length() >= soft_limit:
			sb = _flush_tts_chunk(list, sb, hard_limit)
	_flush_tts_chunk(list, sb, hard_limit)
	return list


func _flush_tts_chunk(list: PackedStringArray, sb: String, hard_limit: int) -> String:
	var chunk := sb.strip_edges()
	if chunk.is_empty():
		return ""
	while chunk.length() > hard_limit:
		list.append(chunk.substr(0, hard_limit))
		chunk = chunk.substr(hard_limit)
	if chunk.length() > 0:
		list.append(chunk)
	return ""
