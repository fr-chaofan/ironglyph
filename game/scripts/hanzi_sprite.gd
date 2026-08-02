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
		_rebuild_brush()

## 是否用**真實筆畫**畫出這個字，而不是交給字型平塗。
##
## Label 把字渲染成一塊實心填充——不管換什麼字型，都不會有濃淡、飛白與提按，
## 也就永遠不會有水墨感。真正的水墨在**筆觸**裡，不在字型裡。
##
## 這裡用的是揮擊刀氣同一套技術：`HanziData` 的 medians（每一筆的中軸點序列）
## 畫成帶 `width_curve` 的 `Line2D`，起筆有頓、收筆漸細。
## 附帶好處是「太細」變成一個參數，不再受制於字型只有 Regular 一個字重。
@export var brush_enabled: bool = true:
	set(value):
		brush_enabled = value
		_rebuild_brush()

## 3 筆的字（如「山」）線寬占字級的比例
@export var brush_width_ratio: float = 0.18
## 23 筆的字（如「巖」）線寬占字級的比例。
## ⚠️ 不隨筆畫數遞減的話，同一個寬度下「山」剛好、「巖」會糊成一團黑。
@export var brush_min_width_ratio: float = 0.065

## 五行屬性著色的亮度加成。
##
## `rendering/viewport/hdr_2d` 開啟後，超過 1.0 的顏色分量會被 WorldEnvironment 的
## glow 撿起來發光。字形是玩家辨識屬性的**主要載體**，值得比一般 UI 更亮一點。
const ELEMENT_GLOW_BOOST := 1.22

## 受擊閃紅的顏色
@export var hit_color: Color = Color(1.0, 0.3, 0.3)

## 受擊閃爍的總時長（秒）
@export var hit_flash_duration: float = 0.15

var _hit_tween: Tween


var _brush_root: Node2D


func _ready() -> void:
	text = character_text
	# 讓字以自身中心為錨點，角色定位/旋轉/縮放才不會偏移
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rebuild_brush()


## 用真實筆畫重畫這個字。
##
## 查不到筆畫資料就**退回字型平塗**——UI 用字、以及不在 Make Me a Hanzi 資料集裡的
## 字（例如「刂」）都走這條路，不能讓它們變成看不見的空白。
func _rebuild_brush() -> void:
	if not is_node_ready():
		return

	if _brush_root != null and is_instance_valid(_brush_root):
		_brush_root.queue_free()
		remove_child(_brush_root)
		_brush_root = null

	var medians: Array = HanziData.get_medians(text) if brush_enabled else []
	if medians.is_empty():
		# 退回字型渲染
		visible_ratio = 1.0
		return

	# 字型那一份不要畫出來，但 font_color 保留著——它是屬性色的唯一真相源，
	# 筆畫的顏色也是從那裡讀的
	visible_ratio = 0.0

	_brush_root = Node2D.new()
	_brush_root.name = "BrushStrokes"
	add_child(_brush_root)

	var font_size := float(get_theme_font_size(&"font_size"))
	var scale_factor := font_size / _EM_SIZE
	var bounds := _median_bounds(medians)
	var center := bounds.get_center()
	var origin := size * 0.5

	# 筆畫越多線越細，否則「巖」(23筆) 會糊成一團
	var density := clampf((float(medians.size()) - 3.0) / 20.0, 0.0, 1.0)
	var width := font_size * lerpf(brush_width_ratio, brush_min_width_ratio, density)

	var glyph_color := get_theme_color(&"font_color")
	var outline_color := get_theme_color(&"font_outline_color")

	# ⚠️ 兩趟畫：先把**所有**筆畫的深色襯底畫完，再畫彩色筆畫。
	# 一筆一筆「襯底＋彩色」交錯的話，後一筆的襯底會壓進前一筆的彩色線裡，
	# 字看起來像被切開。
	for stroke: Array in medians:
		var line := _make_stroke_line(stroke, center, scale_factor, origin, width * 1.5, outline_color)
		if line != null:
			line.z_index = -1
			_brush_root.add_child(line)

	for stroke: Array in medians:
		var line := _make_stroke_line(stroke, center, scale_factor, origin, width, glyph_color)
		if line != null:
			_brush_root.add_child(line)


