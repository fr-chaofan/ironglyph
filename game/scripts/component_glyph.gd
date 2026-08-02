## 部件字形的視覺處理：寫字格 ＋ 淡墨 ＋ 浮動。
##
## **要解決的問題**：10 個部件裡有 7 個是能獨立成字的（雨火金木土山石），
## 其中「山石雨」三個**同時也是敵人的字形**，連屬性色都一樣——
## 玩家看到一個靛藍的「雨」，光看字形分不出那是要打的還是要撿的。
## 在此之前唯一的區分信號只有字號（敵人 64 / 拾取物 40），太單薄。
##
## 三個信號疊加，敵人一個都不套用：
##
## 1. **寫字格**——漢字**學寫字**的視覺語言。字被放進格子裡，意思就是
##    「這是待書寫／待組裝的部件」，而不是「世界裡的一個存在」。
##    零素材（四條線），而且與「令借部件拼字」的設定嚴絲合縫。
## 2. **淡墨**——借來的東西還沒寫進你身上，墨自然比本體淡。
##    ⚠️ 只往紙色化開一點點：化太開屬性色會讀不出來，那是更嚴重的問題。
## 3. **浮動**——部件輕微上下浮並微轉，敵人站立行走。運動是很強的區分信號。
class_name ComponentGlyph
extends Node2D

## 格子邊長相對於字級的比例
const CELL_RATIO := 1.34
## 格線顏色。用淡朱——練習本的田字格就是印成淡紅的，一眼認得出是「寫字格」。
## ⚠️ 透明度要壓得夠低，否則會被誤讀成火屬性的東西。
const GRID_COLOR := Color(0.72, 0.22, 0.18, 0.38)
const GRID_WIDTH := 1.5
## 淡墨程度：往紙色化開多少
const INK_WASH := 0.22

## 浮動幅度與速度
@export var float_amplitude: float = 3.5
@export var float_speed: float = 1.9
@export var tilt_amplitude: float = 0.045

var cell_size: float = 54.0

var _time: float = 0.0
var _base_position: Vector2 = Vector2.ZERO
var _label: Label
var _label_base_position: Vector2 = Vector2.ZERO


## 把一個既有的部件字形 Label 套上寫字格。
##
## ⚠️ **不改動樹結構。** 一開始是把 label reparent 到格子底下，結果
## `get_node("Glyph")` 這類既有路徑全部失效（拾取物與外置顯示都靠它拿 Label）。
## 改成格子當兄弟節點，由格子每幀同時驅動自己與 label 的浮動——
## 兩者同步位移，看起來仍是一體。
static func wrap(label: Label, glyph_font_size: float) -> ComponentGlyph:
	if label == null or not is_instance_valid(label):
		return null
	var parent := label.get_parent()
	if parent == null:
		return null

	var frame := ComponentGlyph.new()
	frame.cell_size = glyph_font_size * CELL_RATIO
	# 格子中心對齊字的中心
	frame.position = label.position + label.size * 0.5
	parent.add_child(frame)
	parent.move_child(frame, label.get_index())

	frame._base_position = frame.position
	frame._label = label
	frame._label_base_position = label.position
	# 讓字繞自己的中心轉，否則微轉會變成繞左上角甩
	label.pivot_offset = label.size * 0.5
	return frame


## 淡墨：往紙色化開一點。保留色相，屬性才讀得出來。
##
## ⚠️ 由**設色的地方**呼叫，不要偷偷改 `font_color`——
## Label 的最終顏色是 `font_color × self_modulate × modulate` 相乘，
## 在 font_color 上動手腳會與元素色疊加兩次，顏色整個跑掉。
static func wash(color: Color) -> Color:
	var washed := color.lerp(Palette.paper(), INK_WASH)
	washed.a = color.a
	return washed


func _ready() -> void:
	# ⚠️ **不要用負的 z_index 把格子壓到字底下。**
	# z_index 預設相對於父節點，負值會讓格子掉到不透明的紙底 ColorRect 之下，
	# 畫面上完全看不到——與 ParallaxBackground 那次是同一個坑。
	# 繪製順序改靠樹順序：wrap() 已經把格子插在 label 前面，自然畫在字底下。
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var bob := Vector2(0.0, sin(_time * float_speed) * float_amplitude)
	var tilt := sin(_time * float_speed * 0.7) * tilt_amplitude

	position = _base_position + bob
	rotation = tilt

	# 字與格子同步浮動。分開動的話字會在格子裡晃，看起來像沒對齊。
	if _label != null and is_instance_valid(_label):
		_label.position = _label_base_position + bob
		_label.rotation = tilt


## 田字格：外框 ＋ 中央十字。
## 十字用虛線——實線會太搶戲，虛線才像練習本上的輔助線。
func _draw() -> void:
	var half := cell_size * 0.5
	var rect := Rect2(-half, -half, cell_size, cell_size)
	draw_rect(rect, GRID_COLOR, false, GRID_WIDTH)
	draw_dashed_line(Vector2(-half, 0.0), Vector2(half, 0.0), GRID_COLOR, GRID_WIDTH, 5.0)
	draw_dashed_line(Vector2(0.0, -half), Vector2(0.0, half), GRID_COLOR, GRID_WIDTH, 5.0)
