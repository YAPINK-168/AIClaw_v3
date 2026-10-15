extends Node
class_name YouyouEyeGazeController

## 视线：eyeLook* 仅写「眼睛左 / 眼睛右」；眨眼同步写睫毛/眉毛（肉眼可见）。

const EYE_MESH_NAMES: PackedStringArray = ["眼睛左", "眼睛右"]
const BLINK_SYNC_MESH_NAMES: PackedStringArray = ["睫毛", "人体_001"]

const SHAPE_OUT_L := "eyeLookOutLeft"
const SHAPE_IN_L := "eyeLookInLeft"
const SHAPE_UP_L := "eyeLookUpLeft"
const SHAPE_DOWN_L := "eyeLookDownLeft"
const SHAPE_OUT_R := "eyeLookOutRight"
const SHAPE_IN_R := "eyeLookInRight"
const SHAPE_UP_R := "eyeLookUpRight"
const SHAPE_DOWN_R := "eyeLookDownRight"

const ALL_LOOK_SHAPES: PackedStringArray = [
	SHAPE_OUT_L, SHAPE_IN_L, SHAPE_UP_L, SHAPE_DOWN_L,
	SHAPE_OUT_R, SHAPE_IN_R, SHAPE_UP_R, SHAPE_DOWN_R,
]

const BLINK_LEFT := "eyeBlinkLeft"
const BLINK_RIGHT := "eyeBlinkRight"

@export var max_horizontal: float = 0.72
@export var max_vertical: float = 0.55
@export var look_weight_horizontal: float = 0.38
@export var look_weight_vertical: float = 0.28
@export var smooth_speed: float = 10.0
@export var wasd_speed: float = 0.85
@export var keyboard_return_speed: float = 8.0
@export var viewport_edge_exponent: float = 1.0

var _eye_meshes: Array[MeshInstance3D] = []
var _blink_sync_meshes: Array[MeshInstance3D] = []
var _camera: Camera3D
var _mouse_gaze := Vector2.ZERO
var _keyboard_gaze := Vector2.ZERO
var _display_gaze := Vector2.ZERO
var _wasd_active := false
var _manual_gaze_override := false
var _autonomous_active := false
var _autonomous_gaze := Vector2.ZERO
var _manual_input_enabled := true
var _blink_weight := 0.0


func setup(model_root: Node3D, camera: Camera3D) -> void:
	_camera = camera
	_eye_meshes.clear()
	_blink_sync_meshes.clear()
	_collect_eye_meshes(model_root)
	_collect_blink_sync_meshes(model_root)
	if _eye_meshes.is_empty():
		push_error("YouyouEyeGazeController: 未找到眼睛网格")
	if _blink_sync_meshes.is_empty():
		push_warning("YouyouEyeGazeController: 未找到眨眼同步网格（睫毛/人体）")


func get_display_gaze() -> Vector2:
	return _display_gaze


func get_autonomous_gaze() -> Vector2:
	return _autonomous_gaze


func get_mouse_gaze_target() -> Vector2:
	return _mouse_gaze


func get_blink_weight() -> float:
	return _blink_weight


func is_wasd_active() -> bool:
	return _wasd_active


func is_manual_gaze_override() -> bool:
	return _manual_gaze_override or _wasd_active


func set_manual_gaze_override(active: bool) -> void:
	_manual_gaze_override = active


func set_autonomous_active(active: bool) -> void:
	_autonomous_active = active


func set_autonomous_gaze(gaze: Vector2) -> void:
	_autonomous_gaze = _clamp_gaze(gaze)


func get_max_horizontal() -> float:
	return max_horizontal


func get_max_vertical() -> float:
	return max_vertical


func set_blink_weight(weight: float) -> void:
	_blink_weight = clampf(weight, 0.0, 1.0)


func apply_blink_weight(weight: float) -> void:
	set_blink_weight(weight)
	_apply_blink_to_meshes()


func set_manual_input_enabled(enabled: bool) -> void:
	_manual_input_enabled = enabled
	if not enabled:
		_wasd_active = false
		_manual_gaze_override = false


func is_manual_input_enabled() -> bool:
	return _manual_input_enabled


func release_look_shapes() -> void:
	_mouse_gaze = Vector2.ZERO
	_keyboard_gaze = Vector2.ZERO
	_display_gaze = Vector2.ZERO
	_autonomous_gaze = Vector2.ZERO
	_wasd_active = false
	for mesh in _eye_meshes:
		_zero_look_shapes(mesh)


func process_gaze(delta: float, viewport: Viewport) -> void:
	if not _manual_input_enabled:
		_wasd_active = false
		_manual_gaze_override = false
		var auto_target := _autonomous_gaze if _autonomous_active else Vector2.ZERO
		_display_gaze = _display_gaze.lerp(auto_target, clampf(smooth_speed * delta, 0.0, 1.0))
		_apply_gaze_to_meshes(_display_gaze)
		_apply_blink_to_meshes()
		return
	if _manual_gaze_override or not _autonomous_active:
		_update_mouse_target(viewport)
		_update_keyboard_gaze(delta)
		var manual_target := _keyboard_gaze
		_display_gaze = _display_gaze.lerp(manual_target, clampf(smooth_speed * delta, 0.0, 1.0))
	else:
		_update_keyboard_gaze(delta)
		if _wasd_active:
			_update_mouse_target(viewport)
			_display_gaze = _display_gaze.lerp(_keyboard_gaze, clampf(smooth_speed * delta, 0.0, 1.0))
		else:
			_display_gaze = _display_gaze.lerp(
				_autonomous_gaze,
				clampf(smooth_speed * delta, 0.0, 1.0),
			)
	_apply_gaze_to_meshes(_display_gaze)
	_apply_blink_to_meshes()


