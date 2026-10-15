extends Node
## 血月冲刷：低价值沿沙面滑出，高价值留下，新高价值从潮向滑入。

const OUT_KINDS: Array[Collectible.Kind] = [
	Collectible.Kind.ROCK,
	Collectible.Kind.COIN,
	Collectible.Kind.WELL,
	Collectible.Kind.POT,
	Collectible.Kind.BARREL,
	Collectible.Kind.SHELL,
]
const STAY_KINDS: Array[Collectible.Kind] = [
	Collectible.Kind.COIN_PILE,
	Collectible.Kind.GEM,
	Collectible.Kind.PEARL,
	Collectible.Kind.NUGGET,
	Collectible.Kind.CHEST,
]
const INCOMING_COUNT := 10
const IN_VIEW_COUNT := 7
const VIEW_HALF := 520.0


func begin(items_root: Node2D, fish_root: Node2D, world_w: float, view_center_x: float, order: MinerOrderState) -> void:
	var dir := 1.0 if randf() < 0.5 else -1.0
	var keep_coins := order != null and order.kind == MinerOrderState.Kind.COIN_RUSH
	var leaving: Array[Collectible] = []
	var staying: Array[Collectible] = []
	for node in items_root.get_children():
		var item := node as Collectible
		if item == null or item.grabbed or item.kind == Collectible.Kind.FISH:
			continue
		if _leaves(item, keep_coins):
			leaving.append(item)
		elif item.kind in STAY_KINDS or (keep_coins and item.kind == Collectible.Kind.COIN):
			staying.append(item)
	for item in leaving:
		var game := _game()
		if game:
			game._unregister_spawn_placement(item.position)
		_slide_out(item, dir, world_w)
	if fish_root != null:
		for node in fish_root.get_children():
			var fish := node as Collectible
			if fish == null or fish.grabbed:
				continue
			_slide_out(fish, dir, world_w)
	for item in staying:
		_flash_stay(item)
	_slide_in(world_w, view_center_x, dir)
	_run_current(items_root, world_w, dir)


func _leaves(item: Collectible, keep_coins: bool) -> bool:
	if item.kind == Collectible.Kind.MYSTERY:
		return false
	if keep_coins and item.kind == Collectible.Kind.COIN:
		return false
	return item.kind in OUT_KINDS


func _slide_out(item: Collectible, dir: float, world_w: float) -> void:
	item.begin_tide_slide()
	var along := clampf(item.position.x / maxf(world_w, 1.0), 0.0, 1.0)
	if dir < 0.0:
		along = 1.0 - along
	var end_x := world_w + 180.0 if dir > 0.0 else -180.0
	var lean := dir * deg_to_rad(14.0)
	var dist := absf(end_x - item.position.x)
	var dur := clampf(dist / 1500.0, 0.55, 1.15)
	var tw := create_tween()
	tw.tween_property(item, "rotation", lean, 0.28)
	tw.parallel().tween_property(item, "modulate", Color(1.28, 0.72, 0.78), 0.28)
	tw.tween_interval(along * 0.28)
	tw.tween_property(item, "position:x", end_x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(item, "rotation", lean * 1.7, dur)
	tw.parallel().tween_property(item, "modulate:a", 0.0, 0.26).set_delay(maxf(dur - 0.26, 0.0))
	tw.tween_callback(_free_item.bind(item))


func _flash_stay(item: Collectible) -> void:
	var base := item.scale
	var tw := create_tween()
	tw.tween_property(item, "scale", base * Vector2(1.08, 0.9), 0.12)
	tw.parallel().tween_property(item, "modulate", Color(1.45, 0.95, 1.05), 0.12)
	tw.tween_property(item, "scale", base * Vector2(0.98, 1.06), 0.1)
	tw.tween_property(item, "scale", base, 0.12)
	tw.parallel().tween_property(item, "modulate", Color.WHITE, 0.12)


func _slide_in(world_w: float, view_center_x: float, dir: float) -> void:
	var game := _game()
	if game == null:
		return
	var margin := 80.0
	var view_min := clampf(view_center_x - VIEW_HALF, margin, world_w - margin)
	var view_max := clampf(view_center_x + VIEW_HALF, margin, world_w - margin)
	if view_max <= view_min + 40.0:
		view_min = margin
		view_max = world_w - margin
	var chest_used := false
	for i in INCOMING_COUNT:
		var kind := _roll_incoming(chest_used)
		if kind == Collectible.Kind.CHEST:
			chest_used = true
		var in_view := i < IN_VIEW_COUNT
		var x := randf_range(view_min, view_max) if in_view else randf_range(margin, world_w - margin)
		var desired := Vector2(x, game._random_y_for_kind(kind))
		var item: Collectible = game._spawn_collectible(kind, desired)
		if item == null:
			continue
		var dest := item.position
		item.begin_tide_slide()
		item.modulate.a = 0.0
		item.position.x = -160.0 if dir > 0.0 else world_w + 160.0
		var tw := create_tween()
		tw.tween_interval(0.55 + float(i) * 0.08)
		tw.tween_property(item, "modulate:a", 1.0, 0.22)
		tw.parallel().tween_property(item, "position:x", dest.x, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(item, "scale", Vector2(1.06, 0.92), 0.08)
		tw.tween_property(item, "scale", Vector2.ONE, 0.1)
		tw.tween_callback(_settle_item.bind(item))


func _roll_incoming(chest_used: bool) -> Collectible.Kind:
	var roll := randi() % 100
	if roll < 40:
		return Collectible.Kind.GEM
	if roll < 70:
		return Collectible.Kind.PEARL
	if roll < 90:
		return Collectible.Kind.NUGGET
	if not chest_used:
		return Collectible.Kind.CHEST
	return Collectible.Kind.GEM


func _run_current(items_root: Node2D, world_w: float, dir: float) -> void:
	var bands: Array[float] = [470.0, 560.0, 650.0]
	for i in bands.size():
		var band := Polygon2D.new()
		var w := 480.0
		var h := 28.0
		band.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)
		])
		band.color = Color(0.95, 0.32, 0.48, 0.2)
		band.z_as_relative = true
		band.z_index = -5
		items_root.add_child(band)
		var from_x := -w if dir > 0.0 else world_w
		var to_x := world_w if dir > 0.0 else -w
		band.position = Vector2(from_x, bands[i])
		var tw := create_tween()
		tw.tween_property(band, "position:x", to_x, 1.65).set_delay(0.32 + float(i) * 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(band.queue_free)


func _free_item(item: Collectible) -> void:
	if is_instance_valid(item):
		item.queue_free()


func _settle_item(item: Collectible) -> void:
	if is_instance_valid(item):
		item.end_tide_slide()


func _game() -> Node:
	var parent := get_parent()
	if parent and parent.has_method("_spawn_collectible"):
		return parent
	return null
