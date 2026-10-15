class_name AliyunNlsConfig
extends Node

## 与 Unity AliyunNlsConfig 相同的字段。密钥请在 Inspector 填写，不要提交到 Git。

@export var app_key: String = ""
@export var region: String = "cn-shanghai"

@export_group("本机 Token（开发用）")
@export var manual_token: String = ""
@export var manual_token_expire_unix: int = 0
@export var access_key_id: String = ""
@export var access_key_secret: String = ""

@export_group("TTS（知妙）")
## 可选。经典 NLS REST TTS 可不填；若走 CosyVoice 等需 model 的接口再填写。
@export var tts_model: String = ""
## 知妙 voice_id。默认 zhimiao_emo；也可在 Inspector 改成你的定制 voice_id。
@export var voice: String = "zhimiao_emo"
@export var sample_rate: int = 16000
@export_range(0, 100) var volume: int = 50


func get_asr_endpoint() -> String:
	return "https://nls-gateway-%s.aliyuncs.com/stream/v1/asr" % region


func get_tts_rest_endpoint() -> String:
	return "https://nls-gateway-%s.aliyuncs.com/stream/v1/tts" % region


## Realtime SpeechTranscriber WebSocket (Aliyun ISI protocol).
func get_realtime_ws_url(token: String) -> String:
	var t := token.strip_edges()
	var r := region.strip_edges()
	if r.is_empty():
		r = "cn-shanghai"
	return "wss://nls-gateway-%s.aliyuncs.com/ws/v1?token=%s" % [r, t.uri_encode()]


func get_token_meta_host() -> String:
	return "nls-meta.cn-shanghai.aliyuncs.com"


func get_tts_model() -> String:
	return tts_model.strip_edges()


func get_tts_voice() -> String:
	if voice.strip_edges().is_empty():
		return "zhimiao_emo"
	var v := voice.strip_edges()
	if v == "知妙" or v.to_lower() == "zhimiao":
		return "zhimiao_emo"
	if v == "知莎" or v.to_lower() == "zhisha":
		return "zhistella"
	return v
