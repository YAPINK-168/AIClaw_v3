class_name Collectible
extends Area2D

enum Kind { COIN, COIN_PILE, PEARL, SHELL, GEM, CHEST, NUGGET, POT, WELL, BARREL, ROCK, FISH, MYSTERY }

## 鱼贴图默认朝左；往右游时由 _update_fish_flip 做 flip_h 镜像
const FISH_TEX: Array[Texture2D] = [
	preload("res://miner/assets/fish_01.png"),
	preload("res://miner/assets/fish_02.png"),
	preload("res://miner/assets/fish_03.png"),
	preload("res://miner/assets/fish_04.png"),
	preload("res://miner/assets/fish_05.png"),
	preload("res://miner/assets/fish_06.png"),
	preload("res://miner/assets/fish_07.png"),
	preload("res://miner/assets/fish_08.png"),
	preload("res://miner/assets/fish_09.png"),
	preload("res://miner/assets/fish_10.png"),
]

## 贝壳 / 珍珠新美术：局内随机抽一张
const SHELL_TEX: Array[Texture2D] = [
	preload("res://miner/assets/shell_variants/shell_01.png"),
	preload("res://miner/assets/shell_variants/shell_02.png"),
	preload("res://miner/assets/shell_variants/shell_03.png"),
]
const PEARL_TEX: Array[Texture2D] = [
	preload("res://miner/assets/shell_pearl_variants/pearl_01.png"),
]
const BARREL_TEX: Array[Texture2D] = [
	preload("res://miner/assets/barrel_variants/barrel_01.png"),
	preload("res://miner/assets/barrel_variants/barrel_02.png"),
]
const MYSTERY_TEX: Array[Texture2D] = [
	preload("res://miner/assets/mystery_variants/mystery_01.png"),
	preload("res://miner/assets/mystery_variants/mystery_02.png"),
	preload("res://miner/assets/mystery_variants/mystery_03.png"),
]
const CHEST_TEX: Array[Texture2D] = [
	preload("res://miner/assets/chest_variants/chest_01.png"),
	preload("res://miner/assets/chest_variants/chest_02.png"),
	preload("res://miner/assets/chest_variants/chest_03.png"),
]
const WELL_TEX: Array[Texture2D] = [
	preload("res://miner/assets/well_variants/well_01.png"),
]
const GEM_TEX: Array[Texture2D] = [
	preload("res://miner/assets/gem_variants/gem_01.png"),
]
const ROCK_TEX: Array[Texture2D] = [
	preload("res://miner/assets/rock_variants/rock_01.png"),
	preload("res://miner/assets/rock_variants/rock_02.png"),
	preload("res://miner/assets/rock_variants/rock_03.png"),
	preload("res://miner/assets/rock_variants/rock_04.png"),
]

@export var kind: Kind = Kind.COIN

var value: int = 50
var mass: float = 1.0
var grabbed: bool = false
var tide_locked: bool = false
var fish_index: int = 0
var nuisance: bool = false
var origin_global: Vector2 = Vector2.ZERO

var _bob_t: float = 0.0
var _base_pos: Vector2 = Vector2.ZERO
var _swim_dir: float = 1.0
var _swim_speed: float = 55.0
var _min_x: float = 70.0
var _max_x: float = 1210.0
var _min_y: float = 188.0
var _max_y: float = 388.0
var _wander: bool = false
var _vel: Vector2 = Vector2.ZERO
var _turn_left: float = 0.0
var _fish_mat: ShaderMaterial
var _mystery_mat: ShaderMaterial
var _wag_amp_base: float = 0.016
var _time_since_turn: float = 0.0
var _wag_rest_left: float = 0.0
var _wag_straight_limit: float = 3.5

const FISH_TAIL_SHADER := preload("res://miner/shaders/fish_tail_wag.gdshader")
const MYSTERY_GLOW_SHADER := preload("res://miner/shaders/mystery_glow.gdshader")
## 海床打捞物视觉与碰撞缩放（与 claw.gd CLAW_VISUAL_SCALE 可分开调）
const PROP_VISUAL_SCALE := 0.56

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("collectibles")
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_bob_t = randf() * TAU
	_apply_kind()
	_base_pos = position


func setup(p_kind: Kind, p_pos: Vector2) -> void:
	kind = p_kind
	position = p_pos
	_base_pos = p_pos
	if is_inside_tree():
		origin_global = global_position
		_apply_kind()


