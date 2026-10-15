extends Area2D

signal item_collected(item: Collectible)
signal item_grabbed(item: Collectible)
signal claw_fired
signal empty_returned

enum State { SWINGING, EXTENDING, RETRACTING }

## 钩爪+锁链整体视觉缩放（改这一处即可）
const CLAW_VISUAL_SCALE := 0.56
const PART_SCALE := 0.26 * CLAW_VISUAL_SCALE
const SPRITE_TILT := deg_to_rad(0.0)
const TEX_BOAT_CLAW := preload("res://miner/assets/claw_boat.png")
## 新爪贴图略放大（原 0.0667 偏小）
const BOAT_CLAW_SCALE := 0.098
const TEX_HUB := preload("res://miner/assets/claw_hub.png")
const TEX_LEFT := preload("res://miner/assets/claw_left.png")
const TEX_RIGHT := preload("res://miner/assets/claw_right.png")
const TEX_CHAIN_LINE := preload("res://miner/assets/rope_boat.png")
## 新金绳贴图更醒目，略加粗
const CHAIN_THICKNESS := 11.0
const CHAIN_HULL_EMBED := 12.0 * CLAW_VISUAL_SCALE
## 钩到物品后收回：耗时 ×(1+此值)，即速度 ÷(1+此值)
const RETRACT_LOADED_DURATION_EXTRA := 1.0
## 抓取判定半径（Area2D 本地）；爪放大后旧值 9.3 太小会「碰到却勾不到」
const CLAW_HIT_RADIUS := 36.0
## 勾到后物品挂在爪尖附近（Area2D 本地 Y；实际以碰撞圆为准）
const CLAW_GRAB_LOCAL_Y := 52.0
const CLAW_GRAB_ABOVE_TIP := 10.0
## 抓斗合页中心到爪尖（本地 +Y）；对齐新 claw_boat 贴图高度 608
const PRONG_TIP_OFFSET := (608.0 - 36.0) * BOAT_CLAW_SCALE
## 额外距离勾取：物理重叠漏检时用爪尖世界距兜底
const CLAW_GRAB_REACH := 52.0
const TEX_CENTER := Vector2(232.0, 118.0)
const JOINT_LEFT := Vector2(139.0, 76.0)
const JOINT_RIGHT := Vector2(325.0, 76.0)

@export var swing_amplitude: float = 1.05
## 斜向出钩时允许爪尖略过沙线再收（宽关卡够屏对角）
@export var seabed_angle_slack: float = 0.62
@export var seabed_depth_slack: float = 64.0
@export var swing_speed: float = 1.42
@export var extend_speed: float = 460.0
@export var retract_speed: float = 440.0
@export var min_length: float = 6.0
@export var max_length: float = 2800.0
@export var seabed_y: float = 719.0
@export var grasp_speed: float = 8.0

var state: State = State.SWINGING
var active: bool = true
var hooked: Collectible = null

var _angle: float = 0.0
var _swing_t: float = 0.0
var _length: float = 6.0
var _grasp: float = 0.0
var _grasp_target: float = 0.0

var _visual: Node2D
var _boat_claw: Sprite2D
var _joint_left: Node2D
var _joint_right: Node2D

@onready var _rope: Line2D = $"../Rope"
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	monitoring = true
	monitorable = false
	_length = min_length
	z_as_relative = true
	z_index = 5
	_setup_chain()
	_build_visuals()
	area_entered.connect(_on_area_entered)
	_apply_pose()
	_apply_grasp()


func try_fire() -> bool:
	if not active or state != State.SWINGING:
		return false
	state = State.EXTENDING
	_grasp_target = -0.4
	claw_fired.emit()
	return true


func _physics_process(delta: float) -> void:
	if not active and state == State.SWINGING:
		_apply_pose()
		_apply_grasp()
		return

	match state:
		State.SWINGING:
			_swing_t += delta * swing_speed
			_angle = sin(_swing_t) * swing_amplitude
		State.EXTENDING:
			_length += extend_speed * delta
			if _should_retract_empty():
				state = State.RETRACTING
				_grasp_target = 0.0
			else:
				_try_catch()
		State.RETRACTING:
			var speed := retract_speed
			if hooked != null:
				var loaded_div := 1.0 + hooked.mass * 0.48
				loaded_div *= 1.0 + RETRACT_LOADED_DURATION_EXTRA
				speed = retract_speed / loaded_div
			_length -= speed * delta
			if _length <= min_length:
				_length = min_length
				_finish_retract()

	_grasp = move_toward(_grasp, _grasp_target, delta * grasp_speed)
	_apply_pose()
	_apply_grasp()


func _should_retract_empty() -> bool:
	if _length >= max_length:
		return true
	# 与 submarine / 刷物同一套 World1280 坐标；global_position 含缩放会导致过早触沙
	var tip_y := _tip_design().y
	if tip_y < seabed_y:
		return false
	if absf(_angle) > seabed_angle_slack and tip_y < seabed_y + seabed_depth_slack:
		return false
	return true


func _submarine_node() -> Node2D:
	var pivot := get_parent() as Node2D
	if pivot == null:
		return null
	return pivot.get_parent() as Node2D


func _grab_anchor_local_y() -> float:
	if _collision != null:
		return _collision.position.y - CLAW_GRAB_ABOVE_TIP
	return CLAW_GRAB_LOCAL_Y