## 把一筆的中軸點序列畫成帶提按的毛筆線條。
func _make_stroke_line(
	stroke: Array,
	center: Vector2,
	scale_factor: float,
	origin: Vector2,
	width: float,
	color: Color
) -> Line2D:
	if stroke.size() < 2:
		return null

	var line := Line2D.new()
	line.width = maxf(1.0, width)
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND

	# 提按：起筆略頓、行筆飽滿、收筆漸細。
	# 收筆不收到 0——那會讓每一筆末端變成尖針，字看起來毛毛躁躁而且更難辨識。
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.82))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(1.0, 0.42))
	line.width_curve = curve

	for point: Array in stroke:
		line.add_point(Vector2(
			(float(point[0]) - center.x) * scale_factor,
			# y 取負號：字身框 y 朝上，螢幕 y 朝下
			-(float(point[1]) - center.y) * scale_factor
		) + origin)
	return line


## 依五行屬性替字形上色。
##
## ⚠️ **這是可讀性功能，不是裝飾。** 在此之前敵人字形一律是白的——子彈有顏色、
## 傷害數字有「剋／抗」，唯獨敵人本體沒有任何屬性線索，玩家只能靠背
## 「河＝水、焰＝火」才知道該換哪個部件。對一個以五行相剋為核心的遊戲，
## 這是最大的一個資訊缺口。
##
## 顏色取自 `Bullet.ELEMENT_COLORS`（GDD 2.3 定案，且已有測試把關任兩色的
## RGB 距離必須大於 0.45），全專案共用同一份色表，不另立第二套。
##
## 玩家的「令」**刻意維持白色**：主角必須在畫面上一眼與敵人區分開，
## 而且玩家的 element 永遠是 neutral，染色沒有資訊量。
func set_element_color(element_name: String) -> void:
	var color: Color = Bullet.ELEMENT_COLORS.get(element_name, Color.WHITE)
	add_theme_color_override(
		&"font_color",
		Color(
			color.r * ELEMENT_GLOW_BOOST,
			color.g * ELEMENT_GLOW_BOOST,
			color.b * ELEMENT_GLOW_BOOST,
			color.a
		)
	)
	# 筆畫的顏色是從 font_color 讀的，換色之後要重畫
	_rebuild_brush()


## 受擊回饋：短暫閃紅再復原。
## 連續受擊時會中斷前一次的 tween，避免多個 tween 疊加把 modulate 卡在中間色。
func flash_hit() -> void:
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	modulate = Color.WHITE
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "modulate", hit_color, hit_flash_duration * 0.33)
	_hit_tween.tween_property(self, "modulate", Color.WHITE, hit_flash_duration * 0.67)


## 筆畫崩解死亡特效（Task 3.4）。
##
## 把字按**真實筆順**拆成一根一根的筆畫飛散，而不是灑幾個通用碎片。
## 筆畫形狀取自 HanziData 的 medians（每筆的中軸點序列），用 Line2D 畫出來——
## 不需要解析 SVG path，medians 本身就是現成的點序列。
##
## 座標系：Make Me a Hanzi 用 1024 單位的字身框，且 y 軸朝上（與螢幕相反）。
## 這裡不去猜它的基線慣例，改用「算出所有點的實際外框再置中」的方式，
## 對任何字都穩定。
const _EM_SIZE := 1024.0

## 碎片存活時間（秒）
@export var shatter_duration: float = 0.7

## 碎片飛散的力道
@export var shatter_force: float = 180.0


