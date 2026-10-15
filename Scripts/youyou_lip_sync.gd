extends Node
class_name YouyouLipSyncController

## P2 口型：复合主键 A/E/i/o/u。P2-2 按 glb morph 位移核查仅对口腔相关网格写权重。
## 眉毛/眼/睫 上虽存在口型键，但 morph 位移接近 0 或与口型无关，不参与口型驱动。

const BLEND_TIME := 0.2

const VISEME_IDS: PackedStringArray = ["a", "e", "i", "o", "u"]

const VISEME_SHAPE_NAMES: Dictionary = {
	"a": "A",
	"e": "E",
	"i": "i",
	"o": "o",
	"u": "u",
}

## 核查结论（柚柚.glb 顶点 delta，权重 0→1 时）：
## - 人体_001 / 上牙 / 下牙 / 舌头：A/o 等有明显口部位移 → 参与，统一系数 1.0。
## - 眉毛：A/E/i/o/u 位移全 0 → 不参与。
## - 眼睛左/右：A/o 位移 0，E/i/u 仅极小局部 → 不参与。
## - 睫毛：位移远小于口腔网格 → 不参与。
const VISEME_MESH_PARTICIPANTS: PackedStringArray = [
	"人体_001",
	"上牙",
	"下牙",
	"舌头",
]

const VISEME_MICRO_KEYS: PackedStringArray = []

const EMOTION_TOUCHED_HINT: PackedStringArray = [
	"smile", "surprise", "angry", "sad", "grin", "wink", "lookleft", "lookright", "laugh",
	"noseSneerLeft", "noseSneerRight", "jawForward",
]

var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _active_viseme := ""
var _active_strength := 0.0
var _tween: Tween
var _tween_gen := 0
var _missing_logged: Dictionary = {}


func setup(meshes: Array[MeshInstance3D], default_shapes: Dictionary = {}) -> void:
	_meshes = meshes
	_default_shapes = default_shapes
	_log_missing_visemes()
	_log_unlisted_participants()


func get_active_viseme() -> String:
	return _active_viseme


func get_active_strength() -> float:
	return _active_strength


func get_participant_mesh_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for mesh in _viseme_meshes():
		names.append(mesh.name)
	return names


func get_managed_viseme_shape_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for vid in VISEME_IDS:
		names.append(String(VISEME_SHAPE_NAMES[vid]))
	for k in VISEME_MICRO_KEYS:
		names.append(String(k))
	return names


func is_viseme_participant_mesh(mesh: MeshInstance3D) -> bool:
	return mesh.name in VISEME_MESH_PARTICIPANTS


func set_viseme(viseme_id: String, strength: float = 1.0, duration: float = BLEND_TIME) -> bool:
	var vid := viseme_id.to_lower()
	if vid not in VISEME_IDS:
		push_error("不是受支持的口型 id：" + viseme_id)
		return false
	if not _has_viseme_shape(vid):
		push_error("口型形态键在参与网格上不存在：" + str(VISEME_SHAPE_NAMES.get(vid, "")))
		return false
	strength = clampf(strength, 0.0, 1.0)
	_active_viseme = vid
	_active_strength = strength
	_apply_viseme_state(duration)
	return true


func clear_viseme(duration: float = BLEND_TIME) -> void:
	_active_viseme = ""
	_active_strength = 0.0
	_apply_viseme_state(duration)


func all_visemes_near_zero(max_weight: float = 0.02) -> bool:
	for mesh in _viseme_meshes():
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
	for mesh in _viseme_meshes():
		for vid in VISEME_IDS:
			var sh := String(VISEME_SHAPE_NAMES[vid])
			if sh == active_shape:
				continue
			var v := read_viseme_on_mesh(mesh, vid)
			if v >= 0.0:
				peak = maxf(peak, v)
	return peak


