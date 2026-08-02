## 打擊感的共用工具：命中停頓與鏡頭震動。
##
## 這些不是美術，是**手感**——同樣一擊 16 傷，有沒有 0.04 秒的停頓，
## 玩家感受到的重量完全不同。而且成本是零素材、幾十行程式碼。
class_name GameFeel
extends RefCounted

## 全域開關。元件測試把它關掉可以避免 `Engine.time_scale` 影響等待計時。
static var enabled: bool = true

## 同一時間只允許一次停頓。多個敵人同幀被打到時不該疊加成長停頓。
static var _stopping: bool = false


## 命中停頓：短暫把時間放慢再恢復。
##
## ⚠️ `Engine.time_scale` 是**全域**的，任何提前 return 的路徑都必須把它還原，
## 否則整個遊戲會永遠卡在慢動作。這裡用 `_stopping` 去重，並且無論如何都會走到還原。
##
## ⚠️ 計時器必須 `ignore_time_scale = true`。用受 time_scale 影響的計時器的話，
## 0.04 秒的停頓在 0.08 倍速下會變成 0.5 秒的實際時間。
static func hit_stop(node: Node, duration: float = 0.04, scale: float = 0.08) -> void:
	if not enabled or _stopping:
		return
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return

	var tree := node.get_tree()
	if tree == null:
		return

	_stopping = true
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_stopping = false


## 讓玩家鏡頭震一下。找不到鏡頭就安靜略過。
static func shake(node: Node, strength: float, duration: float = 0.18) -> void:
	if not enabled or node == null or not is_instance_valid(node):
		return

	var camera := _find_camera(node)
	if camera != null and camera.has_method(&"shake"):
		camera.call(&"shake", strength, duration)


static func _find_camera(node: Node) -> Node:
	var tree := node.get_tree()
	if tree == null:
		return null
	for player: Node in tree.get_nodes_in_group(&"player"):
		var camera := player.get_node_or_null(^"Camera2D")
		if camera != null:
			return camera
	return null
