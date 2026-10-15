extends CanvasLayer

signal restart_pressed

const MUD_SHADER := preload("res://miner/shaders/screen_mud.gdshader")
const WARP_SHADER := preload("res://miner/shaders/screen_warp.gdshader")
const BUBBLE_TEX := preload("res://miner/assets/bubble.png")
const TEX_MUD_BLOB := preload("res://miner/assets/ui/mud_blob.png")
const TEX_BLOOD_BANNER := preload("res://miner/assets/ui/tide/banner_blood_moon.png")
const TEX_BLOOD_ICON := preload("res://miner/assets/ui/tide/icon_rare_blood_moon.png")
const SFX_SETTLE_LOOP := preload("res://miner/assets/audio/settle_bubbles.ogg")
const SFX_SETTLE_BURST := preload("res://miner/assets/audio/swarm.mp3")

const SCORE_PPS := 88.0
const FONT_FILL := Color("#FFD029")
const FONT_STROKE := Color("#784218")
const FONT_OUTLINE := 8
const FONT_TIME := Color("#FFFFFF")
const FONT_ALERT := Color(1.0, 0.42, 0.32)
const SETTLE_EMIT_SECS := 1.05
const SETTLE_REVEAL_AT := 0.72
const SETTLE_DRAIN_SECS := 3.4
const SETTLE_LOOP_VOL := [-9.0, -5.0, -10.5]
const SETTLE_BURST_VOL := -2.5
const _TIME_HUD_SCRIPT := preload("res://miner/scripts/miner_time_hud.gd")
const _SCORE_HUD_SCRIPT := preload("res://miner/scripts/miner_score_hud.gd")

var _time_hud: Control
var _score_hud: Control
@onready var _overlay: Control = $UI/Overlay
@onready var _final: Label = $UI/Overlay/Panel/FinalScore
@onready var _rank: Label = $UI/Overlay/Panel/RankTitle
@onready var _rank_desc: Label = $UI/Overlay/Panel/RankDesc
@onready var _restart: Button = $UI/Overlay/Panel/RestartButton

var _order_hud: MinerOrderHud

var _mud: ColorRect
var _mud_blobs: Control
var _warp: ColorRect
var _banner_root: Control
var _blood_plate: TextureRect
var _blood_icon: TextureRect
var _banner: Label
var _settle_block: ColorRect
var _settle_fx: Node2D
var _settle_emitters: Array[CPUParticles2D] = []
var _mud_mat: ShaderMaterial
var _warp_mat: ShaderMaterial
var _fx_tween: Tween
var _mud_tw: Tween
var _settle_tw: Tween
var _settle_sfx_tw: Tween
var _settle_loops: Array[AudioStreamPlayer] = []
var _settle_bursts: Array[AudioStreamPlayer] = []
var _settle_revealed: bool = false
var _shown_score: int = 0
var _target_score: int = 0
var _score_accum: float = 0.0
var _bounce_tw: Tween


func _ready() -> void:
	_restart.pressed.connect(func() -> void: restart_pressed.emit())
	_restart.focus_mode = Control.FOCUS_NONE
	_overlay.visible = false
	_install_score_hud()
	_install_time_hud()
	_order_hud = MinerOrderHud.new()
	_order_hud.name = "OrderHud"
	$UI.add_child(_order_hud)
	$UI.move_child(_order_hud, 1)
	_build_fx()
	get_viewport().size_changed.connect(_layout_settle_emitters)
	set_process(false)


