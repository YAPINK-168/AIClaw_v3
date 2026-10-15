class_name MinerBgVideo
extends CanvasLayer
## 62 秒局时：单条背景视频；加时阶段循环片尾 12 秒。

signal boot_finished(ok: bool)

const VIDEO_PATH := "res://miner/assets/video/miner_bg.ogv"
## 与 miner_bg.ogv / 局时一致；Theora 的 get_stream_length() 常偏小，seek 以此为准。
const STREAM_DURATION := 62.02
const ROUND_TIME := STREAM_DURATION
## Theora 逐帧 seek 很吃 CPU；平时让播放器自己走，只在大漂移时校正。
const SYNC_DRIFT := 0.32
const SYNC_DRIFT_TAIL := 0.14
const TAIL_SYNC_FROM := 58.5
const MIN_RESYNC_INTERVAL := 0.45
const STALL_TAIL_FROM := 57.5
const OVERTIME_LOOP_SEC := 12.0

var _root: Control
var _display: TextureRect
var _player: VideoStreamPlayer
var _stream: VideoStream
var _last_play_elapsed: float = -1.0
var _last_video_t: float = -1.0
var _last_resync_time: float = -999.0
var _booted: bool = false
var _load_warned: bool = false


func _ready() -> void:
	layer = -1
	visible = true
	follow_viewport_enabled = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_display = _make_display("Display")
	_player = _make_player("Video")
	get_viewport().size_changed.connect(_fit_players)
	call_deferred("_boot")


func _process(_delta: float) -> void:
	if not _booted:
		return
	_sync_display(_display, _player)


func stop_playback() -> void:
	_booted = false
	if _player:
		_player.stop()
	if _display:
		_display.texture = null


func restart_for_round() -> void:
	visible = true
	_stream = _open_video_stream()
	call_deferred("_boot")


func _boot() -> void:
	_fit_players()
	if _stream == null:
		_stream = _open_video_stream()
	var ok := _stream != null
	if not ok and not _load_warned:
		_load_warned = true
		push_error("MinerBgVideo: 无法加载 %s" % VIDEO_PATH)
	if ok:
		_player.stream = _stream
		_player.play()
	_booted = ok
	reset_timeline()
	call_deferred("_finish_boot")


func _open_video_stream() -> VideoStream:
	return _stream_from_path(VIDEO_PATH)