func shatter_and_die() -> void:
	var medians: Array = HanziData.get_medians(text)
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_tree().root

	if medians.is_empty():
		# 沒有筆畫資料（例如UI用字或資料集未收錄）就退回單純淡出，不要整個特效消失
		_fade_out_whole(parent)
		queue_free()
		return

	var font_size := float(get_theme_font_size(&"font_size"))
	var scale_factor := font_size / _EM_SIZE
	var bounds := _median_bounds(medians)
	var center := bounds.get_center()
	var origin := global_position + size * 0.5

	for stroke_median: Array in medians:
		var fragment := _make_stroke_fragment(stroke_median, center, scale_factor, font_size)
		if fragment == null:
			continue
		fragment.global_position = origin
		parent.add_child(fragment)
		_animate_fragment(fragment, stroke_median, center, scale_factor)

	queue_free()


## 把一筆的中軸點序列做成 Line2D
func _make_stroke_fragment(stroke_median: Array, center: Vector2, scale_factor: float, font_size: float) -> Line2D:
	if stroke_median.size() < 2:
		return null

	var line := Line2D.new()
	# 明確標記成碎片。場上的 Line2D 不只碎片一種——字形筆畫、揮擊刀氣都是，
	# 靠「是不是 Line2D」來認碎片會連它們一起數進去。
	line.add_to_group(&"stroke_fragment")
	line.width = maxf(2.0, font_size * 0.09)
	line.default_color = modulate
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = 5

	for point: Array in stroke_median:
		# y 取負號：字身框的 y 朝上，螢幕的 y 朝下
		line.add_point(Vector2(
			(float(point[0]) - center.x) * scale_factor,
			-(float(point[1]) - center.y) * scale_factor
		))
	return line


## 每一筆朝著「自己相對於字心的方向」飛出去，看起來才像整個字炸開，
## 而不是所有碎片往同一個方向飄
func _animate_fragment(fragment: Line2D, stroke_median: Array, center: Vector2, scale_factor: float) -> void:
	var centroid := Vector2.ZERO
	for point: Array in stroke_median:
		centroid += Vector2(float(point[0]), float(point[1]))
	centroid /= float(stroke_median.size())

	var outward := Vector2(
		(centroid.x - center.x) * scale_factor,
		-(centroid.y - center.y) * scale_factor
	)
	if outward.length() < 1.0:
		outward = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	outward = outward.normalized()

	# 略微上飄，讓崩解有「炸起來再落下」的感覺，而非平面散開
	var velocity := outward * shatter_force * randf_range(0.7, 1.3) + Vector2.UP * randf_range(40.0, 110.0)

	var tween := fragment.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fragment, "position", fragment.position + velocity, shatter_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(fragment, "rotation", randf_range(-PI, PI), shatter_duration)
	tween.tween_property(fragment, "modulate:a", 0.0, shatter_duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(fragment.queue_free)


## 所有筆畫點的外框（字身框座標系）
func _median_bounds(medians: Array) -> Rect2:
	var min_point := Vector2.INF
	var max_point := -Vector2.INF
	for stroke_median: Array in medians:
		for point: Array in stroke_median:
			var p := Vector2(float(point[0]), float(point[1]))
			min_point = min_point.min(p)
			max_point = max_point.max(p)
	if min_point == Vector2.INF:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return Rect2(min_point, max_point - min_point)


## 沒有筆畫資料時的退路：整個字淡出
func _fade_out_whole(parent: Node) -> void:
	var ghost := Label.new()
	ghost.text = text
	ghost.global_position = global_position
	ghost.modulate = modulate
	ghost.add_theme_font_size_override(&"font_size", get_theme_font_size(&"font_size"))
	var font := get_theme_font(&"font")
	if font != null:
		ghost.add_theme_font_override(&"font", font)
	parent.add_child(ghost)

	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, shatter_duration)
	tween.tween_property(ghost, "scale", Vector2(1.4, 1.4), shatter_duration)
	tween.chain().tween_callback(ghost.queue_free)
