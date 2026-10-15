class_name YouyouVoiceSecrets
extends RefCounted

## 从本地 ConfigFile 加载凭证（勿提交 Git）。

const PROJECT_PATH := "res://config/youyou_voice_secrets.cfg"
const USER_PATH := "user://youyou_voice_secrets.cfg"
const EXAMPLE_PATH := "res://config/youyou_voice_secrets.example.cfg"

const AliyunNlsConfigScript := preload("res://Scripts/voice/aliyun_nls_config.gd")
const MoonshotLlmClientScript := preload("res://Scripts/voice/moonshot_llm_client.gd")
const BailianTtsConfigScript := preload("res://Scripts/voice/bailian_tts_config.gd")

## 新装 cfg 默认；已有 youyou_voice_secrets.cfg 以文件内 moonshot/max_token 为准。
const DEFAULT_MOONSHOT_MAX_TOKEN := 192


static func resolve_path() -> String:
	if FileAccess.file_exists(PROJECT_PATH):
		return PROJECT_PATH
	if FileAccess.file_exists(USER_PATH):
		return USER_PATH
	return ""


static func load_into(
	aliyun: AliyunNlsConfigScript,
	moonshot: MoonshotLlmClientScript,
	bailian: BailianTtsConfigScript,
) -> String:
	var path := resolve_path()
	if path.is_empty():
		bailian.apply_fixed_defaults()
		_apply_env_api_key(bailian)
		return (
			"未找到语音配置文件。请复制 %s 为 config/youyou_voice_secrets.cfg 并填写（勿提交 Git）。"
			% EXAMPLE_PATH
		)
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return (
			"无法解析配置文件 (err=%s)。Godot 4.7 要求字符串值使用双引号，例如 api_key=\"你的Key\"、空值写 \"\""
			% err
		)

	aliyun.app_key = str(cfg.get_value("aliyun", "app_key", "")).strip_edges()
	aliyun.region = str(cfg.get_value("aliyun", "region", "cn-shanghai")).strip_edges()
	aliyun.access_key_id = str(cfg.get_value("aliyun", "access_key_id", "")).strip_edges()
	aliyun.access_key_secret = str(cfg.get_value("aliyun", "access_key_secret", "")).strip_edges()
	aliyun.manual_token = str(cfg.get_value("aliyun", "manual_token", "")).strip_edges()
	aliyun.manual_token_expire_unix = int(cfg.get_value("aliyun", "manual_token_expire_unix", 0))
	aliyun.voice = str(cfg.get_value("aliyun", "voice", "zhimiao_emo")).strip_edges()
	aliyun.sample_rate = int(cfg.get_value("aliyun", "sample_rate", 16000))
	aliyun.volume = int(cfg.get_value("aliyun", "volume", 50))

	moonshot.api_key = str(cfg.get_value("moonshot", "api_key", "")).strip_edges()
	moonshot.model = str(cfg.get_value("moonshot", "model", "kimi-k2.6")).strip_edges()
	moonshot.api_url = str(cfg.get_value("moonshot", "api_url", "https://api.moonshot.cn/v1/chat/completions")).strip_edges()
	moonshot.max_token = int(cfg.get_value("moonshot", "max_token", DEFAULT_MOONSHOT_MAX_TOKEN))

	bailian.api_key_source = "none"
	var cfg_api_key := str(cfg.get_value("bailian_tts", "api_key", "")).strip_edges()
	bailian.api_key = cfg_api_key
	if not cfg_api_key.is_empty():
		bailian.api_key_source = "cfg"
	bailian.workspace_base_url = str(
		cfg.get_value("bailian_tts", "workspace_base_url", BailianTtsConfigScript.DEFAULT_WORKSPACE_BASE)
	).strip_edges().rstrip("/")
	bailian.workspace_id = str(cfg.get_value("bailian_tts", "workspace_id", "")).strip_edges()
	bailian.region = str(cfg.get_value("bailian_tts", "region", BailianTtsConfigScript.DEFAULT_REGION)).strip_edges()
	bailian.model = str(cfg.get_value("bailian_tts", "model", BailianTtsConfigScript.DEFAULT_MODEL)).strip_edges()
	bailian.voice = str(cfg.get_value("bailian_tts", "voice", BailianTtsConfigScript.DEFAULT_VOICE)).strip_edges()
	bailian.audio_format = str(cfg.get_value("bailian_tts", "format", "wav")).strip_edges()
	bailian.sample_rate = int(cfg.get_value("bailian_tts", "sample_rate", 24000))
	bailian.default_instruction = str(cfg.get_value("bailian_tts", "default_instruction", "")).strip_edges()
	bailian.endpoint_url_override = str(cfg.get_value("bailian_tts", "endpoint_url_override", "")).strip_edges()
	bailian.request_timeout_sec = float(cfg.get_value("bailian_tts", "request_timeout_sec", 90.0))
	var hints_raw := str(cfg.get_value("bailian_tts", "language_hints", "zh")).strip_edges()
	bailian.language_hints = _parse_language_hints(hints_raw)
	var kind_str := str(cfg.get_value("bailian_tts", "endpoint_kind", "speech_synthesizer")).strip_edges().to_lower()
	if kind_str != "speech_synthesizer":
		return "bailian_tts/endpoint_kind 必须为 speech_synthesizer（Qwen-Audio-TTS HTTP）"
	bailian.endpoint_kind = BailianTtsConfigScript.EndpointKind.SPEECH_SYNTHESIZER
	bailian.apply_fixed_defaults()
	_apply_env_api_key(bailian)

	var missing: PackedStringArray = []
	if aliyun.app_key.is_empty():
		missing.append("aliyun/app_key（ASR）")
	if aliyun.access_key_id.is_empty() and aliyun.manual_token.is_empty():
		missing.append("aliyun/access_key_id+secret 或 manual_token（ASR）")
	if aliyun.access_key_secret.is_empty() and aliyun.manual_token.is_empty():
		missing.append("aliyun/access_key_secret（ASR）")
	if moonshot.api_key.is_empty():
		missing.append("moonshot/api_key")
	var tts_missing := bailian.validate_for_tts()
	if not tts_missing.is_empty():
		missing.append(tts_missing)
	if not missing.is_empty():
		return "配置不完整: " + ", ".join(missing)
	return ""


static func validate_tts_only(bailian: BailianTtsConfigScript) -> String:
	if bailian == null:
		return "bailian_tts 未初始化"
	var m := bailian.validate_for_tts()
	if m.is_empty():
		return ""
	return "TTS 配置不完整: " + m


static func _apply_env_api_key(bailian: BailianTtsConfigScript) -> void:
	if bailian.api_key.is_empty():
		var env_key := OS.get_environment("DASHSCOPE_API_KEY").strip_edges()
		if not env_key.is_empty():
			bailian.api_key = env_key
			bailian.api_key_source = "env"


static func _parse_language_hints(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in raw.split(","):
		var s := part.strip_edges()
		if not s.is_empty():
			out.append(s)
	if out.is_empty():
		out.append("zh")
	return out


static func config_status_line(bailian: BailianTtsConfigScript = null) -> String:
	var path := resolve_path()
	var base := "配置: 未找到" if path.is_empty() else "配置: 已加载 (%s)" % path.get_file()
	if bailian != null:
		base += " | " + bailian.status_line_masked()
	return base