func read_viseme_on_mesh(mesh: MeshInstance3D, viseme_id: String) -> float:
	var shape_name := String(VISEME_SHAPE_NAMES.get(viseme_id.to_lower(), ""))
	if shape_name.is_empty():
		return -1.0
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index < 0:
		return -1.0
	return mesh.get_blend_shape_value(index)


func _viseme_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mesh in _meshes:
		if mesh.name in VISEME_MESH_PARTICIPANTS:
			out.append(mesh)
	return out


func _apply_viseme_state(duration: float) -> void:
	var targets := _build_targets()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_gen += 1
	var gen := _tween_gen
	if duration <= 0.0:
		_apply_targets_instant(targets)
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	var tween_count := 0
	for mesh in _viseme_meshes():
		for vid in VISEME_IDS:
			var shape_name := String(VISEME_SHAPE_NAMES[vid])
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var target: float = targets[shape_name]
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			_tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tween_count += 1
		for shape_name in VISEME_MICRO_KEYS:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var target: float = targets[shape_name]
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			_tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tween_count += 1
	if tween_count == 0:
		_tween.kill()
		_tween = null


func _build_targets() -> Dictionary:
	var targets: Dictionary = {}
	for vid in VISEME_IDS:
		var shape_name := String(VISEME_SHAPE_NAMES[vid])
		if _active_viseme == vid and _active_strength > 0.0:
			targets[shape_name] = _active_strength
		else:
			targets[shape_name] = _participant_baseline(shape_name)
	for shape_name in VISEME_MICRO_KEYS:
		targets[shape_name] = _participant_baseline(String(shape_name))
	return targets


func _apply_targets_instant(targets: Dictionary) -> void:
	for mesh in _viseme_meshes():
		for vid in VISEME_IDS:
			var shape_name := String(VISEME_SHAPE_NAMES[vid])
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			mesh.set_blend_shape_value(index, float(targets.get(shape_name, 0.0)))
		for shape_name in VISEME_MICRO_KEYS:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			mesh.set_blend_shape_value(index, float(targets.get(shape_name, 0.0)))


func _participant_baseline(shape_name: String) -> float:
	var sum := 0.0
	var count := 0
	for mesh in _viseme_meshes():
		sum += _baseline_on_mesh(mesh, shape_name)
		count += 1
	if count == 0:
		return 0.0
	return sum / float(count)


func _baseline_on_mesh(mesh: MeshInstance3D, shape_name: String) -> float:
	var per_mesh: Dictionary = _default_shapes.get(mesh, {})
	if per_mesh.has(shape_name):
		return float(per_mesh[shape_name])
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index >= 0:
		return mesh.get_blend_shape_value(index)
	return 0.0


func _has_viseme_shape(viseme_id: String) -> bool:
	var shape_name := String(VISEME_SHAPE_NAMES.get(viseme_id, ""))
	if shape_name.is_empty():
		return false
	for mesh in _viseme_meshes():
		if mesh.find_blend_shape_by_name(shape_name) >= 0:
			return true
	return false


func _log_missing_visemes() -> void:
	for vid in VISEME_IDS:
		if not _has_viseme_shape(vid):
			var key := "viseme:" + vid
			if not _missing_logged.has(key):
				push_error("口型形态键在参与网格上缺失：" + str(VISEME_SHAPE_NAMES[vid]))
				_missing_logged[key] = true


func _log_unlisted_participants() -> void:
	for mesh in _viseme_meshes():
		if mesh.find_blend_shape_by_name("A") < 0:
			push_error("口型参与网格缺少 A 形态：" + mesh.name)
	for name in VISEME_MESH_PARTICIPANTS:
		var found := false
		for mesh in _meshes:
			if mesh.name == name:
				found = true
				break
		if not found and not _missing_logged.has("participant:" + name):
			push_error("口型参与网格在场景中未找到：" + name)
			_missing_logged["participant:" + name] = true


func _setter_for(mesh: MeshInstance3D, index: int, gen: int) -> Callable:
	return func(value: float) -> void:
		if gen != _tween_gen:
			return
		mesh.set_blend_shape_value(index, value)
