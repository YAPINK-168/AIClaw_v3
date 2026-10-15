class_name BailianTtsConfig
extends RefCounted

## 与 AudioPanel `audiopanel.bailian` 对齐的百炼 SpeechSynthesizer 配置。

const ENDPOINT_PATH := "/api/v1/services/audio/tts/SpeechSynthesizer"
const DEFAULT_MODEL := "qwen-audio-3.0-tts-plus"
const DEFAULT_VOICE := "qwen-audio-3.0-tts-plus-vd-bailian-26d6e794c4134aa08f4d6326cc37e642"
const DEFAULT_WORKSPACE_BASE := "https://ws-oezduzmjp58m7g0f.cn-beijing.maas.aliyuncs.com"
const DEFAULT_REGION := "cn-beijing"

enum EndpointKind {
	SPEECH_SYNTHESIZER,
}

@export var endpoint_kind: EndpointKind = EndpointKind.SPEECH_SYNTHESIZER

@export var api_key: String = ""
## 仅用于 UI：none | cfg | env
var api_key_source: String = "none"
## 业务空间根地址（不含路径），与 AudioPanel `base_url` 一致。
@export var workspace_base_url: String = DEFAULT_WORKSPACE_BASE
## 兼容旧配置：仅填 ws-xxx 时与 region 拼接根地址；若 workspace_base_url 已填则忽略。
@export var workspace_id: String = ""
@export var region: String = DEFAULT_REGION
@export var model: String = DEFAULT_MODEL
@export var voice: String = DEFAULT_VOICE
@export var audio_format: String = "wav"
@export var sample_rate: int = 24000
@export var language_hints: PackedStringArray = PackedStringArray(["zh"])
@export var request_timeout_sec: float = 90.0
@export var default_instruction: String = ""
## 完整合成 URL 覆盖（调试用）；非空时优先使用。
@export var endpoint_url_override: String = ""


func get_workspace_root() -> String:
	var override_root := workspace_base_url.strip_edges().rstrip("/")
	if not override_root.is_empty():
		return override_root
	var ws := workspace_id.strip_edges()
	if ws.is_empty():
		return ""
	var reg := region.strip_edges()
	if reg.is_empty():
		reg = DEFAULT_REGION
	return "https://%s.%s.maas.aliyuncs.com" % [ws, reg]


func get_request_url() -> String:
	var full := endpoint_url_override.strip_edges()
	if not full.is_empty():
		return full
	var root := get_workspace_root()
	if root.is_empty():
		return ""
	return root + ENDPOINT_PATH


func apply_fixed_defaults() -> void:
	if model.strip_edges().is_empty():
		model = DEFAULT_MODEL
	if voice.strip_edges().is_empty():
		voice = DEFAULT_VOICE
	if workspace_base_url.strip_edges().is_empty() and workspace_id.strip_edges().is_empty():
		workspace_base_url = DEFAULT_WORKSPACE_BASE
	if region.strip_edges().is_empty():
		region = DEFAULT_REGION
	endpoint_kind = EndpointKind.SPEECH_SYNTHESIZER


func validate_for_tts() -> String:
	apply_fixed_defaults()
	if api_key.strip_edges().is_empty():
		return "bailian_tts/api_key"
	if model != DEFAULT_MODEL:
		return "bailian_tts/model 必须为 %s（当前=%s）" % [DEFAULT_MODEL, model]
	if voice != DEFAULT_VOICE:
		return "bailian_tts/voice 必须为固定自定义音色（当前与项目要求不一致）"
	if get_request_url().is_empty():
		return "bailian_tts/workspace_base_url 或 workspace_id+region"
	var root := get_workspace_root()
	if not root.contains(".cn-beijing.maas.aliyuncs.com"):
		return "bailian_tts 端点地域必须为 cn-beijing（当前 root 不匹配）"
	return ""


func endpoint_kind_name() -> String:
	return "speech_synthesizer"


func is_api_key_configured() -> bool:
	return not api_key.strip_edges().is_empty()


func api_key_status_text() -> String:
	if not is_api_key_configured():
		return "TTS Key: 未配置"
	match api_key_source:
		"cfg":
			return "TTS Key: 已配置（配置文件）"
		"env":
			return "TTS Key: 已配置（环境变量 DASHSCOPE_API_KEY）"
		_:
			return "TTS Key: 已配置"


func status_line_masked() -> String:
	var root := get_workspace_root()
	var root_hint := root if root.length() <= 52 else root.substr(0, 48) + "…"
	return (
		"TTS: %s | %s | model=%s"
		% [api_key_status_text(), root_hint, model]
	)


func _voice_hint() -> String:
	var v := voice.strip_edges()
	if v.length() <= 24:
		return v
	return v.substr(0, 20) + "…"
