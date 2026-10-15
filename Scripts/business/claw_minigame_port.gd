extends Node
class_name ClawMinigamePort

## 给已经做好的小游戏用的接口。业务只负责打开和接收结束，不负责小游戏里面怎么玩。

signal finished(token: int, another_grab: bool)
signal opened(token: int)

var active_token := 0


func open_minigame(token: int) -> void:
	active_token = token
	opened.emit(token)


func notify_finished(another_grab: bool) -> void:
	finished.emit(active_token, another_grab)
