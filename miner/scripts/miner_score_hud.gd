extends Control
class_name MinerScoreHud

const TEX_TITLE := preload("res://miner/assets/ui/score/score_title.png")
const TEX_DIGITS := [
	preload("res://miner/assets/ui/score/digit_0.png"),
	preload("res://miner/assets/ui/score/digit_1.png"),
	preload("res://miner/assets/ui/score/digit_2.png"),
	preload("res://miner/assets/ui/score/digit_3.png"),
	preload("res://miner/assets/ui/score/digit_4.png"),
	preload("res://miner/assets/ui/score/digit_5.png"),
	preload("res://miner/assets/ui/score/digit_6.png"),
	preload("res://miner/assets/ui/score/digit_7.png"),
	preload("res://miner/assets/ui/score/digit_8.png"),
	preload("res://miner/assets/ui/score/digit_9.png"),
]

const ROW_H := 52.0
const TITLE_GAP := 10.0
const DIGIT_GAP := -2.0
const MAX_DIGITS := 8

var _row: HBoxContainer
var _title: TextureRect
var _digits: HBoxContainer
var _digit_nodes: Array[TextureRect] = []
var _ui_ready: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(TITLE_GAP))
	_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_row)
	_title = TextureRect.new()
	_title.name = "Title"
	_title.texture = TEX_TITLE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.custom_minimum_size = Vector2(0.0, ROW_H)
	_row.add_child(_title)
	_digits = HBoxContainer.new()
	_digits.name = "Digits"
	_digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digits.add_theme_constant_override("separation", int(DIGIT_GAP))
	_digits.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_child(_digits)
	for _i in MAX_DIGITS:
		var d := TextureRect.new()
		d.visible = false
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.custom_minimum_size = Vector2(0.0, ROW_H)
		_digits.add_child(d)
		_digit_nodes.append(d)
	_ui_ready = true
	call_deferred("_sync_title_width")
	set_value(0)


func _digit_from_score_string(s: String, index: int) -> int:
	# Godot 4：String[i] 为 Unicode 码点，'0'..='9' → 48..57
	var code := s.unicode_at(index)
	if code >= 48 and code <= 57:
		return code - 48
	return 0


func _sync_title_width() -> void:
	if _title.texture == null:
		return
	var tex: Texture2D = _title.texture
	var tw := tex.get_width()
	var th := maxf(1.0, float(tex.get_height()))
	_title.custom_minimum_size.x = ROW_H * tw / th


func get_bounce_pivot() -> Vector2:
	var w := _row.size.x
	if w <= 1.0:
		w = custom_minimum_size.x
	return Vector2(w * 0.55, ROW_H * 0.5)


func set_value(value: int) -> void:
	if not _ui_ready:
		return
	var n := maxi(0, value)
	var s := str(n)
	var need := s.length()
	while _digit_nodes.size() < need:
		var d := TextureRect.new()
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		d.custom_minimum_size = Vector2(0.0, ROW_H)
		_digits.add_child(d)
		_digit_nodes.append(d)
	for i in _digit_nodes.size():
		var node := _digit_nodes[i]
		if i >= need:
			node.visible = false
			continue
		var digit := _digit_from_score_string(s, i)
		node.texture = TEX_DIGITS[digit]
		node.visible = true
		_apply_digit_width(node, TEX_DIGITS[digit])
	call_deferred("_reflow_row")


func _apply_digit_width(node: TextureRect, tex: Texture2D) -> void:
	if tex == null:
		return
	var tw := tex.get_width()
	var th := maxf(1.0, float(tex.get_height()))
	node.custom_minimum_size.x = ROW_H * tw / th


func _reflow_row() -> void:
	var w := 0.0
	for c in _row.get_children():
		if c is Control:
			w += (c as Control).size.x
	w += TITLE_GAP * maxf(0, _row.get_child_count() - 1)
	custom_minimum_size = Vector2(w, ROW_H)
	size = custom_minimum_size
