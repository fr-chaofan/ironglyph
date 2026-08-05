## 序章「字界殘頁」的關卡出口（Task 4.1a）。
##
## 玩家進入即觸發 `LevelManager.next_level()` 進入水域關；序章沒有存檔點壓力，
## 不需要像 Task 4.1 的 checkpoint.gd 那樣先寫入 SaveSystem。
class_name LevelExit
extends Area2D

## 避免玩家在同一幀被多個碰撞通知重複觸發切換。
var _triggered: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _triggered or not body.is_in_group(&"player"):
		return
	var level_manager := get_node_or_null(^"/root/LevelManager")
	if level_manager == null or not level_manager.has_method(&"next_level"):
		push_warning("LevelExit: 找不到 LevelManager autoload，無法切換關卡")
		return
	_triggered = true
	level_manager.next_level()
