## 五行之呼吸：屬性揮擊刀氣（視覺第二輪）
##
## 這裡驗證的是**造型有沒有真的分化**，不是好不好看。
## 整個需求的核心就是「不是同一條線換顏色」——所以最關鍵的一條是
## `test_六種屬性的造型互不相同`：任兩個屬性生成的點集必須有可量測的差異。
## 好不好看請用 `scenes/vfx_showcase.tscn` 六格並排循環播放來判斷。
extends GutTest

const ShowcaseScript := preload("res://scripts/vfx_showcase.gd")

var _host: Node2D


func before_each() -> void:
	_host = Node2D.new()
	add_child_autofree(_host)


# ---- 資料表 ----

func test_每個五行屬性都有造型參數() -> void:
	var data := MeleeArc.load_vfx_data()
	assert_true(data.has("defaults"), "缺少 defaults，其他屬性沒有東西可以繼承")
	for element: String in ["water", "fire", "metal", "wood", "earth", "neutral"]:
		assert_true(data.has(element), "缺少 %s 的造型參數" % element)


func test_缺項會從defaults補齊() -> void:
	# 中性只寫了少數幾項，其餘要能自動繼承——否則調參時漏寫一個 key 就會拿到 0
	var profile := MeleeArc.get_vfx_profile("neutral")
	for key: String in ["layers", "core_width", "swath_width", "amplitude", "frequency"]:
		assert_true(profile.has(key), "neutral 的 %s 沒有從 defaults 補上" % key)


func test_未知屬性退回defaults而不是空字典() -> void:
	var profile := MeleeArc.get_vfx_profile("no_such_element")
	assert_false(profile.is_empty(), "未知屬性不可以讓揮擊變成看不見的攻擊")
	assert_gt(int(profile.get("layers", 0)), 0)


func test_註解欄位不會汙染參數() -> void:
	# JSON 裡的 _note / _comment 是給人看的，不該混進參數
	var profile := MeleeArc.get_vfx_profile("water")
	for key: String in profile:
		assert_false(key.begins_with("_"), "註解欄位 %s 不該出現在參數裡" % key)


# ---- 造型分化（本功能的核心）----

func test_六種屬性的造型互不相同() -> void:
	# 需求的原話是「根據屬性有不同的屬性效果」，不是換顏色。
	# 任兩個屬性生成的刀氣點集必須有可量測的差異。
	var shapes := {}
	for element: String in ["water", "fire", "metal", "wood", "earth", "neutral"]:
		shapes[element] = _layer_signature(_spawn(element))

	var elements: Array = shapes.keys()
	for i in elements.size():
		for j in range(i + 1, elements.size()):
			var a: String = elements[i]
			var b: String = elements[j]
			assert_ne(
				shapes[a], shapes[b],
				"%s 與 %s 的刀氣造型一模一樣——這就退化成「同一條線換顏色」了" % [a, b]
			)


func test_水有明顯的波浪起伏() -> void:
	var water := MeleeArc.get_vfx_profile("water")
	assert_gt(float(water.get("amplitude", 0.0)), 10.0, "水之呼吸要看得出翻卷的浪")
	assert_gt(int(water.get("layers", 0)), 3, "水要層數多才像一整片推出去")


func test_金銳利而不拖泥帶水() -> void:
	var metal := MeleeArc.get_vfx_profile("metal")
	var water := MeleeArc.get_vfx_profile("water")
	assert_gt(float(metal.get("spike", 0.0)), 0.0, "金要有折線")
	assert_lt(
		int(metal.get("layers", 99)), int(water.get("layers", 0)),
		"刃光的層數要比水少，銳利感來自稀疏"
	)
	assert_lt(
		float(metal.get("swath_width", 99.0)), float(water.get("swath_width", 0.0)),
		"金的刀氣要比水窄"
	)


func test_火會往上飄() -> void:
	var fire := MeleeArc.get_vfx_profile("fire")
	assert_lt(float(fire.get("drift", 0.0)), 0.0, "火舌要往上飄（螢幕 y 朝下，所以是負的）")
	assert_gt(float(fire.get("jitter", 0.0)), 0.0, "火要有抖動才不像一條光滑的緞帶")


func test_木會抽枝() -> void:
	var arc := _spawn("wood")
	var branches := int(MeleeArc.get_vfx_profile("wood").get("branches", 0))
	assert_gt(branches, 0, "木之呼吸要長出短枝")

	var layers := int(MeleeArc.get_vfx_profile("wood").get("layers", 0))
	var lines := _count_child_lines(arc)
	assert_eq(lines, layers + branches, "分枝應該和刀氣層一起掛上去")


# ---- 結構 ----

func test_核心筆畫本身仍是最上層的墨線() -> void:
	# 「核心是字、氣在字外」——屬性層一律壓在筆畫底下，墨線始終看得見
	var arc := _spawn("water")
	assert_gt(arc.points.size(), 1, "核心筆畫不該是空的")

	for child: Node in arc.get_children():
		var line := child as Line2D
		if line == null:
			continue
		assert_lt(line.z_index, 0, "屬性層必須壓在核心筆畫底下")


