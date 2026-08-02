## 橫版鏡頭跟隨（Task 1.5）
##
## 掛在 Player 底下的 Camera2D。平滑跟隨玩家，並可由關卡設定邊界避免拍到關卡外的空白。
class_name CameraBounds
extends Camera2D

@export var smoothing_speed: float = 8.0

## 震動衰減速度。值越大停得越快。
@export var shake_decay: float = 7.0

var _shake_strength: float = 0.0
var _shake_duration_left: float = 0.0

## 是否已經套用過關卡邊界。未套用時 Godot 的 limit_* 仍是預設的正負一億，
## 等同不限制；LevelManager（階段四）載入關卡後應呼叫 set_level_bounds()。
var has_bounds: bool = false


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed


## 鏡頭震動。連續命中時取較強的那一次，不累加——
## 累加的話一秒內打三下會震到畫面完全看不清。
func shake(strength: float, duration: float = 0.18) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration_left = maxf(_shake_duration_left, duration)


func _process(delta: float) -> void:
	if _shake_duration_left <= 0.0:
		# ⚠️ 不要無條件把 offset 歸零：關卡或其他系統可能也想用 offset，
		# 只在震動剛結束的那一幀清乾淨。
		if not is_zero_approx(_shake_strength):
			_shake_strength = 0.0
			offset = Vector2.ZERO
		return

	_shake_duration_left -= delta
	_shake_strength = lerpf(_shake_strength, 0.0, shake_decay * delta)
	offset = Vector2(
		randf_range(-_shake_strength, _shake_strength),
		randf_range(-_shake_strength, _shake_strength)
	)

	if _shake_duration_left <= 0.0:
		offset = Vector2.ZERO


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