func _stream_from_path(path: String) -> VideoStream:
	if not _res_path_exists(path):
		return null
	if path.ends_with(".ogv"):
		return _theora_stream(path)
	var loaded: Variant = ResourceLoader.load(path, "VideoStream", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is VideoStream:
		return loaded as VideoStream
	loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if loaded is VideoStream:
		return loaded as VideoStream
	return null


func _res_path_exists(path: String) -> bool:
	if ResourceLoader.exists(path):
		return true
	return FileAccess.file_exists(path)


func _finish_boot() -> void:
	var theora_ok := ClassDB.class_exists("VideoStreamTheora")
	var frames_ok := false
	for i in 8:
		await get_tree().process_frame
		frames_ok = _player_has_frames(_player)
		if frames_ok:
			break
	var ok := _booted and frames_ok
	if _booted and not frames_ok:
		push_warning(
			"MinerBgVideo: 流已加载但无画面帧，请检查 ogv 编码或渲染器。"
		)
	_write_boot_diag(theora_ok, ok, frames_ok)
	boot_finished.emit(ok)


func _player_has_frames(player: VideoStreamPlayer) -> bool:
	if player == null or not player.is_playing():
		return false
	var tex: Texture2D = player.get_video_texture()
	return tex != null and tex.get_width() > 2 and tex.get_height() > 2


func _theora_stream(path: String) -> VideoStream:
	if not ClassDB.class_exists("VideoStreamTheora"):
		push_warning("MinerBgVideo: VideoStreamTheora unavailable in this build")
		return null
	var inst: Variant = ClassDB.instantiate("VideoStreamTheora")
	if inst == null or not (inst is VideoStream):
		return null
	var stream := inst as VideoStream
	stream.set("file", path)
	return stream


func _write_boot_diag(theora_ok: bool, ok: bool, frames_ok: bool = false) -> void:
	var tex: Texture2D = null
	if _player:
		tex = _player.get_video_texture()
	var tex_sz: Vector2i = tex.get_size() if tex != null else Vector2i.ZERO
	var lines := PackedStringArray([
		"MinerBgVideo boot diag",
		"path=%s exists=%s" % [VIDEO_PATH, _res_path_exists(VIDEO_PATH)],
		"theora_class=%s stream=%s booted=%s ok=%s"
		% [theora_ok, _stream != null, _booted, ok],
		"frames_ok=%s tex_size=%s playing=%s"
		% [frames_ok, tex_sz, _player.is_playing() if _player else false],
	])
	var text := "\n".join(lines) + "\n"
	print(text)
	var f := FileAccess.open("user://miner_bg_video_diag.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _make_display(node_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(t)
	return t


func _sync_display(rect: TextureRect, player: VideoStreamPlayer) -> void:
	if rect == null or player == null:
		return
	var tex: Texture2D = player.get_video_texture()
	if tex != null:
		rect.texture = tex
	rect.visible = rect.texture != null


func _make_player(node_name: String) -> VideoStreamPlayer:
	var p := VideoStreamPlayer.new()
	p.name = node_name
	p.expand = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.bus = &"Master"
	p.volume_db = -80.0
	p.autoplay = false
	p.visible = false
	p.size = Vector2(16, 16)
	_root.add_child(p)
	return p


func _fit_players() -> void:
	var sz := get_viewport().get_visible_rect().size
	if sz.x < 2.0 or sz.y < 2.0:
		sz = Vector2(1280.0, 720.0)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.set_size(sz)
	_root.set_position(Vector2.ZERO)
	if _display:
		_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_display.set_size(sz)
		_display.set_position(Vector2.ZERO)


func has_playback() -> bool:
	return _booted and _stream != null


func is_ready_playback() -> bool:
	return has_playback()


func reset_timeline() -> void:
	_last_play_elapsed = -1.0
	_last_video_t = -1.0
	_last_resync_time = -999.0
	if _booted:
		sync(0.0, true)


func sync(play_elapsed: float, force: bool = false) -> void:
	if not _booted or _player == null:
		return
	play_elapsed = maxf(0.0, play_elapsed)
	var video_t := _map_to_video_time(play_elapsed)
	if not force and absf(play_elapsed - _last_play_elapsed) < 0.008:
		return
	var loop_wrap := (
		_last_video_t >= 0.0
		and video_t + 0.4 < _last_video_t
		and play_elapsed > STREAM_DURATION
	)
	_last_play_elapsed = play_elapsed
	_last_video_t = video_t
	if force or loop_wrap:
		_resync_to(video_t, true)
	else:
		_follow_game_clock(play_elapsed, video_t)
	_keep_playing_through_end(_player, play_elapsed)


func _map_to_video_time(play_elapsed: float) -> float:
	if play_elapsed <= STREAM_DURATION:
		return play_elapsed
	var loop_len := minf(OVERTIME_LOOP_SEC, STREAM_DURATION)
	var loop_start := maxf(0.0, STREAM_DURATION - loop_len)
	return loop_start + fmod(play_elapsed - STREAM_DURATION, loop_len)


func _follow_game_clock(play_elapsed: float, video_t: float) -> void:
	var pos := _player.stream_position
	var drift := absf(pos - video_t)
	var in_overtime := play_elapsed > STREAM_DURATION
	var drift_limit := SYNC_DRIFT_TAIL if video_t >= TAIL_SYNC_FROM or in_overtime else SYNC_DRIFT
	var now := Time.get_ticks_msec() * 0.001
	var interval_ok := (now - _last_resync_time) >= MIN_RESYNC_INTERVAL
	if in_overtime:
		drift_limit = 0.18
		interval_ok = (now - _last_resync_time) >= 0.28
	if drift > drift_limit * 2.2:
		_resync_to(video_t, true)
	elif drift > drift_limit and interval_ok:
		_resync_to(video_t, false)
	elif video_t >= STALL_TAIL_FROM or in_overtime:
		_fix_tail_stall(video_t, now)


func _fix_tail_stall(video_t: float, now: float) -> void:
	var pos := _player.stream_position
	var stalled := not _player.is_playing()
	var behind := pos + 0.35 < video_t
	if not stalled and not behind:
		return
	if (now - _last_resync_time) < 0.22:
		return
	_resync_to(video_t, true)


func _resync_to(video_t: float, force: bool) -> void:
	_seek_player(_player, video_t, force)
	_last_resync_time = Time.get_ticks_msec() * 0.001


func _playback_duration(_player: VideoStreamPlayer) -> float:
	var len := _player.get_stream_length()
	if len > STREAM_DURATION * 0.98:
		return len
	return STREAM_DURATION


func _keep_playing_through_end(player: VideoStreamPlayer, play_elapsed: float) -> void:
	if play_elapsed > STREAM_DURATION:
		if not player.is_playing():
			player.play()
		return
	var end_t := _playback_duration(player)
	if play_elapsed >= end_t - 0.05:
		return
	if not player.is_playing():
		player.play()


func _seek_player(player: VideoStreamPlayer, local_t: float, force: bool = false) -> void:
	var end_t := _playback_duration(player)
	local_t = clampf(local_t, 0.0, end_t)
	if not player.is_playing():
		player.play()
	var eps := 0.04 if force else 0.12
	if absf(player.stream_position - local_t) < eps:
		return
	player.stream_position = local_t
