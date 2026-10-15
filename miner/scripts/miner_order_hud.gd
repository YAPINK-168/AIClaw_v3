extends Control
class_name MinerOrderHud

const TEX_PANEL := preload("res://miner/assets/ui/order/order_panel_bg.png")
const TEX_TIDE_GOLD := preload("res://miner/assets/ui/order/order_tide_gold.png")
const TEX_TIDE_TRACK := preload("res://miner/assets/ui/order/order_tide_track.png")
const TEX_TIDE_FILL := preload("res://miner/assets/ui/order/order_tide_fill.png")
const PATH_LAYOUT := "res://miner/assets/ui/order/order_panel_layout.json"
const PATH_TIDE_LAYOUT := "res://miner/assets/ui/order/order_tide_bar_layout.json"
## 1280×720。右上订单框
const MARGIN_RIGHT := 178.0
const BOX_TOP := 2.0
const MAX_BOX_W := 300.0
const MAX_BOX_H := 168.0

var _bg: TextureRect
var _icon_host: CenterContainer
var _title: Label
var _detail: Label
var _tide_root: Control
var _tide_gold: TextureRect
var _tide_track: TextureRect
var _tide_clip: Control
var _tide_fill: TextureRect
var _layout: Dictionary = {}
var _tide_layout: Dictionary = {}
var _tide_ratio: float = 0.0
var _bound: MinerOrderState


func get_panel_left() -> float:
	return global_position.x


func _ready() -> void:
	_load_layout()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	_apply_frame_size()
	_build()
	call_deferred("_reflow")


func _panel_pixel_size() -> Vector2:
	return Vector2(MAX_BOX_W, MAX_BOX_H)


func _apply_frame_size() -> void:
	var ps := _panel_pixel_size()
	offset_left = -MARGIN_RIGHT - ps.x
	offset_top = BOX_TOP
	offset_right = -MARGIN_RIGHT
	offset_bottom = BOX_TOP + ps.y
	custom_minimum_size = ps
	size = ps


func _load_layout() -> void:
	if FileAccess.file_exists(PATH_LAYOUT):
		var f := FileAccess.open(PATH_LAYOUT, FileAccess.READ)
		if f != null:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary:
				_layout = data
	if FileAccess.file_exists(PATH_TIDE_LAYOUT):
		var tf := FileAccess.open(PATH_TIDE_LAYOUT, FileAccess.READ)
		if tf != null:
			var tdata = JSON.parse_string(tf.get_as_text())
			tf.close()
			if tdata is Dictionary:
				_tide_layout = tdata


func _build() -> void:
	_bg = TextureRect.new()
	_bg.name = "PanelBg"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.texture = TEX_PANEL
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_icon_host = CenterContainer.new()
	_icon_host.name = "OrderIcon"
	_icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_host)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "订单"
	_title.clip_text = true
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_title(_title, 18)
	add_child(_title)
	_detail = Label.new()
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.clip_text = true
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_detail(_detail, 14)
	add_child(_detail)
	_tide_root = Control.new()
	_tide_root.name = "TideBar"
	_tide_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tide_root)
	_tide_gold = TextureRect.new()
	_tide_gold.name = "TideGold"
	_tide_gold.texture = TEX_TIDE_GOLD
	_tide_gold.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tide_gold.stretch_mode = TextureRect.STRETCH_SCALE
	_tide_gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tide_gold.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tide_track = TextureRect.new()
	_tide_track.name = "TideTrack"
	_tide_track.texture = TEX_TIDE_TRACK
	_tide_track.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tide_track.stretch_mode = TextureRect.STRETCH_SCALE
	_tide_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tide_root.add_child(_tide_track)
	_tide_clip = Control.new()
	_tide_clip.name = "TideClip"
	_tide_clip.clip_contents = true
	_tide_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tide_root.add_child(_tide_clip)
	_tide_fill = TextureRect.new()
	_tide_fill.texture = TEX_TIDE_FILL
	_tide_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tide_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_tide_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tide_clip.add_child(_tide_fill)
	_tide_root.add_child(_tide_gold)


func _tex_aspect(size_key: String, fallback: Vector2) -> float:
	var ts: Array = _tide_layout.get(size_key, [fallback.x, fallback.y])
	return float(ts[0]) / maxf(float(ts[1]), 1.0)


func _tide_gold_aspect() -> float:
	return _tex_aspect("texture_size", Vector2(984, 197))


func _fit_size_in_box(box_w: float, box_h: float, aspect: float) -> Vector2:
	if box_w <= 1.0 or box_h <= 1.0 or aspect <= 0.0:
		return Vector2(maxf(box_w, 1.0), maxf(box_h, 1.0))
	var w := box_w
	var h := w / aspect
	if h > box_h:
		h = box_h
		w = h * aspect
	return Vector2(w, h)


