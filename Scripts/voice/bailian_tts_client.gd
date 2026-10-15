class_name BailianTtsClient
extends Node

## 百炼 SpeechSynthesizer 非流式 TTS（与 AudioPanel `bailian_tts.py` 一致）。

const BailianTtsConfigScript := preload("res://Scripts/voice/bailian_tts_config.gd")
const AudioBytesUtilScript := preload("res://Scripts/voice/audio_bytes_util.gd")
const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

var config: BailianTtsConfigScript
var latency: VoiceTurnLatencyScript

var _http_api: HTTPRequest
var _http_download: HTTPRequest
var _session_epoch: int = 0


func setup(tts_config: BailianTtsConfigScript) -> void:
	config = tts_config


func _ready() -> void:
	_http_api = HTTPRequest.new()
	_http_api.timeout = 90.0
	add_child(_http_api)
	_http_download = HTTPRequest.new()
	_http_download.timeout = 120.0
	add_child(_http_download)


func cancel_session() -> void:
	_session_epoch += 1


func _is_stale(epoch_at_start: int) -> bool:
	return epoch_at_start != _session_epoch


## 返回 { ok: bool, audio: PackedByteArray, error: String, duration_sec: float }
func synthesize_text(
	text: String,
	instruction: String = "",
	_session_gen: int = 0,
) -> Dictionary:
	var empty := {"ok": false, "audio": PackedByteArray(), "error": "", "duration_sec": 0.0}
	if config == null:
		empty.error = "缺少 BailianTtsConfig"
		return empty
	var missing := config.validate_for_tts()
	if not missing.is_empty():
		empty.error = "TTS 配置不完整: " + missing
		return empty
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		empty.ok = true
		return empty

	var epoch := _session_epoch
	var url := config.get_request_url()
	var body := _build_request_body(trimmed, instruction)
	print("BailianTtsClient: request_json=", _sanitize_body_for_log(body))
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % config.api_key.strip_edges(),
	])
	_http_api.timeout = config.request_timeout_sec
	print(
		"BailianTtsClient: POST %s model=%s voice=%s text_len=%d"
		% [url, config.model, config.voice, trimmed.length()]
	)
	var http_begin_us := Time.get_ticks_usec()
	if latency != null and latency.enabled:
		latency.mark_once("tts_http_start")
	var err := _http_api.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		empty.error = "TTS 无法发起请求: %s" % err
		return empty

	var completed: Array = await _http_api.request_completed
	if _is_stale(epoch):
		empty.error = "会话已取消"
		return empty

	var result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var data: PackedByteArray = completed[3]
	var text_body := data.get_string_from_utf8()
	print("BailianTtsClient: HTTP status=%s result=%s body_len=%d" % [response_code, result, data.size()])

	if result != HTTPRequest.RESULT_SUCCESS:
		empty.error = "TTS HTTP 传输失败 (result=%s code=%s)" % [result, response_code]
		return empty

	var parsed: Variant = JSON.parse_string(text_body)
	if typeof(parsed) != TYPE_DICTIONARY:
		empty.error = "TTS 响应非 JSON (HTTP %s): %s" % [response_code, _truncate(text_body, 200)]
		return empty

	var root := parsed as Dictionary
	if response_code < 200 or response_code >= 300:
		empty.error = _format_api_error(root, response_code)
		return empty

	var code := str(root.get("code", "")).strip_edges()
	if not code.is_empty():
		empty.error = _format_api_error(root, response_code)
		return empty
	if latency != null and latency.enabled:
		latency.mark_once("tts_http_done")
		var http_ms := float(Time.get_ticks_usec() - http_begin_us) / 1000.0
		latency.notify_tts_http_span(http_ms)

	var audio_bytes := await _extract_audio_bytes(root, epoch)
	if _is_stale(epoch):
		empty.error = "会话已取消"
		return empty
	if audio_bytes.is_empty():
		empty.error = "TTS 未返回可下载音频（缺少 output.audio.url）"
		return empty
	if latency != null and latency.enabled:
		latency.mark_end("tts_first_audio_ready")
		latency.notify_tts_segment_bytes(audio_bytes.size())

	if not _is_wav(audio_bytes):
		push_warning("BailianTtsClient: 下载内容可能不是标准 WAV，仍尝试解码播放")

	var stream := AudioBytesUtilScript.stream_from_bytes(audio_bytes)
	var dur := AudioBytesUtilScript.estimate_duration_sec(stream)
	var req_id := str(root.get("request_id", "")).strip_edges()
	if req_id.is_empty():
		var out_h: Variant = root.get("output", {})
		if typeof(out_h) == TYPE_DICTIONARY:
			req_id = str((out_h as Dictionary).get("request_id", "")).strip_edges()
	if not req_id.is_empty():
		print("BailianTtsClient: request_id=", req_id)
	return {
		"ok": true,
		"audio": audio_bytes,
		"error": "",
		"duration_sec": dur,
		"request_id": req_id,
		"request_json": _sanitize_body_for_log(body),
	}