func set_gaze_immediate(gaze: Vector2) -> void:
	var g := _clamp_gaze(gaze)
	_mouse_gaze = g
	_keyboard_gaze = g
	_display_gaze = g
	_apply_gaze_to_meshes(_display_gaze)
	_apply_blink_to_meshes()


func read_shape_weight(shape_name: String, mesh_name: String = "") -> float:
	if _eye_meshes.is_empty():
		return -1.0
	var peak := -1.0
	for mesh in _eye_meshes:
		if mesh_name != "" and mesh.name != mesh_name:
			continue
		var idx := mesh.find_blend_shape_by_name(shape_name)
		if idx < 0:
			continue
		peak = maxf(peak, mesh.get_blend_shape_value(idx))
	return peak


func get_peak_look_weight() -> float:
	var peak := 0.0
	for shape_name in ALL_LOOK_SHAPES:
		var w := read_shape_weight(shape_name)
		if w >= 0.0:
			peak = maxf(peak, w)
	return peak


func _collect_eye_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.name in EYE_MESH_NAMES and mesh.mesh != null:
			_eye_meshes.append(mesh)
	for child in node.get_children():
		_collect_eye_meshes(child)


func _collect_blink_sync_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.name in BLINK_SYNC_MESH_NAMES and mesh.mesh != null:
			_blink_sync_meshes.append(mesh)
	for child in node.get_children():
		_collect_blink_sync_meshes(child)


func _update_mouse_target(viewport: Viewport) -> void:
	if viewport == null:
		return
	var rect := viewport.get_visible_rect()
	var mouse := viewport.get_mouse_position()
	if not rect.has_point(mouse):
		return
	var center := rect.size * 0.5
	if center.x <= 1.0 or center.y <= 1.0:
		return
	var nx := (mouse.x - center.x) / center.x
	var ny := (mouse.y - center.y) / center.y
	if viewport_edge_exponent != 1.0:
		nx = signf(nx) * pow(absf(nx), viewport_edge_exponent)
		ny = signf(ny) * pow(absf(ny), viewport_edge_exponent)
	_mouse_gaze = Vector2(
		clampf(nx, -1.0, 1.0) * max_horizontal,
		clampf(ny, -1.0, 1.0) * max_vertical,
	)


func _update_keyboard_gaze(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0
	_wasd_active = dir.length_squared() > 0.0
	if _wasd_active:
		_keyboard_gaze += dir.normalized() * wasd_speed * delta
		_keyboard_gaze = _clamp_gaze(_keyboard_gaze)
	else:
		_keyboard_gaze = _keyboard_gaze.lerp(
			_mouse_gaze,
			clampf(keyboard_return_speed * delta, 0.0, 1.0),
		)


func _clamp_gaze(g: Vector2) -> Vector2:
	return Vector2(
		clampf(g.x, -max_horizontal, max_horizontal),
		clampf(g.y, -max_vertical, max_vertical),
	)


func _apply_gaze_to_meshes(gaze: Vector2) -> void:
	var gx := gaze.x / maxf(max_horizontal, 0.001)
	var gy := gaze.y / maxf(max_vertical, 0.001)
	gx = clampf(-gx, -1.0, 1.0) * look_weight_horizontal
	gy = clampf(gy, -1.0, 1.0) * look_weight_vertical
	for mesh in _eye_meshes:
		_zero_look_shapes(mesh)
		if mesh.name == "眼睛左":
			_set_look(mesh, maxf(-gx, 0.0), SHAPE_OUT_L)
			_set_look(mesh, maxf(gx, 0.0), SHAPE_IN_L)
			_set_look(mesh, maxf(-gy, 0.0), SHAPE_UP_L)
			_set_look(mesh, maxf(gy, 0.0), SHAPE_DOWN_L)
		elif mesh.name == "眼睛右":
			_set_look(mesh, maxf(gx, 0.0), SHAPE_OUT_R)
			_set_look(mesh, maxf(-gx, 0.0), SHAPE_IN_R)
			_set_look(mesh, maxf(-gy, 0.0), SHAPE_UP_R)
			_set_look(mesh, maxf(gy, 0.0), SHAPE_DOWN_R)


func _apply_blink_to_meshes() -> void:
	for mesh in _eye_meshes:
		if mesh.name == "眼睛左":
			_write_shape(mesh, BLINK_LEFT, _blink_weight)
		elif mesh.name == "眼睛右":
			_write_shape(mesh, BLINK_RIGHT, _blink_weight)
	for mesh in _blink_sync_meshes:
		_write_shape(mesh, BLINK_LEFT, _blink_weight)
		_write_shape(mesh, BLINK_RIGHT, _blink_weight)


func _zero_look_shapes(mesh: MeshInstance3D) -> void:
	for shape_name in ALL_LOOK_SHAPES:
		var idx := mesh.find_blend_shape_by_name(shape_name)
		if idx >= 0:
			mesh.set_blend_shape_value(idx, 0.0)


func _set_look(mesh: MeshInstance3D, weight: float, shape_name: String) -> void:
	if weight <= 0.0001:
		return
	_write_shape(mesh, shape_name, weight)


func _write_shape(mesh: MeshInstance3D, shape_name: String, weight: float) -> void:
	var idx := mesh.find_blend_shape_by_name(shape_name)
	if idx >= 0:
		mesh.set_blend_shape_value(idx, clampf(weight, 0.0, 1.0))
