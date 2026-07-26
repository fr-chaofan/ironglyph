## 橫版鏡頭跟隨（Task 1.5）
##
## 掛在 Player 底下的 Camera2D。平滑跟隨玩家，並可由關卡設定邊界避免拍到關卡外的空白。
class_name CameraBounds
extends Camera2D

@export var smoothing_speed: float = 8.0

## 是否已經套用過關卡邊界。未套用時 Godot 的 limit_* 仍是預設的正負一億，
## 等同不限制；LevelManager（階段四）載入關卡後應呼叫 set_level_bounds()。
var has_bounds: bool = false


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed


## 由關卡呼叫，把鏡頭限制在關卡矩形內。
func set_level_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.position.x + rect.size.x)
	limit_bottom = int(rect.position.y + rect.size.y)
	has_bounds = true


## 解除邊界限制（例如切換到無邊界的Boss場）
func clear_level_bounds() -> void:
	limit_left = -10000000
	limit_top = -10000000
	limit_right = 10000000
	limit_bottom = 10000000
	has_bounds = false
