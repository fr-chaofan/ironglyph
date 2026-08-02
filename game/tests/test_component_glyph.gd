## 部件字形的視覺區分（寫字格＋淡墨＋浮動）
##
## **要解決的問題**：10 個部件裡有 7 個能獨立成字，其中「山石雨」三個
## **同時也是敵人的字形**，連屬性色都一樣——玩家光看字形分不出要打還是要撿。
## 在此之前唯一的區分信號只有字號，太單薄。
extends GutTest

const PickupScene := preload("res://scenes/component_pickup.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")


func test_確實有字形同時是敵人與部件() -> void:
	# 這條是問題本身的存證。哪天資料表改到不再重疊，這條會失敗提醒我們重新評估。
	var components := {}
	for entry: Dictionary in _load("res://data/components.json"):
		components[String(entry.get("display_glyph", ""))] = true
	var overlap: Array = []
	for entry: Dictionary in _load("res://data/enemies.json"):
		var glyph := String(entry.get("char", ""))
		if components.has(glyph):
			overlap.append(glyph)

	assert_gt(
		overlap.size(), 0,
		"若已無重疊字形，寫字格的必要性要重新評估"
	)


func test_拾取物套上寫字格() -> void:
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.setup({"id": "rain", "display_glyph": "雨", "element": "water"})
	await wait_physics_frames(1)

	var frame: ComponentGlyph = null
	for child: Node in pickup.get_children():
		if child is ComponentGlyph:
			frame = child as ComponentGlyph
			break
	assert_not_null(frame, "部件必須套寫字格，否則與敵人字形分不開")


func test_套格子不改變樹結構() -> void:
	# ⚠️ 一開始是把 Label reparent 到格子底下，結果 get_node("Glyph") 這類
	# 既有路徑全部失效——拾取物與外置顯示都靠它拿 Label。
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	await wait_physics_frames(1)

	assert_not_null(pickup.get_node_or_null(^"Glyph"), "Glyph 必須留在原本的路徑上")


func test_格子畫在字底下但不用負z_index() -> void:
	# ⚠️ 負的 z_index 會讓格子掉到不透明的紙底 ColorRect 之下，畫面上完全看不到
	# ——與 ParallaxBackground 那次是同一個坑。繪製順序靠樹順序。
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	await wait_physics_frames(1)

	var frame: ComponentGlyph = null
	for child: Node in pickup.get_children():
		if child is ComponentGlyph:
			frame = child as ComponentGlyph
			break
	assert_not_null(frame)
	if frame == null:
		return

	assert_gte(frame.z_index, 0, "不可以用負 z_index，會掉到紙底後面")
	var glyph := pickup.get_node(^"Glyph")
	assert_lt(frame.get_index(), glyph.get_index(), "格子要排在字前面才會畫在字底下")


func test_淡墨保留色相但更靠近紙() -> void:
	# 化太開的話屬性色會讀不出來，那是更嚴重的問題
	var raw: Color = Bullet.ELEMENT_COLORS["water"]
	var washed := ComponentGlyph.wash(raw)
	var paper := Palette.paper()

	assert_lt(
		Palette.distance(washed, paper), Palette.distance(raw, paper),
		"淡墨應該更靠近紙色"
	)
	assert_gt(
		Palette.distance(washed, paper), 0.6,
		"但不能化到讀不出屬性"
	)
	assert_gt(washed.b, washed.r, "色相要保留——水還是要偏藍")


func test_淡墨不動font_color() -> void:
	# ⚠️ Label 的最終顏色是 font_color × self_modulate × modulate 相乘，
	# 在 font_color 上動手腳會與元素色疊加兩次，顏色整個跑掉。
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.setup({"id": "rain", "display_glyph": "雨", "element": "water"})
	await wait_physics_frames(1)

	var glyph := pickup.get_node(^"Glyph") as Label
	var font_color := glyph.get_theme_color(&"font_color")
	assert_almost_eq(font_color.r, 1.0, 0.02, "font_color 應維持中性，淡墨走 modulate")


func test_字與格子同步浮動() -> void:
	# 分開動的話字會在格子裡晃，看起來像沒對齊
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	await wait_physics_frames(1)

	var frame: ComponentGlyph = null
	for child: Node in pickup.get_children():
		if child is ComponentGlyph:
			frame = child as ComponentGlyph
			break
	if frame == null:
		return
	var glyph := pickup.get_node(^"Glyph") as Label

	var frame_before := frame.position
	var glyph_before := glyph.position
	frame._process(0.25)

	assert_ne(frame.position, frame_before, "格子應該浮動")
	assert_almost_eq(
		glyph.position.y - glyph_before.y,
		frame.position.y - frame_before.y,
		0.01,
		"字與格子的位移必須一致"
	)


func test_手持的部件不套寫字格() -> void:
	# 寫字格的語義是「待書寫／待組裝的部件」——一旦拿在身上那件事已經完成了。
	# 而且格子跟著角色移動會很吵，與主角的字擠在一起反而更難讀。
	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)

	var display := player.get_node(^"WeaponGlyphDisplay")
	for child: Node in display.get_children():
		assert_false(child is ComponentGlyph, "手持的部件不該套寫字格")


func test_手持的部件仍然是淡墨() -> void:
	# 格子拿掉了，但「借來的東西還沒寫進你身上」這件事還在
	var raw: Color = Bullet.ELEMENT_COLORS["water"]
	assert_lt(
		Palette.distance(ComponentGlyph.wash(raw), Palette.paper()),
		Palette.distance(raw, Palette.paper())
	)


func test_部件字級明顯小於角色() -> void:
	# 字號是區分度的第一道信號，差距不夠大就白費
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	await wait_physics_frames(1)
	var pickup_size := (pickup.get_node(^"Glyph") as Label).get_theme_font_size(&"font_size")

	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	var enemy_size := enemy.hanzi_sprite.get_theme_font_size(&"font_size")

	assert_lt(
		float(pickup_size), float(enemy_size) * 0.6,
		"部件字級要明顯小於角色，%d vs %d 差距不夠" % [pickup_size, enemy_size]
	)


func test_敵人不套寫字格() -> void:
	# 格子是「這是待組裝的部件」的信號，敵人套上就失去意義了
	var enemy: Enemy = EnemyScene.instantiate()
	add_child_autofree(enemy)
	enemy.setup({
		"char": "雨", "element": "water", "ai": "stationary_aoe",
		"hp": 20, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)

	for child: Node in enemy.get_children():
		assert_false(child is ComponentGlyph, "敵人不可以套寫字格")


func _load(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []
