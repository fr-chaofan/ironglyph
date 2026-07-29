## 部件與聲符字核的資料查詢器（Task 2.6）。
##
## component_id 是玩法資料的穩定識別碼；顯示字形只用於畫面，不能反過來當 ID。
## 所有公開 getter 都回傳深拷貝，避免呼叫端意外修改共用資料。
class_name FusionResolver
extends RefCounted

const COMPONENTS_PATH := "res://data/components.json"
const RECIPES_PATH := "res://data/fusion_recipes.json"

var _components_by_id: Dictionary = {}
var _recipes: Array = []


func _init() -> void:
	reload()


func reload() -> void:
	_components_by_id.clear()
	_recipes.clear()

	var components_data := _load_json_array(COMPONENTS_PATH)
	for value: Variant in components_data:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var component: Dictionary = value
		var component_id := String(component.get("id", "")).strip_edges()
		if component_id.is_empty():
			push_warning("FusionResolver: components.json 有缺少 id 的項目，已略過")
			continue
		if _components_by_id.has(component_id):
			push_warning("FusionResolver: 重複的 component_id「%s」，後者已略過" % component_id)
			continue
		_components_by_id[component_id] = component.duplicate(true)

	var recipes_data := _load_json_array(RECIPES_PATH)
	for value: Variant in recipes_data:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var recipe: Dictionary = value
		var core := String(recipe.get("core_glyph", "")).strip_edges()
		var component_id := String(recipe.get("component_id", "")).strip_edges()
		if core.is_empty() or component_id.is_empty():
			push_warning("FusionResolver: fusion_recipes.json 有缺少 core_glyph/component_id 的項目，已略過")
			continue
		_recipes.append(recipe.duplicate(true))


func get_component(component_id: String) -> Dictionary:
	var normalized_id := component_id.strip_edges()
	if not _components_by_id.has(normalized_id):
		return {}
	return (_components_by_id[normalized_id] as Dictionary).duplicate(true)


func get_component_for_source_radical(radical: String) -> Dictionary:
	var normalized_radical := radical.strip_edges()
	if normalized_radical.is_empty():
		return {}

	for component: Dictionary in _components_by_id.values():
		var source_radicals: Variant = component.get("source_radicals", [])
		if typeof(source_radicals) != TYPE_ARRAY:
			continue
		for source: Variant in source_radicals:
			if String(source).strip_edges() == normalized_radical:
				return component.duplicate(true)
	return {}


func resolve(core_glyph: String, component_id: String) -> Dictionary:
	var normalized_core := core_glyph.strip_edges()
	var normalized_id := component_id.strip_edges()
	if normalized_core.is_empty() or not _components_by_id.has(normalized_id):
		return {}

	for recipe: Dictionary in _recipes:
		if String(recipe.get("core_glyph", "")).strip_edges() != normalized_core:
			continue
		if String(recipe.get("component_id", "")).strip_edges() == normalized_id:
			return recipe.duplicate(true)
	return {}


func get_all_components() -> Array:
	var result: Array = []
	for component: Dictionary in _components_by_id.values():
		result.append(component.duplicate(true))
	return result


func get_all_recipes() -> Array:
	return _recipes.duplicate(true)


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FusionResolver: 無法開啟 %s（錯誤碼 %d）" % [path, FileAccess.get_open_error()])
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		push_error("FusionResolver: %s 解析失敗，應為陣列" % path)
		return []
	return parsed