func configure_swim_bounds(min_x: float, max_x: float, min_y: float, max_y: float) -> void:
	_min_x = min_x
	_max_x = max_x
	_min_y = min_y
	_max_y = max_y


func setup_fish(p_index: int, p_pos: Vector2, p_dir: float, p_speed: float) -> void:
	fish_index = clampi(p_index, 0, FISH_TEX.size() - 1)
	_swim_dir = 1.0 if p_dir >= 0.0 else -1.0
	_swim_speed = p_speed
	setup(Kind.FISH, p_pos)


func setup_nuisance_fish(p_index: int, p_pos: Vector2, p_dir: float, p_speed: float, p_value: int = 20) -> void:
	nuisance = true
	setup_fish(p_index, p_pos, p_dir, p_speed)
	value = p_value
	mass = 0.35
	_wander = true
	if is_node_ready():
		_pick_wander_vel()
		_turn_left = randf_range(0.5, 1.3)
	add_to_group("nuisance_fish")


func begin_tide_slide() -> void:
	tide_locked = true
	monitorable = false


func end_tide_slide() -> void:
	tide_locked = false
	monitorable = true
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	_base_pos = position


func _process(delta: float) -> void:
	if grabbed or tide_locked:
		return
	if kind == Kind.FISH:
		_bob_t += delta * (1.8 if _wander else 2.1)
		if _wander:
			_wander_swim(delta)
		else:
			var prev_dir := _swim_dir
			_base_pos.x += _swim_dir * _swim_speed * delta
			if _base_pos.x <= _min_x:
				_base_pos.x = _min_x
				_swim_dir = 1.0
			elif _base_pos.x >= _max_x:
				_base_pos.x = _max_x
				_swim_dir = -1.0
			if _swim_dir != prev_dir:
				_note_fish_turn()
			_update_fish_flip()
			position = _base_pos + Vector2(0.0, sin(_bob_t) * 5.5)
		_tick_fish_tail_wag(delta)
		_update_fish_tail_wag()
		return
	_bob_t += delta * 1.5
	position = _base_pos + Vector2(0.0, sin(_bob_t) * 3.0)


func _prop_s(visual_scale: float) -> float:
	return visual_scale * PROP_VISUAL_SCALE


func _prop_r(radius: float) -> float:
	return radius * PROP_VISUAL_SCALE


static func placement_radius(p_kind: Kind) -> float:
	## 生成避让半径（按新贴图视觉占位略放大，避免贴在一起）
	var base: float
	match p_kind:
		Kind.COIN:
			base = 20.0
		Kind.COIN_PILE:
			base = 34.0
		Kind.PEARL:
			base = 36.0
		Kind.SHELL:
			base = 30.0
		Kind.GEM:
			base = 22.0
		Kind.CHEST:
			base = 42.0
		Kind.NUGGET:
			base = 30.0
		Kind.POT:
			base = 34.0
		Kind.WELL:
			base = 36.0
		Kind.BARREL:
			base = 40.0
		Kind.ROCK:
			base = 30.0
		Kind.MYSTERY:
			base = 34.0
		_:
			base = 28.0
	return base * PROP_VISUAL_SCALE


