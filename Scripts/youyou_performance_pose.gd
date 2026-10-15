extends Node
class_name YouyouPerformancePoseController

const FacePresenter := preload("res://Scripts/youyou_face_presenter.gd")

## 动作表现层 → 目标表情。只通过 YouyouFacePresenter 写权重。

const POSE_BASE_IDLE := "base_idle"
const POSE_ATTRACT := "attract"

const POSE_TO_PRIMARY: Dictionary = {
	POSE_BASE_IDLE: "smile",
	POSE_ATTRACT: "laugh",
}

var _face: FacePresenter
var _is_viseme_blocking: Callable

var _current_pose := POSE_BASE_IDLE
var _hello_generation := 0
var _auto_generation := 0


func setup(
	face: FacePresenter,
	is_viseme_blocking: Callable = Callable(),
) -> void:
	_face = face
	_is_viseme_blocking = is_viseme_blocking


func get_current_pose() -> String:
	return _current_pose


func note_pose(pose: String) -> void:
	if pose in POSE_TO_PRIMARY:
		_current_pose = pose


func get_target_primary_for_pose(pose: String) -> String:
	return String(POSE_TO_PRIMARY.get(pose, "smile"))


func performance_blend_duration() -> float:
	if _face != null:
		return _face.performance_blend_duration()
	return FacePresenter.TRANSITION_BLEND_TIME_DEFAULT


func _viseme_blocks() -> bool:
	return _is_viseme_blocking.is_valid() and bool(_is_viseme_blocking.call())


func apply_pose(pose: String, force: bool = false) -> bool:
	if _face == null:
		return false
	if _viseme_blocks():
		return false
	if pose not in POSE_TO_PRIMARY:
		return false
	var target_primary := get_target_primary_for_pose(pose)
	var duration := performance_blend_duration()
	if not force and pose == _current_pose:
		if _face.get_active_primary() == target_primary and not _face.is_transition_running():
			return false
	_current_pose = pose
	if target_primary == FacePresenter.DEFAULT_PRIMARY:
		_face.reset_to_default(duration)
	else:
		_face.set_primary(target_primary, duration)
	return true


func sync_emotion_restore_primary() -> String:
	return get_target_primary_for_pose(_current_pose)


func begin_hello_performance(apply_pose_now: bool = true) -> int:
	_hello_generation += 1
	if apply_pose_now:
		apply_pose(POSE_ATTRACT, true)
	return _hello_generation


func hello_end_may_run(generation: int) -> bool:
	return generation == _hello_generation


func consume_hello_end(generation: int) -> bool:
	if generation != _hello_generation:
		return false
	_hello_generation += 1
	return true


func invalidate_hello() -> void:
	_hello_generation += 1


func bump_auto_session() -> int:
	_auto_generation += 1
	return _auto_generation


func begin_auto_attract_performance(apply_pose_now: bool = true) -> int:
	bump_auto_session()
	if apply_pose_now:
		apply_pose(POSE_ATTRACT, true)
	return _auto_generation


func auto_finish_may_run(generation: int) -> bool:
	return generation == _auto_generation


func consume_auto_finish(generation: int) -> bool:
	if generation != _auto_generation:
		return false
	_auto_generation += 1
	return true


func invalidate_auto() -> void:
	_auto_generation += 1
