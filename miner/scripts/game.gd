extends Node2D

signal settled(score: int)

const COLLECTIBLE_SCENE := preload("res://miner/scenes/collectible.tscn")
const ROUND_TIME := 62.02
const HIGH_VALUE := 400
const SETTLE_DELAY := 0.5

const SFX_GRAB := preload("res://miner/assets/audio/grab.ogg")
const SFX_FIRE := preload("res://miner/assets/audio/fire.ogg")
const SFX_COLLECT := preload("res://miner/assets/audio/collect.ogg")
const SFX_COLLECT_HIGH := preload("res://miner/assets/audio/collect_high.ogg")
const SFX_START := preload("res://miner/assets/audio/start.ogg")
const SFX_PRIZE_GOLD := preload("res://miner/assets/audio/prize_gold.ogg")
const SFX_PRIZE_SILVER := preload("res://miner/assets/audio/prize_silver.ogg")
const SFX_PRIZE_BRONZE := preload("res://miner/assets/audio/prize_bronze.ogg")
const SFX_MUD := preload("res://miner/assets/audio/mud.ogg")
const SFX_WARP := preload("res://miner/assets/audio/warp.mp3")
const SFX_SWARM := preload("res://miner/assets/audio/swarm.mp3")
const SFX_BOMB_OPEN := preload("res://miner/assets/audio/bomb_open.ogg")
const BGM_STREAM := preload("res://miner/assets/audio/bgm.mp3")
const SEA_SURFACE_SHADER := preload("res://miner/shaders/sea_surface.gdshader")
const WIDE_LEVEL_PATH := "res://miner/data/level_wide_01.json"
const WORLD_MARGIN := 140.0
const WIDE_ASPECT_MIN := 2.2
## 宽关卡右缘时镜头会 clamp，屏幕正中物品在潜艇左侧，需更长绳长斜向够到
const CLAW_MAX_LENGTH_WIDE := 2800.0
const CLAW_MAX_LENGTH_DEFAULT := 980.0
const CLAW_SEABED_Y_WIDE := 719.0
const CLAW_SWING_WIDE := 0.82
const CLAW_TIP_LEAD := 120.0
## 720 设计稿三层（上：潜艇 / 中：鱼群 / 下：打捞物，与关卡红线一致）
const BLOOD_MOON_CHANCE := 0.04
const LAYER_SURFACE_Y := 176.0
## 视频背景时船体略下移，与画面里的水面线对齐
const SUBMARINE_VIDEO_Y_DROP := 44.0
## 退潮时船体在潮层内额外下沉（set_tide_drop_y，避免每帧 align 抖动）
const SUBMARINE_EBB_EXTRA_Y := 26.0
## 低水位时再抬高一点（可为负，仅作用于退潮结束后）
const SUBMARINE_POST_EBB_Y := -10.0
## >1 时同样进度下下沉更慢
const SUBMARINE_EBB_DROP_POWER := 1.28
const LAYER_SUB_HULL_PAD := 28.0
const LAYER_FISH_Y_MIN := 186.0
## 鱼群下沿上移（对应新鱼图，避免太靠上）
const LAYER_FISH_Y_MAX := 336.0
const LAYER_SALVAGE_Y_MIN := 398.0
## 新贴图更大：打捞约 620，避免物体中心落到海底下半截出视口（设计高 720）
const LAYER_SALVAGE_Y_MAX := 620.0
## 高价值物（宝石/珍珠）仍靠下，并随新贴图高度上移
const LAYER_DEEP_Y_MIN := 540.0
const LAYER_DEEP_Y_MAX := 620.0
const DESIGN_Y_FISH_MIN := 280.0
const DESIGN_Y_FISH_MAX := 450.0
const DESIGN_Y_SALVAGE_MIN := 470.0
const DESIGN_Y_SALVAGE_MAX := 672.0
const SHELL_SALVAGE_COUNT_MIN := 7
const SHELL_SALVAGE_COUNT_MAX := 10
const GEM_BOTTOM_COUNT_MIN := 4
const GEM_BOTTOM_COUNT_MAX := 4
const PEARL_BOTTOM_COUNT_MIN := 2
const PEARL_BOTTOM_COUNT_MAX := 2
const FISH_SWIM_MARGIN_X := 70.0
const FISH_EXTRA_RATIO := 0.5
## 新打捞贴图更大，生成间距按可视占位再拉开一点
const SPAWN_SEPARATION_GAP := 40.0
const SPAWN_RESOLVE_MAX_TRIES := 80
const MysteryRevealScript := preload("res://miner/scripts/mystery_reveal.gd")
const MysteryLootScript := preload("res://miner/scripts/mystery_loot.gd")
const BombDetonateScript := preload("res://miner/scripts/bomb_detonate.gd")
const TideWaterVisualScript := preload("res://miner/scripts/tide_water_visual.gd")
const MinerBgVideoScript := preload("res://miner/scripts/miner_bg_video.gd")
const TEX_SAND_LAYER := preload("res://miner/assets/tide/seabed_sand_layer.png")
const USE_VIDEO_BG := true
## 关卡坐标与同事布局一致；整层缩放以填满视口（对齐 feast_game）
const DESIGN_SIZE := Vector2(1280.0, 720.0)

var _world: Node2D
var _world_w: float = 1280.0
var _wide_level: bool = false
var _layered_tide_bg: bool = false

@onready var _background: Sprite2D = $Background
@onready var _items_root: Node2D = $Collectibles
@onready var _submarine: Node2D = $Submarine
@onready var _claw = $Submarine/HookPivot/Claw
@onready var _hud = $HUD

var score: int = 0
var time_left: float = ROUND_TIME
var playing: bool = true
## 局内真实流逝时间（不受「时间+10」回拨 time_left 影响），供背景视频同步。
var _round_play_elapsed: float = 0.0

var _spawned_kinds: Dictionary = {}
var _caught_kinds: Dictionary = {}
var _spawned_fish: Dictionary = {}
var _caught_fish: Dictionary = {}
var _shots: int = 0
var _hits: int = 0
var _spawn_placements: Array[Vector3] = []

