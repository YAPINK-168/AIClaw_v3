extends Node
class_name YouyouFacePresenter

## 正式 + 测试共用的面部表现：拆分 Eyes_*/Mouth_*、口型 A/E/I/O/U、复合主键归零、视线复合键。

const PatchApplier := preload("res://youyou_assets/expressions_split/apply_youyou_blendshapes.gd")
const PATCH_BIN_PATH := "res://youyou_assets/expressions_split/youyou_blendshapes.bin"

const VISEME_IDS: PackedStringArray = ["a", "e", "i", "o", "u"]
const VISEME_SHAPE_NAMES: Dictionary = {
	"a": "A", "e": "E", "i": "i", "o": "o", "u": "u",
}
const VISEME_MESH_PARTICIPANTS: PackedStringArray = [
	"人体_001", "上牙", "下牙", "舌头",
]
## 测试场景人工验收系数（HUD 可读嘴情 0.35；口型/过渡滑条约在 0–1 的 75% / 27%）
const APPROVED_MOUTH_EMOTION_COEF := 0.35
const APPROVED_VISEME_COEF := 0.75
const APPROVED_BLEND_TIME := 0.27
const VISEME_BLEND_TIME := APPROVED_BLEND_TIME

const SPLIT_EMOTION_IDS: PackedStringArray = [
	"smile", "surprise", "laugh", "angry", "sad", "grin",
]
const LEGACY_COMPOSITE_KEYS: PackedStringArray = [
	"smile", "surprise", "laugh", "angry", "sad", "grin",
]
const GAZE_KEYS: PackedStringArray = ["wink", "lookleft", "lookright"]
const DEFAULT_EMOTION := "smile"
const DEFAULT_PRIMARY := "smile"
const TRANSITION_BLEND_TIME_DEFAULT := 0.4

const SPLIT_PROFILES: Dictionary = {
	"smile": {"label": "微笑", "eyes": "Eyes_smile", "mouth": "Mouth_smile"},
	"surprise": {"label": "惊讶", "eyes": "Eyes_surprise", "mouth": "Mouth_surprise"},
	"laugh": {"label": "大笑", "eyes": "Eyes_laugh", "mouth": "Mouth_laugh"},
	"angry": {"label": "生气", "eyes": "Eyes_angry", "mouth": "Mouth_angry"},
	"sad": {"label": "难过", "eyes": "Eyes_sad", "mouth": "Mouth_sad"},
	"grin": {"label": "眯眼笑", "eyes": "Eyes_grin", "mouth": "Mouth_grin"},
}

var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _managed_shapes: PackedStringArray = []
var _split_shape_names: PackedStringArray = []
var _emotion_ready: Dictionary = {}

var _active_emotion := DEFAULT_EMOTION
var _active_gaze := ""
var _active_viseme := ""
var _viseme_strength := 0.0

var _mouth_emotion_coef := APPROVED_MOUTH_EMOTION_COEF
var _viseme_coef := APPROVED_VISEME_COEF
var _blend_time := APPROVED_BLEND_TIME
var _performance_blend_time := TRANSITION_BLEND_TIME_DEFAULT

var _tween: Tween
var _tween_gen := 0
var _transition_progress := 1.0


static func apply_split_patch_to_model(model: Node3D) -> Dictionary:
	if not FileAccess.file_exists(PATCH_BIN_PATH):
		var msg := "拆分补丁二进制不存在：" + PATCH_BIN_PATH
		push_error(msg)
		return {"ok": false, "summary": msg, "diagnostics": [], "success_count": 0, "total_count": 8}
	var applier: Node = PatchApplier.new()
	applier.name = "YouyouSplitPatchApplier"
	model.add_child(applier)
	var result: Dictionary = applier.call("apply_blendshapes_with_diagnostics")
	applier.queue_free()
	return result


static func capture_zero_baseline(meshes: Array[MeshInstance3D]) -> Dictionary:
	var out: Dictionary = {}
	for mesh in meshes:
		var values := {}
		for i in mesh.mesh.get_blend_shape_count():
			values[String(mesh.mesh.get_blend_shape_name(i))] = 0.0
		out[mesh] = values
	return out


func setup(meshes: Array[MeshInstance3D], default_shapes: Dictionary = {}) -> void:
	_meshes = meshes
	_default_shapes = default_shapes
	_build_split_shape_list()
	_refresh_emotion_readiness()
	_build_managed_shapes()


func configure_patch_readiness(_diagnostics: Array) -> void:
	_refresh_emotion_readiness()


