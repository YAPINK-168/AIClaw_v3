class_name MysteryReveal
extends Node2D

signal finished(loot: MysteryLoot)

# Kenney Particle Pack + Smoke Particles (CC0, kenney.nl)
const BOX_TEX := preload("res://miner/assets/mystery_box.png")
const TEX_STAR := preload("res://miner/assets/vfx/star_burst.png")
const TEX_FLARE := preload("res://miner/assets/vfx/flare.png")
const TEX_SPARKLE := preload("res://miner/assets/vfx/sparkle.png")
const TEX_MAGIC := preload("res://miner/assets/vfx/magic.png")
const TEX_RAY := preload("res://miner/assets/vfx/ray.png")
const TEX_GLOW := preload("res://miner/assets/vfx/glow_ring.png")
const TEX_FLASH := preload("res://miner/assets/vfx/flash.png")
const TEX_FLASH_CORE := preload("res://miner/assets/vfx/flash_core.png")
const GLOW_SHADER := preload("res://miner/shaders/mystery_glow.gdshader")
const SFX_SHAKE := preload("res://miner/assets/audio/bag_shake.ogg")

var loot: MysteryLoot

var _root: Node2D
var _box: Sprite2D
var _glow: Sprite2D
var _star: Sprite2D
var _flare: Sprite2D
var _flare2: Sprite2D
var _ring: Sprite2D
var _flash: Sprite2D
var _flash_core: Sprite2D
var _sparkles: CPUParticles2D
var _burst: CPUParticles2D
var _base_scale: Vector2 = Vector2.ONE * 0.13
var _awarded: bool = false
var _add: CanvasItemMaterial


func play(tex: Texture2D, start_scale: Vector2, p_loot: MysteryLoot) -> void:
	loot = p_loot
	_base_scale = start_scale
	add_to_group("mystery_reveal")
	z_as_relative = false
	z_index = 80
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_build(tex if tex else BOX_TEX)
	_root.scale = _base_scale
	_run()


func _build(tex: Texture2D) -> void:
	_ring = _fx_sprite(TEX_GLOW, Color(1.0, 0.82, 0.35, 0.0), Vector2(0.35, 0.35))
	_star = _fx_sprite(TEX_STAR, Color(1.0, 0.88, 0.4, 0.0), Vector2(0.55, 0.55))
	_flare = _fx_sprite(TEX_FLARE, Color(1.0, 0.92, 0.55, 0.0), Vector2(0.9, 0.9))
	_flare2 = _fx_sprite(TEX_FLARE, Color(1.0, 0.78, 0.4, 0.0), Vector2(0.7, 0.7))
	_flare2.rotation = PI * 0.5
	_flash = _fx_sprite(TEX_FLASH, Color(1.0, 0.92, 0.55, 0.0), Vector2(0.15, 0.15))
	_flash_core = _fx_sprite(TEX_FLASH_CORE, Color(1.0, 0.95, 0.7, 0.0), Vector2(0.08, 0.08))

	_root = Node2D.new()
	add_child(_root)
	_glow = Sprite2D.new()
	_glow.texture = tex
	_glow.centered = true
	_glow.material = _add
	_glow.modulate = Color(1.0, 0.9, 0.45, 0.0)
	_glow.scale = Vector2(1.1, 1.1)
	_root.add_child(_glow)
	_box = Sprite2D.new()
	_box.texture = tex
	_box.centered = true
	_box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = GLOW_SHADER
	_box.material = glow_mat
	_root.add_child(_box)

	_sparkles = _make_particles(TEX_SPARKLE, 28, 0.7, 40.0, 110.0, 0.07, 0.16)
	_sparkles.emitting = false
	add_child(_sparkles)
	_burst = _make_particles(TEX_MAGIC, 42, 0.65, 160.0, 340.0, 0.08, 0.22)
	_burst.explosiveness = 1.0
	_burst.one_shot = true
	_burst.emitting = false
	add_child(_burst)


func _fx_sprite(tex: Texture2D, modulate: Color, sc: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.material = _add
	s.modulate = modulate
	s.scale = sc
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(s)
	return s


func _run() -> void:
	var spin := create_tween()
	spin.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	spin.set_loops()
	spin.tween_property(_star, "rotation", TAU, 2.6).from(0.0)
	var spin2 := create_tween()
	spin2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	spin2.set_loops()
	spin2.tween_property(_flare, "rotation", -TAU, 3.4).from(0.0)

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_root, "scale", _base_scale * 1.5, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_shake)


