extends RefCounted
class_name MinerOrderState
## 订单逻辑占位（P0）：局内跟踪进度，结算倍率后续接。

enum Kind { FISH_VARIETY, NO_ROCK, COIN_RUSH }

const ICON_FISH := "res://miner/assets/ui/order/order_icon_fish_variety.png"
const ICON_NO_ROCK := "res://miner/assets/ui/order/order_icon_no_rock.png"
const ICON_COIN := "res://miner/assets/ui/order/order_icon_coin_rush.png"

var kind: Kind = Kind.FISH_VARIETY
var title: String = ""
var detail: String = ""
var slot_labels: PackedStringArray = PackedStringArray()
var slot_done: Array[bool] = []
var failed: bool = false
var complete: bool = false

var _fish_seen: Dictionary = {}
var _coin_count: int = 0


static func roll() -> MinerOrderState:
	var o := MinerOrderState.new()
	var pick := randi() % 3
	match pick:
		0:
			o.kind = Kind.FISH_VARIETY
			o.title = "订单：三种鲜鱼"
			o.detail = "抓 3 条不同种类的鱼"
			o.slot_labels = PackedStringArray(["鱼 A", "鱼 B", "鱼 C"])
		1:
			o.kind = Kind.NO_ROCK
			o.title = "订单：避开顽石"
			o.detail = "本局不要抓石头或木桶"
			o.slot_labels = PackedStringArray(["禁石头", "禁木桶"])
		_:
			o.kind = Kind.COIN_RUSH
			o.title = "订单：淘金"
			o.detail = "抓 5 个金币或钱堆"
			o.slot_labels = PackedStringArray(["×5"])
	o.slot_done.resize(o.slot_labels.size())
	for i in o.slot_done.size():
		o.slot_done[i] = false
	return o


func on_catch(item: Collectible) -> void:
	if complete or failed:
		return
	match kind:
		Kind.FISH_VARIETY:
			if item.kind != Collectible.Kind.FISH:
				return
			_fish_seen[item.fish_index] = true
			var n := _fish_seen.size()
			for i in mini(n, slot_done.size()):
				slot_done[i] = true
			if n >= slot_done.size():
				complete = true
		Kind.NO_ROCK:
			if item.kind == Collectible.Kind.ROCK or item.kind == Collectible.Kind.BARREL:
				failed = true
				for i in slot_done.size():
					slot_done[i] = false
		Kind.COIN_RUSH:
			if item.kind == Collectible.Kind.COIN or item.kind == Collectible.Kind.COIN_PILE:
				_coin_count += 1
				if slot_done.size() > 0:
					slot_done[0] = _coin_count >= 5
				if _coin_count >= 5:
					complete = true


func multiplier() -> float:
	if failed:
		return 0.6
	if complete:
		return 1.4
	return 1.0


func status_line() -> String:
	if failed:
		return "订单失败 · 倍率 ×%.1f" % multiplier()
	if complete:
		return "订单完成 · 倍率 ×%.1f" % multiplier()
	return detail


func icon_path() -> String:
	match kind:
		Kind.FISH_VARIETY:
			return ICON_FISH
		Kind.NO_ROCK:
			return ICON_NO_ROCK
		Kind.COIN_RUSH:
			return ICON_COIN
	return ""


func coin_count() -> int:
	return _coin_count


func icon_badge() -> String:
	match kind:
		Kind.FISH_VARIETY:
			return "%d/3" % _fish_seen.size()
		Kind.NO_ROCK:
			if failed:
				return "×"
			if complete:
				return "✓"
			return "○"
		Kind.COIN_RUSH:
			return "%d/5" % _coin_count
	return ""


func icon_modulate() -> Color:
	if failed:
		return Color(1.0, 0.45, 0.38, 0.95)
	if complete:
		return Color(0.75, 1.0, 0.82, 1.0)
	return Color(1, 1, 1, 1)


func progress_ratio() -> float:
	match kind:
		Kind.FISH_VARIETY:
			return clampf(float(_fish_seen.size()) / 3.0, 0.0, 1.0)
		Kind.NO_ROCK:
			if failed:
				return 0.0
			return 1.0
		Kind.COIN_RUSH:
			return clampf(float(_coin_count) / 5.0, 0.0, 1.0)
	return 0.0
