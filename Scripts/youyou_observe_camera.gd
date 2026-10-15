extends Node3D

const MIN_DISTANCE := 0.35
const MAX_DISTANCE := 4.5
const PAN_LIMIT := 0.55
const ORBIT_SPEED := 0.008
const PAN_SPEED := 0.0014
const ZOOM_STEP := 1.1
const PITCH_LIMIT_DOWN := -55.0
const PITCH_LIMIT_UP := 65.0

@onready var _camera: Camera3D = $Camera3D

var _yaw := 0.0
var _pitch := 0.0
var _distance := 1.6
var _distance_target := 1.6
var _home_position := Vector3(0.0, 0.52, 0.02)
var _home_yaw := 0.0
var _home_pitch := 0.0
var _home_distance := 1.6
var _dragging := false
var _panning := false


func _ready() -> void:
	_camera.current = true
	position = _home_position
	_apply_transform()
	var args := OS.get_cmdline_user_args()
	_check_log("ready args=" + str(args))
	if "--camera-check" in args:
		_run_camera_check()
	else:
		_frame_model()


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-10.0 * delta)
	_distance = lerpf(_distance, _distance_target, blend)
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _dragging:
		_on_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		reset_view()
		get_viewport().set_input_as_handled()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		_panning = event.pressed and event.shift_pressed
		if not event.pressed:
			_panning = false
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_distance_target = clampf(_distance_target / ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_distance_target = clampf(_distance_target * ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
		get_viewport().set_input_as_handled()


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.shift_pressed or _panning:
		_pan(event.relative)
	else:
		_orbit(event.relative)
	get_viewport().set_input_as_handled()


func _orbit(relative: Vector2) -> void:
	_yaw -= relative.x * ORBIT_SPEED
	_pitch = clampf(_pitch - relative.y * ORBIT_SPEED, deg_to_rad(PITCH_LIMIT_DOWN), deg_to_rad(PITCH_LIMIT_UP))
	_apply_transform()


func _pan(relative: Vector2) -> void:
	var basis := global_transform.basis
	var offset := (-basis.x * relative.x + basis.y * relative.y) * PAN_SPEED * _distance
	position += offset
	var from_home := position - _home_position
	if from_home.length() > PAN_LIMIT:
		position = _home_position + from_home.normalized() * PAN_LIMIT
	_apply_transform()


func reset_view() -> void:
	position = _home_position
	_yaw = _home_yaw
	_pitch = _home_pitch
	_distance = _home_distance
	_distance_target = _home_distance
	_apply_transform()


func _apply_transform() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)


func _frame_model() -> void:
	for _i in 2:
		await get_tree().process_frame
	var model := get_parent().get_node_or_null("YouyouModel") as Node3D
	var skeleton := model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D if model != null else null
	if skeleton == null:
		push_error("观察相机未找到骨架，使用预设中心。")
		_store_home()
		return
	var hips := _bone_world(skeleton, "mixamorig_Hips")
	var head := _bone_world(skeleton, "mixamorig_Head")
	var foot_y := minf(_bone_world(skeleton, "mixamorig_LeftFoot").y, _bone_world(skeleton, "mixamorig_RightFoot").y)
	var hand_span := absf(_bone_world(skeleton, "mixamorig_LeftHand").x - _bone_world(skeleton, "mixamorig_RightHand").x)
	var body_height := maxf(head.y - foot_y, 0.2)
	var hair_top := head.y + body_height * 0.30
	var sole := foot_y - body_height * 0.18
	var full_height := hair_top - sole
	var focus := Vector3((hips.x + head.x) * 0.5, (hair_top + sole) * 0.5, hips.z)
	position = focus
	_distance_target = _fit_extents(full_height, maxf(hand_span, full_height * 0.38))
	_distance = _distance_target
	_yaw = 0.0
	_pitch = 0.0
	_apply_transform()
	_store_home()
	if "--camera-check" in OS.get_cmdline_user_args():
		print("observe_focus=%s height=%s hands=%s dist=%s" % [focus, full_height, hand_span, _distance_target])


func _bone_world(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		push_error("缺少骨骼：" + bone_name)
		return skeleton.global_position
	return skeleton.to_global(skeleton.get_bone_global_pose(index).origin)


func _fit_extents(height: float, width: float) -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var vertical := tan(deg_to_rad(_camera.fov * 0.5))
	var horizontal := vertical * aspect
	var dist_y := (height * 0.5 * 1.20) / vertical
	var dist_x := (width * 0.5 * 1.12) / horizontal
	return clampf(maxf(dist_y, dist_x), MIN_DISTANCE, MAX_DISTANCE)


func _store_home() -> void:
	_home_position = position
	_home_yaw = _yaw
	_home_pitch = _pitch
	_home_distance = _distance_target


func _run_camera_check() -> void:
	_check_log("check-start args=" + str(OS.get_cmdline_user_args()))
	await _frame_model()
	_check_log("framed pos=" + str(position) + " dist=" + str(_distance_target))
	var lines: PackedStringArray = []
	var model := get_parent().get_node("YouyouModel") as Node3D
	var player := model.get_node("PreviewAnimationPlayer") as AnimationPlayer
	var body := model.get_node("Armature/Skeleton3D/人体_001") as MeshInstance3D
	var smile_index := body.find_blend_shape_by_name("smile")
	var anim_before := player.assigned_animation
	var smile_before := body.get_blend_shape_value(smile_index)
	var home_pos := position
	var home_dist := _distance_target
	await _save_png("C:/Users/29385/AppData/Local/Temp/youyou_cam_front.png")
	_press_middle(false)
	_move_mouse(Vector2(80, 0))
	var yaw_after_horizontal := _yaw
	var cam_x := _camera.global_position.x
	lines.append("home_dist=" + str(home_dist))
	_move_mouse(Vector2(0, -2000))
	var pitch_up := _pitch
	_move_mouse(Vector2(0, 4000))
	var pitch_down := _pitch
	_release_middle()
	var yaw_after_release := _yaw
	_zoom(-3)
	var zoom_in := _distance_target
	_zoom(30)
	var zoom_far := _distance_target
	_zoom(-30)
	var zoom_near := _distance_target
	_distance = _home_distance
	_distance_target = _home_distance
	_yaw = _home_yaw
	_pitch = _home_pitch
	position = _home_position
	_apply_transform()
	_press_middle(true)
	_move_mouse(Vector2(400, -300))
	var pan_offset := position - _home_position
	_release_middle()
	_push_key(KEY_R)
	await get_tree().process_frame
	lines.append("horizontal_yaw=" + str(yaw_after_horizontal))
	lines.append("camera_x_after_yaw=" + str(cam_x))
	lines.append("pitch_up=" + str(rad_to_deg(pitch_up)))
	lines.append("pitch_down=" + str(rad_to_deg(pitch_down)))
	lines.append("yaw_held_after_release=" + str(is_equal_approx(yaw_after_release, yaw_after_horizontal)))
	lines.append("zoom_in=" + str(zoom_in))
	lines.append("zoom_far=" + str(zoom_far))
	lines.append("zoom_near=" + str(zoom_near))
	lines.append("pan_length=" + str(pan_offset.length()))
	lines.append("reset_pos=" + str(position.is_equal_approx(home_pos)))
	lines.append("reset_dist=" + str(is_equal_approx(_distance_target, home_dist)))
	lines.append("anim_same=" + str(player.assigned_animation == anim_before))
	lines.append("smile_same=" + str(is_equal_approx(body.get_blend_shape_value(smile_index), smile_before)))
	_push_key(KEY_2)
	await get_tree().process_frame
	var surprise_index := body.find_blend_shape_by_name("surprise")
	var surprise_after_key := body.get_blend_shape_value(surprise_index)
	_press_middle(false)
	_move_mouse(Vector2(30, 10))
	_release_middle()
	reset_view()
	lines.append("surprise_after_key=" + str(surprise_after_key))
	lines.append("surprise_after_camera=" + str(body.get_blend_shape_value(surprise_index)))
	lines.append("anim_after_camera=" + str(player.assigned_animation))
	_push_key(KEY_I)
	await get_tree().process_frame
	lines.append("idle_after_i=" + str(player.assigned_animation))
	var dir := "C:/Users/29385/AppData/Local/Temp"
	_press_middle(false)
	_move_mouse(Vector2(140, -20))
	_release_middle()
	_distance = _distance_target
	_apply_transform()
	await _save_png(dir + "/youyou_cam_orbit.png")
	_check_log("\n".join(lines))
	print("\n".join(lines))
	get_tree().quit()


func _check_log(message: String) -> void:
	var file := FileAccess.open("C:/Users/29385/AppData/Local/Temp/youyou_camera_check.log", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("C:/Users/29385/AppData/Local/Temp/youyou_camera_check.log", FileAccess.WRITE)
	if file == null:
		push_error("无法写相机检查日志")
		return
	file.seek_end()
	file.store_line(message)
	file.close()


func _press_middle(shift_down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = true
	event.shift_pressed = shift_down
	_unhandled_input(event)


func _release_middle() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = false
	_unhandled_input(event)


func _move_mouse(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.shift_pressed = _panning
	event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	_unhandled_input(event)


func _zoom(steps: int) -> void:
	var zoom_out := steps > 0
	for _i in absi(steps):
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN if zoom_out else MOUSE_BUTTON_WHEEL_UP
		event.pressed = true
		_unhandled_input(event)


func _push_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = false
	get_viewport().push_input(event)


func _save_png(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("png %s size=%s err=%s" % [path, image.get_size(), err])
