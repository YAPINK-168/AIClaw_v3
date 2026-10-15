extends Control
class_name MinerTimeHud

const TEX_PANEL := preload("res://miner/assets/ui/time/time_panel.png")
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
const PATH_LAYOUT := "res://miner/assets/ui/time/time_panel_layout.json"

var _layout: Dictionary = {}
var _panel: TextureRect
var _digit_host: Control
var _digit_center: CenterContainer
var _digits: HBoxContainer
var _digit_nodes: Array[TextureRect] = []
var _ui_ready: bool = false
var _digit_h: float = 48.0
var _shown: int = 0


func _ready() -> void:
	_load_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	_apply_panel_size()
	_panel = TextureRect.new()
	_panel.name = "Panel"
	_panel.texture = TEX_PANEL
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_digit_host = Control.new()
	_digit_host.name = "DigitHost"
	_digit_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_digit_host)
	_digit_center = CenterContainer.new()
	_digit_center.name = "DigitCenter"
	_digit_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digit_host.add_child(_digit_center)
	var gap := int(_layout.get("digit_gap", -4))
	_digits = HBoxContainer.new()
	_digits.name = "Digits"
	_digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digits.add_theme_constant_override("separation", gap)
	_digits.alignment = BoxContainer.ALIGNMENT_CENTER
	_digit_center.add_child(_digits)
	for _i in 3:
		var d := TextureRect.new()
		d.visible = false
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_digits.add_child(d)
		_digit_nodes.append(d)
	_ui_ready = true
	call_deferred("_reflow_digits")
	set_value(0)


func _load_layout() -> void:
	if FileAccess.file_exists(PATH_LAYOUT):
		var f := FileAccess.open(PATH_LAYOUT, FileAccess.READ)
		if f != null:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary:
				_layout = data


func _panel_aspect() -> float:
	var ts: Array = _layout.get("texture_size", [1004, 697])
	return float(ts[0]) / maxf(float(ts[1]), 1.0)


func _apply_panel_size() -> void:
	var mr: float = float(_layout.get("margin_right", 10.0))
	var mt: float = float(_layout.get("margin_top", 4.0))
	var pw: float = float(_layout.get("display_width", 118.0))
	var order_edge: float = float(_layout.get("clear_of_order_right", 178.0))
	var gap_order: float = float(_layout.get("gap_to_order", 18.0))
	var max_pw: float = maxf(92.0, order_edge - mr - gap_order)
	pw = minf(pw, max_pw)
	var ph: float = pw / _panel_aspect()
	custom_minimum_size = Vector2(pw, ph)
	size = custom_minimum_size
	offset_left = -mr - pw
	offset_top = mt
	offset_right = -mr
	offset_bottom = mt + ph


func _digit_from_string(s: String, index: int) -> int:
	var code := s.unicode_at(index)
	if code >= 48 and code <= 57:
		return code - 48
	return 0


func _reflow_digits() -> void:
	if not _ui_ready or _digit_host == null:
		return
	var dr: Array = _layout.get("digit_rect", [0.50, 0.54, 0.80, 0.82])
	var off: Array = _layout.get("digit_offset", [0.0, 0.0])
	var pw: float = size.x
	var ph: float = size.y
	var left: float = pw * float(dr[0]) + float(off[0])
	var top: float = ph * float(dr[1]) + float(off[1])
	var right: float = pw * float(dr[2]) + float(off[0])
	var bottom: float = ph * float(dr[3]) + float(off[1])
	var box_h: float = maxf(bottom - top, 8.0)
	var h_scale: float = float(_layout.get("digit_height_scale", 0.76))
	_digit_h = box_h * h_scale
	_digit_host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_digit_host.offset_left = left
	_digit_host.offset_top = top
	_digit_host.offset_right = right
	_digit_host.offset_bottom = bottom
	_digit_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_digit_center.offset_left = 0.0
	_digit_center.offset_top = 0.0
	_digit_center.offset_right = 0.0
	_digit_center.offset_bottom = 0.0
	for node in _digit_nodes:
		if node.visible:
			_apply_digit_width(node, node.texture)


func _apply_digit_width(node: TextureRect, tex: Texture2D) -> void:
	if tex == null:
		return
	var tw := tex.get_width()
	var th := maxf(1.0, float(tex.get_height()))
	node.custom_minimum_size = Vector2(_digit_h * tw / th, _digit_h)


func set_value(seconds: int) -> void:
	if not _ui_ready:
		return
	_shown = maxi(0, seconds)
	var s := str(_shown)
	var need := s.length()
	for i in _digit_nodes.size():
		var node := _digit_nodes[i]
		if i >= need:
			node.visible = false
			continue
		var digit := _digit_from_string(s, i)
		node.texture = TEX_DIGITS[digit]
		node.visible = true
		_apply_digit_width(node, TEX_DIGITS[digit])
	call_deferred("_reflow_digits")


func set_urgent(urgent: bool) -> void:
	if _digits == null:
		return
	var col := Color(1.0, 0.42, 0.32) if urgent else Color.WHITE
	for node in _digit_nodes:
		node.modulate = col


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_reflow_digits")
