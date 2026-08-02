## 「令 × 部件」單槽裝備狀態機（Task 2.6）。
##
## 這裡是玩家裝備狀態的唯一真相源：
## - CORE：只顯示聲符字核「令」，使用中性基礎攻擊。
## - FUSED：相容部件與字核合成完整字，使用配方內的特殊攻擊。
## - HELD：不相容部件維持外置手持，使用其 fallback weapon。
class_name GlyphLoadout
extends Node

signal loadout_changed(snapshot: Dictionary)
signal component_ejected(component: Dictionary, world_position: Vector2)

enum Mode {
	CORE,
	FUSED,
	HELD,
}

const CORE_WEAPON_ID := "gong"
## 「令」自己的字核近戰，永遠可用（Task 2.7c）
const CORE_MELEE_PROFILE_ID := "ling_slash"
const FUSION_RESOLVER_SCRIPT := preload("res://scripts/fusion_resolver.gd")

@export var core_glyph: String = "令"
@export var hanzi_sprite_path: NodePath = ^"../HanziSprite"
@export var weapon_manager_path: NodePath = ^"../WeaponManager"
@export var weapon_glyph_display_path: NodePath = ^"../WeaponGlyphDisplay"

var mode: int = Mode.CORE
var current_component: Dictionary = {}
var current_recipe: Dictionary = {}

var _resolver = FUSION_RESOLVER_SCRIPT.new()
var _hanzi_sprite: HanziSprite
var _weapon_manager: WeaponManager
var _weapon_glyph_display: Node
var _visible_glyph: String = ""
var _external_weapon: Dictionary = {}
var _active_weapon: Dictionary = {}


func _ready() -> void:
	_hanzi_sprite = get_node_or_null(hanzi_sprite_path) as HanziSprite
	_weapon_manager = get_node_or_null(weapon_manager_path) as WeaponManager
	_weapon_glyph_display = get_node_or_null(weapon_glyph_display_path)
	_enter_core()


func _process(_delta: float) -> void:
	if not InputMap.has_action(&"eject_component"):
		return
	if not Input.is_action_just_pressed(&"eject_component"):
		return

	var ejected := eject_component()
	if ejected.is_empty():
		return
	component_ejected.emit(ejected.duplicate(true), _get_owner_world_position())


## 裝備指定的穩定 component_id；回傳被替換的舊部件。
func equip_component_id(component_id: String) -> Dictionary:
	var component: Dictionary = _resolver.get_component(component_id)
	if component.is_empty():
		return {}

	var old_component := current_component.duplicate(true)
	current_component = component.duplicate(true)
	current_recipe = _resolver.resolve(core_glyph, component_id)

	if current_recipe.is_empty():
		_enter_held()
	else:
		_enter_fused()

	return old_component


## 卸下目前部件並回到 CORE；直接呼叫不會生成世界掉落物。
func eject_component() -> Dictionary:
	if current_component.is_empty():
		return {}

	var ejected := current_component.duplicate(true)
	_enter_core()
	return ejected


func preview_component_id(component_id: String) -> Dictionary:
	var component: Dictionary = _resolver.get_component(component_id)
	if component.is_empty():
		return {}

	var recipe: Dictionary = _resolver.resolve(core_glyph, component_id)
	var preview: Dictionary
	if not recipe.is_empty():
		preview = {
			"mode": "fused",
			"mode_id": Mode.FUSED,
			"core_glyph": core_glyph,
			"visible_glyph": String(recipe.get("result_glyph", core_glyph)),
			"component": component.duplicate(true),
			"recipe": recipe.duplicate(true),
			"external_weapon": {},
			"active_weapon": _get_recipe_attack(recipe),
		}
	else:
		preview = {
			"mode": "held",
			"mode_id": Mode.HELD,
			"core_glyph": core_glyph,
			"visible_glyph": core_glyph,
			"component": component.duplicate(true),
			"recipe": {},
			"external_weapon": _make_external_weapon(component),
			"active_weapon": _get_fallback_weapon(component),
		}
	return preview.duplicate(true)


## 簡短別名，供拾取物或未來 HUD 做無副作用預覽。
func preview(component_id: String) -> Dictionary:
	return preview_component_id(component_id).duplicate(true)


func get_snapshot() -> Dictionary:
	return {
		"mode": _mode_name(mode),
		"mode_id": mode,
		"core_glyph": core_glyph,
		"visible_glyph": _visible_glyph,
		"component": current_component.duplicate(true),
		"recipe": current_recipe.duplicate(true),
		"external_weapon": _external_weapon.duplicate(true),
		"active_weapon": _active_weapon.duplicate(true),
		"melee_weapon": get_melee_profile(),
	}.duplicate(true)


