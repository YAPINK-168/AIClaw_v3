extends RefCounted
class_name YouyouActionEventCatalog

## 事件动作登记（测试场专用，禁止目录扫描、禁止自动并入正式池）。

const CONFIG_PATH := "res://config/youyou_action_event_catalog.json"

const ALLOWED_ACCEPTANCE: PackedStringArray = ["draft", "pending"]

static var _entries: Array[Dictionary] = []
static var _meta: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_entries = []
	_meta = {}
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("事件动作登记缺失：" + CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取：" + CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("事件登记 JSON 格式错误")
		return
	_meta = parsed.duplicate()
	_meta.erase("entries")
	var raw: Variant = parsed.get("entries", [])
	if typeof(raw) != TYPE_ARRAY:
		push_error("事件登记 entries 必须为数组")
		return
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var status := String(entry.get("manual_acceptance_status", "draft"))
		if status not in ALLOWED_ACCEPTANCE:
			push_warning(
				"事件动作 %s 验收状态 %s 非法，已视为 draft"
				% [String(entry.get("action_id", "?")), status]
			)
			entry["manual_acceptance_status"] = "draft"
		_entries.append(entry)


static func get_catalog_notes() -> String:
	ensure_loaded()
	return String(_meta.get("catalog_notes", ""))


static func get_entries() -> Array[Dictionary]:
	ensure_loaded()
	return _entries.duplicate()


static func find_entry(action_id: String) -> Dictionary:
	ensure_loaded()
	for entry in _entries:
		if String(entry.get("action_id", "")) == action_id:
			return entry.duplicate()
	return {}


static func get_action_ids() -> PackedStringArray:
	ensure_loaded()
	var ids: PackedStringArray = []
	for entry in _entries:
		ids.append(String(entry.get("action_id", "")))
	return ids


static func validate_registry() -> Dictionary:
	ensure_loaded()
	var issues: PackedStringArray = []
	var ids_seen: Dictionary = {}
	for entry in _entries:
		var aid := String(entry.get("action_id", ""))
		if aid == "":
			issues.append("条目缺少 action_id")
			continue
		if ids_seen.has(aid):
			issues.append("重复 action_id：" + aid)
		ids_seen[aid] = true
		if String(entry.get("scene", "")) == "":
			issues.append("%s 缺少 scene" % aid)
		var status := String(entry.get("manual_acceptance_status", ""))
		if status not in ALLOWED_ACCEPTANCE:
			issues.append("%s 验收状态非法：%s" % [aid, status])
	return {"ok": issues.is_empty(), "issues": issues, "count": _entries.size()}


## 只读：加载 GLB、提取动画 clip（不写入白名单或正式配置）。
static func probe_animation_clip(scene_path: String, source_anim: String) -> Dictionary:
	var result := {
		"ok": false,
		"scene_path": scene_path,
		"source_anim": source_anim,
		"clip_length": 0.0,
		"reason": "",
	}
	if scene_path == "":
		result["reason"] = "scene 路径为空"
		return result
	if not FileAccess.file_exists(scene_path):
		result["reason"] = "场景文件不存在"
		return result
	var packed := load(scene_path) as PackedScene
	if packed == null:
		result["reason"] = "PackedScene 加载失败（导入/路径）"
		return result
	var instance := packed.instantiate()
	var source := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source == null:
		instance.free()
		result["reason"] = "未找到 AnimationPlayer"
		return result
	if not source.has_animation(source_anim):
		var names: PackedStringArray = []
		for anim_name in source.get_animation_list():
			names.append(String(anim_name))
		instance.free()
		result["reason"] = "动画不存在；AnimationPlayer 内列表=%s" % ",".join(names)
		return result
	var clip := source.get_animation(source_anim) as Animation
	if clip == null:
		instance.free()
		result["reason"] = "get_animation 返回空"
		return result
	if clip.get_track_count() <= 0:
		instance.free()
		result["reason"] = "动画轨道数为 0"
		return result
	result["clip_length"] = clip.length
	result["ok"] = clip.length > 0.01
	if not result["ok"]:
		result["reason"] = "动画长度过短"
	else:
		result["reason"] = "ok"
	instance.free()
	return result
