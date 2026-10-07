extends Node
## 入口：把自己交给 Game 作为界面容器。

func _ready() -> void:
	Game.boot(self)
