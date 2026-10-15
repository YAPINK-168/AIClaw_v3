extends Control
## 圆柱转盘。卡片仍是两款，但结果固定停在深海寻宝。

signal spin_finished(game_id: String)

const VISIBLE_NOTE := "抓取失败 · 幸运抽游戏"
const FORCE_RESULT_ID := "miner"
const SPIN_DURATION := 3.2
const CARD_W := 200.0
const CARD_H := 250.0

const GAMES: Array[Dictionary] = [
	{"id": "plane", "title": "霓虹空战", "card": "res://assets/minigame_cards/card_plane.png"},
	{"id": "miner", "title": "深海寻宝", "card": "res://assets/minigame_cards/card_miner.png"},
]

const BGM_PATH := "res://audio/bgm_roulette.wav"
const SFX_START := "res://audio/roulette/sfx_start.wav"
const SFX_TICK := "res://audio/roulette/sfx_tick.wav"
const SFX_STOP := "res://audio/roulette/sfx_stop.wav"

var _textures: Array[Texture2D] = []
var _titles: PackedStringArray = PackedStringArray()
var _ids: PackedStringArray = PackedStringArray()
var _spinning := false
var _spin_t := 0.0
var _offset := 0.0
var _start_offset := 0.0
var _end_offset := 0.0
var _result_index := 0
var _pulse := 0.0
var _prev_offset := 0.0
var _bgm: AudioStreamPlayer
var _sfx: AudioStreamPlayer
var _tick: AudioStream


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	_load_catalog()
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "RouletteBgm"
	add_child(_bgm)
	if ResourceLoader.exists(BGM_PATH):
		var bgm := load(BGM_PATH) as AudioStream
		if bgm != null:
			bgm = bgm.duplicate()
			if bgm is AudioStreamWAV:
				(bgm as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			_bgm.stream = bgm
			_bgm.volume_db = -9.0
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "RouletteSfx"
	add_child(_sfx)
	if ResourceLoader.exists(SFX_TICK):
		_tick = load(SFX_TICK) as AudioStream


func _load_catalog() -> void:
	_textures.clear()
	_titles.clear()
	_ids.clear()
	for g in GAMES:
		_ids.append(str(g["id"]))
		_titles.append(str(g["title"]))
		var path := str(g.get("card", ""))
		var tex: Texture2D = null
		if path != "" and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		_textures.append(tex)


func is_spinning() -> bool:
	return _spinning


func start_spin() -> void:
	if _ids.is_empty():
		_load_catalog()
	visible = true
	_spinning = true
	_spin_t = 0.0
	_start_offset = _offset
	var n := _ids.size()
	var target := 0
	for i in n:
		if _ids[i] == FORCE_RESULT_ID:
			target = i
			break
	_result_index = target
	var loops := 4 + randi() % 3
	var desired := float(loops * n + target)
	var cur_mod := fposmod(_offset, float(n))
	_end_offset = _offset + (desired - cur_mod)
	if _end_offset <= _offset:
		_end_offset += float(n)
	_prev_offset = _offset
	_play_sfx(SFX_START, 1.0)
	if _bgm.stream != null:
		_bgm.play()
	set_process(true)
	queue_redraw()


func stop_audio() -> void:
	if _bgm != null:
		_bgm.stop()
	if _sfx != null:
		_sfx.stop()


func _process(delta: float) -> void:
	_pulse += delta
	if not _spinning:
		queue_redraw()
		return
	_spin_t += delta
	var u := clampf(_spin_t / SPIN_DURATION, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 3.0)
	_offset = lerpf(_start_offset, _end_offset, e)
	_emit_scroll_ticks(e)
	queue_redraw()
	if u >= 1.0:
		_spinning = false
		_offset = _end_offset
		_prev_offset = _offset
		_play_sfx(SFX_STOP, 1.0)
		set_process(true)
		var gid := _ids[_result_index]
		spin_finished.emit(gid)


func _emit_scroll_ticks(ease_out: float) -> void:
	var prev_floor := int(floor(_prev_offset))
	var cur_floor := int(floor(_offset))
	if cur_floor > prev_floor:
		var steps := mini(cur_floor - prev_floor, 8)
		for _i in steps:
			_play_tick(ease_out)
	_prev_offset = _offset


func _play_tick(ease_out: float) -> void:
	if _sfx == null or _tick == null:
		return
	_sfx.stream = _tick
	_sfx.pitch_scale = lerpf(1.1, 0.78, clampf(ease_out, 0.0, 1.0))
	_sfx.volume_db = -6.0
	_sfx.play()


func _play_sfx(path: String, pitch: float) -> void:
	if _sfx == null or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.pitch_scale = pitch
	_sfx.volume_db = -4.0
	_sfx.play()


func _draw() -> void:
	var rect := get_rect()
	var cx := rect.size.x * 0.5
	var cy := rect.size.y * 0.5 + 10.0
	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.78, 0.62, 0.42, 0.92), true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(cx - 140, 48), VISIBLE_NOTE, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("6B4F3A"))
	draw_string(font, Vector2(cx - 150, 82), "圆柱滚动，这一次只会抽中深海寻宝", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.55, 0.4, 0.3, 1))
	var n := maxi(1, _ids.size())
	var radius := 210.0
	for i in n:
		var slot := float(i) - fposmod(_offset, float(n))
		while slot > n * 0.5:
			slot -= float(n)
		while slot < -n * 0.5:
			slot += float(n)
		var angle := slot * (TAU / float(n))
		if absf(angle) > PI * 0.55:
			continue
		var depth := cos(angle)
		var x := cx + sin(angle) * radius
		var scale := 0.55 + 0.45 * depth
		var alpha := clampf(0.25 + 0.75 * depth, 0.2, 1.0)
		var w := CARD_W * scale
		var h := CARD_H * scale
		var y := cy - h * 0.5 + (1.0 - depth) * 18.0
		var card_r := Rect2(x - w * 0.5, y, w, h)
		_draw_card(card_r, i, alpha, depth > 0.92)
	var frame := Rect2(cx - CARD_W * 0.55, cy - CARD_H * 0.55, CARD_W * 1.1, CARD_H * 1.1)
	var glow := 0.55 + 0.45 * sin(_pulse * 6.0)
	draw_rect(frame, Color(0.91, 0.72, 0.43, 0.35 + 0.25 * glow), false, 4.0)
	draw_rect(frame.grow(6.0), Color(0.83, 0.54, 0.29, 0.55), false, 2.0)
	if not _spinning:
		var title := _titles[_result_index] if _result_index < _titles.size() else ""
		draw_string(font, Vector2(cx - 80, rect.size.y - 70), "抽中：%s" % title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("D4894A"))
		draw_string(font, Vector2(cx - 150, rect.size.y - 40), "按 Ctrl+G 或空格开始", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("6B4F3A"))


func _draw_card(r: Rect2, index: int, alpha: float, selected: bool) -> void:
	var bg := Color(1.0, 0.97, 0.92, alpha)
	var border := Color(0.91, 0.72, 0.43, alpha)
	if selected:
		border = Color(0.83, 0.54, 0.29, alpha)
	draw_rect(r, bg, true)
	draw_rect(r, border, false, 3.0 if selected else 2.0)
	var tex: Texture2D = _textures[index] if index < _textures.size() else null
	if tex:
		var pad := 10.0
		var tr := Rect2(r.position + Vector2(pad, pad), r.size - Vector2(pad * 2.0, pad * 2.0 + 36.0))
		draw_texture_rect(tex, tr, false, Color(1, 1, 1, alpha))
	var font := ThemeDB.fallback_font
	var title := _titles[index] if index < _titles.size() else ""
	var fs := 18 if selected else 14
	draw_string(font, r.position + Vector2(16, r.size.y - 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.42, 0.31, 0.23, alpha))
