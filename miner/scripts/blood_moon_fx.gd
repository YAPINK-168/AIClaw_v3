extends Node2D
## 血月月盘与三朵红云。钉在长图天空上，不跟船走。

const TEX_MOON := preload("res://miner/assets/tide/blood_moon/moon_blood.png")
const TEX_CLOUDS: Array[Texture2D] = [
	preload("res://miner/assets/tide/blood_moon/cloud_blood_01.png"),
	preload("res://miner/assets/tide/blood_moon/cloud_blood_02.png"),
	preload("res://miner/assets/tide/blood_moon/cloud_blood_03.png"),
]

var _sprites: Array[Sprite2D] = []


func _ready() -> void:
	z_as_relative = true
	z_index = 4
	_add_cloud(TEX_CLOUDS[1], -460.0, 58.0, 72.0, 0)
	_add_cloud(TEX_CLOUDS[2], 470.0, 64.0, 68.0, 0)
	_add_cloud(TEX_CLOUDS[0], -40.0, 42.0, 86.0, 1)
	var moon := _add_sprite(TEX_MOON, 210.0, 68.0, 128.0, 2)
	moon.z_index = 2
	modulate.a = 0.0


func place_on_map(world_w: float) -> void:
	var mid := world_w * 0.5
	for sprite in _sprites:
		sprite.position.x = mid + float(sprite.get_meta("ox"))


func set_reveal(reveal: float) -> void:
	modulate.a = clampf(reveal, 0.0, 1.0)


func _add_cloud(tex: Texture2D, ox: float, y: float, target_h: float, z: int) -> void:
	_add_sprite(tex, ox, y, target_h, z)


func _add_sprite(tex: Texture2D, ox: float, y: float, target_h: float, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.z_as_relative = true
	sprite.z_index = z
	var tex_h := tex.get_height()
	var s := target_h / maxf(float(tex_h), 1.0)
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(ox, y)
	sprite.set_meta("ox", ox)
	add_child(sprite)
	_sprites.append(sprite)
	return sprite