func _build_request_body(text: String, instruction: String) -> String:
	var input := {
		"text": text,
		"voice": config.voice.strip_edges(),
		"format": config.audio_format.strip_edges() if not config.audio_format.is_empty() else "wav",
		"sample_rate": config.sample_rate,
		"language_hints": _language_hints_array(),
	}
	var instr := instruction.strip_edges()
	if instr.is_empty():
		instr = config.default_instruction.strip_edges()
	if not instr.is_empty():
		input["instruction"] = instr
	return JSON.stringify({"model": config.model.strip_edges(), "input": input})


func _language_hints_array() -> Array:
	if config.language_hints.is_empty():
		return ["zh"]
	var out: Array = []
	for h in config.language_hints:
		var s := str(h).strip_edges()
		if not s.is_empty():
			out.append(s)
	return out if not out.is_empty() else ["zh"]


func _extract_audio_bytes(root: Dictionary, epoch: int) -> PackedByteArray:
	var output: Variant = root.get("output", {})
	if typeof(output) != TYPE_DICTIONARY:
		return PackedByteArray()
	var audio: Variant = (output as Dictionary).get("audio", {})
	if typeof(audio) != TYPE_DICTIONARY:
		return PackedByteArray()
	var ad := audio as Dictionary
	var b64 := str(ad.get("data", "")).strip_edges()
	if not b64.is_empty():
		return Marshalls.base64_to_raw(b64)
	var audio_url := str(ad.get("url", "")).strip_edges()
	if audio_url.is_empty():
		return PackedByteArray()
	if latency != null and latency.enabled:
		latency.mark_once("tts_download_start")
	if not _is_allowed_audio_url(audio_url):
		push_error("TTS 音频 URL 不在阿里云域名上")
		return PackedByteArray()
	return await _download_url(audio_url, epoch)


func _is_allowed_audio_url(url: String) -> bool:
	var lower := url.to_lower()
	if not (lower.begins_with("http://") or lower.begins_with("https://")):
		return false
	return ".aliyuncs.com" in lower


func _download_url(url: String, epoch: int) -> PackedByteArray:
	var err := _http_download.request(url)
	if err != OK:
		push_error("TTS 音频下载无法发起: %s" % err)
		return PackedByteArray()
	var completed: Array = await _http_download.request_completed
	if _is_stale(epoch):
		return PackedByteArray()
	var result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var data: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_error("TTS 音频下载失败 HTTP %s (bytes=%d)" % [response_code, data.size()])
		return PackedByteArray()
	if data.is_empty():
		push_error("TTS 音频下载为空")
		return PackedByteArray()
	print(
		"BailianTtsClient: 已下载音频 bytes=%d format=%s"
		% [data.size(), AudioBytesUtilScript.detect_format(data)]
	)
	return data


static func _is_wav(blob: PackedByteArray) -> bool:
	return (
		blob.size() >= 44
		and blob[0] == 0x52
		and blob[1] == 0x49
		and blob[2] == 0x46
		and blob[3] == 0x46
		and blob[8] == 0x57
		and blob[9] == 0x41
		and blob[10] == 0x56
		and blob[11] == 0x45
	)


func _format_api_error(root: Dictionary, http_code: int) -> String:
	var code := str(root.get("code", "")).strip_edges()
	var message := str(root.get("message", "")).strip_edges()
	var req_id := str(root.get("request_id", "")).strip_edges()
	var parts: PackedStringArray = PackedStringArray()
	parts.append("HTTP %s" % http_code)
	if not code.is_empty():
		parts.append("code=%s" % code)
	if not message.is_empty():
		parts.append(message)
	if not req_id.is_empty():
		parts.append("request_id=%s" % req_id)
	return "TTS 失败: " + " | ".join(parts)


static func _truncate(s: String, max_len: int) -> String:
	if s.length() <= max_len:
		return s
	return s.substr(0, max_len) + "…"


## 供日志：完整 model/voice/instruction，不含密钥。
static func _sanitize_body_for_log(body_json: String) -> String:
	var parsed: Variant = JSON.parse_string(body_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _truncate(body_json, 400)
	return JSON.stringify(parsed)