func _content_box(w: float, h: float) -> Dictionary:
	var cr: Array = _layout.get("content_rect", [0.14, 0.18, 0.86, 0.78])
	var left := w * float(cr[0])
	var top := h * float(cr[1])
	var right := w * float(cr[2])
	var bottom := h * float(cr[3])
	return {"left": left, "top": top, "right": right, "bottom": bottom, "w": right - left, "h": bottom - top}


func _reflow() -> void:
	if _title == null or _detail == null or _icon_host == null:
		return
	var fb := _panel_pixel_size()
	var w := size.x if size.x > 8.0 else fb.x
	var h := size.y if size.y > 8.0 else fb.y
	var box := _content_box(w, h)
	var pad := 4.0
	var box_h: float = float(box["h"])
	var box_top: float = float(box["top"])
	var box_left: float = float(box["left"])
	var box_right: float = float(box["right"])
	var box_w: float = float(box["w"])
	## 新面板自带装饰，默认不显示订单图标
	_icon_host.visible = false
	_title.visible = true
	_detail.visible = true
	var tac_pre: Array = _tide_layout.get("anchor_in_content", [0.08, 0.66, 0.92, 0.96])
	var tx0_pre: float = box_left + box_w * float(tac_pre[0])
	var tx1_pre: float = box_left + box_w * float(tac_pre[2])
	var tide_w_pre: float = maxf(tx1_pre - tx0_pre, 40.0)
	var gold_aspect: float = _tide_gold_aspect()
	var tide_h: float = tide_w_pre / gold_aspect
	## 进度条按金框贴图比例显示，与分件图同尺度（不再压到 52px）
	var min_tide_h: float = float(_tide_layout.get("min_bar_height", 34.0))
	var max_tide_h: float = float(_tide_layout.get("max_bar_height", 68.0))
	tide_h = clampf(tide_h, min_tide_h, max_tide_h)
	tide_w_pre = tide_h * gold_aspect
	var mid_x: float = (tx0_pre + tx1_pre) * 0.5
	tx0_pre = mid_x - tide_w_pre * 0.5
	tx1_pre = mid_x + tide_w_pre * 0.5
	var tide_y1: float = box_top + box_h - pad
	var tide_y0: float = tide_y1 - tide_h
	var upper_h: float = maxf(24.0, tide_y0 - box_top - pad)
	var title_h: float = clampf(upper_h * 0.48, 18.0, 40.0)
	var detail_h: float = maxf(14.0, upper_h - title_h - 2.0)
	var x0: float = box_left + pad
	var x1: float = box_right - pad
	var y0: float = box_top + pad
	_icon_host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_icon_host.offset_left = x0
	_icon_host.offset_top = y0
	_icon_host.offset_right = x1
	_icon_host.offset_bottom = y0
	_title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_title.offset_left = x0
	_title.offset_top = y0
	_title.offset_right = x1
	_title.offset_bottom = y0 + title_h
	var detail_top := y0 + title_h + 2.0
	_detail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_detail.offset_left = x0
	_detail.offset_top = detail_top
	_detail.offset_right = x1
	_detail.offset_bottom = detail_top + detail_h
	_detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	var tx0: float = tx0_pre
	var tx1: float = tx1_pre
	_tide_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tide_root.offset_left = tx0
	_tide_root.offset_top = tide_y0
	_tide_root.offset_right = tx1
	_tide_root.offset_bottom = tide_y1
	_layout_tide_layers()
	_apply_tide_fill()
	_fit_all_texts()


func _layout_tide_layers() -> void:
	if _tide_track == null or _tide_gold == null:
		return
	## 金框与棕槽同一外框、同一缩放，避免棕槽看起来比金框小一圈
	_tide_gold.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tide_gold.offset_left = 0.0
	_tide_gold.offset_top = 0.0
	_tide_gold.offset_right = 0.0
	_tide_gold.offset_bottom = 0.0
	_tide_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tide_track.offset_left = 0.0
	_tide_track.offset_top = 0.0
	_tide_track.offset_right = 0.0
	_tide_track.offset_bottom = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reflow()


func bind_order(state: MinerOrderState) -> void:
	_bound = state
	if state == null:
		visible = false
		return
	visible = true
	_title.text = state.title
	_detail.text = state.status_line()
	## 进度条跟订单，不跟潮汐：鲜鱼每多一种鱼 +1/3 格
	_tide_ratio = state.progress_ratio()
	_rebuild_icon(state)
	call_deferred("_reflow")
	call_deferred("_apply_tide_fill")


