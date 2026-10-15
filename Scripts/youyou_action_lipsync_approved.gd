extends RefCounted
class_name YouyouActionLipsyncApproved

## 已验收动作：权威 JSON + 显式待机/招揽白名单（禁止目录扫描扩池）。

const CONFIG_PATH := "res://config/youyou_action_lipsync_approved.json"

## 角色专属待机（轻待机随机池）
const LIGHT_IDLE_WHITELIST: PackedStringArray = [
	"youyou_Basic_Idle01",
	"youyou_Basic_Idle02",
	"youyou_Basic_Idle03",
	"youyou_Basic_Idle04",
	"youyou_Basic_Idle05",
]

## 轻招揽随机池
const ATTRACT_WHITELIST: PackedStringArray = [
	"youyou_Hello_Idle01",
	"youyou_Hello_Idle02",
	"youyou_Hello_Idle03",
	"youyou_Hello_Idle05",
	"youyou_Hello_Idle06",
	"youyou_Hello_Idle07",
	"youyou_Hello_Idle08",
]

const CLIP_REGISTRY: Dictionary = {
	"youyou_Basic_Idle01": {
		"scene": "res://待机Animation/youyou_Basic_Idle01.001.glb",
		"source_anim": "youyou_Basic_Idle01_001",
	},
	"youyou_Basic_Idle02": {
		"scene": "res://待机Animation/youyou_Basic_Idle02.glb",
		"source_anim": "youyou_Basic_Idle02",
	},
	"youyou_Basic_Idle03": {
		"scene": "res://待机Animation/youyou_Basic_Idle03.glb",
		"source_anim": "youyou_Basic_Idle03",
	},
	"youyou_Basic_Idle04": {
		"scene": "res://待机Animation/youyou_Basic_Idle04.glb",
		"source_anim": "youyou_Basic_Idle04",
	},
	"youyou_Basic_Idle05": {
		"scene": "res://待机Animation/youyou_Basic_Idle05.glb",
		"source_anim": "youyou_Basic_Idle05",
	},
	"youyou_Hello_Idle01": {
		"scene": "res://待机Animation/youyou_Hello_Idle01.glb",
		"source_anim": "youyou_Hello_Idle01",
	},
	"youyou_Hello_Idle02": {
		"scene": "res://待机Animation/youyou_Hello_Idle02.glb",
		"source_anim": "youyou_Hello_Idle02",
	},
	"youyou_Hello_Idle03": {
		"scene": "res://待机Animation/youyou_Hello_Idle03.glb",
		"source_anim": "youyou_Hello_Idle03",
	},
	"youyou_Hello_Idle05": {
		"scene": "res://待机Animation/youyou_Hello_Idle05.glb",
		"source_anim": "youyou_Hello_Idle05",
	},
	"youyou_Hello_Idle06": {
		"scene": "res://待机Animation/youyou_Hello_Idle06.glb",
		"source_anim": "youyou_Hello_Idle06",
	},
	"youyou_Hello_Idle07": {
		"scene": "res://待机Animation/youyou_Hello_Idle07.glb",
		"source_anim": "youyou_Hello_Idle07",
	},
	"youyou_Hello_Idle08": {
		"scene": "res://待机Animation/youyou_Hello_Idle08.glb",
		"source_anim": "youyou_Hello_Idle08",
	},
}

static var _entries: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_entries = {}
	load_config()


static func load_config() -> bool:
	if _loaded:
		return not _entries.is_empty()
	_loaded = true
	_entries = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("验收配置缺失：" + CONFIG_PATH)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not (parsed is Dictionary):
		push_error("验收配置 JSON 无效")
		return false
	var entries: Variant = (parsed as Dictionary).get("entries", {})
	if entries is Dictionary:
		_entries = entries as Dictionary
	return true


static func get_light_idle_whitelist() -> PackedStringArray:
	return LIGHT_IDLE_WHITELIST.duplicate()


static func get_attract_whitelist() -> PackedStringArray:
	return ATTRACT_WHITELIST.duplicate()


static func all_whitelisted_action_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for id in LIGHT_IDLE_WHITELIST:
		if id not in ids:
			ids.append(id)
	for id in ATTRACT_WHITELIST:
		if id not in ids:
			ids.append(id)
	return ids


static func is_whitelisted(action_id: String) -> bool:
	return action_id in LIGHT_IDLE_WHITELIST or action_id in ATTRACT_WHITELIST


static func pool_for(action_id: String) -> String:
	if action_id in LIGHT_IDLE_WHITELIST:
		return "light_idle"
	if action_id in ATTRACT_WHITELIST:
		return "attract"
	return ""


static func get_params(action_id: String) -> Dictionary:
	load_config()
	var raw: Variant = _entries.get(action_id, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func validate_entry(action_id: String) -> Dictionary:
	var errors: PackedStringArray = []
	if not is_whitelisted(action_id):
		errors.append("不在白名单")
		return {"ok": false, "errors": errors}
	load_config()
	var params := get_params(action_id)
	if params.is_empty():
		errors.append("验收配置无条目")
	if String(params.get("manual_acceptance_status", "")) != "approved":
		errors.append("未标记 approved")
	var audio := String(params.get("audio_path", ""))
	if audio == "" or not FileAccess.file_exists(audio):
		errors.append("配音缺失：" + audio)
	if not CLIP_REGISTRY.has(action_id):
		errors.append("无 clip 注册信息")
	return {"ok": errors.is_empty(), "errors": errors, "params": params}


static func get_clip_registry(action_id: String) -> Dictionary:
	if CLIP_REGISTRY.has(action_id):
		return (CLIP_REGISTRY[action_id] as Dictionary).duplicate()
	return {}


static func take_animation_clip(action_id: String) -> Animation:
	var reg := get_clip_registry(action_id)
	if reg.is_empty():
		return null
	var scene_path := String(reg.get("scene", ""))
	var source_anim := String(reg.get("source_anim", action_id))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null or not source.has_animation(source_anim):
		instance.free()
		return null
	var clip := (source.get_animation(source_anim) as Animation).duplicate(true) as Animation
	instance.free()
	return clip
