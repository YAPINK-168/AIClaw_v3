class_name LlmResponse
extends RefCounted

## Kimi 结构化回复。VoiceChatFlow 只消费本对象，不自行解析 JSON。
## emotion = 相对稳定的情绪状态；expression = 具体脸部表现（由 ExpressionComboController 消费）。

const EMOTIONS: Array[String] = [
	"neutral", "happy", "sad", "angry", "surprised",
	"shy", "curious", "confused", "proud", "playful",
]

## Face presentation ids for ExpressionComboController (not BlendShape names).
const EXPRESSIONS: Array[String] = [
	"neutral", "happy", "excited", "shy", "embarrassed",
	"curious", "thinking", "surprise", "angry", "wronged",
	"sad", "disappointed", "playful", "teasing", "confused",
	"proud", "cute", "pleading", "pouting", "sleepy",
	"expectant", "admiring",
	## Kept for event-audio / idle presets (LLM may still emit; not preferred).
	"sorrow", "laugh",
]

const ACTIONS: Array[String] = [
	"none", "greet", "chat", "invite_game", "encourage", "watch_claw", "celebrate", "comfort",
]

## false 表示 API/解析失败，控制器不得据此调用 TTS。
var ok: bool = true
var reply: String = ""
var emotion: String = "neutral"
var intensity: float = 0.0
var action: String = "chat"
## Digital-human face combo id (JSON key: expression). Independent from emotion.
var expression: String = "neutral"


static func failure() -> LlmResponse:
	var r := LlmResponse.new()
	r.ok = false
	r.reply = ""
	r.emotion = "neutral"
	r.intensity = 0.0
	r.action = "chat"
	r.expression = "neutral"
	return r


static func fallback(reply_text: String = "抱歉，我刚才没听清，你能再说一次吗？") -> LlmResponse:
	var r := LlmResponse.new()
	r.ok = true
	r.reply = reply_text
	r.emotion = "neutral"
	r.intensity = 0.2
	r.action = "chat"
	r.expression = "neutral"
	return r


static func from_dict(data: Dictionary) -> LlmResponse:
	var r := LlmResponse.new()
	r.reply = str(data.get("reply", "")).strip_edges()
	r.emotion = _normalize_emotion(str(data.get("emotion", "neutral")).strip_edges())
	r.intensity = _normalize_intensity(data.get("intensity", 0.4))
	r.action = _normalize_action(str(data.get("action", "chat")).strip_edges())
	r.expression = _normalize_expression(str(data.get("expression", "neutral")).strip_edges())
	return r


func to_json_string() -> String:
	var payload := {
		"reply": reply,
		"emotion": emotion,
		"expression": expression,
		"intensity": intensity,
		"action": action,
	}
	return JSON.stringify(payload)


static func _normalize_emotion(value: String) -> String:
	var v := value.to_lower().strip_edges()
	# Legacy / TTS-facing alias → canonical emotion id.
	if v == "surprise":
		v = "surprised"
	if EMOTIONS.has(v):
		return v
	return "neutral"


static func _normalize_expression(value: String) -> String:
	var v := value.to_lower().strip_edges()
	# Common slips / aliases.
	if v == "surprised":
		v = "surprise"
	if v == "sorrow":
		# Prefer new "sad" for LLM face; keep sorrow accepted for event audio.
		pass
	if v == "embarassed" or v == "embarrased":
		v = "embarrassed"
	if v.is_empty() or not EXPRESSIONS.has(v):
		return "neutral"
	return v


static func _normalize_intensity(value: Variant) -> float:
	var f: float = 0.4
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			f = float(value)
		TYPE_STRING:
			var s := str(value).strip_edges()
			if s.is_empty() or not s.is_valid_float():
				return 0.4
			f = float(s)
		_:
			return 0.4
	if is_nan(f) or is_inf(f):
		return 0.4
	if f < 0.0:
		return 0.0
	if f > 1.0:
		return 1.0
	return f


static func _normalize_action(value: String) -> String:
	var v := value.to_lower()
	if ACTIONS.has(v):
		return v
	return "chat"