func test_筆觸有提按與濃淡() -> void:
	# 水墨質感的兩個來源：width_curve 兩端收細、gradient 沿線變淡
	var arc := _spawn("water")
	assert_not_null(arc.width_curve, "缺少提按，筆觸會是死板的等寬線")
	assert_not_null(arc.gradient, "缺少濃淡，墨色不會有變化")
	assert_lt(
		arc.width_curve.sample(1.0), arc.width_curve.sample(0.35),
		"收筆要比中段細"
	)


func test_層數與參數一致() -> void:
	for element: String in ["water", "metal", "earth"]:
		var arc := _spawn(element)
		var profile := MeleeArc.get_vfx_profile(element)
		var expected := int(profile.get("layers", 0)) + int(profile.get("branches", 0))
		assert_eq(_count_child_lines(arc), expected, "%s 的刀氣層數不對" % element)


func test_粒子數依屬性而不同() -> void:
	var fire := _count_particles(_spawn("fire"))
	var neutral := _count_particles(_spawn("neutral"))

	assert_gt(fire, 0, "火要有火星")
	assert_eq(neutral, 0, "純墨不該有粒子——它就是一筆書法")


func test_造型是確定性的不會每幀抖動() -> void:
	# 用 randf() 的話同一次揮擊每次重算都不一樣，測試也無法斷言形狀
	var a := _layer_signature(_spawn("fire"))
	var b := _layer_signature(_spawn("fire"))
	assert_eq(a, b, "同樣參數應該生成同樣造型")


# ---- 展示場景 ----

func test_展示場涵蓋全部五行加中性() -> void:
	# 漏掉一個屬性的話，調參時就有一種效果永遠沒被看過
	for element: String in Bullet.ELEMENT_COLORS:
		assert_has(
			ShowcaseScript.ELEMENTS, element,
			"展示場少了 %s，這個屬性的造型永遠不會被看到" % element
		)


func test_展示場的每個屬性都有中文標題() -> void:
	for element: String in ShowcaseScript.ELEMENTS:
		assert_true(
			ShowcaseScript.ELEMENT_LABELS.has(element),
			"展示場的 %s 沒有標題，畫面上分不出哪一格是什麼" % element
		)


func test_展示場的所有內容都在鏡頭範圍內() -> void:
	# ⚠️ 這一條是修正回歸用的。
	# 第一版把字形樣本排放在 y=400、濃淡對照排在 y=590，而 720 高的視口
	# 只看得到 y ∈ [-360, 360]——兩排全都在畫面外，實機上完全看不到。
	# 內容一多就會再犯，所以鏡頭改成自動框住內容，並且用這條測試守住。
	var showcase: Node2D = load("res://scenes/vfx_showcase.tscn").instantiate()
	add_child_autofree(showcase)
	await wait_physics_frames(1)

	var camera := showcase.get_node(^"Camera2D") as Camera2D
	var bounds: Rect2 = showcase.get_content_bounds()
	assert_gt(bounds.size.x, 0.0, "內容外框不該是空的")

	# 鏡頭實際看得到的世界範圍
	var visible_size := Vector2(showcase.get_viewport_rect().size) / camera.zoom
	var visible := Rect2(camera.position - visible_size * 0.5, visible_size)

	assert_true(
		visible.encloses(bounds),
		"有內容在鏡頭外：可見範圍 %s 裝不下內容 %s" % [visible, bounds]
	)


func test_展示場的三個區塊都有登記佔位() -> void:
	# 漏登記的區塊不會被鏡頭計算涵蓋，等於又跑到畫面外
	var showcase: Node2D = load("res://scenes/vfx_showcase.tscn").instantiate()
	add_child_autofree(showcase)
	await wait_physics_frames(1)

	var bounds: Rect2 = showcase.get_content_bounds()
	# 六格屬性 + 六個字形樣本 + 四檔濃淡，垂直方向一定跨得很開
	assert_gt(bounds.size.y, 600.0, "縱向內容看起來沒有全部登記進去")


# ---- helpers ----

func _spawn(element: String) -> MeleeArc:
	var color: Color = Bullet.ELEMENT_COLORS.get(element, Color.WHITE)
	return MeleeArc.spawn(_host, Vector2.ZERO, 1.0, "令", color, 0.2, 58.0, false, element)


## 把所有刀氣層的點壓成一個可比較的字串。
func _layer_signature(arc: MeleeArc) -> String:
	if arc == null:
		return ""
	var parts: PackedStringArray = []
	for child: Node in arc.get_children():
		var line := child as Line2D
		if line == null:
			continue
		for point: Vector2 in line.points:
			parts.append("%.1f,%.1f" % [point.x, point.y])
	return "|".join(parts)


func _count_child_lines(arc: MeleeArc) -> int:
	var count := 0
	for child: Node in arc.get_children():
		if child is Line2D:
			count += 1
	return count


func _count_particles(arc: MeleeArc) -> int:
	for child: Node in arc.get_children():
		var particles := child as CPUParticles2D
		if particles != null:
			return particles.amount
	return 0
