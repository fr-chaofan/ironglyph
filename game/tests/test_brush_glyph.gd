## 筆畫渲染的字形（視覺第三輪）
##
## Label 把字畫成一塊實心填充——不管換什麼字型都不會有濃淡、飛白與提按。
## 真正的水墨在**筆觸**裡，所以字形改用 `HanziData` 的 medians 畫成帶提按的 Line2D，
## 與揮擊刀氣同一套技術。
##
## 這裡驗證的是**結構與退路**：該用筆畫的有沒有用、沒有筆畫資料的會不會變成空白、
## 筆畫多的字有沒有變細。好不好看用 `scenes/vfx_showcase.tscn` 判斷。
extends GutTest

const EnemyScene := preload("res://scenes/enemy_base.tscn")


func _make_sprite(glyph: String, font_size: int = 64) -> HanziSprite:
	var sprite := HanziSprite.new()
	sprite.add_theme_font_size_override(&"font_size", font_size)
	sprite.size = Vector2(64, 76)
	sprite.character_text = glyph
	add_child_autofree(sprite)
	await wait_physics_frames(1)
	sprite.character_text = glyph  # 進樹之後再觸發一次重建
	return sprite


func _brush_lines(sprite: HanziSprite) -> Array:
	var root := sprite.get_node_or_null(^"BrushStrokes")
	if root == null:
		return []
	var lines: Array = []
	for child: Node in root.get_children():
		if child is Line2D:
			lines.append(child)
	return lines


# ---- 有筆畫資料就用筆畫畫 ----

func test_有筆畫資料的字改用筆畫渲染() -> void:
	var sprite: HanziSprite = await _make_sprite("令")
	var lines := _brush_lines(sprite)

	# 每一筆畫兩條線：深色襯底 + 彩色筆畫
	assert_eq(lines.size(), HanziData.get_medians("令").size() * 2, "「令」5筆應畫出 5×2 條線")
	assert_eq(sprite.visible_ratio, 0.0, "字型那一份不該同時畫出來，否則會與筆畫疊成雙影")


func test_筆畫帶提按而不是等寬() -> void:
	var sprite: HanziSprite = await _make_sprite("令")
	var line: Line2D = _brush_lines(sprite)[0]

	assert_not_null(line.width_curve, "沒有 width_curve 就是死板的等寬線，不會有毛筆感")
	assert_lt(line.width_curve.sample(1.0), line.width_curve.sample(0.22), "收筆要比行筆細")
	assert_gt(line.width_curve.sample(1.0), 0.0, "收筆不可收到 0——會變成毛躁的尖針且更難辨識")


func test_襯底比彩色筆畫粗() -> void:
	# 深色襯底就是原本 Label 描邊的替代品，沒有它字在亮背景上會糊掉
	var sprite: HanziSprite = await _make_sprite("令")
	var lines := _brush_lines(sprite)
	var stroke_count := HanziData.get_medians("令").size()

	var underlay: Line2D = lines[0]
	var top: Line2D = lines[stroke_count]
	assert_gt(underlay.width, top.width, "襯底要比彩色筆畫粗才看得到輪廓")
	assert_lt(underlay.z_index, top.z_index, "襯底要在底下")


func test_襯底全部畫完才畫彩色筆畫() -> void:
	# 一筆一筆「襯底＋彩色」交錯的話，後一筆的襯底會壓進前一筆的彩色線，字看起來像被切開
	var sprite: HanziSprite = await _make_sprite("森")
	var lines := _brush_lines(sprite)
	var stroke_count := HanziData.get_medians("森").size()

	for i in stroke_count:
		assert_eq((lines[i] as Line2D).z_index, -1, "前半段應該全是襯底")
	for i in range(stroke_count, lines.size()):
		assert_eq((lines[i] as Line2D).z_index, 0, "後半段應該全是彩色筆畫")


# ---- 筆畫數與線寬 ----

func test_筆畫多的字線條要變細() -> void:
	# 同一個寬度下「山」(3筆) 剛好，「巖」(23筆) 會糊成一團黑
	var few: HanziSprite = await _make_sprite("山")
	var many: HanziSprite = await _make_sprite("巖")

	var few_width: float = (_brush_lines(few)[0] as Line2D).width
	var many_width: float = (_brush_lines(many)[0] as Line2D).width

	assert_lt(many_width, few_width, "巖(23筆) 的線必須比 山(3筆) 細")
	assert_gt(many_width, 0.0)


func test_線寬隨字級縮放() -> void:
	var small: HanziSprite = await _make_sprite("令", 32)
	var large: HanziSprite = await _make_sprite("令", 96)

	assert_lt(
		(_brush_lines(small)[0] as Line2D).width,
		(_brush_lines(large)[0] as Line2D).width,
		"線寬要跟著字級走，否則小字會被粗線糊掉"
	)


# ---- 退路 ----

func test_沒有筆畫資料的字退回字型渲染() -> void:
	# 「刂」不在 Make Me a Hanzi 資料集裡；UI 文字也一樣走這條路。
	# 沒有退路的話這些字會變成看不見的空白。
	assert_true(HanziData.get_medians("刂").is_empty(), "前置條件：「刂」應該查不到筆畫")

	var sprite: HanziSprite = await _make_sprite("刂")
	assert_eq(_brush_lines(sprite).size(), 0)
	assert_eq(sprite.visible_ratio, 1.0, "查不到筆畫時必須讓字型把字畫出來")


func test_關掉開關就退回字型渲染() -> void:
	var sprite: HanziSprite = await _make_sprite("令")
	assert_gt(_brush_lines(sprite).size(), 0)

	sprite.brush_enabled = false
	assert_eq(_brush_lines(sprite).size(), 0)
	assert_eq(sprite.visible_ratio, 1.0)


func test_換字會重畫筆畫() -> void:
	# 主角合體成「零」時字會變，筆畫必須跟著換
	var sprite: HanziSprite = await _make_sprite("令")
	assert_eq(_brush_lines(sprite).size(), HanziData.get_medians("令").size() * 2)

	sprite.character_text = "零"
	assert_eq(
		_brush_lines(sprite).size(), HanziData.get_medians("零").size() * 2,
		"換字之後筆畫數要跟著變"
	)


# ---- 與既有系統的整合 ----

func test_屬性著色會套用到筆畫上() -> void:
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.setup({
		"char": "焰", "element": "fire", "ai": "patrol_ranged",
		"hp": 30, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)

	var lines := _brush_lines(enemy.hanzi_sprite)
	assert_gt(lines.size(), 0, "敵人字形應該用筆畫畫")

	# 後半段是彩色筆畫
	var top: Line2D = lines[lines.size() - 1]
	var expected: Color = Bullet.ELEMENT_COLORS["fire"]
	assert_almost_eq(top.default_color.r / HanziSprite.ELEMENT_GLOW_BOOST, expected.r, 0.01)
	assert_almost_eq(top.default_color.g / HanziSprite.ELEMENT_GLOW_BOOST, expected.g, 0.01)


func test_崩解碎片不會把字形筆畫算進去() -> void:
	# 字形筆畫與崩解碎片都是 Line2D，靠型別分辨會數錯——碎片改用 group 標記
	var sprite: HanziSprite = await _make_sprite("山")
	assert_gt(_brush_lines(sprite).size(), 0)

	assert_eq(
		get_tree().get_nodes_in_group(&"stroke_fragment").size(), 0,
		"字形的筆畫不可以被標記成崩解碎片"
	)