func _build_fx() -> void:
	_warp_mat = ShaderMaterial.new()
	_warp_mat.shader = WARP_SHADER
	_warp = _make_fx_rect(_warp_mat)
	_mud_mat = ShaderMaterial.new()
	_mud_mat.shader = MUD_SHADER
	_mud = _make_fx_rect(_mud_mat)
	_mud_blobs = Control.new()
	_mud_blobs.name = "MudBlobs"
	_mud_blobs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mud_blobs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mud_blobs.visible = false
	$UI.add_child(_mud_blobs)
	_banner_root = Control.new()
	_banner_root.name = "BannerRoot"
	_banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_root.visible = false
	$UI.add_child(_banner_root)
	_blood_plate = _make_banner_tex(TEX_BLOOD_BANNER, -280.0, -148.0, 280.0, 28.0)
	_blood_icon = _make_banner_tex(TEX_BLOOD_ICON, -236.0, -92.0, -164.0, -20.0)
	_blood_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_banner_root.add_child(_blood_plate)
	_banner_root.add_child(_blood_icon)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.5
	_banner.anchor_bottom = 0.5
	_banner.offset_left = -220.0
	_banner.offset_right = 250.0
	_banner.offset_top = -148.0
	_banner.offset_bottom = 28.0
	_banner.add_theme_font_size_override("font_size", 44)
	_style_gold_text(_banner, FONT_OUTLINE)
	_banner_root.add_child(_banner)
	$UI.move_child(_warp, _overlay.get_index())
	$UI.move_child(_mud, _overlay.get_index())
	$UI.move_child(_mud_blobs, _overlay.get_index())
	$UI.move_child(_banner_root, _overlay.get_index())
	_build_settle_bubbles()


