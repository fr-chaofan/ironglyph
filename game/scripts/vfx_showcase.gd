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

## 筆順濃淡對照排：同一個字用不同的 brush_ink_depletion 並排，直接挑數值。
## 用「森」——12 筆而且相鄰筆畫多，最看得出「糊不糊」。
const INK_COMPARISON_GLYPH := "森"
const INK_COMPARISON_VALUES := [1.0, 0.9, 0.78, 0.65]

## 內容四周留白，避免貼著畫面邊緣
const CONTENT_MARGIN := 90.0

var _slots: Array[Node2D] = []
## 每一塊內容的中心與半徑，用來算鏡頭要拉多遠
var _content_extents: Array[Rect2] = []


func _ready() -> void:
	_build_layout()
	_build_glyph_samples()
	_build_ink_comparison()
	_fit_camera()
	_loop()


## 全部內容的外框。
func get_content_bounds() -> Rect2:
	if _content_extents.is_empty():
		return Rect2()
	var bounds: Rect2 = _content_extents[0]
	for rect: Rect2 in _content_extents:
		bounds = bounds.merge(rect)
	return bounds.grow(CONTENT_MARGIN)


## 讓鏡頭自動框住所有內容。
##
## ⚠️ **不要手動排座標再假設看得到。** 第一版就是這樣——字形樣本排放在 y=400、
## 濃淡對照排在 y=590，而 720 高的視口只看得到 y ∈ [-360, 360]，
## 兩排全都在畫面外，實機上完全看不到。內容一多就會再犯，所以改成鏡頭自己適應內容。
func _fit_camera() -> void:
	var camera := get_node_or_null(^"Camera2D") as Camera2D
	if camera == null:
		return

	var bounds := get_content_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var viewport_size := Vector2(get_viewport_rect().size)
	var zoom := minf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y)
	camera.zoom = Vector2.ONE * minf(1.0, zoom)
	camera.position = bounds.get_center()

	# ⚠️ 背景要跟著鏡頭鋪滿。固定大小的 ColorRect 一旦鏡頭拉遠就露出邊緣，
	# 畫面右側與下方會出現黑帶——紙只鋪了一半看起來比全黑還糟。
	var background := get_node_or_null(^"Background") as ColorRect
	if background != null:
		var visible_size := Vector2(get_viewport_rect().size) / camera.zoom
		background.size = visible_size * 1.1
		background.position = camera.position - background.size * 0.5
		background.color = Palette.paper()


## 登記一塊內容的佔位，供 _fit_camera 計算。
func _register_extent(center: Vector2, half_size: Vector2) -> void:
	_content_extents.append(Rect2(center - half_size, half_size * 2.0))


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
		# 揮擊會往外掃，佔位要比字本身大
		_register_extent(slot.position + Vector2(0.0, 40.0), Vector2(150.0, 140.0))

		# 揮擊的錨點：一個靜止的字，讓刀氣有東西可以纏。
		# 用 HanziSprite 而不是純 Label——這樣展示場看到的就是遊戲裡真正的筆畫渲染
		var glyph := HanziSprite.new()
		glyph.add_theme_font_override(&"font", font)
		glyph.add_theme_font_size_override(&"font_size", 64)
		glyph.add_theme_constant_override(&"outline_size", 5)
		glyph.add_theme_color_override(&"font_outline_color", Palette.paper())
		glyph.add_theme_color_override(&"font_color", Palette.ink())
		glyph.size = Vector2(64, 76)
		glyph.position = Vector2(-32, -38)
		slot.add_child(glyph)
		glyph.character_text = showcase_glyph

		var caption := Label.new()
		caption.text = "%s\n%s" % [ELEMENT_LABELS.get(element, element), element]
		caption.add_theme_font_override(&"font", font)
		caption.add_theme_font_size_override(&"font_size", 20)
		caption.add_theme_constant_override(&"outline_size", 4)
		caption.add_theme_color_override(&"font_outline_color", Palette.paper())
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
		_register_extent(row.position + slot.position + Vector2(0.0, 20.0), Vector2(75.0, 70.0))

		var glyph := HanziSprite.new()
		glyph.add_theme_font_override(&"font", font)
		glyph.add_theme_font_size_override(&"font_size", 72)
		glyph.add_theme_color_override(&"font_outline_color", Palette.paper())
		glyph.add_theme_color_override(&"font_color", Palette.ink())
		glyph.size = Vector2(72, 84)
		glyph.position = Vector2(-36, -42)
		slot.add_child(glyph)
		glyph.character_text = glyph_text

		var caption := Label.new()
		caption.text = "%d 筆" % HanziData.get_medians(glyph_text).size()
		caption.add_theme_font_override(&"font", font)
		caption.add_theme_font_size_override(&"font_size", 18)
		caption.add_theme_color_override(&"font_color", Color(0.35, 0.33, 0.30))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(120, 24)
		caption.position = Vector2(-60, 56)
		slot.add_child(caption)


## 筆順濃淡對照排。
##
## 「同樣的顏色填充所以看著有點糊」的直接解法就是這個參數——
## 1.0 是每一筆都一樣濃（最糊），越小則越後面的筆畫墨越淡、相鄰筆畫越分得開。
## 並排看才挑得出想要的那一檔。
func _build_ink_comparison() -> void:
	var font: FontFile = load(FONT_PATH)
	var row := Node2D.new()
	row.position = Vector2(0.0, row_spacing * 1.25 + 190.0)
	add_child(row)

	var title := Label.new()
	title.text = "筆順濃淡對照（brush_ink_depletion）"
	title.add_theme_font_override(&"font", font)
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", Color(0.35, 0.33, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(400, 24)
	title.position = Vector2(-200, -76)
	row.add_child(title)

	for i in INK_COMPARISON_VALUES.size():
		var value: float = INK_COMPARISON_VALUES[i]
		var slot := Node2D.new()
		slot.position = Vector2((float(i) - 1.5) * 150.0, 0.0)
		row.add_child(slot)
		_register_extent(row.position + slot.position + Vector2(0.0, 20.0), Vector2(75.0, 80.0))

		var glyph := HanziSprite.new()
		glyph.add_theme_font_override(&"font", font)
		glyph.add_theme_font_size_override(&"font_size", 72)
		glyph.add_theme_color_override(&"font_outline_color", Palette.paper())
		glyph.add_theme_color_override(&"font_color", Palette.ink())
		glyph.size = Vector2(72, 84)
		glyph.position = Vector2(-36, -42)
		glyph.brush_ink_depletion = value
		slot.add_child(glyph)
		glyph.character_text = INK_COMPARISON_GLYPH

		var caption := Label.new()
		caption.text = "%.2f%s" % [value, "（現值）" if is_equal_approx(value, 0.78) else ""]
		caption.add_theme_font_override(&"font", font)
		caption.add_theme_font_size_override(&"font_size", 18)
		caption.add_theme_color_override(&"font_color", Color(0.35, 0.33, 0.30))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size = Vector2(140, 24)
		caption.position = Vector2(-70, 56)
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