func _tip_design() -> Vector2:
	var sub := _submarine_node()
	var pivot := get_parent() as Node2D
	if sub == null or pivot == null:
		return global_position
	var dir := Vector2.DOWN.rotated(_angle)
	var tip_on_sub := pivot.position + dir * (_length + PRONG_TIP_OFFSET)
	return sub.position + tip_on_sub


func _try_catch() -> void:
	for area in get_overlapping_areas():
		if _hook_if_possible(area):
			return
	## 物理重叠偶尔漏帧：用爪尖距离再扫一遍
	_try_catch_by_tip_distance()


func _try_catch_by_tip_distance() -> void:
	var tip := _collision.global_position if _collision else global_position
	var best: Collectible = null
	var best_d := CLAW_GRAB_REACH
	for node in get_tree().get_nodes_in_group("collectibles"):
		var item := node as Collectible
		if item == null or item.grabbed or item.tide_locked:
			continue
		var reach := CLAW_GRAB_REACH + Collectible.placement_radius(item.kind) * 0.55
		var d := tip.distance_to(item.global_position)
		if d < best_d and d <= reach:
			best_d = d
			best = item
	if best != null:
		_hook_if_possible(best)


func _on_area_entered(area: Area2D) -> void:
	if state == State.EXTENDING:
		_hook_if_possible(area)


func _hook_if_possible(area: Area2D) -> bool:
	if state != State.EXTENDING:
		return false
	var item := area as Collectible
	if item == null or item.grabbed or item.tide_locked:
		return false
	item.grabbed = true
	item.set_process(false)
	if item.has_method("freeze_for_grab"):
		item.freeze_for_grab()
	var world_scale := item.global_scale
	item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector2(0.0, _grab_anchor_local_y())
	item.rotation = -rotation
	item.scale = world_scale / global_scale
	item.z_as_relative = true
	item.z_index = 1
	hooked = item
	state = State.RETRACTING
	_grasp_target = 1.0
	item_grabbed.emit(item)
	return true


func _finish_retract() -> void:
	if hooked != null:
		var item := hooked
		hooked = null
		item_collected.emit(item)
		item.queue_free()
	else:
		empty_returned.emit()
	_grasp_target = 0.0
	_resume_swing()


func _resume_swing() -> void:
	# Keep _swing_t from before fire so pendulum phase and direction continue.
	state = State.SWINGING


func _apply_pose() -> void:
	var dir := Vector2.DOWN.rotated(_angle)
	position = dir * _length
	rotation = _angle
	if _rope:
		# Hull end stays on the sub's local up axis so the chain never
		# shoots through the top. Draw claw -> hull so new links unspool
		# from the ship instead of the claw.
		var hull := Vector2(0.0, -CHAIN_HULL_EMBED)
		_rope.points = PackedVector2Array([position, hull])


func _apply_grasp() -> void:
	if _boat_claw != null:
		var t := clampf((_grasp + 0.4) / 1.4, 0.0, 1.0)
		var sx := lerpf(1.08, 0.74, t)
		_boat_claw.scale = Vector2(sx, 1.0)
		return
	if _joint_left == null:
		return
	_joint_left.rotation = deg_to_rad(-34.0) * _grasp
	_joint_right.rotation = deg_to_rad(34.0) * _grasp


func _setup_chain() -> void:
	if _rope == null:
		return
	_rope.visible = true
	_rope.texture = TEX_CHAIN_LINE
	_rope.texture_mode = Line2D.LINE_TEXTURE_TILE
	_rope.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_rope.width = CHAIN_THICKNESS
	_rope.default_color = Color.WHITE
	_rope.begin_cap_mode = Line2D.LINE_CAP_NONE
	_rope.end_cap_mode = Line2D.LINE_CAP_NONE
	_rope.joint_mode = Line2D.LINE_JOINT_ROUND
	_rope.antialiased = true
	_rope.z_as_relative = true
	_rope.z_index = 1


func _build_visuals() -> void:
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	_visual = Node2D.new()
	_visual.z_as_relative = true
	add_child(_visual)
	_boat_claw = Sprite2D.new()
	_boat_claw.texture = TEX_BOAT_CLAW
	_boat_claw.centered = true
	_boat_claw.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_visual.add_child(_boat_claw)
	_visual.scale = Vector2(BOAT_CLAW_SCALE, BOAT_CLAW_SCALE)
	var tex_h := TEX_BOAT_CLAW.get_height()
	# 木盖顶对齐绳端
	_boat_claw.position = Vector2(0.0, tex_h * 0.5 - 18.0)
	## 碰撞放在爪尖附近，半径随新爪放大
	_collision.position = Vector2(0.0, (tex_h - 36.0) * BOAT_CLAW_SCALE)
	var circle := CircleShape2D.new()
	circle.radius = CLAW_HIT_RADIUS
	_collision.shape = circle


func _make_joint(joint_px: Vector2, z: int) -> Node2D:
	var joint := Node2D.new()
	joint.position = joint_px - TEX_CENTER
	joint.z_as_relative = true
	joint.z_index = z
	_visual.add_child(joint)
	return joint


func _make_part(tex: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_as_relative = true
	return sprite


func _make_part_offset(tex: Texture2D, joint_px: Vector2) -> Sprite2D:
	var sprite := _make_part(tex)
	sprite.position = TEX_CENTER - joint_px
	return sprite
