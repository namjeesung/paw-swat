extends Node
## 物理帧计时：priority 最小的节点记开始，最大的记结束
static var t0 := 0
static var acc := 0
static var steps := 0
var last := false
func _ready() -> void:
	process_physics_priority = 100000 if last else -100000
func _physics_process(_d: float) -> void:
	if not last:
		t0 = Time.get_ticks_usec()
	else:
		acc += Time.get_ticks_usec() - t0
		steps += 1
