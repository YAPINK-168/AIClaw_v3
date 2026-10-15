class_name VisemeProceduralDriver
extends Node

## 近似口型：播放期间轮换 A/E/I/O/U，非真实音素对齐。

const VISEMES: PackedStringArray = ["a", "e", "i", "o", "u"]
const FacePresenterScript := preload("res://Scripts/youyou_face_presenter.gd")

@export var interval_sec: float = 0.13
@export var viseme_blend: float = 0.08

var _face: FacePresenterScript
var _player: AudioStreamPlayer
var _active := false
var _idx := 0
var _timer := 0.0


func setup(face: FacePresenterScript, player: AudioStreamPlayer) -> void:
	_face = face
	_player = player


func start() -> void:
	_active = true
	_idx = 0
	_timer = 0.0


func stop() -> void:
	_active = false
	if _face != null:
		_face.clear_viseme(viseme_blend)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active or _face == null or _player == null:
		return
	if not _player.playing:
		return
	_timer += delta
	if _timer < interval_sec:
		return
	_timer = 0.0
	_face.set_viseme(VISEMES[_idx], viseme_blend)
	_idx = (_idx + 1) % VISEMES.size()