func configure_coefficients(mouth_emotion: float, viseme: float, blend_time: float) -> void:
	_mouth_emotion_coef = clampf(mouth_emotion, 0.0, 1.0)
	_viseme_coef = clampf(viseme, 0.0, 1.0)
	_blend_time = maxf(blend_time, 0.0)


func apply_approved_coefficients() -> void:
	configure_coefficients(
		APPROVED_MOUTH_EMOTION_COEF,
		APPROVED_VISEME_COEF,
		APPROVED_BLEND_TIME,
	)


func configure_performance_blend(duration: float) -> void:
	_performance_blend_time = maxf(duration, 0.0)


func get_emotion_ids() -> PackedStringArray:
	return SPLIT_EMOTION_IDS.duplicate()


func get_emotion_label(emotion_id: String) -> String:
	var p: Dictionary = SPLIT_PROFILES.get(emotion_id, {})
	return String(p.get("label", emotion_id))


func is_emotion_available(emotion_id: String) -> bool:
	return bool(_emotion_ready.get(emotion_id, false))


func get_emotion_readiness() -> Dictionary:
	return _emotion_ready.duplicate()


func get_split_shape_names() -> PackedStringArray:
	return _split_shape_names.duplicate()


func is_composite_emotion(_emotion_id: String) -> bool:
	return false


func get_active_emotion() -> String:
	return _active_emotion


func get_active_viseme() -> String:
	return _active_viseme


func get_active_primary() -> String:
	if _active_gaze != "":
		return _active_gaze
	return _active_emotion


func get_emotion_restore_primary() -> String:
	if _active_emotion != "":
		return _active_emotion
	return DEFAULT_EMOTION


func get_transition_progress() -> float:
	return _transition_progress


func is_transition_running() -> bool:
	return _tween != null and _tween.is_valid() and _transition_progress < 0.999


func performance_blend_duration() -> float:
	return _performance_blend_time


func set_coefficients(mouth_emotion: float, viseme: float, blend_time: float) -> void:
	configure_coefficients(mouth_emotion, viseme, blend_time)


func get_coefficients() -> Vector3:
	return Vector3(_mouth_emotion_coef, _viseme_coef, _blend_time)


func set_emotion(emotion_id: String, duration: float = -1.0) -> bool:
	if emotion_id not in SPLIT_PROFILES:
		return false
	if not is_emotion_available(emotion_id):
		push_warning("拆分情绪未就绪，跳过：" + emotion_id)
		return false
	_active_gaze = ""
	_active_emotion = emotion_id
	_apply_state(duration)
	return true


func set_gaze(gaze_id: String, duration: float = -1.0) -> bool:
	if gaze_id != "" and gaze_id not in GAZE_KEYS:
		return false
	if gaze_id != "" and not _shape_exists_any_mesh(gaze_id):
		push_warning("视线形态键不存在：" + gaze_id)
		return false
	_active_gaze = gaze_id
	if gaze_id != "":
		_active_emotion = ""
	_apply_state(duration)
	return true


func set_primary(shape_name: String, duration: float = -1.0) -> bool:
	if shape_name in SPLIT_EMOTION_IDS:
		return set_emotion(shape_name, duration)
	if shape_name in GAZE_KEYS:
		return set_gaze(shape_name, duration)
	return false


func set_viseme(viseme_id: String, duration: float = -1.0) -> bool:
	var vid := viseme_id.to_lower()
	if vid not in VISEME_IDS:
		return false
	_active_viseme = vid
	_viseme_strength = 1.0
	_apply_state(duration)
	return true


func clear_viseme(duration: float = -1.0) -> void:
	_active_viseme = ""
	_viseme_strength = 0.0
	_apply_state(duration)


func reset_all(duration: float = -1.0) -> void:
	_active_gaze = ""
	_active_emotion = DEFAULT_EMOTION
	_active_viseme = ""
	_viseme_strength = 0.0
	if not is_emotion_available(DEFAULT_EMOTION):
		_active_emotion = ""
	_apply_state(duration)


func reset_to_default(duration: float = -1.0) -> void:
	if duration < 0.0:
		reset_all(_performance_blend_time)
	else:
		reset_all(duration)


func read_shape_on_body(shape_name: String) -> float:
	var body := _find_mesh("人体_001")
	if body == null:
		return -1.0
	var idx := body.find_blend_shape_by_name(shape_name)
	if idx < 0:
		return -1.0
	return body.get_blend_shape_value(idx)