var _bgm: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sfx_fire: AudioStreamPlayer
var _sfx_grab: AudioStreamPlayer
var _sfx_collect: AudioStreamPlayer
var _sfx_collect_high: AudioStreamPlayer
var _sfx_prize_gold: AudioStreamPlayer
var _sfx_prize_silver: AudioStreamPlayer
var _sfx_prize_bronze: AudioStreamPlayer
var _sfx_mud: AudioStreamPlayer
var _sfx_warp: AudioStreamPlayer
var _sfx_swarm: AudioStreamPlayer
var _sfx_bomb_open: AudioStreamPlayer
var _mystery_pending: Array = []
var _prize_dolls: int = 0
var _prize_coins: int = 0
var _swarm_left: float = 0.0
var _bomb_ending: bool = false
var _bomb_anim_done: bool = false
var _game_over: bool = false
var _got_mystery_gold: bool = false
var _got_mystery_silver: bool = false
var _mystery_gold_detail: String = ""
var _awaiting_settlement: bool = false
var _finalize_tw: Tween
var _order: MinerOrderState
var _tide: MinerTideState = MinerTideState.new()
var _tide_layer: Node2D
var _fish_root: Node2D
var _water_visual: Node2D
var _blood_fx: Node2D
var _blood_wash: Node
var _blood_washed: bool = false
var _fish_purged_after_ebb: bool = false
var _bg_video: MinerBgVideo
var _video_ui_active: bool = false


func _ready() -> void:
	add_to_group("game")
	if TEX_SAND_LAYER and not USE_VIDEO_BG:
		_background.texture = TEX_SAND_LAYER
		_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_layered_tide_bg = true
	elif TEX_SAND_LAYER and USE_VIDEO_BG:
		# 宽关卡仍用沙层宽高比，但不显示静态海床/水层贴图
		_background.texture = TEX_SAND_LAYER
		_layered_tide_bg = false
	_ensure_world()
	_setup_video_background()
	_setup_wide_level()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	call_deferred("_post_layout_sync")
	_setup_audio()
	_round_play_elapsed = 0.0
	_tide.reset()
	_fish_purged_after_ebb = false
	_spawn_items()
	_hud.set_score(0)
	_hud.set_time(time_left)
	_order = MinerOrderState.roll()
	_hud.bind_order(_order)
	_tide.blood_moon = randf() < BLOOD_MOON_CHANCE
	_hud.restart_pressed.connect(_on_restart)
	_claw.item_collected.connect(_on_item_collected)
	_claw.item_grabbed.connect(_on_item_grabbed)
	_claw.claw_fired.connect(_on_claw_fired)
	_claw.empty_returned.connect(_on_empty_returned)
	call_deferred("_refresh_claw_reach")
	call_deferred("_sync_video_background")
	_play_sting(SFX_START)


func _process(delta: float) -> void:
	if playing:
		var can_steer: bool = _claw.state == _claw.State.SWINGING
		var axis := Input.get_axis("move_left", "move_right") if can_steer else 0.0
		if can_steer:
			var host := get_parent()
			if host and host.has_method("miner_steer_axis"):
				var board_axis: float = host.miner_steer_axis()
				if absf(board_axis) > absf(axis):
					axis = board_axis
		_submarine.set_move_axis(axis)
		if _submarine.has_method("set_operating"):
			_submarine.set_operating(_claw.state != _claw.State.SWINGING)
		_update_tide()
		_update_world_scroll()
		if not _bomb_ending:
			_round_play_elapsed += delta
		_sync_video_background()
		if not _bomb_ending:
			time_left -= delta
			_hud.set_time(time_left)
		if _swarm_left > 0.0:
			_swarm_left -= delta
			if _swarm_left <= 0.0:
				_clear_nuisance()
		if time_left <= 0.0:
			_begin_end_game()
	else:
		_submarine.set_move_axis(0.0)
		if _submarine.has_method("set_operating"):
			_submarine.set_operating(false)
		_sync_video_background()


func _setup_video_background() -> void:
	if not USE_VIDEO_BG:
		return
	if _bg_video != null:
		return
	var shell := get_parent()
	if shell == null or not shell.has_method("obtain_bg_video"):
		push_warning("MinerBgVideo: 未找到 MinerGame 壳，无法挂载背景视频")
		return
	_bg_video = shell.obtain_bg_video()
	if not _bg_video.boot_finished.is_connected(_on_bg_video_boot):
		_bg_video.boot_finished.connect(_on_bg_video_boot)


func _sync_video_background() -> void:
	if _bg_video == null:
		return
	_bg_video.sync(_round_play_elapsed)


func _apply_video_bg_mode() -> void:
	if not USE_VIDEO_BG or not _video_ui_active:
		return
	if _background:
		_background.visible = false
		_background.material = null
	if _water_visual:
		_water_visual.visible = false
	if _world:
		var bubbles := _world.get_node_or_null("SeabedBubbles") as Node2D
		if bubbles:
			bubbles.visible = false


func _on_bg_video_boot(ok: bool) -> void:
	if not USE_VIDEO_BG:
		return
	_video_ui_active = ok
	if ok:
		_apply_video_bg_mode()
		_apply_submarine_layer()
		return
	push_error(
		"MinerBgVideo: 视频未就绪，已恢复静态海床。"
		+ " 请确认 miner/assets/video/miner_bg.ogv 存在，且引擎支持 VideoStreamTheora。"
	)
	_layered_tide_bg = true
	if _background:
		_background.visible = true
	if _water_visual:
		_water_visual.visible = true
	_on_viewport_resized()


func press_fire() -> void:
	if _awaiting_settlement or _bomb_ending:
		return
	if not playing:
		if _hud.can_restart():
			_on_restart()
		return
	_claw.try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("fire"):
		return
	if not playing and event is InputEventMouseButton:
		return
	press_fire()
	get_viewport().set_input_as_handled()


func _on_claw_fired() -> void:
	_shots += 1
	_play_one_shot(_sfx_fire)


func _on_item_grabbed(item: Collectible) -> void:
	_hits += 1
	if not item.nuisance:
		_note_catch(item)
		if _order:
			_order.on_catch(item)
			_hud.bind_order(_order)
	_play_one_shot(_sfx_grab)