## K 近戰用的 profile（Task 2.7c）。
##
## 分派規則見 `docs/COMBAT.md` 3.2：部件不是在近戰與遠程之間二選一，
## 而是決定**強化哪一邊**——玩家永遠同時握有一個遠程與一個近戰選項。
##
## - CORE / HELD・投射類 → 令筆擊（neutral）
## - FUSED → 令筆擊，但**染上融合字的屬性**，這是合體除了換遠程武器之外的第二層價值
## - HELD・近戰類（刂）→ 換成該部件指定的近戰 profile（刀刃筆擊・金屬性）
func get_melee_profile() -> Dictionary:
	if mode == Mode.HELD:
		var external_id := String(_external_weapon.get("melee_profile_id", "")).strip_edges()
		if not external_id.is_empty():
			var external_profile := MeleeAttack.get_profile(external_id)
			if not external_profile.is_empty():
				return external_profile

	var profile := MeleeAttack.get_profile(CORE_MELEE_PROFILE_ID)
	if profile.is_empty():
		return {}
	profile["glyph"] = core_glyph

	if mode == Mode.FUSED:
		var element := String(_get_recipe_attack(current_recipe).get("element", "")).strip_edges()
		if not element.is_empty():
			profile["element"] = element
	return profile


## J 遠程用的 profile。近戰類部件在此退回 CORE 基礎弓——
## 這樣手持「刂」的玩家仍然打得到遠處的敵人。
func get_ranged_profile() -> Dictionary:
	return _active_weapon.duplicate(true)


func _enter_core() -> void:
	mode = Mode.CORE
	current_component = {}
	current_recipe = {}
	_visible_glyph = core_glyph
	_external_weapon = {}
	_set_main_glyph(core_glyph)
	_set_active_weapon_by_id(CORE_WEAPON_ID)
	_emit_loadout_changed()


func _enter_fused() -> void:
	mode = Mode.FUSED
	_visible_glyph = String(current_recipe.get("result_glyph", core_glyph)).strip_edges()
	if _visible_glyph.is_empty():
		_visible_glyph = core_glyph
	_external_weapon = {}
	_set_main_glyph(_visible_glyph)

	var attack := _get_recipe_attack(current_recipe)
	_set_active_weapon(attack)
	_emit_loadout_changed()


func _enter_held() -> void:
	mode = Mode.HELD
	_visible_glyph = core_glyph
	_set_main_glyph(core_glyph)

	var fallback := _get_fallback_weapon(current_component)
	# 近戰類部件（刂）強化的是 K，J 退回基礎弓——否則手持它就完全沒有遠程手段。
	# 外置顯示仍用 fallback，玩家看到的還是自己手上那個部件。
	if String(fallback.get("attack_type", "projectile")) == "melee":
		_set_active_weapon_by_id(CORE_WEAPON_ID)
	else:
		_set_active_weapon(fallback)
	_external_weapon = _make_external_weapon(current_component, fallback)
	_emit_loadout_changed()


func _set_main_glyph(glyph: String) -> void:
	if _hanzi_sprite != null and is_instance_valid(_hanzi_sprite):
		_hanzi_sprite.character_text = glyph


func _set_active_weapon_by_id(weapon_id: String) -> void:
	if _weapon_manager == null or not is_instance_valid(_weapon_manager):
		_active_weapon = {"id": weapon_id}
		return

	if _weapon_manager.set_active_weapon_by_id(weapon_id):
		_active_weapon = _weapon_manager.get_current_weapon()
	else:
		_active_weapon = {}


func _set_active_weapon(weapon: Dictionary) -> void:
	_active_weapon = weapon.duplicate(true)
	if _weapon_manager != null and is_instance_valid(_weapon_manager):
		_weapon_manager.set_active_weapon(_active_weapon)
		_active_weapon = _weapon_manager.get_current_weapon()


func _get_fallback_weapon(component: Dictionary) -> Dictionary:
	var weapon_id := String(component.get("fallback_weapon_id", "")).strip_edges()
	if weapon_id.is_empty():
		return {}
	if _weapon_manager == null or not is_instance_valid(_weapon_manager):
		return {"id": weapon_id}
	return _weapon_manager.get_weapon_by_id(weapon_id)


func _get_recipe_attack(recipe: Dictionary) -> Dictionary:
	var value: Variant = recipe.get("attack", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func _make_external_weapon(component: Dictionary, fallback: Dictionary = {}) -> Dictionary:
	var external := fallback.duplicate(true)
	if external.is_empty():
		external = {
			"id": String(component.get("fallback_weapon_id", "")),
			"element": String(component.get("element", "neutral")),
		}
	external["display_glyph"] = String(component.get("display_glyph", ""))
	return external


func _emit_loadout_changed() -> void:
	loadout_changed.emit(get_snapshot())


func _get_owner_world_position() -> Vector2:
	var owner_node := get_parent() as Node2D
	return Vector2.ZERO if owner_node == null else owner_node.global_position


func _mode_name(value: int) -> String:
	match value:
		Mode.FUSED:
			return "fused"
		Mode.HELD:
			return "held"
		_:
			return "core"