func _make_banner_tex(tex: Texture2D, left: float, top: float, right: float, bottom: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 0.5
	rect.anchor_bottom = 0.5
	rect.offset_left = left
	rect.offset_top = top
	rect.offset_right = right
	rect.offset_bottom = bottom
	rect.visible = false
	return rect


func _make_fx_rect(mat: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.visible = false
	rect.color = Color.WHITE
	$UI.add_child(rect)
	return rect


func _install_score_hud() -> void:
	var legacy := $UI.get_node_or_null("ScoreLabel") as Label
	_score_hud = _SCORE_HUD_SCRIPT.new()
	_score_hud.name = "ScoreHud"
	if legacy:
		_score_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_score_hud.offset_left = legacy.offset_left
		_score_hud.offset_top = legacy.offset_top
		_score_hud.offset_right = legacy.offset_right
		_score_hud.offset_bottom = legacy.offset_bottom
		var idx := legacy.get_index()
		legacy.get_parent().add_child(_score_hud)
		legacy.get_parent().move_child(_score_hud, idx)
		legacy.queue_free()
	else:
		_score_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_score_hud.offset_left = 22.0
		_score_hud.offset_top = 6.0
		_score_hud.offset_right = 348.0
		_score_hud.offset_bottom = 60.0
		$UI.add_child(_score_hud)
	# set_value(0) 在 MinerScoreHud._ready 里已调用


func _install_time_hud() -> void:
	var legacy := $UI.get_node_or_null("TimeLabel") as Label
	_time_hud = _TIME_HUD_SCRIPT.new()
	_time_hud.name = "TimeHud"
	if legacy:
		var idx := legacy.get_index()
		legacy.get_parent().add_child(_time_hud)
		legacy.get_parent().move_child(_time_hud, idx)
		legacy.queue_free()
	else:
		$UI.add_child(_time_hud)
	_time_hud.set_value(62)


func _sync_score_display() -> void:
	if _score_hud:
		_score_hud.set_value(_shown_score)


func bind_order(state: MinerOrderState) -> void:
	if _order_hud:
		_order_hud.bind_order(state)
	var hint := get_node_or_null("UI/Hint") as Label
	if hint:
		hint.visible = state == null


func get_order_panel_left() -> float:
	if _order_hud == null:
		return 99999.0
	return _order_hud.get_panel_left()


func set_ebb_bar_ratio(r: float) -> void:
	if _order_hud:
		_order_hud.set_ebb_bar_ratio(r)


func set_score(value: int) -> void:
	var next := maxi(0, value)
	if next <= _shown_score:
		_target_score = next
		_shown_score = next
		_score_accum = 0.0
		_sync_score_display()
		set_process(false)
		return
	var starting := _shown_score == _target_score
	_target_score = next
	if starting:
		_score_accum = 0.0
		_bounce_score()
	set_process(true)


func _process(delta: float) -> void:
	if _shown_score >= _target_score:
		set_process(false)
		return
	_score_accum += SCORE_PPS * delta
	var n := mini(_target_score - _shown_score, int(_score_accum))
	if n <= 0:
		return
	_score_accum -= float(n)
	var bounce := false
	for _i in n:
		_shown_score += 1
		if _shown_score % 100 == 0 or _shown_score == _target_score:
			bounce = true
	_sync_score_display()
	if bounce:
		_bounce_score()
	if _shown_score >= _target_score:
		_score_accum = 0.0
		set_process(false)


func _bounce_score() -> void:
	if _score_hud == null:
		return
	if _bounce_tw:
		_bounce_tw.kill()
	_score_hud.pivot_offset = _score_hud.get_bounce_pivot()
	_score_hud.scale = Vector2.ONE
	_bounce_tw = create_tween()
	_bounce_tw.tween_property(_score_hud, "scale", Vector2(1.22, 1.28), 0.055).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bounce_tw.tween_property(_score_hud, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE)


func set_time(seconds: float) -> void:
	var t := maxi(0, ceili(seconds))
	if _time_hud:
		_time_hud.set_value(t)
		_time_hud.set_urgent(seconds <= 10.0)


func show_game_over(score: int, title: String = "见习探索者", desc: String = "继续探索海底吧", prizes: String = "") -> void:
	_final.text = "本轮收获  %d" % score
	if prizes != "":
		_final.text += "\n%s" % prizes
		_final.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_layout_settle_text(prizes != "")
	if _rank:
		_rank.text = title
	if _rank_desc:
		_rank_desc.text = desc
	_shown_score = score
	_target_score = score
	_score_accum = 0.0
	_sync_score_display()
	if _score_hud:
		_score_hud.scale = Vector2.ONE
	set_process(false)
	_overlay.visible = false
	_play_settle_bubbles()


func can_restart() -> bool:
	return _overlay.visible and (_settle_block == null or not _settle_block.visible)


func _build_settle_bubbles() -> void:
	_settle_block = ColorRect.new()
	_settle_block.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settle_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_settle_block.color = Color(0, 0, 0, 0)
	_settle_block.visible = false
	_settle_block.z_index = 80
	$UI.add_child(_settle_block)
	_settle_fx = Node2D.new()
	_settle_fx.name = "SettleBubbles"
	_settle_fx.z_index = 90
	_settle_fx.visible = false
	add_child(_settle_fx)
	_settle_emitters = [
		_make_rise_particles(1120, 0.85, 1.9, 200.0, 340.0, 0.7, 11),
		_make_rise_particles(2560, 0.38, 1.2, 260.0, 440.0, 0.82, 29),
		_make_rise_particles(2080, 0.16, 0.52, 330.0, 560.0, 0.58, 47),
	]
	_layout_settle_emitters()
	_build_settle_sfx()


func _build_settle_sfx() -> void:
	var loop_stream := SFX_SETTLE_LOOP.duplicate()
	if loop_stream is AudioStreamOggVorbis:
		(loop_stream as AudioStreamOggVorbis).loop = true
	var loop_pitches := [0.78, 1.0, 1.26]
	for i in loop_pitches.size():
		var p := AudioStreamPlayer.new()
		p.name = "SettleLoop%d" % i
		p.stream = loop_stream
		p.pitch_scale = loop_pitches[i]
		p.volume_db = SETTLE_LOOP_VOL[i]
		add_child(p)
		_settle_loops.append(p)
	for i in 3:
		var b := AudioStreamPlayer.new()
		b.name = "SettleBurst%d" % i
		b.stream = SFX_SETTLE_BURST
		b.pitch_scale = 0.86 + float(i) * 0.16
		b.volume_db = SETTLE_BURST_VOL
		add_child(b)
		_settle_bursts.append(b)
	_warm_settle_sfx()


func _warm_settle_sfx() -> void:
	for player in _settle_loops + _settle_bursts:
		var vol := player.volume_db
		player.volume_db = -80.0
		player.play()
		player.stop()
		player.volume_db = vol
		player.seek(0.0)


func _play_settle_sfx() -> void:
	_stop_settle_sfx()
	for i in _settle_loops.size():
		var p := _settle_loops[i]
		p.volume_db = SETTLE_LOOP_VOL[i]
		p.play(randf() * 0.7)
	if _settle_bursts.is_empty():
		return
	_settle_bursts[0].pitch_scale = 0.86
	_settle_bursts[0].volume_db = SETTLE_BURST_VOL
	_settle_bursts[0].play()
	_settle_sfx_tw = create_tween()
	_settle_sfx_tw.tween_interval(0.14)
	_settle_sfx_tw.tween_callback(func() -> void:
		if _settle_bursts.size() > 1:
			_settle_bursts[1].pitch_scale = 1.02
			_settle_bursts[1].volume_db = SETTLE_BURST_VOL
			_settle_bursts[1].play()
	)
	_settle_sfx_tw.tween_interval(0.2)
	_settle_sfx_tw.tween_callback(func() -> void:
		if _settle_bursts.size() > 2:
			_settle_bursts[2].pitch_scale = 1.18
			_settle_bursts[2].volume_db = SETTLE_BURST_VOL
			_settle_bursts[2].play()
	)


func _fade_settle_sfx(secs: float) -> void:
	if _settle_sfx_tw:
		_settle_sfx_tw.kill()
	_settle_sfx_tw = create_tween()
	_settle_sfx_tw.set_parallel(true)
	for p in _settle_loops:
		_settle_sfx_tw.tween_property(p, "volume_db", -80.0, secs)
	for p in _settle_bursts:
		_settle_sfx_tw.tween_property(p, "volume_db", -80.0, minf(secs, 1.1))
	_settle_sfx_tw.chain().tween_callback(_stop_settle_sfx)


func _stop_settle_sfx() -> void:
	if _settle_sfx_tw:
		_settle_sfx_tw.kill()
		_settle_sfx_tw = null
	for p in _settle_loops:
		p.stop()
	for p in _settle_bursts:
		p.stop()


func _make_rise_particles(amount: int, scale_min: float, scale_max: float, vel_min: float, vel_max: float, alpha: float, p_seed: int) -> CPUParticles2D:
	var fx := CPUParticles2D.new()
	fx.texture = BUBBLE_TEX
	fx.amount = amount
	fx.lifetime = 3.8
	fx.preprocess = 0.0
	fx.explosiveness = 0.12
	fx.randomness = 0.72
	fx.lifetime_randomness = 0.06
	fx.use_fixed_seed = true
	fx.seed = p_seed
	fx.one_shot = false
	fx.emitting = false
	fx.local_coords = false
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fx.direction = Vector2(0.0, -1.0)
	fx.spread = 16.0
	fx.gravity = Vector2(0.0, -55.0)
	fx.initial_velocity_min = vel_min
	fx.initial_velocity_max = vel_max
	fx.linear_accel_min = 8.0
	fx.linear_accel_max = 28.0
	fx.tangential_accel_min = -38.0
	fx.tangential_accel_max = 38.0
	fx.damping_min = 0.0
	fx.damping_max = 1.5
	fx.angle_min = -18.0
	fx.angle_max = 18.0
	fx.angular_velocity_min = -50.0
	fx.angular_velocity_max = 50.0
	fx.scale_amount_min = scale_min
	fx.scale_amount_max = scale_max
	fx.color = Color(1.0, 1.0, 1.0, alpha)
	_settle_fx.add_child(fx)
	return fx


func _layout_settle_emitters() -> void:
	var sz := get_viewport().get_visible_rect().size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(1280.0, 720.0)
	if _settle_fx == null:
		return
	for fx in _settle_emitters:
		fx.position = Vector2(sz.x * 0.5, sz.y + 40.0)
		fx.emission_rect_extents = Vector2(sz.x * 0.56, 90.0)


func _play_settle_bubbles() -> void:
	_settle_revealed = false
	_layout_settle_emitters()
	if _settle_block:
		_settle_block.visible = true
		_settle_block.mouse_filter = Control.MOUSE_FILTER_STOP
	if _settle_fx:
		_settle_fx.visible = true
	for fx in _settle_emitters:
		fx.seed = randi()
		fx.emitting = false
		fx.restart()
		fx.emitting = true
	_play_settle_sfx()
	if _settle_tw:
		_settle_tw.kill()
	_settle_tw = create_tween()
	_settle_tw.tween_interval(SETTLE_REVEAL_AT)
	_settle_tw.tween_callback(_reveal_settle_overlay)
	_settle_tw.tween_interval(maxf(0.0, SETTLE_EMIT_SECS - SETTLE_REVEAL_AT))
	_settle_tw.tween_callback(_stop_settle_emit)
	_settle_tw.tween_interval(SETTLE_DRAIN_SECS)
	_settle_tw.tween_callback(_finish_settle_bubbles)


func _stop_settle_emit() -> void:
	for fx in _settle_emitters:
		fx.emitting = false
	_fade_settle_sfx(maxf(0.8, SETTLE_DRAIN_SECS * 0.75))


func _reveal_settle_overlay() -> void:
	if _settle_revealed:
		return
	_settle_revealed = true
	_overlay.visible = true
	clear_screen_fx()


func _finish_settle_bubbles() -> void:
	if not _settle_revealed:
		_reveal_settle_overlay()
	for fx in _settle_emitters:
		fx.emitting = false
	_stop_settle_sfx()
	if _settle_fx:
		_settle_fx.visible = false
	if _settle_block:
		_settle_block.visible = false
		_settle_block.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout_settle_text(has_prize: bool) -> void:
	var lift := 30.0 if has_prize else 0.0
	if _rank:
		_rank.offset_top = 228.0 - lift
		_rank.offset_bottom = 348.0 - lift
	if _rank_desc:
		_rank_desc.offset_top = 348.0 - lift
		_rank_desc.offset_bottom = 398.0 - lift
	if _final:
		_final.offset_top = 402.0 - lift
		_final.offset_bottom = 458.0 if not has_prize else 480.0 - lift


func _style_gold_text(ctrl: Control, outline_px: int = FONT_OUTLINE, fill: Color = FONT_FILL) -> void:
	ctrl.add_theme_color_override("font_color", fill)
	ctrl.add_theme_color_override("font_outline_color", FONT_STROKE)
	ctrl.add_theme_constant_override("outline_size", outline_px)
	if ctrl is Button:
		var btn := ctrl as Button
		btn.add_theme_color_override("font_hover_color", Color("#FFE252"))
		btn.add_theme_color_override("font_pressed_color", Color("#F0B81A"))


func spawn_popup(global_pos: Vector2, text: String, color: Color = Color(1.0, 0.92, 0.45)) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.z_index = 20
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.add_theme_font_size_override("font_size", 28)
	_style_gold_text(lbl)
	$UI.add_child(lbl)
	lbl.global_position = global_pos + Vector2(-24, -20)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.7)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tw.chain().tween_callback(lbl.queue_free)


func show_banner(text: String, color: Color, duration: float = 1.4, blood_plate: bool = false) -> void:
	_banner.text = text
	_style_gold_text(_banner, FONT_OUTLINE, FONT_FILL if blood_plate else color)
	_blood_plate.visible = blood_plate
	_blood_icon.visible = blood_plate
	_banner_root.modulate = Color(1, 1, 1, 0)
	_banner_root.visible = true
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_property(_banner_root, "modulate:a", 1.0, 0.12)
	_fx_tween.tween_interval(duration)
	_fx_tween.tween_property(_banner_root, "modulate:a", 0.0, 0.28)
	_fx_tween.tween_callback(func() -> void: _banner_root.visible = false)


func play_mud(seconds: float) -> void:
	_mud.visible = true
	_mud_mat.set_shader_parameter("amount", 0.0)
	_mud_mat.set_shader_parameter("wipe", 0.0)
	_spawn_mud_blobs()
	var fade_in := 0.12
	var wipe_out := 1.35
	if _mud_tw:
		_mud_tw.kill()
	_mud_tw = create_tween()
	var mud_fade_in := func(v: float) -> void:
		_mud_mat.set_shader_parameter("amount", v)
		if _mud_blobs:
			_mud_blobs.modulate.a = v
	_mud_tw.tween_method(mud_fade_in, 0.0, 1.0, fade_in)
	_mud_tw.tween_interval(maxf(0.0, seconds - fade_in - wipe_out))
	var mud_wipe_out := func(v: float) -> void:
		_mud_mat.set_shader_parameter("wipe", v)
		if _mud_blobs:
			_mud_blobs.modulate.a = 1.0 - v
	_mud_tw.tween_method(mud_wipe_out, 0.0, 1.0, wipe_out)
	_mud_tw.tween_callback(func() -> void:
		_mud.visible = false
		_mud_mat.set_shader_parameter("wipe", 0.0)
		_mud_mat.set_shader_parameter("amount", 0.0)
		_clear_mud_blobs()
	)


func _spawn_mud_blobs() -> void:
	_clear_mud_blobs()
	if _mud_blobs == null or TEX_MUD_BLOB == null:
		return
	_mud_blobs.visible = true
	_mud_blobs.modulate.a = 0.0
	var vs := get_viewport().get_visible_rect().size
	var spots: Array[Vector2] = [
		Vector2(0.18, 0.22), Vector2(0.72, 0.18), Vector2(0.55, 0.62),
		Vector2(0.28, 0.70), Vector2(0.82, 0.55), Vector2(0.45, 0.40),
	]
	for i in spots.size():
		var tr := TextureRect.new()
		tr.texture = TEX_MUD_BLOB
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := randf_range(140.0, 220.0)
		var c := spots[i] * vs
		tr.position = c - Vector2(side, side) * 0.5
		tr.size = Vector2(side, side)
		tr.rotation = randf_range(-0.35, 0.35)
		tr.modulate = Color(1, 1, 1, randf_range(0.85, 1.0))
		_mud_blobs.add_child(tr)


func _clear_mud_blobs() -> void:
	if _mud_blobs == null:
		return
	for c in _mud_blobs.get_children():
		c.queue_free()
	_mud_blobs.visible = false
	_mud_blobs.modulate.a = 1.0


func play_warp(seconds: float) -> void:
	_play_screen_fx(_warp, _warp_mat, seconds, 0.1, 0.5)


func _play_screen_fx(rect: ColorRect, mat: ShaderMaterial, seconds: float, fade_in: float, fade_out: float) -> void:
	rect.visible = true
	mat.set_shader_parameter("amount", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("amount", v), 0.0, 1.0, fade_in)
	tw.tween_interval(maxf(0.0, seconds - fade_in - fade_out))
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("amount", v), 1.0, 0.0, fade_out)
	tw.tween_callback(func() -> void: rect.visible = false)


func clear_screen_fx() -> void:
	if _mud_tw:
		_mud_tw.kill()
		_mud_tw = null
	if _mud:
		_mud.visible = false
		if _mud_mat:
			_mud_mat.set_shader_parameter("amount", 0.0)
			_mud_mat.set_shader_parameter("wipe", 0.0)
	_clear_mud_blobs()
	if _warp:
		_warp.visible = false
	if _banner_root:
		_banner_root.visible = false
