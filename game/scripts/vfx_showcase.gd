## 五行之呼吸展示場（純調參用，不是遊戲的一部分）。
##
## 六種屬性並排循環揮擊，F5 一次就能全部看到並互相對照。
##
## **為什麼需要這個場景**：特效好不好看只有在有畫面的機器上判斷得了，而在
## `test_room` 裡要看齊六種屬性，得先湊齊六種部件、還得記得哪隻敵人是什麼屬性——
## 一輪比對下來早就忘了前一個長什麼樣。並排循環才比較得出「火太散」「水振幅太大」
## 這種相對判斷。
##
## 調參流程：改 `data/element_vfx.json` → F5 → 看 → 再改。不需要動任何程式碼。
extends Node2D

const ELEMENTS := ["water", "fire", "metal", "wood", "earth", "neutral"]
const ELEMENT_LABELS := {
	"water": "水之呼吸",
	"fire": "炎之呼吸",
	"metal": "金之呼吸",
	"wood": "木之呼吸",
	"earth": "土之呼吸",
	"neutral": "無屬性・純墨",
}
const FONT_PATH := "res://assets/fonts/LXGWWenKaiTC-Regular.ttf"

## 每次揮擊之間的間隔
@export var swing_interval: float = 1.4
## 展示用的揮擊範圍，比實際的 58 大一些看得清楚
@export var showcase_reach: float = 90.0
## 每一格的間距
@export var column_spacing: float = 300.0
@export var row_spacing: float = 320.0
## 展示用的字。用「令」——主角的字核，筆畫數適中看得出筆形
@export var showcase_glyph: String = "令"

## 底下那一排字形樣本：筆畫數由少到多，用來判斷筆畫渲染的辨識度。
## 「巖」23 筆是全專案最複雜的字，它糊不糊決定線寬參數要不要再收。
const GLYPH_SAMPLES := ["山", "令", "河", "劍", "藤", "巖"]

var _slots: Array[Node2D] = []


func _ready() -> void:
	_build_layout()
	_build_glyph_samples()
	_loop()


func _build_layout() -> void:
	var font: FontFile = load(FONT_PATH)
	for i in ELEMENTS.size():
		var element: String = ELEMENTS[i]
		var column := i % 3
		var row := i / 3

		var slot := Node2D.new()
		slot.position = Vector2(
			(float(column) - 1.0) * column_spacing,
			(float(row) - 0.5) * row_spacing
		)
		add_child(slot)
		_slots.append(slot)

		# 揮擊的錨點：一個靜止的字，讓刀氣有東西可以纏。
		# 用 HanziSprite 而不是純 Label——這樣展示場看到的就是遊戲裡真正的筆畫渲染
		var glyph := HanziSprite.new()
		glyph.add_theme_font_override(&"font", font)
		glyph.add_theme_font_size_override(&"font_size", 64)
		glyph.add_theme_constant_override(&"outline_size", 5)
		glyph.add_theme_color_override(&"font_outline_color", Color(0.05, 0.05, 0.1))
		glyph.add_theme_color_override(&"font_color", Color(1, 1, 1))
		glyph.size = Vector2(64, 76)
		glyph.position = Vector2(-32, -38)
		slot.add_child(glyph)
		glyph.character_text = showcase_glyph

		var caption := Label.new()
		caption.text = "%s\n%s" % [ELEMENT_LABELS.get(element, element), element]
		caption.add_theme_font_override(&"font", font)
		caption.add_theme_font_size_override(&"font_size", 20)
		caption.add_theme_constant_override(&"outline_size", 4)
		caption.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
		caption.add_theme_color_override(
			&"font_color", Bullet.ELEMENT_COLORS.get(element, Color.WHITE)
		)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(220, 56)
		caption.position = Vector2(-110, 96)
		slot.add_child(caption)


## 底下一排字形樣本，筆畫數由少到多。
##
## 「巖」23 筆是全專案最複雜的字——線寬若沒有隨筆畫數遞減，它會糊成一團黑。
## 這一排就是為了讓那個參數有東西可以對照著調。
func _build_glyph_samples() -> void:
	var font: FontFile = load(FONT_PATH)
	var row := Node2D.new()
	row.position = Vector2(0.0, row_spacing * 1.25)
	add_child(row)

	for i in GLYPH_SAMPLES.size():
		var glyph_text: String = GLYPH_SAMPLES[i]
		var slot := Node2D.new()
		slot.position = Vector2((float(i) - 2.5) * 150.0, 0.0)
		row.add_child(slot)

		var glyph := HanziSprite.new()
		glyph.add_theme_font_override(&"font", font)
		glyph.add_theme_font_size_override(&"font_size", 72)
		glyph.add_theme_color_override(&"font_outline_color", Color(0.05, 0.05, 0.1))
		glyph.add_theme_color_override(&"font_color", Color(1, 1, 1))
		glyph.size = Vector2(72, 84)
		glyph.position = Vector2(-36, -42)
		slot.add_child(glyph)
		glyph.character_text = glyph_text

		var caption := Label.new()
		caption.text = "%d 筆" % HanziData.get_medians(glyph_text).size()
		caption.add_theme_font_override(&"font", font)
		caption.add_theme_font_size_override(&"font_size", 18)
		caption.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(120, 24)
		caption.position = Vector2(-60, 56)
		slot.add_child(caption)


## 六種屬性依序揮，揮完一輪停一拍再來。
## 全部同時揮的話畫面太亂，反而看不出單一屬性的造型。
func _loop() -> void:
	while is_inside_tree():
		for i in ELEMENTS.size():
			if not is_inside_tree():
				return
			_swing(i)
			await get_tree().create_timer(swing_interval / float(ELEMENTS.size())).timeout
		await get_tree().create_timer(swing_interval * 0.5).timeout


func _swing(index: int) -> void:
	if index >= _slots.size():
		return
	var element: String = ELEMENTS[index]
	var color: Color = Bullet.ELEMENT_COLORS.get(element, Color.WHITE)
	MeleeArc.spawn(
		_slots[index],
		Vector2(showcase_reach * 0.6, 0.0),
		1.0,
		showcase_glyph,
		color,
		0.55,
		showcase_reach,
		false,
		element
	)
