extends Node
class_name YouyouTestAudioVisemeDriver

## 测试场景专用：口型轮换跟随 AudioStreamPlayer 实际播放进度（含 pitch_scale 变速）。

const VISEMES: PackedStringArray = ["a", "e", "i", "o", "u"]
const FacePresenterScript := preload("res://Scripts/youyou_face_presenter.gd")

@export var interval_sec: float = 0.13

var _face: FacePresenterScript
var _player: AudioStreamPlayer
var _active := false
var _idx := 0
var _accum := 0.0
var _last_pos := 0.0
var _viseme_blend := 0.08


func setup(face: FacePresenterScript, player: AudioStreamPlayer) -> void:
	_face = face
	_player = player


func configure_viseme_blend(blend: float) -> void:
	_viseme_blend = maxf(blend, 0.0)


func start() -> void:
	_active = true
	_idx = 0
	_accum = 0.0
	_last_pos = 0.0
	if _player != null and _player.playing:
		_last_pos = _player.get_playback_position()


func stop(clear_duration: float = -1.0) -> void:
	_active = false
	if _face != null:
		var d := _viseme_blend if clear_duration < 0.0 else clear_duration
		_face.clear_viseme(d)


func is_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if not _active or _face == null or _player == null:
		return
	if not _player.playing:
		return
	var pos := _player.get_playback_position()
	var advanced := pos - _last_pos
	if advanced < 0.0:
		advanced = pos
	_last_pos = pos
	if advanced <= 0.0:
		return
	_accum += advanced
	var step := maxf(interval_sec, 0.04)
	while _accum >= step:
		_accum -= step
		_face.set_viseme(VISEMES[_idx], _viseme_blend)
		_idx = (_idx + 1) % VISEMES.size()
