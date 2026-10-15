extends Node2D

const TEX := preload("res://miner/assets/bubble.png")

const SPOTS: Array[Vector2] = [
	Vector2(86.0, 548.0),
	Vector2(448.0, 508.0),
	Vector2(848.0, 538.0),
	Vector2(1108.0, 652.0),
	Vector2(1246.0, 562.0),
	Vector2(1520.0, 528.0),
	Vector2(1880.0, 558.0),
	Vector2(2160.0, 642.0),
]

var _vents: Array[Dictionary] = []


func _ready() -> void:
	z_as_relative = true
	z_index = 0
	for i in SPOTS.size():
		_vents.append(_make_vent(SPOTS[i], i))


func _process(delta: float) -> void:
	for vent in _vents:
		vent["wait"] = float(vent["wait"]) - delta
		if float(vent["wait"]) > 0.0:
			continue
		_start_burst(vent)


func _make_vent(pos: Vector2, seed_i: int) -> Dictionary:
	var fx := CPUParticles2D.new()
	fx.position = pos + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
	fx.texture = TEX
	fx.one_shot = true
	fx.explosiveness = 0.82
	fx.randomness = 0.28
	fx.local_coords = false
	fx.emitting = false
	fx.direction = Vector2(0.0, -1.0)
	fx.spread = 10.0
	fx.gravity = Vector2(0.0, -6.0)
	fx.initial_velocity_min = 62.0
	fx.initial_velocity_max = 86.0
	fx.linear_accel_min = 0.0
	fx.linear_accel_max = 4.0
	fx.tangential_accel_min = -6.0
	fx.tangential_accel_max = 6.0
	fx.damping_min = 0.0
	fx.damping_max = 1.4
	fx.scale_amount_min = 0.42
	fx.scale_amount_max = 0.95
	fx.color = Color(1.0, 1.0, 1.0, 0.39)
	add_child(fx)
	return {
		"fx": fx,
		"wait": 0.4 + float(seed_i) * 0.85 + randf() * 1.6,
	}


func _start_burst(vent: Dictionary) -> void:
	var fx := vent["fx"] as CPUParticles2D
	fx.amount = randi_range(3, 6)
	var rise := fx.position.y + 80.0
	fx.lifetime = clampf(rise / 68.0, 6.0, 12.5)
	fx.restart()
	fx.emitting = true
	vent["wait"] = randf_range(2.8, 6.4)
