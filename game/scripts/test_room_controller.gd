## 手動驗證場景的生命週期控制。
##
## TestRoom 不是正式關卡，也沒有 Phase 4 的 checkpoint / LevelManager。
## 玩家死亡後等待筆畫崩解完成，再完整重載場景，避免留下仍可操作的空殼，
## 同時確保 ComponentDropper、HUD 等只綁定初始 Player 的測試用節點取得新引用。
extends Node2D

@export_range(0.0, 5.0, 0.05) var death_reload_delay: float = 0.8
@export var player_path: NodePath = ^"Player"

var _reload_pending: bool = false


func _ready() -> void:
	var player := get_node_or_null(player_path)
	if player == null or not player.has_signal(&"died"):
		push_warning("TestRoomController: 找不到可監聽死亡事件的 Player")
		return

	var callback := Callable(self, "_on_player_died")
	if not player.is_connected(&"died", callback):
		player.connect(&"died", callback)


func _on_player_died() -> void:
	if _reload_pending:
		return
	_reload_pending = true

	await get_tree().create_timer(death_reload_delay).timeout
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()
