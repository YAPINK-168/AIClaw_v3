extends Node2D

const SFX_SULK := preload("res://miner/assets/audio/sulk.mp3")
const TEX_IP_IDLE := preload("res://miner/assets/ip/ip_boat_idle_01.png")
const TEX_IP_OPERATE := preload("res://miner/assets/ip/ip_boat_operate_01.png")
const TEX_IP_OPERATE_UP := preload("res://miner/assets/ip/ip_boat_operate_02.png")
const TEX_IP_HAPPY := preload("res://miner/assets/ip/ip_boat_happy_01.png")
const TEX_IP_SAD := preload("res://miner/assets/ip/ip_boat_sad_01.png")
const EMOTION_HOLD := 0.8

## 待机只用一张船体贴图（如 IP idle_01），起伏靠代码，不依赖第二帧动画。
@export var bob_amount: float = 3.5
@export var bob_speed: float = 1.55
@export var move_speed: float = 320.0
@export var min_x: float = 140.0
@export var max_x: float = 1140.0

var _emotion_left: float = 0.0
var _t: float = 0.0
var _operating: bool = false
var _operate_t: float = 0.0
var _rest: Vector2 = Vector2.ZERO
var _move_axis: float = 0.0
var _tide_drop_y: float = 0.0
var _base_scale: Vector2 = Vector2.ONE
var _celebrate_tw: Tween
var _sulk_tw: Tween
var _sulk_marks: Node2D
var _sfx_sulk: AudioStreamPlayer

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _pivot: Marker2D = $HookPivot
@onready var _bubbles: CPUParticles2D = $Bubbles


func _ready() -> void:
	_rest = position
	_base_scale = _sprite.scale
	_place_hook()
	_build_sulk_marks()
	_sfx_sulk = AudioStreamPlayer.new()
	_sfx_sulk.name = "SFXSulk"
	_sfx_sulk.stream = SFX_SULK
	add_child(_sfx_sulk)


