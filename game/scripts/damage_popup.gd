## 飄出傷害數字，並標示這一擊是優勢/劣勢/中性
##
## 這是玩家（與測試者）唯一能直接看出五行倍率有沒有生效的回饋。
## 階段六 Task 6.1 做正式HUD時，樣式可能會併進去統一管理。
class_name DamagePopup
extends RefCounted

const ADVANTAGE_COLOR := Color(1.0, 0.85, 0.2)
const DISADVANTAGE_COLOR := Color(0.55, 0.6, 0.7)
const RISE_DISTANCE := -50.0
const DURATION := 0.7


## 在 target 上方飄出一個傷害數字。
## multiplier 決定顏色與後綴：>1 顯示「剋!」、<1 顯示「抗」。
static func show_damage(target: Node2D, amount: int, multiplier: float) -> Label:
	if target == null or not is_instance_valid(target):
		return null

	var popup := Label.new()
	popup.z_index = 10
	popup.text = str(amount)
	popup.add_theme_font_size_override(&"font_size", 26)
	popup.add_theme_constant_override(&"outline_size", 5)
	popup.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))

	if multiplier > 1.0:
		popup.text += "  剋!"
		popup.add_theme_color_override(&"font_color", ADVANTAGE_COLOR)
	elif multiplier < 1.0:
		popup.text += "  抗"
		popup.add_theme_color_override(&"font_color", DISADVANTAGE_COLOR)
	else:
		popup.add_theme_color_override(&"font_color", Color.WHITE)

	# 掛在目標身上，位置才會跟著目標；目標被釋放時數字也一起消失
	popup.position = Vector2(-20, -70)
	target.add_child(popup)

	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y + RISE_DISTANCE, DURATION)
	tween.tween_property(popup, "modulate:a", 0.0, DURATION)
	tween.chain().tween_callback(popup.queue_free)

	return popup
