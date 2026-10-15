extends Node
class_name YouyouExpressionController

## P0 主表情 + P1 微表情补充。
## 柚柚.glb 的主键（smile / surprise / laugh / wink / grin 等）已是 Faceit 烘焙的复合 morph，
## 与 ARKit 通道（mouthSmile、jawOpen、eyeBlink 等）叠加会重复驱动同一区域。
## 对复合主键：仅保留主键=1，微表情回到基线；微表情仅保留 sad 等主键未充分表达的补充通道。

const PRIMARY_KEYS: PackedStringArray = [
	"smile",
	"surprise",
	"angry",
	"sad",
	"grin",
	"wink",
	"lookleft",
	"lookright",
	"laugh",
]
const DEFAULT_PRIMARY := "smile"
## 预览 / 口型协调沿用的默认过渡时长（秒）
const BLEND_TIME := 0.2
## 互斥主表情：最终仅一项为 1.0；过渡时对各项独立插值，避免瞬时跳变
const MUTEX_PRIMARIES: PackedStringArray = [
	"smile",
	"surprise",
	"laugh",
	"angry",
	"sad",
	"grin",
]
## 视线 / 眨眼类主键：与互斥组相同「单主键激活」策略；后续 FacePoseMixer 可改为叠加层
const GAZE_PRIMARIES: PackedStringArray = ["wink", "lookleft", "lookright"]
const TRANSITION_BLEND_TIME_DEFAULT := 0.4

## 主键 -> { micro: { shape: weight } }；主键权重固定为 1.0（互斥）
const RECIPES: Dictionary = {
	# 复合主键已含口型/颊部，不再叠 mouthSmile / cheekSquint
	"smile": {
		"micro": {},
	},
	# 复合主键已含眼/眉/口；移除 eyeWide / browUp / jawOpen 避免嘴眼双重拉伸
	"surprise": {
		"micro": {},
	},
	"angry": {
		"micro": {},
	},
	"sad": {
		"micro": {
			"noseSneerLeft": 0.45,
			"noseSneerRight": 0.45,
			"jawForward": 0.15,
		},
	},
	"grin": {
		"micro": {},
	},
	# wink 主键即闭眼；eyeBlinkLeft=1 与主键叠加导致眼皮异常
	"wink": {
		"micro": {},
	},
	"laugh": {
		"micro": {},
	},
	# look* 主键已含眼球方向，不再叠 eyeLook*
	"lookleft": {
		"micro": {},
	},
	"lookright": {
		"micro": {},
	},
}

## 自动化：这些主键在 isolation 检查中要求口/眼相关 ARKit 通道保持基线
const COMPOSITE_NO_STACK: PackedStringArray = [
	"smile",
	"surprise",
	"angry",
	"laugh",
	"wink",
	"grin",
	"lookleft",
	"lookright",
]
const STACK_GUARD_SHAPES: PackedStringArray = [
	"mouthSmileLeft",
	"mouthSmileRight",
	"jawOpen",
	"eyeBlinkLeft",
	"eyeWideLeft",
	"cheekSquintLeft",
	"eyeLookOutLeft",
	"browDownLeft",
	"eyeSquintLeft",
	"mouthFrownLeft",
]

var _meshes: Array[MeshInstance3D] = []
var _default_shapes: Dictionary = {}
var _managed_micro: PackedStringArray = []
var _active_primary := DEFAULT_PRIMARY
var _tween: Tween
var _tween_gen := 0
var _missing_logged: Dictionary = {}
var _last_micro_targets: Dictionary = {}

## P2-3：口型活跃时暂时写 0 的嘴部复合主键（单 morph 无法拆嘴/眼，惊讶/大笑等整键抑制）
const MOUTH_CONFLICTING_PRIMARIES: PackedStringArray = [
	"smile",
	"surprise",
	"angry",
	"sad",
	"grin",
	"laugh",
]
## 口型期间尽量保留（纯眼/视线向；与口型仍可能轻微叠加）
const VISEME_PRESERVED_PRIMARIES: PackedStringArray = ["wink", "lookleft", "lookright"]

var _mouth_suppressed_for_viseme := false

var _primary_blend_time := BLEND_TIME
var _blend_trans: Tween.TransitionType = Tween.TRANS_CUBIC
var _blend_ease: Tween.EaseType = Tween.EASE_IN_OUT
var _transition_target_primary := DEFAULT_PRIMARY
var _transition_progress := 1.0
var _progress_gen := 0


func _ready() -> void:
	_build_managed_micro_list()


func _build_managed_micro_list() -> void:
	var keys: Dictionary = {}
	for primary in RECIPES:
		var micro: Dictionary = RECIPES[primary].get("micro", {})
		for shape_name in micro:
			keys[shape_name] = true
	_managed_micro = PackedStringArray(keys.keys())
	_managed_micro.sort()