func celebrate() -> void:
	_hide_sulk()
	if _uses_ip_boat():
		_show_emotion(TEX_IP_HAPPY)
		return
	if _celebrate_tw:
		_celebrate_tw.kill()
	_sprite.scale = _base_scale
	_sprite.rotation = 0.0
	_celebrate_tw = create_tween()
	_celebrate_tw.set_parallel(true)
	_celebrate_tw.tween_property(_sprite, "scale", _base_scale * 1.14, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_celebrate_tw.tween_property(_sprite, "rotation", deg_to_rad(-7.0), 0.06).set_trans(Tween.TRANS_SINE)
	_celebrate_tw.chain().tween_property(_sprite, "rotation", deg_to_rad(6.0), 0.07).set_trans(Tween.TRANS_SINE)
	_celebrate_tw.tween_property(_sprite, "scale", _base_scale, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_celebrate_tw.chain().tween_property(_sprite, "rotation", 0.0, 0.08).set_trans(Tween.TRANS_SINE)


func sulk() -> void:
	if _uses_ip_boat():
		_hide_sulk()
		_show_emotion(TEX_IP_SAD)
		if _sfx_sulk:
			_sfx_sulk.seek(0.0)
			_sfx_sulk.play()
		return
	if _celebrate_tw:
		_celebrate_tw.kill()
	_sprite.scale = _base_scale
	_sprite.rotation = 0.0
	if _sulk_marks == null:
		_build_sulk_marks()
	_sulk_marks.visible = true
	_sulk_marks.modulate.a = 0.0
	_sulk_marks.scale = Vector2(0.72, 0.72)
	if _sulk_tw:
		_sulk_tw.kill()
	_sulk_tw = create_tween()
	_sulk_tw.set_parallel(true)
	if _sfx_sulk:
		_sfx_sulk.seek(0.0)
		_sfx_sulk.play()
	_sulk_tw.tween_property(_sulk_marks, "modulate:a", 1.0, 0.1)
	_sulk_tw.tween_property(_sulk_marks, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sulk_tw.set_parallel(false)
	_sulk_tw.chain().tween_interval(0.7)
	_sulk_tw.tween_property(_sulk_marks, "modulate:a", 0.0, 0.22)
	_sulk_tw.tween_callback(_hide_sulk)


func _hide_sulk() -> void:
	if _sulk_tw:
		_sulk_tw.kill()
		_sulk_tw = null
	if _sulk_marks:
		_sulk_marks.visible = false
		_sulk_marks.modulate.a = 0.0


func _build_sulk_marks() -> void:
	_sulk_marks = Node2D.new()
	_sulk_marks.z_as_relative = true
	_sulk_marks.z_index = 8
	_sulk_marks.position = Vector2(62.0, -44.0)
	_sulk_marks.rotation = deg_to_rad(8.0)
	add_child(_sulk_marks)
	var specs: Array = [
		[Vector2(-10.0, 0.0), 18.0],
		[Vector2(0.0, 0.0), 28.0],
		[Vector2(10.0, 0.0), 22.0],
	]
	for spec in specs:
		var line := Line2D.new()
		line.width = 5.5
		line.default_color = Color(0.52, 0.28, 0.08)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		var pos: Vector2 = spec[0]
		var h: float = spec[1]
		line.points = PackedVector2Array([pos, pos + Vector2(0.0, h)])
		_sulk_marks.add_child(line)
	_hide_sulk()


func set_move_axis(axis: float) -> void:
	_move_axis = clampf(axis, -1.0, 1.0)


func set_operating(on: bool) -> void:
	if not _uses_ip_boat() or _emotion_left > 0.0:
		return
	if _operating == on:
		return
	_operating = on
	_operate_t = 0.0
	_apply_ip_tex(TEX_IP_OPERATE if on else TEX_IP_IDLE)


func _uses_ip_boat() -> bool:
	return _sprite != null and _sprite.texture != null and _sprite.texture.resource_path.find("ip_boat") >= 0


func _show_emotion(tex: Texture2D) -> void:
	_emotion_left = EMOTION_HOLD
	_sprite.scale = _base_scale
	_sprite.rotation = 0.0
	_apply_ip_tex(tex)


func _apply_ip_tex(tex: Texture2D) -> void:
	if _sprite.texture == tex:
		return
	_sprite.texture = tex
	_place_hook()


func reset_rest(pos: Vector2) -> void:
	_rest = pos
	position = _rest + Vector2(0.0, _tide_drop_y)


func set_tide_drop_y(y: float) -> void:
	_tide_drop_y = y


## 船体下缘 + 浮动不超过 surface_y（设计稿红线）；只改 Y，保留当前 X
func align_above_surface_line(surface_y: float, pad: float = 6.0) -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var half_h := _sprite.texture.get_height() * absf(_sprite.scale.y) * 0.5
	var y := surface_y - half_h - bob_amount - pad
	# 与 game 只改 position.x 时保持一致，避免 _process 用旧 _rest 拉回场景坐标
	var x := position.x if absf(position.x - _rest.x) > 0.01 else _rest.x
	reset_rest(Vector2(x, y))


func _process(delta: float) -> void:
	if _emotion_left > 0.0:
		_emotion_left = maxf(_emotion_left - delta, 0.0)
		if _emotion_left <= 0.0 and _uses_ip_boat():
			_apply_ip_tex(TEX_IP_OPERATE if _operating else TEX_IP_IDLE)
	if _operating and _emotion_left <= 0.0:
		_operate_t += delta
		var raised := int(_operate_t / 0.16) % 2 == 1
		_apply_ip_tex(TEX_IP_OPERATE_UP if raised else TEX_IP_OPERATE)
	_t += delta * bob_speed
	_rest.x = clampf(_rest.x + _move_axis * move_speed * delta, min_x, max_x)
	position = _rest + Vector2(sin(_t * 0.45) * 2.2, sin(_t) * bob_amount) + Vector2(0.0, _tide_drop_y)


func _place_hook() -> void:
	if _sprite.texture == null:
		return
	var size := _sprite.texture.get_size() * _sprite.scale
	_sprite.z_as_relative = true
	_sprite.z_index = 2
	var tex_path := _sprite.texture.resource_path
	if tex_path.find("ip_boat") >= 0:
		var half := size * 0.5
		# 绳从船底垂下，不从手上的绞盘伸出
		_pivot.position = Vector2(0.0, half.y * 0.9)
		_bubbles.position = Vector2(-half.x * 0.55, -half.y * 0.35)
	else:
		_pivot.position = Vector2(11.0, size.y * 0.5 - 16.0)
		_bubbles.position = Vector2(-size.x * 0.28, -size.y * 0.08)
