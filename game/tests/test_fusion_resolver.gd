## 部件 catalog 與「令」字融合配方（Task 2.6）
extends GutTest

const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")
const EXPECTED_COMPONENT_IDS := [
	"blade",
	"earth",
	"fire",
	"grass",
	"metal",
	"mountain",
	"rain",
	"stone",
	"water",
	"wood",
]
const REQUIRED_COMPONENT_FIELDS := [
	"id",
	"source_radicals",
	"display_glyph",
	"element",
	"fallback_weapon_id",
]
const REQUIRED_ATTACK_FIELDS := [
	"id",
	"radical",
	"name",
	"element",
	"damage",
	"fire_rate",
	"projectile",
	"range",
	"pattern",
	"projectile_count",
]
const VALID_ELEMENTS := ["water", "fire", "metal", "wood", "earth", "neutral"]

var _resolver


func before_each() -> void:
	_resolver = FusionResolverScript.new()


func test_十種部件id唯一且欄位完整() -> void:
	var components: Array = _resolver.get_all_components()
	assert_eq(components.size(), 10, "MVP catalog 應完整收錄10種掉落部件")

	var seen_ids: Dictionary = {}
	for component: Dictionary in components:
		for field: String in REQUIRED_COMPONENT_FIELDS:
			assert_true(component.has(field), "部件 %s 缺少欄位 %s" % [component.get("id", "?"), field])

		var component_id := String(component.get("id", "")).strip_edges()
		assert_false(component_id.is_empty(), "component id 不可為空")
		assert_false(seen_ids.has(component_id), "component id「%s」不可重複" % component_id)
		seen_ids[component_id] = true

		var source_radicals: Variant = component.get("source_radicals", null)
		assert_typeof(source_radicals, TYPE_ARRAY, "%s 的 source_radicals 必須是陣列" % component_id)
		if typeof(source_radicals) == TYPE_ARRAY:
			assert_gt(source_radicals.size(), 0, "%s 至少要有一個來源部件" % component_id)
			for source: Variant in source_radicals:
				assert_false(String(source).strip_edges().is_empty(), "%s 不可含空來源部件" % component_id)

		assert_false(String(component.get("display_glyph", "")).strip_edges().is_empty())
		assert_has(VALID_ELEMENTS, component.get("element", ""), "%s 使用未知元素" % component_id)
		assert_false(String(component.get("fallback_weapon_id", "")).strip_edges().is_empty())

	var actual_ids: Array = seen_ids.keys()
	actual_ids.sort()
	assert_eq(actual_ids, EXPECTED_COMPONENT_IDS, "component ids 應與MVP catalog完全一致")


func test_每個fallback_weapon_id都存在於武器catalog() -> void:
	var weapon_manager := WeaponManager.new()
	add_child_autofree(weapon_manager)
	weapon_manager.load_weapons()

	var weapon_ids: Dictionary = {}
	for weapon: Dictionary in weapon_manager.weapons:
		weapon_ids[String(weapon.get("id", ""))] = true

	for component: Dictionary in _resolver.get_all_components():
		var fallback_id := String(component.get("fallback_weapon_id", ""))
		assert_true(
			weapon_ids.has(fallback_id),
			"部件 %s 的 fallback 武器「%s」不存在" % [component.get("id", "?"), fallback_id]
		)


func test_金部來源正規化為metal且畫面顯示金() -> void:
	var component_from_radical: Dictionary = _resolver.get_component_for_source_radical("釒")
	var component_from_full_glyph: Dictionary = _resolver.get_component_for_source_radical("金")

	assert_eq(component_from_radical.get("id", ""), "metal")
	assert_eq(component_from_full_glyph.get("id", ""), "metal")
	assert_eq(component_from_radical.get("display_glyph", ""), "金", "subset字型沒有 standalone「釒」")
	assert_has(component_from_radical.get("source_radicals", []), "釒")
	assert_has(component_from_radical.get("source_radicals", []), "金")
	assert_true(_resolver.get_component_for_source_radical("钅").is_empty(), "不可接受簡體偏旁「钅」")


func test_唯一配方為令加雨融合成零() -> void:
	var recipes: Array = _resolver.get_all_recipes()
	assert_eq(
		recipes.size(), 9,
		"九條形聲配方。十個部件裡只有「山」拼不出字——繁體沒有 ⿰山令"
	)

	var recipe: Dictionary = _resolver.resolve("令", "rain")
	assert_false(recipe.is_empty())
	assert_eq(recipe.get("core_glyph", ""), "令")
	assert_eq(recipe.get("component_id", ""), "rain")
	assert_eq(recipe.get("result_glyph", ""), "零")
	assert_eq(recipe.get("layout", ""), "top_bottom")
	assert_eq(recipe.get("ability_id", ""), "scattering_rain")

	var attack: Dictionary = recipe.get("attack", {})
	for field: String in REQUIRED_ATTACK_FIELDS:
		assert_true(attack.has(field), "scattering_rain attack 缺少欄位 %s" % field)
	assert_eq(attack.get("id", ""), "scattering_rain")
	assert_eq(attack.get("radical", ""), "雨")
	assert_eq(attack.get("name", ""), "零落")
	assert_eq(attack.get("element", ""), "water")
	assert_eq(int(attack.get("damage", 0)), 5)
	assert_almost_eq(float(attack.get("fire_rate", 0.0)), 0.9, 0.001)
	assert_eq(attack.get("projectile", ""), "wave")
	assert_eq(attack.get("range", ""), "medium")
	assert_eq(attack.get("pattern", ""), "rain", "零的本義是落雨，彈幕從上方落下")
	assert_eq(int(attack.get("projectile_count", 0)), 7)


func test_未知部件或未策展組合不會擅自造字() -> void:
	assert_true(_resolver.get_component("missing").is_empty())
	assert_true(_resolver.get_component_for_source_radical("不存在").is_empty())
	# 繁體沒有「山＋令」的字：「嶺」是 ⿱山領（領才是 ⿰令頁），
	# 「岭」只作為簡化形存在——山屬部件因此永遠無法融合。
	assert_true(_resolver.resolve("令", "mountain").is_empty(), "令+山 在繁體裡拼不出字")
	assert_true(_resolver.resolve("良", "rain").is_empty())
	assert_true(_resolver.resolve("", "rain").is_empty())
	assert_true(_resolver.resolve("令", "missing").is_empty())


func test_配方字形都有HanziData() -> void:
	for recipe: Dictionary in _resolver.get_all_recipes():
		var core := String(recipe.get("core_glyph", ""))
		var result := String(recipe.get("result_glyph", ""))
		assert_true(HanziData.has_character(core), "字核「%s」缺少筆畫資料" % core)
		assert_true(HanziData.has_character(result), "融合字「%s」缺少筆畫資料" % result)
