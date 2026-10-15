class_name MoonshotLlmClient
extends Node

const VoiceTurnLatencyScript := preload("res://Scripts/voice/voice_turn_latency.gd")

## Moonshot / Kimi Chat Completions HTTP 客户端。
## 只负责：URL、API Key、Model、Headers、Body、HTTP、提取 message.content。

@export var api_url: String = "https://api.moonshot.cn/v1/chat/completions"
@export var api_key: String = ""
@export var model: String = "kimi-k2.6"
@export var max_token: int = 192
@export var temperatures: float = 0.7
@export var disable_thinking_for_k26: bool = true

var _http: HTTPRequest
var _chat_gen: int = 0
var latency: VoiceTurnLatencyScript


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 90.0
	add_child(_http)


func cancel_inflight() -> void:
	_chat_gen += 1
	if _http != null:
		_http.cancel_request()


func chat(messages: Array[Dictionary]) -> String:
	if api_key.is_empty():
		push_error("当前没有填写 APIKey，请在 MoonshotLlmClient 中填写")
		return ""

	var gen := _chat_gen
	if latency != null and latency.enabled:
		latency.mark_once("llm_start")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	var err := _http.request(get_chat_completions_url(), headers, HTTPClient.METHOD_POST, _build_body(messages, false))
	if err != OK:
		push_error("对话请求无法发起: %s" % err)
		_close_llm_timing()
		return ""

	var completed: Array = await _http.request_completed
	if gen != _chat_gen:
		_close_llm_timing()
		return ""
	var result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var body: PackedByteArray = completed[3]
	var text: String = body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		push_error("请求失败: HTTP状态码：%s, URL：%s\n%s" % [response_code, get_chat_completions_url(), text])
		_close_llm_timing()
		return ""

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("解析返回结果失败: " + text)
		_close_llm_timing()
		return ""

	var parsed_dict: Dictionary = parsed
	var choices: Variant = parsed_dict.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		push_error("没有收到任何回复")
		_close_llm_timing()
		return ""

	var choice: Variant = choices[0]
	if typeof(choice) != TYPE_DICTIONARY or not (choice as Dictionary).has("message"):
		push_error("没有收到任何回复")
		_close_llm_timing()
		return ""

	var choice_dict: Dictionary = choice
	var message: Variant = choice_dict.get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		push_error("没有收到任何回复")
		_close_llm_timing()
		return ""
	var message_dict: Dictionary = message
	var content: String = str(message_dict.get("content", "")).strip_edges()
	if content.is_empty():
		push_error("没有收到任何回复")
		_close_llm_timing()
		return ""
	_close_llm_timing()
	return content


func _close_llm_timing() -> void:
	if latency != null and latency.enabled and latency.has_mark("llm_start"):
		latency.mark_end("llm_end")


func get_chat_completions_url() -> String:
	var url := api_url.strip_edges().trim_suffix("/")
	if url.is_empty():
		return "https://api.moonshot.cn/v1/chat/completions"
	if url.to_lower().ends_with("/chat/completions"):
		return url
	if url.to_lower().ends_with("/v1"):
		return url + "/chat/completions"
	return url


func _is_kimi_k2_family() -> bool:
	if model.is_empty():
		return false
	var m := model.to_lower()
	return m.begins_with("kimi-k2.") or m.begins_with("kimi-k2-") or m == "kimi-k2.6" or m.contains("k2.6")


func _build_body(messages: Array[Dictionary], stream: bool) -> String:
	var sb := PackedStringArray()
	sb.append("{")
	sb.append("\"model\":\"%s\"," % _escape_json(model))
	sb.append("\"messages\":[")
	for i in messages.size():
		if i > 0:
			sb.append(",")
		var msg: Dictionary = messages[i]
		sb.append("{\"role\":\"%s\",\"content\":\"%s\"}" % [
			_escape_json(str(msg.get("role", ""))),
			_escape_json(str(msg.get("content", ""))),
		])
	sb.append("],")
	sb.append("\"stream\":%s," % ("true" if stream else "false"))
	sb.append("\"max_tokens\":%d" % (max_token if max_token > 0 else 192))
	if _is_kimi_k2_family():
		if disable_thinking_for_k26:
			sb.append(",\"thinking\":{\"type\":\"disabled\"}")
	else:
		sb.append(",\"temperature\":%s" % str(temperatures))
	sb.append("}")
	return "".join(sb)


func _escape_json(s: String) -> String:
	return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