func _apply_kind() -> void:
	if _sprite == null:
		return
	if kind != Kind.FISH and kind != Kind.MYSTERY:
		_sprite.material = null
		_fish_mat = null
		_mystery_mat = null
	var circle := CircleShape2D.new()
	match kind:
		Kind.COIN:
			_sprite.texture = preload("res://miner/assets/coin.png")
			## 新图约 512px（旧约 76px），缩到接近旧金币屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.11)
			value = 50
			mass = 0.55
			circle.radius = _prop_r(14.0)
		Kind.COIN_PILE:
			_sprite.texture = preload("res://miner/assets/coin_pile.png")
			## 新图约 512px（旧约 172px），缩到接近旧金币堆屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.16)
			value = 180
			mass = 1.05
			circle.radius = _prop_r(24.0)
		Kind.PEARL:
			_sprite.texture = PEARL_TEX[randi() % PEARL_TEX.size()]
			## 新图约 512px，缩到接近旧珍珠屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.16)
			value = 300
			mass = 0.85
			circle.radius = _prop_r(22.0)
		Kind.SHELL:
			_sprite.texture = SHELL_TEX[randi() % SHELL_TEX.size()]
			_sprite.scale = Vector2.ONE * _prop_s(0.15)
			value = 120
			mass = 0.75
			circle.radius = _prop_r(20.0)
		Kind.GEM:
			_sprite.texture = GEM_TEX[randi() % GEM_TEX.size()]
			## 新图约 512px（旧约 128px），按原透明通道替换，不抠黑
			_sprite.scale = Vector2.ONE * _prop_s(0.15)
			value = 250
			mass = 0.72
			circle.radius = _prop_r(17.0)
		Kind.CHEST:
			_sprite.texture = CHEST_TEX[randi() % CHEST_TEX.size()]
			## 新图约 512px（旧约 212px），缩到接近旧宝箱屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.17)
			value = 500
			mass = 2.5
			circle.radius = _prop_r(32.0)
		Kind.NUGGET:
			_sprite.texture = preload("res://miner/assets/nugget.png")
			_sprite.scale = Vector2.ONE * _prop_s(0.55)
			value = 400
			mass = 1.7
			circle.radius = _prop_r(26.0)
		Kind.POT:
			_sprite.texture = preload("res://miner/assets/pot.png")
			_sprite.scale = Vector2.ONE * _prop_s(0.52)
			value = 80
			mass = 2.1
			circle.radius = _prop_r(28.0)
		Kind.WELL:
			_sprite.texture = WELL_TEX[randi() % WELL_TEX.size()]
			## 新图约 512px（旧约 145px），缩到接近旧井屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.16)
			value = 60
			mass = 2.6
			circle.radius = _prop_r(26.0)
		Kind.BARREL:
			_sprite.texture = BARREL_TEX[randi() % BARREL_TEX.size()]
			## 新图约 512px，缩到接近旧木桶屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.18)
			value = 90
			mass = 2.9
			circle.radius = _prop_r(32.0)
		Kind.ROCK:
			_sprite.texture = ROCK_TEX[randi() % ROCK_TEX.size()]
			## 新图约 512px，保留原透明通道，局内随机抽
			_sprite.scale = Vector2.ONE * _prop_s(0.17)
			value = 20
			mass = 2.3
			circle.radius = _prop_r(26.0)
		Kind.MYSTERY:
			_sprite.texture = MYSTERY_TEX[randi() % MYSTERY_TEX.size()]
			## 新图约 512px（旧图约 717px），略放大以保持屏上尺寸
			_sprite.scale = Vector2.ONE * _prop_s(0.15)
			value = 0
			mass = 1.25
			circle.radius = _prop_r(22.0)
			_apply_mystery_glow()
		Kind.FISH:
			_apply_fish(circle)
	_collision.shape = circle


func _apply_mystery_glow() -> void:
	if _mystery_mat == null:
		_mystery_mat = ShaderMaterial.new()
		_mystery_mat.shader = MYSTERY_GLOW_SHADER
	_sprite.material = _mystery_mat


func _apply_fish(circle: CircleShape2D) -> void:
	_sprite.texture = FISH_TEX[fish_index]
	## 新图约 512px；x=视觉缩放、y=碰撞半径（相对旧鱼屏上尺寸）
	var sizes: Array[Vector2] = [
		Vector2(0.13, 18.0),
		Vector2(0.14, 16.0),
		Vector2(0.12, 20.0),
		Vector2(0.15, 16.0),
		Vector2(0.13, 20.0),
		Vector2(0.13, 20.0),
		Vector2(0.12, 20.0),
		Vector2(0.12, 22.0),
		Vector2(0.13, 18.0),
		Vector2(0.14, 20.0),
	]
	var values: Array[int] = [90, 110, 140, 80, 160, 180, 150, 200, 120, 170]
	var masses: Array[float] = [0.50, 0.45, 0.55, 0.40, 0.52, 0.58, 0.54, 0.62, 0.48, 0.56]
	var spec: Vector2 = sizes[fish_index]
	_sprite.scale = Vector2.ONE * _prop_s(spec.x)
	circle.radius = _prop_r(spec.y)
	value = values[fish_index]
	mass = masses[fish_index]
	z_as_relative = true
	z_index = 2
	var ranked: Array[int] = values.duplicate()
	ranked.sort()
	_wander = value >= ranked[ranked.size() - 3]
	if _wander:
		_pick_wander_vel()
		_turn_left = randf_range(1.8, 3.4)
	_wag_straight_limit = randf_range(2.6, 4.8)
	_time_since_turn = randf_range(0.0, 1.2)
	_wag_rest_left = 0.0
	_setup_fish_tail_shader()
	_update_fish_flip()