func read_shape_on_any_mesh(shape_name: String) -> float:
	for mesh in _meshes:
		var idx := mesh.find_blend_shape_by_name(shape_name)
		if idx >= 0:
			return mesh.get_blend_shape_value(idx)
	return -1.0


func read_primary_on_mesh(mesh: MeshInstance3D, primary: String) -> float:
	if primary in SPLIT_EMOTION_IDS:
		var p: Dictionary = SPLIT_PROFILES.get(primary, {})
		var eyes := String(p.get("eyes", ""))
		var mouth := String(p.get("mouth", ""))
		var ev := -1.0
		var mv := -1.0
		if eyes != "":
			var ei := mesh.find_blend_shape_by_name(eyes)
			if ei >= 0:
				ev = mesh.get_blend_shape_value(ei)
		if mouth != "":
			var mi := mesh.find_blend_shape_by_name(mouth)
			if mi >= 0:
				mv = mesh.get_blend_shape_value(mi)
		if ev < 0.0 and mv < 0.0:
			return -1.0
		return maxf(ev, mv)
	var index := mesh.find_blend_shape_by_name(primary)
	if index < 0:
		return -1.0
	return mesh.get_blend_shape_value(index)


func read_viseme_on_mesh(mesh: MeshInstance3D, viseme_id: String) -> float:
	var shape_name := String(VISEME_SHAPE_NAMES.get(viseme_id.to_lower(), ""))
	if shape_name.is_empty():
		return -1.0
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index < 0:
		return -1.0
	return mesh.get_blend_shape_value(index)


func is_viseme_participant_mesh(mesh: MeshInstance3D) -> bool:
	return mesh.name in VISEME_MESH_PARTICIPANTS


func all_visemes_near_zero(max_weight: float = 0.02) -> bool:
	for mesh in _meshes:
		if not is_viseme_participant_mesh(mesh):
			continue
		for vid in VISEME_IDS:
			var v := read_viseme_on_mesh(mesh, vid)
			if v < 0.0:
				continue
			if v > max_weight:
				return false
	return true


func max_viseme_weight_excluding(active_vid: String, max_weight: float = 0.02) -> float:
	var active_shape := String(VISEME_SHAPE_NAMES.get(active_vid.to_lower(), ""))
	var peak := 0.0
	for mesh in _meshes:
		if not is_viseme_participant_mesh(mesh):
			continue
		for vid in VISEME_IDS:
			var sh := String(VISEME_SHAPE_NAMES[vid])
			if sh == active_shape:
				continue
			var v := read_viseme_on_mesh(mesh, vid)
			if v >= 0.0:
				peak = maxf(peak, v)
	return peak


func sample_debug_lines(max_shapes: int = 10) -> PackedStringArray:
	var lines: PackedStringArray = []
	var profile: Dictionary = SPLIT_PROFILES.get(_active_emotion, {})
	var eyes_key := String(profile.get("eyes", ""))
	var mouth_key := String(profile.get("mouth", ""))
	lines.append(
		"情绪: %s | 视线: %s | 口型: %s | 嘴情系数: %.2f"
		% [
			get_emotion_label(_active_emotion) if _active_emotion != "" else "—",
			_active_gaze if _active_gaze != "" else "—",
			_active_viseme if _active_viseme != "" else "—",
			_mouth_emotion_coef,
		]
	)
	if eyes_key != "":
		lines.append("  活动眼键 %s=%.3f" % [eyes_key, read_shape_on_any_mesh(eyes_key)])
	if mouth_key != "":
		lines.append("  活动嘴键 %s=%.3f" % [mouth_key, read_shape_on_any_mesh(mouth_key)])
	if _active_viseme != "":
		var vname := String(VISEME_SHAPE_NAMES[_active_viseme])
		lines.append("  活动元音 %s=%.3f" % [vname, read_shape_on_any_mesh(vname)])
	var shown := 0
	for shape_name in _managed_shapes:
		if shown >= max_shapes:
			break
		var v := read_shape_on_any_mesh(shape_name)
		if v < 0.0 or absf(v) < 0.02:
			continue
		lines.append("  %s=%.3f" % [shape_name, v])
		shown += 1
	return lines


func _build_split_shape_list() -> void:
	var keys: Dictionary = {}
	for eid in SPLIT_PROFILES:
		var p: Dictionary = SPLIT_PROFILES[eid]
		keys[String(p["eyes"])] = true
		keys[String(p["mouth"])] = true
	_split_shape_names = PackedStringArray(keys.keys())
	_split_shape_names.sort()


