class_name BombDetonate
extends CanvasLayer

signal finished

const BOMB_TEX := preload("res://miner/assets/bomb.png")
const TEX_FLASH := preload("res://miner/assets/vfx/flash.png")
const TEX_FLASH_CORE := preload("res://miner/assets/vfx/flash_core.png")
const TEX_STAR := preload("res://miner/assets/vfx/star_burst.png")
const TEX_FLARE := preload("res://miner/assets/vfx/flare.png")
const TEX_GLOW := preload("res://miner/assets/vfx/glow_ring.png")
const TEX_SPARKLE := preload("res://miner/assets/vfx/sparkle.png")
const TEX_MAGIC := preload("res://miner/assets/vfx/magic.png")
const SFX_BOOM := preload("res://miner/assets/audio/bomb_explode.mp3")

const BASE_SCALE := 0.145
const PULSE_COUNT := 4

var _root: Node2D
var _bomb: Sprite2D
var _flash: Sprite2D
var _flash_core: Sprite2D
var _star: Sprite2D
var _flare: Sprite2D
var _ring: Sprite2D
var _burst: CPUParticles2D
var _sparks: CPUParticles2D
var _done: bool = false
var _add: CanvasItemMaterial


func play_at(world_pos: Vector2) -> void:
	add_to_group("bomb_detonate")
	layer = 80
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_root = Node2D.new()
	add_child(_root)
	_root.global_position = world_pos
	_build()
	await _run()
	_finish()


func _build() -> void:
	_ring = _fx_sprite(TEX_GLOW, Color(1.0, 0.45, 0.18, 0.0), Vector2(0.45, 0.45))
	_star = _fx_sprite(TEX_STAR, Color(1.0, 0.7, 0.28, 0.0), Vector2(0.4, 0.4))
	_flare = _fx_sprite(TEX_FLARE, Color(1.0, 0.55, 0.2, 0.0), Vector2(0.55, 0.55))
	_flash = _fx_sprite(TEX_FLASH, Color(1.0, 0.85, 0.45, 0.0), Vector2(0.2, 0.2))
	_flash_core = _fx_sprite(TEX_FLASH_CORE, Color(1.0, 0.95, 0.7, 0.0), Vector2(0.12, 0.12))

	_bomb = Sprite2D.new()
	_bomb.texture = BOMB_TEX
	_bomb.centered = true
	_bomb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bomb.scale = Vector2.ONE * BASE_SCALE
	_root.add_child(_bomb)

	_sparks = _make_particles(TEX_SPARKLE, 22, 0.55, 40.0, 120.0, 0.05, 0.12)
	_sparks.color = Color(1.0, 0.55, 0.2)
	_sparks.emitting = true
	_root.add_child(_sparks)
	_burst = _make_particles(TEX_MAGIC, 56, 0.7, 180.0, 420.0, 0.08, 0.24)
	_burst.color = Color(1.0, 0.5, 0.18)
	_burst.explosiveness = 1.0
	_burst.one_shot = true
	_burst.emitting = false
	_root.add_child(_burst)


func _fx_sprite(tex: Texture2D, modulate: Color, sc: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.material = _add
	s.modulate = modulate
	s.scale = sc
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_root.add_child(s)
	return s


func _run() -> void:
	for _i in PULSE_COUNT:
		await _tween_bomb(Vector2.ONE * (BASE_SCALE * 1.28), Color(1.85, 1.35, 0.85), 0.18)
		await _tween_bomb(Vector2.ONE * (BASE_SCALE * 0.9), Color.WHITE, 0.18)
	await _explode()


func _tween_bomb(to_scale: Vector2, to_mod: Color, duration: float) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(_bomb, "scale", to_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bomb, "modulate", to_mod, duration)
	await tw.finished


func _explode() -> void:
	_sparks.emitting = false
	_burst.emitting = true
	var sfx := AudioStreamPlayer.new()
	sfx.stream = SFX_BOOM
	add_child(sfx)
	sfx.play()
	var boom := create_tween()
	boom.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	boom.set_parallel(true)
	boom.tween_property(_bomb, "scale", Vector2.ONE * (BASE_SCALE * 1.85), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	boom.tween_property(_bomb, "modulate", Color(2.2, 1.6, 0.7), 0.12)
	boom.tween_property(_flash, "modulate:a", 1.0, 0.06)
	boom.tween_property(_flash, "scale", Vector2(2.4, 2.4), 0.28)
	boom.tween_property(_flash_core, "modulate:a", 0.95, 0.05)
	boom.tween_property(_flash_core, "scale", Vector2(1.8, 1.8), 0.22)
	boom.tween_property(_star, "modulate:a", 0.95, 0.08)
	boom.tween_property(_star, "scale", Vector2(2.2, 2.2), 0.3)
	boom.tween_property(_flare, "modulate:a", 0.9, 0.08)
	boom.tween_property(_flare, "scale", Vector2(2.6, 2.6), 0.3)
	boom.tween_property(_ring, "modulate:a", 0.85, 0.08)
	boom.tween_property(_ring, "scale", Vector2(2.8, 2.8), 0.35)
	await boom.finished
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.set_parallel(true)
	fade.tween_property(_bomb, "modulate:a", 0.0, 0.2)
	fade.tween_property(_flash, "modulate:a", 0.0, 0.4)
	fade.tween_property(_flash_core, "modulate:a", 0.0, 0.32)
	fade.tween_property(_star, "modulate:a", 0.0, 0.32)
	fade.tween_property(_flare, "modulate:a", 0.0, 0.32)
	fade.tween_property(_ring, "modulate:a", 0.0, 0.36)
	await fade.finished
	await get_tree().create_timer(0.12, true, false, true).timeout


func _make_particles(tex: Texture2D, amount: int, life: float, vmin: float, vmax: float, smin: float, smax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 80)
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.damping_min = 16.0
	p.damping_max = 60.0
	return p


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
