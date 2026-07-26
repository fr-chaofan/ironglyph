## Character 基類的傷害/死亡邏輯（Task 1.3）
extends GutTest

var CharacterScript := preload("res://scripts/character.gd")


func _make_character(max_hp: int = 100, element: String = "neutral") -> Character:
	var c: Character = CharacterScript.new()
	c.max_hp = max_hp
	c.element = element
	add_child_autofree(c)
	return c


func test_ready後hp等於max_hp() -> void:
	var c := _make_character(75)
	assert_eq(c.hp, 75)


func test_take_damage_扣血() -> void:
	var c := _make_character(100)
	c.take_damage(30, "fire")
	assert_eq(c.hp, 70)


func test_取得不到ElementSystem時回退為中性倍率() -> void:
	# character.gd 用 get_node_or_null("/root/ElementSystem") 探測單例，取不到就回傳 1.0。
	# 這個回退路徑在階段一是常態；階段二之後雖然單例一定在，但仍要保證
	# 單元測試或工具場景等沒有載入 autoload 的情境不會崩潰。
	# 這裡暫時把單例改名，讓探測失敗，藉此實際走到回退分支。
	var singleton := get_tree().root.get_node_or_null(^"ElementSystem")
	assert_not_null(singleton, "階段二後單例應存在")
	singleton.name = "ElementSystemHidden"

	var c := _make_character(100)
	assert_almost_eq(c.get_element_multiplier("fire", "wood"), 1.0, 0.001,
		"探測不到單例時應回退為 1.0 而非崩潰")
	c.take_damage(25, "fire")
	assert_eq(c.hp, 75, "回退倍率 1.0 時傷害應原樣扣除")

	singleton.name = "ElementSystem"


func test_有ElementSystem時走真實相剋表() -> void:
	var c := _make_character(100, "wood")
	assert_almost_eq(c.get_element_multiplier("fire", "wood"), 1.0, 0.001,
		"火不剋木，應為中性")
	assert_almost_eq(c.get_element_multiplier("metal", "wood"), 1.5, 0.001,
		"金剋木，應為優勢倍率")


func test_hp不會扣成負數() -> void:
	var c := _make_character(20)
	c.take_damage(999, "metal")
	assert_eq(c.hp, 0, "hp 應被夾在 0，不應為負")


func test_hp歸零時發出died訊號() -> void:
	var c := _make_character(10)
	watch_signals(c)
	c.take_damage(10, "metal")
	assert_signal_emitted(c, "died")


func test_已死亡後再受擊不重複觸發died() -> void:
	# 同一幀多發子彈打中將死的目標時，die() 只應該跑一次
	var c := _make_character(10)
	c.take_damage(10, "metal")
	watch_signals(c)
	c.take_damage(10, "metal")
	assert_signal_not_emitted(c, "died", "第二次受擊不應再次發出 died")


func test_hp_changed訊號帶出目前值() -> void:
	var c := _make_character(50)
	watch_signals(c)
	c.take_damage(20, "water")
	assert_signal_emitted_with_parameters(c, "hp_changed", [30, 50])


func test_重力取自ProjectSettings() -> void:
	var c := _make_character()
	assert_almost_eq(
		c.gravity,
		float(ProjectSettings.get_setting("physics/2d/default_gravity")),
		0.001,
		"重力應讀 project.godot，不要在腳本裡寫死"
	)