func _refresh_emotion_readiness() -> void:
	_emotion_ready.clear()
	for eid in SPLIT_EMOTION_IDS:
		var p: Dictionary = SPLIT_PROFILES[eid]
		var eyes := String(p["eyes"])
		var mouth := String(p["mouth"])
		_emotion_ready[eid] = _shape_exists_any_mesh(eyes) and _shape_exists_any_mesh(mouth)


func _build_managed_shapes() -> void:
	var keys: Dictionary = {}
	for name in _split_shape_names:
		keys[name] = true
	for pk in LEGACY_COMPOSITE_KEYS:
		keys[pk] = true
	for vid in VISEME_IDS:
		keys[String(VISEME_SHAPE_NAMES[vid])] = true
	for gk in GAZE_KEYS:
		keys[gk] = true
	_managed_shapes = PackedStringArray(keys.keys())
	_managed_shapes.sort()


func _shape_exists_any_mesh(shape_name: String) -> bool:
	for mesh in _meshes:
		if mesh.find_blend_shape_by_name(shape_name) >= 0:
			return true
	return false


func _find_mesh(name: String) -> MeshInstance3D:
	for mesh in _meshes:
		if mesh.name == name:
			return mesh
	return null


func _resolve_duration(requested: float) -> float:
	if requested >= 0.0:
		return requested
	return _blend_time


func _apply_state(duration: float = -1.0) -> void:
	var dur := _resolve_duration(duration)
	var targets := _build_targets()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_gen += 1
	var gen := _tween_gen
	if dur <= 0.0:
		_transition_progress = 1.0
		_apply_targets_instant(targets)
		return
	_transition_progress = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	var count := 0
	var progress_step := _tween.tween_method(_progress_setter(gen), 0.0, 1.0, dur)
	progress_step.set_trans(Tween.TRANS_CUBIC)
	progress_step.set_ease(Tween.EASE_IN_OUT)
	count += 1
	for mesh in _meshes:
		for shape_name in _managed_shapes:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			if not targets.has(shape_name):
				continue
			var target: float = targets[shape_name]
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			var tw := _tween.tween_method(_setter_for(mesh, index, gen), start, target, dur)
			tw.set_trans(Tween.TRANS_CUBIC)
			tw.set_ease(Tween.EASE_IN_OUT)
			count += 1
	if count <= 1:
		_transition_progress = 1.0
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = null


func _progress_setter(gen: int) -> Callable:
	return func(value: float) -> void:
		if gen != _tween_gen:
			return
		_transition_progress = value


func _build_targets() -> Dictionary:
	var targets: Dictionary = {}
	for shape_name in _managed_shapes:
		targets[shape_name] = _baseline_for_shape(shape_name)

	for pk in LEGACY_COMPOSITE_KEYS:
		targets[pk] = 0.0

	for name in _split_shape_names:
		targets[name] = 0.0

	for gk in GAZE_KEYS:
		targets[gk] = 0.0

	if _active_gaze != "":
		targets[_active_gaze] = 1.0
	else:
		var viseme_active := _active_viseme != "" and _viseme_strength > 0.0
		var mouth_scale := _mouth_emotion_coef if viseme_active else 1.0
		if _active_emotion != "" and is_emotion_available(_active_emotion):
			var profile: Dictionary = SPLIT_PROFILES[_active_emotion]
			targets[String(profile["eyes"])] = 1.0
			targets[String(profile["mouth"])] = mouth_scale

	for vid in VISEME_IDS:
		targets[String(VISEME_SHAPE_NAMES[vid])] = 0.0
	if _active_viseme != "" and _viseme_strength > 0.0:
		targets[String(VISEME_SHAPE_NAMES[_active_viseme])] = _viseme_coef * _viseme_strength

	return targets


func _baseline_for_shape(shape_name: String) -> float:
	var sum := 0.0
	var count := 0
	for mesh in _meshes:
		var per_mesh: Dictionary = _default_shapes.get(mesh, {})
		if per_mesh.has(shape_name):
			sum += float(per_mesh[shape_name])
			count += 1
		else:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index >= 0:
				sum += mesh.get_blend_shape_value(index)
				count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


func _apply_targets_instant(targets: Dictionary) -> void:
	for mesh in _meshes:
		for shape_name in _managed_shapes:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0 or not targets.has(shape_name):
				continue
			mesh.set_blend_shape_value(index, float(targets[shape_name]))


func _setter_for(mesh: MeshInstance3D, index: int, gen: int) -> Callable:
	return func(value: float) -> void:
		if gen != _tween_gen:
			return
		mesh.set_blend_shape_value(index, value)
