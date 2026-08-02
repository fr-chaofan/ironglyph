## 飄出傷害數字，並標示這一擊是優勢/劣勢/中性
##
## 這是玩家（與測試者）唯一能直接看出五行倍率有沒有生效的回饋。
## 階段六 Task 6.1 做正式HUD時，樣式可能會併進去統一管理。
class_name DamagePopup
extends RefCounted

static var ADVANTAGE_COLOR: Color = Palette.element("fire")
## 打斷蓄力的回饋色。刻意選一個不在五行配色裡的顏色，
## 才不會被誤讀成某個屬性的傷害數字。
static var INTERRUPT_COLOR: Color = Color(0.55, 0.15, 0.55)
static var DISADVANTAGE_COLOR: Color = Palette.element("metal")
const RISE_DISTANCE := -50.0
const DURATION := 0.7


## 在 target 上方飄出一個傷害數字。
## multiplier 決定顏色與後綴：>1 顯示「剋!」、<1 顯示「抗」。
static func show_damage(target: Node2D, amount: int, multiplier: float) -> Label:
	var label := str(amount)
	var color := Palette.ink()
	if multiplier > 1.0:
		label += "  剋!"
		color = ADVANTAGE_COLOR
	elif multiplier < 1.0:
		label += "  抗"
		color = DISADVANTAGE_COLOR
	return show_text(target, label, color)


## 飄出任意文字。除了傷害數字，也給「打斷！」這類狀態回饋用（Task 2.7c）。
##
## 狀態回饋是玩家唯一能看出機制有沒有生效的線索——「字形有沒有縮回去」這種
## 靠肉眼比對縮放的驗證方式，實機測試時根本分辨不出來。
static func show_text(
	target: Node2D,
	text: String,
	color: Color = Color.WHITE,
	font_size: int = 26
) -> Label:
	if target == null or not is_instance_valid(target):
		return null

	var popup := Label.new()
	popup.z_index = 10
	popup.text = text
	popup.add_theme_font_size_override(&"font_size", font_size)
	popup.add_theme_constant_override(&"outline_size", 5)
	# 紙上用紙色描邊，數字壓在深色角色上也讀得到
	popup.add_theme_color_override(&"font_outline_color", Palette.paper())
	popup.add_theme_color_override(&"font_color", color)

	# 掛在目標身上，位置才會跟著目標；目標被釋放時文字也一起消失
	popup.position = Vector2(-20, -70)
	target.add_child(popup)

	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y + RISE_DISTANCE, DURATION)
	tween.tween_property(popup, "modulate:a", 0.0, DURATION)
	tween.chain().tween_callback(popup.queue_free)

	return popup
