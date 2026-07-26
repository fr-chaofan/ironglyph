## 五行相剋倍率（Task 2.1）
##
## 純邏輯，不需要場景。
extends GutTest

## 相剋環：水剋火、火剋金、金剋木、木剋土、土剋水
const COUNTER_CYCLE := [
	["water", "fire"],
	["fire", "metal"],
	["metal", "wood"],
	["wood", "earth"],
	["earth", "water"],
]


func test_單例已載入資料() -> void:
	assert_not_null(ElementSystem)
	assert_eq(ElementSystem.relations.size(), 5, "五行應有5個屬性")


func test_倍率取自資料檔() -> void:
	assert_almost_eq(ElementSystem.advantage_mult, 1.5, 0.001)
	assert_almost_eq(ElementSystem.disadvantage_mult, 0.6, 0.001)


func test_相剋環每一環都是優勢倍率() -> void:
	for pair: Array in COUNTER_CYCLE:
		assert_almost_eq(
			ElementSystem.get_multiplier(pair[0], pair[1]), 1.5, 0.001,
			"%s 剋 %s，應為優勢倍率" % [pair[0], pair[1]]
		)


func test_被剋方向是劣勢倍率() -> void:
	for pair: Array in COUNTER_CYCLE:
		assert_almost_eq(
			ElementSystem.get_multiplier(pair[1], pair[0]), 0.6, 0.001,
			"%s 被 %s 剋，反打應為劣勢倍率" % [pair[1], pair[0]]
		)


func test_同屬性為中性倍率() -> void:
	for element: String in ElementSystem.ELEMENTS:
		assert_almost_eq(ElementSystem.get_multiplier(element, element), 1.0, 0.001)


func test_neutral雙向都是中性倍率() -> void:
	for element: String in ElementSystem.ELEMENTS:
		assert_almost_eq(ElementSystem.get_multiplier("neutral", element), 1.0, 0.001)
		assert_almost_eq(ElementSystem.get_multiplier(element, "neutral"), 1.0, 0.001)


func test_未知屬性回傳中性倍率而非報錯() -> void:
	assert_almost_eq(ElementSystem.get_multiplier("plasma", "fire"), 1.0, 0.001)
	assert_almost_eq(ElementSystem.get_multiplier("fire", "plasma"), 1.0, 0.001)
	assert_almost_eq(ElementSystem.get_multiplier("", ""), 1.0, 0.001)


func test_資料表的beats與loses_to互相一致() -> void:
	# loses_to 是可以從 beats 推導出來的冗餘資料，一旦兩邊寫得不一致，
	# 會出現「A剋B、但B也剋A」這種矛盾。這裡確認每個 loses_to 都對得上。
	for defender: String in ElementSystem.relations:
		var loses_to: String = ElementSystem.relations[defender].get("loses_to", "")
		assert_true(
			ElementSystem.relations.has(loses_to),
			"%s 的 loses_to「%s」不是有效屬性" % [defender, loses_to]
		)
		assert_eq(
			ElementSystem.relations[loses_to].get("beats", ""), defender,
			"%s 宣稱被 %s 剋，但 %s 的 beats 不是 %s" % [defender, loses_to, loses_to, defender]
		)


func test_相剋環完整且無自剋() -> void:
	# 每個屬性剋且只剋一個、被且只被一個剋，形成單一循環而非分岔
	var beaten := {}
	for attacker: String in ElementSystem.relations:
		var target: String = ElementSystem.relations[attacker].get("beats", "")
		assert_ne(attacker, target, "%s 不應剋自己" % attacker)
		assert_false(beaten.has(target), "%s 被超過一個屬性剋" % target)
		beaten[target] = attacker
	assert_eq(beaten.size(), 5, "五個屬性應各自恰好被一個屬性剋")


func test_has_advantage() -> void:
	assert_true(ElementSystem.has_advantage("water", "fire"))
	assert_false(ElementSystem.has_advantage("fire", "water"))
	assert_false(ElementSystem.has_advantage("water", "water"))


func test_get_counter_to_找出剋制此屬性的屬性() -> void:
	# 供UI提示玩家「該換哪個屬性的武器」
	assert_eq(ElementSystem.get_counter_to("fire"), "water")
	assert_eq(ElementSystem.get_counter_to("water"), "earth")
	assert_eq(ElementSystem.get_counter_to("plasma"), "")


func test_Character透過單例取得真實倍率() -> void:
	# Task 1.3 的 get_element_multiplier() 在階段一回退為 1.0，
	# ElementSystem 註冊後應自動改走相剋表，不需要改 character.gd
	var c: Character = preload("res://scripts/character.gd").new()
	c.max_hp = 100
	c.element = "fire"
	add_child_autofree(c)

	assert_almost_eq(c.get_element_multiplier("water", "fire"), 1.5, 0.001,
		"應已改走 ElementSystem 而非回退值")

	c.take_damage(10, "water")
	assert_eq(c.hp, 85, "水打火 10 傷害 ×1.5 = 15")