func _shake() -> void:
	var sfx := AudioStreamPlayer.new()
	sfx.stream = SFX_SHAKE
	add_child(sfx)
	sfx.play()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var amp := 16.0
	var rot := 0.22
	for i in 5:
		var side := 1.0 if i % 2 == 0 else -1.0
		tw.tween_property(_root, "rotation", rot * side, 0.065).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(_root, "position", Vector2(amp * side, -amp * 0.25), 0.065)
		amp *= 0.78
		rot *= 0.82
	tw.tween_property(_root, "rotation", 0.0, 0.08)
	tw.parallel().tween_property(_root, "position", Vector2.ZERO, 0.08)
	tw.tween_callback(_glow_up)


func _glow_up() -> void:
	_sparkles.emitting = true
	_spawn_rays()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(_box, "modulate", Color(2.2, 2.05, 1.55), 0.48)
	tw.tween_property(_glow, "modulate:a", 0.7, 0.48)
	tw.tween_property(_star, "modulate:a", 0.95, 0.4)
	tw.tween_property(_star, "scale", Vector2(1.35, 1.35), 0.5)
	tw.tween_property(_flare, "modulate:a", 0.9, 0.4)
	tw.tween_property(_flare, "scale", Vector2(1.55, 1.55), 0.5)
	tw.tween_property(_flare2, "modulate:a", 0.55, 0.45)
	tw.tween_property(_ring, "modulate:a", 0.7, 0.45)
	tw.tween_property(_ring, "scale", Vector2(1.15, 1.15), 0.5)
	tw.chain().tween_callback(_explode)


func _explode() -> void:
	_sparkles.emitting = false
	_burst.emitting = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.tween_property(_flash, "modulate:a", 0.95, 0.08)
	tw.tween_property(_flash, "scale", Vector2(1.35, 1.35), 0.28)
	tw.tween_property(_flash_core, "modulate:a", 0.85, 0.06)
	tw.tween_property(_flash_core, "scale", Vector2(1.1, 1.1), 0.22)
	tw.tween_property(_star, "scale", Vector2(2.1, 2.1), 0.28)
	tw.tween_property(_flare, "scale", Vector2(2.4, 2.4), 0.28)
	tw.tween_property(_ring, "scale", Vector2(2.6, 2.6), 0.35)
	tw.tween_property(_root, "scale", _base_scale * 2.05, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_box, "modulate:a", 0.0, 0.18)
	tw.tween_property(_glow, "modulate:a", 0.0, 0.18)
	tw.chain()
	tw.set_parallel(true)
	tw.tween_property(_flash, "modulate:a", 0.0, 0.38)
	tw.tween_property(_flash_core, "modulate:a", 0.0, 0.32)
	tw.tween_property(_star, "modulate:a", 0.0, 0.32)
	tw.tween_property(_flare, "modulate:a", 0.0, 0.32)
	tw.tween_property(_flare2, "modulate:a", 0.0, 0.28)
	tw.tween_property(_ring, "modulate:a", 0.0, 0.35)
	tw.chain()
	tw.set_parallel(false)
	tw.tween_interval(0.18)
	tw.tween_callback(_finish)


func _spawn_rays() -> void:
	var count := 12
	for i in count:
		var pivot := Node2D.new()
		pivot.rotation = TAU * float(i) / float(count) + randf_range(-0.06, 0.06)
		add_child(pivot)
		var beam := Sprite2D.new()
		beam.texture = TEX_RAY
		beam.centered = true
		beam.rotation = -PI * 0.5
		beam.position = Vector2(28, 0)
		beam.scale = Vector2(0.12, 0.06)
		beam.modulate = Color(1.0, 0.9, 0.45, 0.0)
		beam.material = _add
		beam.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pivot.add_child(beam)
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.set_parallel(true)
		tw.tween_property(beam, "modulate:a", 0.95, 0.16).set_delay(0.28)
		tw.tween_property(beam, "position:x", 150.0 + randf_range(-12, 36), 0.5).set_delay(0.28)
		tw.tween_property(beam, "scale", Vector2(0.72 + randf() * 0.2, 0.22), 0.5).set_delay(0.28)
		tw.chain().tween_property(beam, "modulate:a", 0.0, 0.32)


func _make_particles(tex: Texture2D, amount: int, life: float, vmin: float, vmax: float, smin: float, smax: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 40)
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	p.color = Color(1.0, 0.9, 0.55)
	p.hue_variation_min = -0.15
	p.hue_variation_max = 0.2
	p.damping_min = 20.0
	p.damping_max = 70.0
	return p


func _finish() -> void:
	if _awarded:
		return
	_awarded = true
	finished.emit(loot)
	queue_free()