func setup(meshes: Array[MeshInstance3D], default_shapes: Dictionary = {}) -> void:
	_meshes = meshes
	_default_shapes = default_shapes
	_log_missing_primaries()
	_log_missing_recipe_shapes()


func get_active_primary() -> String:
	return _active_primary


func get_emotion_restore_primary() -> String:
	return _active_primary


func is_mouth_suppressed_for_viseme() -> bool:
	return _mouth_suppressed_for_viseme


func read_primary_on_mesh(mesh: MeshInstance3D, primary: String) -> float:
	var index := mesh.find_blend_shape_by_name(primary)
	if index < 0:
		return -1.0
	return mesh.get_blend_shape_value(index)


func suppress_mouth_for_viseme(duration: float) -> void:
	_mouth_suppressed_for_viseme = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_gen += 1
	var gen := _tween_gen
	if duration <= 0.0:
		_apply_mouth_suppression_instant()
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	var tween_count := _append_mouth_suppression_tweens(gen, duration)
	if tween_count == 0:
		_tween.kill()
		_tween = null


func restore_emotion_after_viseme(primary: String, duration: float) -> void:
	_mouth_suppressed_for_viseme = false
	if primary not in PRIMARY_KEYS:
		primary = DEFAULT_PRIMARY
	set_primary(primary, duration)


func get_recipe_micro(primary: String) -> Dictionary:
	if not RECIPES.has(primary):
		return {}
	return (RECIPES[primary].get("micro", {}) as Dictionary).duplicate()


func get_managed_micro_keys() -> PackedStringArray:
	return _managed_micro


func configure_primary_blend(
	duration: float = TRANSITION_BLEND_TIME_DEFAULT,
	trans: Tween.TransitionType = Tween.TRANS_CUBIC,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
) -> void:
	_primary_blend_time = maxf(duration, 0.0)
	_blend_trans = trans
	_blend_ease = ease


func get_primary_blend_time() -> float:
	return _primary_blend_time


func get_transition_target() -> String:
	return _transition_target_primary


func get_transition_progress() -> float:
	return _transition_progress


func is_transition_running() -> bool:
	return _tween != null and _tween.is_valid() and _transition_progress < 0.999


func resolve_blend_duration(requested: float) -> float:
	if requested >= 0.0:
		return requested
	return _primary_blend_time


func set_primary(shape_name: String, duration: float = -1.0) -> bool:
	if shape_name not in PRIMARY_KEYS:
		push_error("不是受支持的主表情：" + shape_name)
		return false
	if not _has_primary(shape_name):
		push_error("主表情在当前模型上不存在：" + shape_name)
		return false
	if not RECIPES.has(shape_name):
		push_error("缺少表情配方：" + shape_name)
		return false
	_active_primary = shape_name
	_apply_expression(shape_name, resolve_blend_duration(duration))
	return true


func reset_to_default(duration: float = -1.0) -> void:
	if not _has_primary(DEFAULT_PRIMARY):
		push_error("默认主表情 smile 不存在，无法恢复。")
		return
	_active_primary = DEFAULT_PRIMARY
	_apply_expression(DEFAULT_PRIMARY, resolve_blend_duration(duration), true)


func _apply_expression(primary: String, duration: float, use_baseline_micro: bool = false) -> void:
	var recipe_micro: Dictionary = {} if use_baseline_micro else get_recipe_micro(primary)
	var micro_targets := _resolve_micro_targets(recipe_micro)
	_last_micro_targets = micro_targets.duplicate()
	_transition_target_primary = primary
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween_gen += 1
	var gen := _tween_gen
	if duration <= 0.0:
		_transition_progress = 1.0
		_apply_targets_instant(primary, micro_targets)
		return
	_transition_progress = 0.0
	_progress_gen = gen
	_tween = create_tween()
	_tween.set_parallel(true)
	var tween_count := 0
	var progress_step := _tween.tween_method(_progress_setter(gen), 0.0, 1.0, duration)
	progress_step.set_trans(_blend_trans)
	progress_step.set_ease(_blend_ease)
	tween_count += 1
	for mesh in _meshes:
		for shape_name in PRIMARY_KEYS:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var target := 1.0 if shape_name == primary else 0.0
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			var tweener := _tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tweener.set_trans(_blend_trans)
			tweener.set_ease(_blend_ease)
			tween_count += 1
		for shape_name in _managed_micro:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			if not micro_targets.has(shape_name):
				continue
			var target: float = micro_targets[shape_name]
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			var tweener := _tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tweener.set_trans(_blend_trans)
			tweener.set_ease(_blend_ease)
			tween_count += 1
	if tween_count == 0:
		_tween.kill()
		_tween = null
		_transition_progress = 1.0