func set_ebb_bar_ratio(_r: float) -> void:
	## 兼容旧调用：订单条只反映订单进度，忽略潮汐比值
	if _bound != null:
		_tide_ratio = _bound.progress_ratio()
	_apply_tide_fill()


func _apply_tide_fill() -> void:
	if _tide_root == null or _tide_clip == null or _tide_fill == null:
		return
	var fw: float = _tide_root.size.x
	var fh: float = _tide_root.size.y
	if fw < 4.0 or fh < 4.0:
		return
	_layout_tide_layers()
	var fr: Array = _tide_layout.get("fill_rect", [0.055, 0.24, 0.945, 0.76])
	var fx0: float = float(fr[0])
	var fy0: float = float(fr[1])
	var fx1: float = float(fr[2])
	var fy1: float = float(fr[3])
	var fill_l: float = fx0 * fw
	var fill_t: float = fy0 * fh
	var fill_r: float = fx1 * fw
	var fill_b: float = fy1 * fh
	var fill_w: float = fill_r - fill_l
	var fill_h: float = fill_b - fill_t
	var ratio: float = clampf(_tide_ratio, 0.0, 1.0)
	var prog_w: float = fill_w * ratio
	if ratio > 0.0:
		prog_w = maxf(prog_w, 2.0)
	_tide_clip.visible = ratio > 0.001
	_tide_clip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tide_clip.offset_left = fill_l
	_tide_clip.offset_top = fill_t
	_tide_clip.offset_right = fill_l + prog_w
	_tide_clip.offset_bottom = fill_t + fill_h
	## 蓝条与棕槽同一内框尺寸，clip 从左向右裁进度
	_tide_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tide_fill.offset_left = 0.0
	_tide_fill.offset_top = 0.0
	_tide_fill.offset_right = fill_w
	_tide_fill.offset_bottom = fill_h


func _rebuild_icon(state: MinerOrderState) -> void:
	for c in _icon_host.get_children():
		c.queue_free()
	var ip := state.icon_path()
	if ip == "" or not ResourceLoader.exists(ip):
		return
	var tex := load(ip) as Texture2D
	if tex == null:
		return
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(40, 40)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := 28.0
	wrap.custom_minimum_size = Vector2(side, side)
	var icon := TextureRect.new()
	icon.texture = tex
	icon.custom_minimum_size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.modulate = state.icon_modulate()
	wrap.add_child(icon)
	var badge := Label.new()
	badge.text = state.icon_badge()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	badge.offset_top = -maxf(11.0, side * 0.42)
	if state.failed:
		badge.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
	elif state.complete:
		badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
	else:
		badge.add_theme_color_override("font_color", Color("FFD029"))
	badge.add_theme_color_override("font_outline_color", Color("784218"))
	badge.add_theme_constant_override("outline_size", 4)
	badge.add_theme_font_size_override("font_size", clampi(int(side * 0.32), 9, 14))
	wrap.add_child(badge)
	_icon_host.add_child(wrap)
	_fit_single_line(badge, badge.text, side, 18.0, 9, 14)


func _fit_all_texts() -> void:
	if _title == null or _detail == null:
		return
	var title_w := _title.offset_right - _title.offset_left
	var title_h := _title.offset_bottom - _title.offset_top
	var title_min := 11 if title_h < 28.0 else 14
	_fit_single_line(_title, _title.text, title_w, title_h, title_min, 28)
	var dw := _detail.offset_right - _detail.offset_left
	var dh := _detail.offset_bottom - _detail.offset_top
	_fit_single_line(_detail, _detail.text, dw, dh, 10, 18)


func _fit_single_line(l: Label, text: String, max_w: float, max_h: float, min_fs: int, max_fs: int) -> void:
	l.text = text
	var font := l.get_theme_font(&"font")
	if font == null:
		if l == _detail:
			_style_detail(l, clampi(max_fs, min_fs, max_fs))
		else:
			_style_title(l, clampi(max_fs, min_fs, max_fs))
		return
	var best := min_fs
	for fs in range(max_fs, min_fs - 1, -1):
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		if sz.x <= max_w and sz.y <= max_h:
			best = fs
			break
	if l == _detail:
		_style_detail(l, best)
	else:
		_style_title(l, best)


func _style_title(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("FFD029"))
	l.add_theme_color_override("font_outline_color", Color("5A2A10"))
	var outline := clampi(int(round(float(size) * 0.36)), 3, 10)
	l.add_theme_constant_override("outline_size", outline)


func _style_detail(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("6B2E1A"))
	l.add_theme_color_override("font_outline_color", Color("FFF4E0"))
	var outline := clampi(int(round(float(size) * 0.28)), 2, 8)
	l.add_theme_constant_override("outline_size", outline)