func _ensure_world() -> void:
	if _world != null:
		return
	_world = Node2D.new()
	_world.name = "World1280"
	add_child(_world)
	move_child(_world, 0)
	for node_name in ["Background", "Collectibles", "SeabedBubbles"]:
		var n := get_node_or_null(node_name)
		if n:
			n.reparent(_world)
	_tide_layer = Node2D.new()
	_tide_layer.name = "TideLayer"
	_world.add_child(_tide_layer)
	_fish_root = Node2D.new()
	_fish_root.name = "FishContainer"
	_water_visual = TideWaterVisualScript.new()
	_water_visual.name = "WaterVisual"
	_tide_layer.add_child(_water_visual)
	_tide_layer.add_child(_fish_root)
	var fx_script: Script = load("res://miner/scripts/blood_moon_fx.gd")
	_blood_fx = Node2D.new()
	_blood_fx.set_script(fx_script)
	_blood_fx.name = "BloodMoonFx"
	_tide_layer.add_child(_blood_fx)
	_water_visual.setup(LAYER_SURFACE_Y, _world_w if _world_w > 1.0 else DESIGN_SIZE.x)
	var sub := get_node_or_null("Submarine") as Node2D
	if sub == null:
		sub = _world.get_node_or_null("TideLayer/Submarine") as Node2D
	if sub:
		if sub.get_parent() != _tide_layer:
			sub.reparent(_tide_layer)
		sub.z_index = 10
	_fish_root.z_index = 2
	_refresh_world_refs()


func _refresh_world_refs() -> void:
	if _world == null:
		return
	_submarine = _world.get_node("TideLayer/Submarine") as Node2D
	_claw = _world.get_node("TideLayer/Submarine/HookPivot/Claw")
	_background = _world.get_node("Background") as Sprite2D
	_items_root = _world.get_node("Collectibles") as Node2D
	_tide_layer = _world.get_node("TideLayer") as Node2D
	_fish_root = _world.get_node("TideLayer/FishContainer") as Node2D
	_water_visual = _world.get_node("TideLayer/WaterVisual") as Node2D


func _setup_wide_level() -> void:
	var tex := _background.texture
	if tex == null:
		return
	var ts := tex.get_size()
	_wide_level = ts.x / maxf(ts.y, 1.0) >= WIDE_ASPECT_MIN
	if not _wide_level:
		_world_w = DESIGN_SIZE.x
		_claw.max_length = CLAW_MAX_LENGTH_DEFAULT
		_claw.seabed_y = 712.0
		_claw.swing_amplitude = 1.05
		_submarine.min_x = WORLD_MARGIN
		_submarine.max_x = _world_w - WORLD_MARGIN
		_submarine.position.x = _world_w * 0.5
		_apply_submarine_layer()
		return
	var s := DESIGN_SIZE.y / ts.y
	_world_w = ts.x * s
	_submarine.min_x = WORLD_MARGIN
	_submarine.max_x = _world_w - WORLD_MARGIN
	var start_x := _world_w * 0.5
	_submarine.position.x = start_x
	_apply_submarine_layer()
	_apply_claw_wide_reach()
	_update_world_scroll()


func _refresh_claw_reach() -> void:
	if _claw == null or _submarine == null:
		return
	if _wide_level:
		_claw.seabed_y = CLAW_SEABED_Y_WIDE
		_claw.swing_amplitude = CLAW_SWING_WIDE
		_claw.max_length = _calc_claw_max_length(CLAW_SEABED_Y_WIDE, CLAW_SWING_WIDE)
	else:
		_claw.seabed_y = 712.0
		_claw.swing_amplitude = 1.05
		_claw.max_length = _calc_claw_max_length(712.0, 1.05)


func _calc_claw_max_length(seabed_y: float, swing_amp: float) -> float:
	var pivot := _submarine.get_node("HookPivot") as Node2D
	var pivot_y := pivot.global_position.y if pivot != null else 220.0
	var cos_a := maxf(cos(swing_amp), 0.40)
	var along := (seabed_y - pivot_y + CLAW_TIP_LEAD) / cos_a
	var floor_len := CLAW_MAX_LENGTH_WIDE if _wide_level else CLAW_MAX_LENGTH_DEFAULT
	return maxf(along * 1.25, floor_len)


func _apply_claw_wide_reach() -> void:
	if not _wide_level:
		return
	_refresh_claw_reach()


func _update_world_scroll() -> void:
	if _world == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return
	var s := _world.scale.x
	if s < 0.001:
		return
	var half := DESIGN_SIZE.x * 0.5
	var cx := half
	if _wide_level and _world_w > DESIGN_SIZE.x + 1.0:
		cx = clampf(_submarine.position.x, half, _world_w - half)
	_world.position = Vector2(vs.x * 0.5 - cx * s, (vs.y - DESIGN_SIZE.y * s) * 0.5)
	_apply_order_airwall(vs, s)


func _apply_order_airwall(vs: Vector2, world_scale: float) -> void:
	if _submarine == null or _hud == null or world_scale < 0.001:
		return
	var panel_left: float = _hud.get_order_panel_left()
	if panel_left > vs.x:
		return
	var half := DESIGN_SIZE.x * 0.5
	var cx_lock := _world_w - half
	var world_x := vs.x * 0.5 - cx_lock * world_scale
	var boat_half := 90.0
	var max_boat := (panel_left - 20.0 - world_x) / world_scale - boat_half
	_submarine.max_x = clampf(max_boat, _submarine.min_x + 40.0, _world_w - WORLD_MARGIN)
	if _submarine.position.x > _submarine.max_x:
		_submarine.position.x = _submarine.max_x


func _on_viewport_resized() -> void:
	_fit_world_to_viewport()
	_fit_background()
	_post_layout_sync()


func _fit_world_to_viewport() -> void:
	if _world == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 8.0 or vs.y < 8.0:
		return
	var s := maxf(vs.x / DESIGN_SIZE.x, vs.y / DESIGN_SIZE.y)
	_world.scale = Vector2(s, s)
	_update_world_scroll()


