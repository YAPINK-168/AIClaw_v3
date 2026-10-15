class_name YouyouDialogueClient
extends Node

const YouyouSystemPrompt := preload("res://Scripts/voice/youyou_system_prompt.gd")
const MoonshotLlmClientScript := preload("res://Scripts/voice/moonshot_llm_client.gd")
const LlmResponseScript := preload("res://Scripts/voice/llm_response.gd")

var llm_client: MoonshotLlmClientScript

var _history: Array[Dictionary] = []
var _system_inserted := false


func setup(client: MoonshotLlmClientScript) -> void:
	llm_client = client


func restart() -> void:
	_history.clear()
	_system_inserted = false


## 取消轮次时移除尚未得到 assistant 回复的 user 消息。
func rollback_pending_user_turn() -> void:
	if _history.is_empty():
		return
	var last: Dictionary = _history[_history.size() - 1]
	if str(last.get("role", "")) == "user":
		_history.pop_back()


func ask(player_text: String) -> LlmResponseScript:
	if llm_client == null:
		push_error("缺少 MoonshotLlmClient")
		return LlmResponseScript.failure()
	_ensure_system()
	_history.append({"role": "user", "content": player_text})
	var content: String = await llm_client.chat(_history)
	if content.is_empty():
		rollback_pending_user_turn()
		return LlmResponseScript.failure()
	var response: LlmResponseScript = _parse_llm_json(content)
	_history.append({"role": "assistant", "content": response.to_json_string()})
	while _history.size() > 5:
		if _history.size() <= 2:
			break
		_history.remove_at(1)
	return response


func _ensure_system() -> void:
	if _system_inserted:
		return
	_history.clear()
	_history.append({"role": "system", "content": YouyouSystemPrompt.TEXT})
	_system_inserted = true


func _parse_llm_json(raw_content: String) -> LlmResponseScript:
	var candidate := _extract_json_text(raw_content)
	var parsed: Variant = JSON.parse_string(candidate)
	if typeof(parsed) != TYPE_DICTIONARY:
		var fb := LlmResponseScript.fallback()
		if not raw_content.is_empty() and not raw_content.begins_with("{"):
			fb.reply = raw_content.strip_edges()
		return fb
	var response := LlmResponseScript.from_dict(parsed as Dictionary)
	if response.reply.is_empty():
		return LlmResponseScript.failure()
	return response


func _extract_json_text(raw: String) -> String:
	var text := raw.strip_edges()
	if text.begins_with("```"):
		var first_nl := text.find("\n")
		if first_nl >= 0:
			text = text.substr(first_nl + 1)
		var fence := text.rfind("```")
		if fence >= 0:
			text = text.substr(0, fence)
		text = text.strip_edges()
	var start := text.find("{")
	var end := text.rfind("}")
	if start >= 0 and end > start:
		return text.substr(start, end - start + 1)
	return text