func _resolve_micro_targets(recipe_micro: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	for shape_name in _managed_micro:
		if recipe_micro.has(shape_name):
			targets[shape_name] = float(recipe_micro[shape_name])
		else:
			targets[shape_name] = _global_baseline(shape_name)
	return targets


func _global_baseline(shape_name: String) -> float:
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


func _apply_targets_instant(primary: String, micro_targets: Dictionary) -> void:
	for mesh in _meshes:
		for shape_name in PRIMARY_KEYS:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			mesh.set_blend_shape_value(index, 1.0 if shape_name == primary else 0.0)
		for shape_name in _managed_micro:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			if micro_targets.has(shape_name):
				mesh.set_blend_shape_value(index, float(micro_targets[shape_name]))


func _has_primary(shape_name: String) -> bool:
	for mesh in _meshes:
		if mesh.find_blend_shape_by_name(shape_name) >= 0:
			return true
	return false


func _log_missing_primaries() -> void:
	for shape_name in PRIMARY_KEYS:
		if not _has_primary(shape_name):
			if not _missing_logged.has("primary:" + shape_name):
				push_error("主表情形态键缺失，将跳过：" + shape_name)
				_missing_logged["primary:" + shape_name] = true


func _log_missing_recipe_shapes() -> void:
	for primary in RECIPES:
		var micro: Dictionary = RECIPES[primary].get("micro", {})
		for shape_name in micro:
			if not _shape_exists_any_mesh(String(shape_name)):
				var key := "micro:%s:%s" % [primary, shape_name]
				if not _missing_logged.has(key):
					push_error("配方形态键在模型上不存在（已跳过该键）：%s / %s" % [primary, shape_name])
					_missing_logged[key] = true


func _shape_exists_any_mesh(shape_name: String) -> bool:
	for mesh in _meshes:
		if mesh.find_blend_shape_by_name(shape_name) >= 0:
			return true
	return false


func _setter_for(mesh: MeshInstance3D, index: int, gen: int) -> Callable:
	return func(value: float) -> void:
		if gen != _tween_gen:
			return
		mesh.set_blend_shape_value(index, value)


func _progress_setter(gen: int) -> Callable:
	return func(value: float) -> void:
		if gen != _progress_gen:
			return
		_transition_progress = clampf(value, 0.0, 1.0)


func read_micro_on_mesh(mesh: MeshInstance3D, shape_name: String) -> float:
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index < 0:
		return -1.0
	return mesh.get_blend_shape_value(index)


func is_composite_primary(primary: String) -> bool:
	return primary in COMPOSITE_NO_STACK


func max_stack_guard_delta(mesh: MeshInstance3D, primary: String) -> float:
	if primary not in COMPOSITE_NO_STACK:
		return 0.0
	var max_delta := 0.0
	for shape_name in STACK_GUARD_SHAPES:
		var current := read_micro_on_mesh(mesh, shape_name)
		if current < 0.0:
			continue
		var baseline := _baseline_on_mesh(mesh, shape_name)
		max_delta = maxf(max_delta, absf(current - baseline))
	return max_delta


func _baseline_on_mesh(mesh: MeshInstance3D, shape_name: String) -> float:
	var per_mesh: Dictionary = _default_shapes.get(mesh, {})
	if per_mesh.has(shape_name):
		return float(per_mesh[shape_name])
	var index := mesh.find_blend_shape_by_name(shape_name)
	if index >= 0:
		return mesh.get_blend_shape_value(index)
	return 0.0


func _append_mouth_suppression_tweens(gen: int, duration: float) -> int:
	var tween_count := 0
	for mesh in _meshes:
		for shape_name in MOUTH_CONFLICTING_PRIMARIES:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, 0.0):
				continue
			var tweener := _tween.tween_method(_setter_for(mesh, index, gen), start, 0.0, duration)
			tweener.set_trans(_blend_trans)
			tweener.set_ease(_blend_ease)
			tween_count += 1
		for shape_name in _managed_micro:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var target := _baseline_on_mesh(mesh, shape_name)
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			var tweener := _tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tweener.set_trans(_blend_trans)
			tweener.set_ease(_blend_ease)
			tween_count += 1
		for shape_name in VISEME_PRESERVED_PRIMARIES:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index < 0:
				continue
			var target := 1.0 if _active_primary == shape_name else 0.0
			var start := mesh.get_blend_shape_value(index)
			if is_equal_approx(start, target):
				continue
			var tweener := _tween.tween_method(_setter_for(mesh, index, gen), start, target, duration)
			tweener.set_trans(_blend_trans)
			tweener.set_ease(_blend_ease)
			tween_count += 1
	return tween_count


func _apply_mouth_suppression_instant() -> void:
	for mesh in _meshes:
		for shape_name in MOUTH_CONFLICTING_PRIMARIES:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index >= 0:
				mesh.set_blend_shape_value(index, 0.0)
		for shape_name in _managed_micro:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index >= 0:
				mesh.set_blend_shape_value(index, _baseline_on_mesh(mesh, shape_name))
		for shape_name in VISEME_PRESERVED_PRIMARIES:
			var index := mesh.find_blend_shape_by_name(shape_name)
			if index >= 0:
				mesh.set_blend_shape_value(index, 1.0 if _active_primary == shape_name else 0.0)