func _fit_background() -> void:
	if USE_VIDEO_BG:
		if _video_ui_active:
			_apply_video_bg_mode()
		_apply_submarine_layer()
		return
	var tex := _background.texture
	if tex == null:
		return
	var ts := tex.get_size()
	var s: float
	if _wide_level:
		s = DESIGN_SIZE.y / ts.y
		_world_w = ts.x * s
		_background.position = Vector2(_world_w * 0.5, DESIGN_SIZE.y * 0.5)
	else:
		s = maxf(DESIGN_SIZE.x / ts.x, DESIGN_SIZE.y / ts.y)
		_background.position = DESIGN_SIZE * 0.5
	_background.z_index = -2
	_background.centered = true
	_background.scale = Vector2(s, s)
	if _bg_video == null:
		_background.visible = true
	else:
		_background.visible = false
	if _layered_tide_bg:
		_background.material = null
	else:
		_ensure_sea_surface()
	if _wide_level:
		_submarine.max_x = _world_w - WORLD_MARGIN
		_apply_claw_wide_reach()
	if _water_visual and _water_visual.has_method("fit_like_background"):
		_water_visual.fit_like_background(_world_w, DESIGN_SIZE.y, s)
	if _water_visual and _water_visual.has_method("set_tide_scroll"):
		_water_visual.set_tide_scroll(_tide.tide_layer_y)
	_apply_submarine_layer()
	_update_world_scroll()


func _ensure_sea_surface() -> void:
	if _background.material is ShaderMaterial:
		return
	var mat := ShaderMaterial.new()
	mat.shader = SEA_SURFACE_SHADER
	_background.material = mat


func _map_y_to_fish_layer(design_y: float) -> float:
	var t := inverse_lerp(DESIGN_Y_FISH_MIN, DESIGN_Y_FISH_MAX, design_y)
	return lerpf(LAYER_FISH_Y_MIN, LAYER_FISH_Y_MAX, clampf(t, 0.0, 1.0))


func _map_y_to_salvage_layer(design_y: float) -> float:
	var t := inverse_lerp(DESIGN_Y_SALVAGE_MIN, DESIGN_Y_SALVAGE_MAX, design_y)
	return lerpf(LAYER_SALVAGE_Y_MIN, LAYER_SALVAGE_Y_MAX, clampf(t, 0.0, 1.0))


func _random_y_in_salvage_layer() -> float:
	var lim := _spawn_y_limits(Collectible.Kind.SHELL)
	return randf_range(lim.x, lim.y)


func _is_deep_treasure(kind: Collectible.Kind) -> bool:
	return kind == Collectible.Kind.GEM or kind == Collectible.Kind.PEARL


func _spawn_y_limits(kind: Collectible.Kind) -> Vector2:
	var lim := Vector2(LAYER_SALVAGE_Y_MIN, LAYER_SALVAGE_Y_MAX)
	if _is_deep_treasure(kind):
		lim = Vector2(LAYER_DEEP_Y_MIN, LAYER_DEEP_Y_MAX)
	## 按贴图占位再抬高下限，防止半截沉到视口外
	var clearance := maxf(Collectible.placement_radius(kind) * 2.2, 70.0)
	var max_y := minf(lim.y, DESIGN_SIZE.y - clearance)
	var min_y := minf(lim.x, max_y - 12.0)
	return Vector2(min_y, max_y)


func _random_y_for_kind(kind: Collectible.Kind) -> float:
	var lim := _spawn_y_limits(kind)
	return randf_range(lim.x, lim.y)


func _post_layout_sync() -> void:
	_ensure_world()
	_apply_submarine_layer()
	_refresh_claw_reach()
	_update_world_scroll()


func _submarine_tide_drop_y() -> float:
	if _tide == null:
		return 0.0
	if _tide.elapsed < MinerTideState.EBB_START:
		return 0.0
	if _tide.phase == MinerTideState.Phase.LOW_HOLD:
		return SUBMARINE_EBB_EXTRA_Y + SUBMARINE_POST_EBB_Y
	if _tide.phase == MinerTideState.Phase.EBBING:
		var t := pow(_tide.ebb_motion_progress(), SUBMARINE_EBB_DROP_POWER)
		return lerpf(0.0, SUBMARINE_EBB_EXTRA_Y, t)
	return 0.0


func _apply_submarine_layer() -> void:
	_ensure_world()
	_refresh_world_refs()
	if _submarine == null:
		return
	if _submarine.has_method("align_above_surface_line"):
		var surface_y := LAYER_SURFACE_Y
		if USE_VIDEO_BG and _video_ui_active:
			surface_y += SUBMARINE_VIDEO_Y_DROP
		_submarine.align_above_surface_line(surface_y, LAYER_SUB_HULL_PAD)
	if _submarine.has_method("set_tide_drop_y"):
		_submarine.set_tide_drop_y(_submarine_tide_drop_y())


func _spawn_items() -> void:
	_spawn_placements.clear()
	if _wide_level and FileAccess.file_exists(WIDE_LEVEL_PATH):
		_spawn_from_level_json(WIDE_LEVEL_PATH)
	else:
		_spawn_default_layout(_world_w / DESIGN_SIZE.x if _wide_level else 1.0)
	_spawn_random_shells()
	_spawn_bottom_treasures()


func _spawn_random_shells() -> void:
	var n := randi_range(SHELL_SALVAGE_COUNT_MIN, SHELL_SALVAGE_COUNT_MAX)
	var margin := WORLD_MARGIN + 48.0
	var world_w := _world_w if _wide_level else DESIGN_SIZE.x
	var max_x := world_w - margin
	if max_x <= margin:
		return
	for _i in n:
		var pos := Vector2(randf_range(margin, max_x), _random_y_in_salvage_layer())
		_spawn_collectible(Collectible.Kind.SHELL, pos)


func _spawn_bottom_treasures() -> void:
	var margin := WORLD_MARGIN + 48.0
	var world_w := _world_w if _wide_level else DESIGN_SIZE.x
	var max_x := world_w - margin
	if max_x <= margin:
		return
	var gem_n := randi_range(GEM_BOTTOM_COUNT_MIN, GEM_BOTTOM_COUNT_MAX) if _wide_level else 1
	var pearl_n := randi_range(PEARL_BOTTOM_COUNT_MIN, PEARL_BOTTOM_COUNT_MAX) if _wide_level else randi_range(0, 1)
	for _i in gem_n:
		var pos := Vector2(randf_range(margin, max_x), _random_y_for_kind(Collectible.Kind.GEM))
		_spawn_collectible(Collectible.Kind.GEM, pos)
	for _i in pearl_n:
		var pos := Vector2(randf_range(margin, max_x), _random_y_for_kind(Collectible.Kind.PEARL))
		_spawn_collectible(Collectible.Kind.PEARL, pos)


