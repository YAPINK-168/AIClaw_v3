class_name MysteryLoot
extends RefCounted

enum Id {
	EXTRA_GRAB,
	SCORE_10000,
	DOLL,
	COINS_10,
	SCORE_1000,
	SCORE_1500,
	SCORE_2000,
	TIME_10,
	SCORE_100,
	SCORE_200,
	SCORE_300,
	MUD,
	BOMB,
	SWARM,
	WARP,
}

var id: int = Id.SCORE_100
var title: String = "铜奖"
var detail: String = "100积分"
var score: int = 0
var is_punish: bool = false
var origin: Vector2 = Vector2.ZERO


func banner() -> String:
	return "%s  %s" % [title, detail]


func banner_color() -> Color:
	if is_punish:
		return Color(1.0, 0.42, 0.32)
	if title == "金奖":
		return Color(1.0, 0.84, 0.28)
	if title == "银奖":
		return Color(0.86, 0.92, 1.0)
	return Color(1.0, 0.72, 0.38)


static func roll() -> MysteryLoot:
	var table: Array = [
		[7, Id.EXTRA_GRAB, "金奖", "再抓一次", 0, false],
		[3, Id.SCORE_10000, "金奖", "10000积分", 10000, false],
		[3, Id.DOLL, "金奖", "娃娃一个", 0, false],
		[7, Id.COINS_10, "金奖", "10游戏币", 0, false],
		[50, Id.SCORE_1000, "银奖", "1000积分", 1000, false],
		[40, Id.SCORE_1500, "银奖", "1500积分", 1500, false],
		[20, Id.SCORE_2000, "银奖", "2000积分", 2000, false],
		[70, Id.TIME_10, "银奖", "游戏时间+10秒", 0, false],
		[170, Id.SCORE_100, "铜奖", "100积分", 100, false],
		[150, Id.SCORE_200, "铜奖", "200积分", 200, false],
		[80, Id.SCORE_300, "铜奖", "300积分", 300, false],
		[100, Id.MUD, "惩罚", "泥巴", 0, true],
		[100, Id.BOMB, "惩罚", "炸弹", 0, true],
		[100, Id.SWARM, "惩罚", "干扰", 0, true],
		[100, Id.WARP, "惩罚", "迷幻", 0, true],
	]
	var pick := randi() % 1000
	var acc := 0
	for row in table:
		acc += int(row[0])
		if pick < acc:
			return _make(row[1], row[2], row[3], row[4], row[5])
	return _make(Id.SCORE_100, "铜奖", "100积分", 100, false)


static func _make(p_id: int, p_title: String, p_detail: String, p_score: int, p_punish: bool) -> MysteryLoot:
	var loot := MysteryLoot.new()
	loot.id = p_id
	loot.title = p_title
	loot.detail = p_detail
	loot.score = p_score
	loot.is_punish = p_punish
	return loot
