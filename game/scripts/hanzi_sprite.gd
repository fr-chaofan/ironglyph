## 用漢字當角色視覺的元件（Task 1.4）
##
## Player 與所有 Enemy 共用。繼承 Label 而非 Sprite2D——角色外觀就是字本身。
##
## ⚠️ 這個節點**永遠不可水平鏡像翻轉**。像素精靈常用 `scale.x = sign(dir)` 表現朝向，
## 但漢字鏡像後會變成無法辨識的反字（「我」鏡像後不是「我」）。朝向一律交給
## 獨立的 DirectionIndicator 節點表現，見 player.gd。
@tool
class_name HanziSprite
extends Label

## 要顯示的漢字。在編輯器裡改會即時反映（@tool）。
@export var character_text: String = "字":
	set(value):
		character_text = value
		text = value

## 受擊閃紅的顏色
@export var hit_color: Color = Color(1.0, 0.3, 0.3)

## 受擊閃爍的總時長（秒）
@export var hit_flash_duration: float = 0.15

var _hit_tween: Tween


func _ready() -> void:
	text = character_text
	# 讓字以自身中心為錨點，角色定位/旋轉/縮放才不會偏移
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## 受擊回饋：短暫閃紅再復原。
## 連續受擊時會中斷前一次的 tween，避免多個 tween 疊加把 modulate 卡在中間色。
func flash_hit() -> void:
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	modulate = Color.WHITE
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", hit_color, hit_flash_duration * 0.33)
	_hit_tween.tween_property(self, "modulate", Color.WHITE, hit_flash_duration * 0.67)


## 筆畫崩解死亡特效。
## 階段三 Task 3.4 會用 HanziData.get_strokes()/get_medians() 把字拆成筆畫碎片飛散；
## 目前先直接消失，讓階段一的流程能跑通。
func shatter_and_die() -> void:
	queue_free()