func _spawn_default_layout(xf: float) -> void:
	var layout: Array = [
		[Collectible.Kind.COIN, Vector2(500, 658)],
		[Collectible.Kind.COIN_PILE, Vector2(290, 648)],
		[Collectible.Kind.COIN_PILE, Vector2(870, 655)],
		[Collectible.Kind.NUGGET, Vector2(1145, 490)],
		[Collectible.Kind.CHEST, Vector2(190, 628)],
		[Collectible.Kind.POT, Vector2(245, 485)],
		[Collectible.Kind.WELL, Vector2(545, 575)],
		[Collectible.Kind.BARREL, Vector2(760, 598)],
		[Collectible.Kind.ROCK, Vector2(350, 505)],
		[Collectible.Kind.ROCK, Vector2(1065, 555)],
		[Collectible.Kind.MYSTERY, Vector2(400, 625)],
		[Collectible.Kind.MYSTERY, Vector2(640, 575)],
		[Collectible.Kind.MYSTERY, Vector2(920, 480)],
		[Collectible.Kind.MYSTERY, Vector2(980, 630)],
	]
	for entry in layout:
		var pos: Vector2 = entry[1] as Vector2
		var mapped := Vector2(pos.x * xf, _map_y_to_salvage_layer(pos.y))
		_spawn_collectible(entry[0] as Collectible.Kind, mapped)
	_spawn_fish([], xf)