func _setup_fish_tail_shader() -> void:
	if _fish_mat == null:
		_fish_mat = ShaderMaterial.new()
		_fish_mat.shader = FISH_TAIL_SHADER
	_sprite.material = _fish_mat
	_wag_amp_base = 0.013 + float(fish_index % 3) * 0.0025
	_fish_mat.set_shader_parameter("wag_speed", 6.4 + float(fish_index) * 0.45)
	_fish_mat.set_shader_parameter("tail_start", 0.40 + float(fish_index % 4) * 0.02)
	_update_fish_tail_wag()


func _note_fish_turn() -> void:
	_time_since_turn = 0.0
	_wag_rest_left = 0.0


func _tick_fish_tail_wag(delta: float) -> void:
	if _wag_rest_left > 0.0:
		_wag_rest_left -= delta
		return
	_time_since_turn += delta
	if _time_since_turn >= _wag_straight_limit:
		_wag_rest_left = randf_range(0.8, 2.0)
		_time_since_turn = 0.0


func _update_fish_tail_wag() -> void:
	if _fish_mat == null:
		return
	var amp := 0.0 if _wag_rest_left > 0.0 else _wag_amp_base
	_fish_mat.set_shader_parameter("wag_amp", amp)
	_fish_mat.set_shader_parameter("phase", _bob_t * TAU)


func _wander_swim(delta: float) -> void:
	_turn_left -= delta
	if _turn_left <= 0.0:
		_pick_wander_vel()
		_turn_left = randf_range(2.2, 4.8)
		_note_fish_turn()
	_base_pos += _vel * delta
	if _base_pos.x <= _min_x:
		_base_pos.x = _min_x
		if _vel.x < 0.0:
			_note_fish_turn()
		_vel.x = absf(_vel.x)
	elif _base_pos.x >= _max_x:
		_base_pos.x = _max_x
		if _vel.x > 0.0:
			_note_fish_turn()
		_vel.x = -absf(_vel.x)
	if _base_pos.y <= _min_y:
		_base_pos.y = _min_y
		if _vel.y < 0.0:
			_note_fish_turn()
		_vel.y = absf(_vel.y)
	elif _base_pos.y >= _max_y:
		_base_pos.y = _max_y
		if _vel.y > 0.0:
			_note_fish_turn()
		_vel.y = -absf(_vel.y)
	if absf(_vel.x) < 8.0:
		_vel.x = _swim_dir * maxf(_swim_speed * 0.45, 24.0)
	_swim_dir = 1.0 if _vel.x >= 0.0 else -1.0
	_update_fish_flip()
	_face_velocity(delta)
	position = _base_pos + Vector2(0.0, sin(_bob_t) * 3.0)


func _pick_wander_vel() -> void:
	var hx := -1.0 if randf() < 0.5 else 1.0
	if absf(_vel.x) > 1.0 and randf() < 0.4:
		hx = signf(_vel.x)
	var slopes: Array[float] = [-0.95, -0.65, -0.35, 0.0, 0.0, 0.35, 0.65, 0.95]
	var hy: float = slopes[randi() % slopes.size()]
	var dir := Vector2(hx, hy)
	if dir.length() < 0.15:
		dir = Vector2(hx, 0.0)
	_vel = dir.normalized() * (_swim_speed * randf_range(0.8, 1.28))


func _update_fish_flip() -> void:
	if _sprite == null:
		return
	## 贴图朝左：dir>0（往右）时镜像翻转
	_sprite.flip_h = _swim_dir > 0.0
	if not _wander:
		_sprite.rotation = 0.0


func _face_velocity(delta: float) -> void:
	if _sprite == null or _vel.length() < 1.0:
		return
	var target := _vel.angle()
	if _vel.x < 0.0:
		target += PI
	_sprite.rotation = lerp_angle(_sprite.rotation, target, clampf(delta * 7.0, 0.0, 1.0))


func freeze_for_grab() -> void:
	if _fish_mat:
		_fish_mat.set_shader_parameter("wag_amp", 0.0)
	if _sprite:
		_sprite.rotation = 0.0
