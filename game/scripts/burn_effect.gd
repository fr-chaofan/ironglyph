## 灼燒：附在目標身上按節拍持續扣血（炩・炩明）。
##
## 做成一個掛在目標底下的節點，而不是一整套狀態系統——目前只有一個來源，
## 為它建狀態框架是過度設計。日後若有第二、第三種持續效果再抽共用層。
##
## ⚠️ 同一個目標**不會疊加多層**：重複命中只重置剩餘跳數，
## 否則連射的火屬武器會讓灼燒無限累積，傷害完全失控。
class_name BurnEffect
extends Node

const GROUP := &"burn_effect"

var damage: int = 3
var ticks_left: int = 3
var interval: float = 0.5
var element: String = "fire"

var _timer: float = 0.0


## 對目標施加灼燒。已經在燒的話只刷新，不疊加。
static func apply(target: Node, config: Dictionary, element_name: String) -> BurnEffect:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return null

	for child: Node in target.get_children():
		if child is BurnEffect:
			var existing := child as BurnEffect
			existing.ticks_left = int(config.get("ticks", 3))
			return existing

	var burn := BurnEffect.new()
	burn.add_to_group(GROUP)
	burn.damage = int(config.get("damage", 3))
	burn.ticks_left = int(config.get("ticks", 3))
	burn.interval = float(config.get("interval", 0.5))
	burn.element = element_name
	target.add_child(burn)
	return burn


func _process(delta: float) -> void:
	_timer += delta
	if _timer < interval:
		return
	_timer = 0.0

	var target := get_parent() as Character
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		queue_free()
		return

	target.take_damage(damage, element)
	ticks_left -= 1
	if ticks_left <= 0:
		queue_free()