func _spawn_from_level_json(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("miner wide level json invalid")
		_spawn_default_layout(_world_w / DESIGN_SIZE.x if _wide_level else 1.0)
		return
	var design_w := float(data.get("world_design_w", 1280))
	var xf := _world_w / maxf(design_w, 1.0)
	for row in data.get("items", []):
		if typeof(row) != TYPE_ARRAY or row.size() < 3:
			continue
		var kind := _kind_from_string(String(row[0]))
		if kind < 0:
			continue
		if kind == Collectible.Kind.GEM or kind == Collectible.Kind.PEARL or kind == Collectible.Kind.SHELL:
			continue
		var pos := Vector2(float(row[1]) * xf, _map_y_to_salvage_layer(float(row[2])))
		_spawn_collectible(kind as Collectible.Kind, pos)
	var fish_rows: Array = data.get("fish", [])
	_spawn_fish(fish_rows, xf)


func _kind_from_string(name: String) -> int:
	match name.to_lower():
		"coin":
			return Collectible.Kind.COIN
		"coin_pile":
			return Collectible.Kind.COIN_PILE
		"pearl":
			return Collectible.Kind.PEARL
		"shell":
			return Collectible.Kind.SHELL
		"gem":
			return Collectible.Kind.GEM
		"chest":
			return Collectible.Kind.CHEST
		"nugget":
			return Collectible.Kind.NUGGET
		"pot":
			return Collectible.Kind.POT
		"well":
			return Collectible.Kind.WELL
		"barrel":
			return Collectible.Kind.BARREL
		"rock":
			return Collectible.Kind.ROCK
		"mystery":
			return Collectible.Kind.MYSTERY
		_:
			return -1


func _spawn_overlaps(pos: Vector2, radius: float) -> bool:
	for p in _spawn_placements:
		var min_d := radius + p.z + SPAWN_SEPARATION_GAP
		if pos.distance_to(Vector2(p.x, p.y)) < min_d:
			return true
	return false


func _register_spawn_placement(pos: Vector2, radius: float) -> void:
	_spawn_placements.append(Vector3(pos.x, pos.y, radius))


func _unregister_spawn_placement(pos: Vector2) -> void:
	for i in range(_spawn_placements.size() - 1, -1, -1):
		var p: Vector3 = _spawn_placements[i]
		if Vector2(p.x, p.y).distance_to(pos) <= 6.0:
			_spawn_placements.remove_at(i)
			return


func _resolve_collectible_pos(kind: Collectible.Kind, desired: Vector2) -> Vector2:
	var y_lim := _spawn_y_limits(kind)
	desired.y = clampf(desired.y, y_lim.x, y_lim.y)
	var radius := Collectible.placement_radius(kind)
	if not _spawn_overlaps(desired, radius):
		return desired
	var margin := 48.0
	var world_w := _world_w if _wide_level else DESIGN_SIZE.x
	var max_x := world_w - margin
	if max_x <= margin:
		return desired
	for _t in SPAWN_RESOLVE_MAX_TRIES:
		var cand := Vector2(randf_range(margin, max_x), _random_y_for_kind(kind))
		if not _spawn_overlaps(cand, radius):
			return cand
	for ring in range(1, 14):
		var step := 16.0 + float(ring) * 12.0
		for angle_i in range(10):
			var a := float(angle_i) * TAU / 10.0
			var cand := desired + Vector2(cos(a), sin(a)) * step
			cand.x = clampf(cand.x, margin, max_x)
			cand.y = clampf(cand.y, y_lim.x, y_lim.y)
			if not _spawn_overlaps(cand, radius):
				return cand
	return desired


func _spawn_collectible(kind: Collectible.Kind, pos: Vector2) -> Collectible:
	pos = _resolve_collectible_pos(kind, pos)
	var radius := Collectible.placement_radius(kind)
	_register_spawn_placement(pos, radius)
	var item := COLLECTIBLE_SCENE.instantiate() as Collectible
	_items_root.add_child(item)
	item.setup(kind, pos)
	_note_spawn(item)
	return item


func _fish_swim_bounds() -> Vector4:
	var w := _world_w if _wide_level else DESIGN_SIZE.x
	var max_y := _tide.get_fish_swim_y_max(LAYER_FISH_Y_MIN, LAYER_FISH_Y_MAX)
	return Vector4(
		FISH_SWIM_MARGIN_X,
		w - FISH_SWIM_MARGIN_X,
		LAYER_FISH_Y_MIN,
		max_y
	)


func _apply_fish_swim_bounds(fish: Collectible) -> void:
	var b := _fish_swim_bounds()
	fish.configure_swim_bounds(b.x, b.y, b.z, b.w)


func _apply_all_fish_swim_bounds() -> void:
	if _fish_root == null:
		return
	var b := _fish_swim_bounds()
	for node in _fish_root.get_children():
		var fish := node as Collectible
		if fish == null or fish.grabbed:
			continue
		fish.configure_swim_bounds(b.x, b.y, b.z, b.w)


func _update_tide() -> void:
	if not playing or _bomb_ending:
		return
	var elapsed := ROUND_TIME - time_left
	_tide.advance(elapsed, LAYER_FISH_Y_MIN, LAYER_FISH_Y_MAX)
	if _tide_layer:
		_tide_layer.position.y = _tide.tide_layer_y
	if _water_visual and _water_visual.has_method("set_tide_scroll"):
		_water_visual.set_tide_scroll(_tide.tide_layer_y)
	_hud.set_ebb_bar_ratio(_tide.ebb_bar_ratio)
	if _water_visual and _water_visual.has_method("set_blood"):
		_water_visual.set_blood(_tide.blood)
	_sync_blood_moon_fx()
	if _tide.consume_blood_banner():
		_hud.show_banner("血月潮", Color(1.0, 0.62, 0.74), 2.0, true)
		_start_blood_wash()
	elif _tide.consume_ebb_banner():
		_hud.show_banner("开始退潮", Color(0.55, 0.85, 1.0), 2.0)
	_apply_all_fish_swim_bounds()
	_cull_fish_outside_bounds()
	if _tide.should_purge_all_fish() and not _fish_purged_after_ebb:
		_purge_tide_fish()
		_fish_purged_after_ebb = true


func _start_blood_wash() -> void:
	if _blood_washed or _items_root == null:
		return
	_blood_washed = true
	if _blood_wash == null:
		var script: Script = load("res://miner/scripts/blood_moon_wash.gd")
		_blood_wash = Node.new()
		_blood_wash.set_script(script)
		_blood_wash.name = "BloodMoonWash"
		add_child(_blood_wash)
	var world_w := _world_w if _world_w > 1.0 else DESIGN_SIZE.x
	var center_x := _submarine.position.x if _submarine != null else world_w * 0.5
	_blood_wash.begin(_items_root, _fish_root, world_w, center_x, _order)


func _sync_blood_moon_fx() -> void:
	if _blood_fx == null or not _blood_fx.has_method("place_on_map"):
		return
	_blood_fx.place_on_map(_world_w if _world_w > 1.0 else DESIGN_SIZE.x)
	_blood_fx.set_reveal(_tide.blood)


func _cull_fish_outside_bounds() -> void:
	if _fish_root == null:
		return
	var max_y := _fish_swim_bounds().w
	for node in _fish_root.get_children():
		var fish := node as Collectible
		if fish == null or fish.grabbed:
			continue
		if fish.position.y > max_y + 12.0:
			fish.queue_free()


func _purge_tide_fish() -> void:
	if _fish_root == null:
		return
	for node in _fish_root.get_children():
		var fish := node as Collectible
		if fish == null or fish.grabbed:
			continue
		fish.queue_free()


func _spawn_fish_entry(entry: Array, xf: float, pos: Vector2, swim_dir: float, swim_speed: float) -> void:
	_ensure_world()
	var root := _fish_root if _fish_root != null else _items_root
	var fish := COLLECTIBLE_SCENE.instantiate() as Collectible
	root.add_child(fish)
	fish.setup_fish(entry[0] as int, pos, swim_dir, swim_speed)
	_apply_fish_swim_bounds(fish)
	_note_spawn(fish)


func _spawn_fish(schools: Array, xf: float = 1.0) -> void:
	if schools.is_empty():
		schools = [
			[0, 180, 332, 1.0, 58.0],
			[4, 820, 358, -1.0, 72.0],
			[2, 430, 388, 1.0, 46.0],
			[6, 1040, 416, -1.0, 64.0],
			[1, 620, 308, -1.0, 80.0],
			[7, 300, 442, 1.0, 50.0],
			[5, 960, 378, 1.0, 42.0],
			[3, 720, 326, -1.0, 88.0],
		]
	for entry in schools:
		var pos := Vector2(float(entry[1]) * xf, _map_y_to_fish_layer(float(entry[2])))
		_spawn_fish_entry(entry, xf, pos, entry[3] as float, entry[4] as float)
	var extra_n := int(round(float(schools.size()) * FISH_EXTRA_RATIO))
	if extra_n <= 0:
		return
	var bounds := _fish_swim_bounds()
	for i in extra_n:
		var template: Array = schools[i % schools.size()]
		var pos := Vector2(
			randf_range(bounds.x, bounds.y),
			randf_range(bounds.z, bounds.w)
		)
		var dir := 1.0 if randf() < 0.5 else -1.0
		var speed := float(template[4]) * randf_range(0.9, 1.12)
		_spawn_fish_entry(template, xf, pos, dir, speed)


func _on_empty_returned() -> void:
	_submarine.sulk()
	if _awaiting_settlement:
		_schedule_finalize_after_award()


func _on_item_collected(item: Collectible) -> void:
	if item.kind == Collectible.Kind.MYSTERY:
		_submarine.celebrate()
		_begin_mystery_reveal(item)
		return
	_award_item(item.value, _submarine.global_position + Vector2(40, 30))
	_submarine.celebrate()
	if _awaiting_settlement:
		_schedule_finalize_after_award()


func _award_item(p_value: int, popup_pos: Vector2) -> void:
	score += p_value
	_hud.set_score(score)
	_hud.spawn_popup(popup_pos, "+%d" % p_value)
	_play_collect(p_value)


func _begin_mystery_reveal(item: Collectible) -> void:
	var loot: MysteryLoot = MysteryLootScript.roll()
	loot.origin = item.origin_global
	_mystery_pending.append(loot)
	var fx := MysteryRevealScript.new()
	add_child(fx)
	fx.global_position = get_viewport_rect().size * 0.5
	var spr := item.get_node_or_null("Sprite2D") as Sprite2D
	var tex: Texture2D = spr.texture if spr and spr.texture else preload("res://miner/assets/mystery_box.png")
	var start_scale := spr.global_scale if spr else Vector2.ONE * 0.13
	fx.finished.connect(_on_mystery_finished)
	fx.play(tex, start_scale, loot)


func _on_mystery_finished(loot: MysteryLoot) -> void:
	var idx := _mystery_pending.find(loot)
	if idx >= 0:
		_mystery_pending.remove_at(idx)
	if _bomb_ending:
		return
	if playing or _awaiting_settlement:
		_apply_mystery_loot(loot, true)
		if loot.id == MysteryLoot.Id.BOMB:
			return
		if _awaiting_settlement:
			_schedule_finalize_after_award()


func _apply_mystery_loot(loot: MysteryLoot, live: bool) -> void:
	if loot.title == "金奖":
		_got_mystery_gold = true
		_mystery_gold_detail = loot.detail
	elif loot.title == "银奖":
		_got_mystery_silver = true
	var pos := get_viewport_rect().size * 0.5
	if live:
		_hud.show_banner(loot.banner(), loot.banner_color())
		_play_mystery_prize_sfx(loot)
		if loot.is_punish:
			_submarine.sulk()
		else:
			_submarine.celebrate()
	if loot.score > 0:
		_award_item(loot.score, pos)
		return
	match loot.id:
		MysteryLoot.Id.DOLL:
			_prize_dolls += 1
		MysteryLoot.Id.COINS_10:
			_prize_coins += 10
		MysteryLoot.Id.TIME_10:
			if live and not _awaiting_settlement:
				time_left += 10.0
				_hud.set_time(time_left)
				_hud.spawn_popup(pos, "时间 +10", Color(0.55, 1.0, 0.7))
			elif live and _awaiting_settlement:
				_hud.spawn_popup(pos, "时间 +10", Color(0.55, 1.0, 0.7))
		MysteryLoot.Id.MUD:
			if live:
				_hud.play_mud(3.0)
				_play_one_shot(_sfx_mud)
		MysteryLoot.Id.BOMB:
			if live:
				_play_one_shot(_sfx_bomb_open)
				_begin_bomb_end(loot.origin)
		MysteryLoot.Id.SWARM:
			if live:
				_spawn_nuisance_school()
				_play_one_shot(_sfx_swarm)
		MysteryLoot.Id.WARP:
			if live:
				_hud.play_warp(5.0)
				_play_one_shot(_sfx_warp)


func _begin_bomb_end(origin: Vector2) -> void:
	if _bomb_ending:
		return
	_bomb_ending = true
	_bomb_anim_done = false
	playing = false
	_claw.active = false
	_submarine.set_move_axis(0.0)
	if _finalize_tw:
		_finalize_tw.kill()
		_finalize_tw = null
	var fx := BombDetonateScript.new()
	add_child(fx)
	fx.finished.connect(_on_bomb_anim_finished, CONNECT_ONE_SHOT)
	fx.play_at(origin)


func _on_bomb_anim_finished() -> void:
	_bomb_anim_done = true
	_finalize_settlement()


func _spawn_nuisance_school() -> void:
	_clear_nuisance()
	_swarm_left = 10.0
	var cheap: Array[int] = [3, 3, 0, 1]
	_ensure_world()
	var root := _fish_root if _fish_root != null else _items_root
	for i in 14:
		var fish := COLLECTIBLE_SCENE.instantiate() as Collectible
		root.add_child(fish)
		var from_left := i % 2 == 0
		var edge_x := _world_w + 50.0 if not from_left else -50.0
		var pos := Vector2(edge_x, randf_range(LAYER_FISH_Y_MIN, LAYER_FISH_Y_MAX))
		var dir := 1.0 if from_left else -1.0
		fish.setup_nuisance_fish(cheap[i % cheap.size()], pos, dir, randf_range(96.0, 148.0), 20)
		_apply_fish_swim_bounds(fish)


func _clear_nuisance() -> void:
	_swarm_left = 0.0
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("nuisance_fish"):
		var item := node as Collectible
		if item == null or item.grabbed:
			continue
		item.queue_free()


func _prize_summary() -> String:
	var bits: PackedStringArray = []
	if _mystery_gold_detail != "":
		bits.append("金奖  %s" % _mystery_gold_detail)
	if _prize_dolls > 0:
		bits.append("娃娃 x%d" % _prize_dolls)
	if _prize_coins > 0:
		bits.append("游戏币 +%d" % _prize_coins)
	return "  ".join(bits)


func _begin_end_game() -> void:
	if _game_over or _awaiting_settlement or _bomb_ending:
		return
	_awaiting_settlement = true
	playing = false
	time_left = 0.0
	_hud.set_time(0.0)
	_try_finalize_settlement()


func _schedule_finalize_after_award(delay: float = SETTLE_DELAY) -> void:
	if _finalize_tw:
		_finalize_tw.kill()
	_finalize_tw = create_tween()
	_finalize_tw.tween_interval(delay)
	_finalize_tw.tween_callback(_try_finalize_settlement)


func _try_finalize_settlement() -> void:
	if not _awaiting_settlement or _game_over:
		return
	if _bomb_ending and not _bomb_anim_done:
		return
	if _claw.hooked != null:
		return
	if not _mystery_pending.is_empty():
		return
	for node in get_tree().get_nodes_in_group("mystery_reveal"):
		if is_instance_valid(node):
			return
	for node in get_tree().get_nodes_in_group("bomb_detonate"):
		if is_instance_valid(node):
			return
	_finalize_settlement()


func _finalize_settlement() -> void:
	if _game_over:
		return
	if _bomb_ending and not _bomb_anim_done:
		return
	_game_over = true
	playing = false
	_awaiting_settlement = false
	if _finalize_tw:
		_finalize_tw.kill()
		_finalize_tw = null
	for leftover in _mystery_pending:
		_apply_mystery_loot(leftover as MysteryLoot, false)
	_mystery_pending.clear()
	_clear_nuisance()
	_hud.set_score(score)
	for node in get_tree().get_nodes_in_group("mystery_reveal"):
		node.queue_free()
	_claw.active = false
	_release_cabinet_input()
	if _bgm:
		_bgm.stop()
	var rank: Array[String] = _eval_title()
	_hud.show_game_over(score, rank[0], rank[1], _prize_summary())
	settled.emit(score)


func _setup_audio() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BGM"
	var stream := BGM_STREAM
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_bgm.stream = stream
	_bgm.volume_db = -1.4
	add_child(_bgm)
	_bgm.play()
	_sting = AudioStreamPlayer.new()
	_sting.name = "Sting"
	add_child(_sting)
	_sfx_fire = _make_sfx_player("SFXFire", SFX_FIRE)
	_sfx_grab = _make_sfx_player("SFXGrab", SFX_GRAB)
	_sfx_collect = _make_sfx_player("SFXCollect", SFX_COLLECT)
	_sfx_collect_high = _make_sfx_player("SFXCollectHigh", SFX_COLLECT_HIGH)
	_sfx_prize_gold = _make_sfx_player("SFXPrizeGold", SFX_PRIZE_GOLD)
	_sfx_prize_silver = _make_sfx_player("SFXPrizeSilver", SFX_PRIZE_SILVER)
	_sfx_prize_bronze = _make_sfx_player("SFXPrizeBronze", SFX_PRIZE_BRONZE)
	_sfx_mud = _make_sfx_player("SFXMud", SFX_MUD)
	_sfx_warp = _make_sfx_player("SFXWarp", SFX_WARP)
	_sfx_swarm = _make_sfx_player("SFXSwarm", SFX_SWARM)
	var bomb_open: AudioStream = SFX_BOMB_OPEN.duplicate()
	if bomb_open is AudioStreamOggVorbis:
		(bomb_open as AudioStreamOggVorbis).loop = false
	_sfx_bomb_open = _make_sfx_player("SFXBombOpen", bomb_open)
	_warm_sfx_players([
		_sfx_fire, _sfx_grab, _sfx_collect, _sfx_collect_high,
		_sfx_prize_gold, _sfx_prize_silver, _sfx_prize_bronze, _sfx_mud,
		_sfx_warp, _sfx_swarm, _sfx_bomb_open,
	])


func _make_sfx_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	add_child(player)
	return player


func _warm_sfx_players(players: Array) -> void:
	for node in players:
		var player := node as AudioStreamPlayer
		if player == null:
			continue
		var vol := player.volume_db
		player.volume_db = -80.0
		player.play()
		player.stop()
		player.volume_db = vol
		player.seek(0.0)


func _play_collect(value: int) -> void:
	if value >= HIGH_VALUE:
		_play_one_shot(_sfx_collect_high)
	else:
		_play_one_shot(_sfx_collect)


func _play_mystery_prize_sfx(loot: MysteryLoot) -> void:
	match loot.title:
		"金奖":
			_play_one_shot(_sfx_prize_gold)
		"银奖":
			_play_one_shot(_sfx_prize_silver)
		"铜奖":
			_play_one_shot(_sfx_prize_bronze)


func _play_one_shot(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.seek(0.0)
	player.play()


func _play_sting(stream: AudioStream) -> void:
	if _sting == null or stream == null:
		return
	_sting.stream = stream
	_sting.play()


func _on_restart() -> void:
	var host := get_parent()
	if host and host.has_method("replay_round"):
		host.replay_round()
		return
	if has_node("/root/IoBoard") and get_node("/root/IoBoard").has_method("set_input_enabled"):
		get_node("/root/IoBoard").set_input_enabled(true)
	get_tree().reload_current_scene()


func _release_cabinet_input() -> void:
	if has_node("/root/IoBoard") and get_node("/root/IoBoard").has_method("set_input_enabled"):
		get_node("/root/IoBoard").set_input_enabled(false)


func _note_spawn(item: Collectible) -> void:
	_spawned_kinds[item.kind] = int(_spawned_kinds.get(item.kind, 0)) + 1
	if item.kind == Collectible.Kind.FISH:
		_spawned_fish[item.fish_index] = int(_spawned_fish.get(item.fish_index, 0)) + 1


func _note_catch(item: Collectible) -> void:
	_caught_kinds[item.kind] = int(_caught_kinds.get(item.kind, 0)) + 1
	if item.kind == Collectible.Kind.FISH:
		_caught_fish[item.fish_index] = int(_caught_fish.get(item.fish_index, 0)) + 1


func _caught_all_kinds(kinds: Array) -> bool:
	for kind in kinds:
		var need := int(_spawned_kinds.get(kind, 0))
		if need <= 0:
			return false
		if int(_caught_kinds.get(kind, 0)) < need:
			return false
	return true


func _caught_count(kinds: Array) -> int:
	var total := 0
	for kind in kinds:
		total += int(_caught_kinds.get(kind, 0))
	return total


func _caught_all_fish() -> bool:
	if _spawned_fish.is_empty():
		return false
	for idx in _spawned_fish:
		if int(_caught_fish.get(idx, 0)) < int(_spawned_fish[idx]):
			return false
	return true


func _is_collector() -> bool:
	if not _caught_all_kinds([Collectible.Kind.CHEST, Collectible.Kind.NUGGET]):
		return false
	for idx in _unique_fish_indices():
		if int(_caught_fish.get(idx, 0)) < 1:
			return false
	return true


func _unique_fish_indices() -> Array[int]:
	var values: Array[int] = [90, 110, 140, 80, 160, 180, 150, 200]
	var ranked: Array[int] = values.duplicate()
	ranked.sort()
	var cutoff := ranked[ranked.size() - 3]
	var out: Array[int] = []
	for i in values.size():
		if values[i] >= cutoff:
			out.append(i)
	return out


func _eval_title() -> Array[String]:
	if _got_mystery_gold:
		return ["天命之子", "在神秘箱子中获得金奖"]
	if _got_mystery_silver:
		return ["幸运儿", "在神秘箱子中获得银奖"]
	if score >= 2500 and not _got_mystery_gold and not _got_mystery_silver:
		return ["深海征服者", "未开出金奖、银奖且得分超过 2500"]
	if _is_collector():
		return ["收藏家", "集齐宝箱、金块与三条珍稀鱼"]
	if _bomb_ending:
		return ["烫手福袋", "被神秘箱子中开出的炸弹终结"]
	if _caught_all_kinds([Collectible.Kind.MYSTERY]):
		return ["秘宝猎手", "开启了所有神秘宝箱"]
	if _caught_all_fish():
		return ["捕鱼达人", "抓到了海里的每一条鱼"]
	if _caught_count([
		Collectible.Kind.COIN,
		Collectible.Kind.COIN_PILE,
		Collectible.Kind.NUGGET,
	]) >= 3:
		return ["淘金客", "捞到 3 个以上的金币或金块"]
	if _caught_count([
		Collectible.Kind.ROCK,
		Collectible.Kind.WELL,
		Collectible.Kind.POT,
		Collectible.Kind.BARREL,
	]) >= 3:
		return ["拾荒者", "捞到 3 个以上的石头、瓦罐或木桶"]
	if _shots > 0 and _shots == _hits:
		return ["神枪手", "每一次出爪都命中目标"]
	if score <= 0:
		return ["慈善家", "这一轮什么也没捞到"]
	return ["见习探索者", "继续探索海底吧"]
