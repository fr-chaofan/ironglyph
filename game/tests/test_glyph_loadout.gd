## 「令 × 部件」單槽狀態機（Task 2.6）
##
## GlyphLoadout 是裝備狀態的唯一真相源；這裡驗證 CORE / FUSED / HELD
## 的字形、攻擊與外置顯示始終同步，而且對外 Dictionary 都是深拷貝。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const GlyphLoadoutScript := preload("res://scripts/glyph_loadout.gd")

var _player: Node2D
var _loadout
var _weapon_manager: WeaponManager
var _display: WeaponGlyphDisplay
var _main_glyph: HanziSprite
var _external_glyph: Label


func before_each() -> void:
	_release_inputs()
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(3)

	_loadout = _player.get_node(^"GlyphLoadout")
	_weapon_manager = _player.get_node(^"WeaponManager") as WeaponManager
	_display = _player.get_node(^"WeaponGlyphDisplay") as WeaponGlyphDisplay
	_main_glyph = _player.get_node(^"HanziSprite") as HanziSprite
	_external_glyph = _display.get_node(^"Glyph") as Label

	# 狀態測試只關心最後呈現，不等待Task 2.5的切換Tween。
	_display.switch_duration = 0.0


func after_each() -> void:
	_release_inputs()


func test_開局是core令並使用gong且外置字隱藏() -> void:
	var snapshot: Dictionary = _loadout.get_snapshot()

	assert_eq(snapshot.get("mode", ""), "core")
	assert_eq(snapshot.get("mode_id", -1), GlyphLoadoutScript.Mode.CORE)
	assert_eq(snapshot.get("visible_glyph", ""), "令")
	assert_true((snapshot.get("component", {}) as Dictionary).is_empty())
	assert_true((snapshot.get("recipe", {}) as Dictionary).is_empty())
	assert_true((snapshot.get("external_weapon", {}) as Dictionary).is_empty())
	assert_eq((snapshot.get("active_weapon", {}) as Dictionary).get("id", ""), "gong")
	assert_eq(_weapon_manager.get_current_weapon().get("id", ""), "gong")
	assert_eq(_main_glyph.text, "令")
	assert_false(_display.visible, "CORE 不應顯示外置部件")
	assert_eq(_external_glyph.text, "")


func test_rain進入fused零並裝備reset_burst且外置字隱藏() -> void:
	var replaced: Dictionary = _loadout.equip_component_id("rain")
	var snapshot: Dictionary = _loadout.get_snapshot()

	assert_true(replaced.is_empty(), "空槽第一次裝備不應替換任何部件")
	assert_eq(snapshot.get("mode", ""), "fused")
	assert_eq(snapshot.get("mode_id", -1), GlyphLoadoutScript.Mode.FUSED)
	assert_eq(snapshot.get("visible_glyph", ""), "零")
	assert_eq((snapshot.get("component", {}) as Dictionary).get("id", ""), "rain")
	assert_eq((snapshot.get("recipe", {}) as Dictionary).get("ability_id", ""), "reset_burst")
	assert_eq((snapshot.get("active_weapon", {}) as Dictionary).get("id", ""), "reset_burst")
	assert_eq(_weapon_manager.get_current_weapon().get("id", ""), "reset_burst")
	assert_eq(_main_glyph.text, "零")
	assert_false(_display.visible, "完整融合字應顯示在主字，不可再顯示外置「雨」")
	assert_eq(_external_glyph.text, "")


func test_fire替換rain後進入held令火huo並回傳舊rain() -> void:
	_loadout.equip_component_id("rain")
	var replaced: Dictionary = _loadout.equip_component_id("fire")
	var snapshot: Dictionary = _loadout.get_snapshot()

	assert_eq(replaced.get("id", ""), "rain", "單槽替換必須回傳原本的rain")
	assert_eq(snapshot.get("mode", ""), "held")
	assert_eq(snapshot.get("mode_id", -1), GlyphLoadoutScript.Mode.HELD)
	assert_eq(snapshot.get("visible_glyph", ""), "令")
	assert_eq((snapshot.get("component", {}) as Dictionary).get("id", ""), "fire")
	assert_true((snapshot.get("recipe", {}) as Dictionary).is_empty())
	assert_eq((snapshot.get("external_weapon", {}) as Dictionary).get("display_glyph", ""), "火")
	assert_eq((snapshot.get("active_weapon", {}) as Dictionary).get("id", ""), "huo")
	assert_eq(_weapon_manager.get_current_weapon().get("id", ""), "huo")
	assert_eq(_main_glyph.text, "令")
	assert_true(_display.visible, "HELD 必須顯示外置部件")
	assert_eq(_external_glyph.text, "火")


func test_eject回到core並回傳目前部件() -> void:
	_loadout.equip_component_id("fire")
	var ejected: Dictionary = _loadout.eject_component()
	var snapshot: Dictionary = _loadout.get_snapshot()

	assert_eq(ejected.get("id", ""), "fire")
	assert_eq(snapshot.get("mode", ""), "core")
	assert_eq(snapshot.get("visible_glyph", ""), "令")
	assert_true((snapshot.get("component", {}) as Dictionary).is_empty())
	assert_eq((snapshot.get("active_weapon", {}) as Dictionary).get("id", ""), "gong")
	assert_eq(_weapon_manager.get_current_weapon().get("id", ""), "gong")
	assert_eq(_main_glyph.text, "令")
	assert_false(_display.visible)
	assert_eq(_external_glyph.text, "")


func test_snapshot是深拷貝且外部修改不污染loadout() -> void:
	_loadout.equip_component_id("rain")
	var snapshot: Dictionary = _loadout.get_snapshot()

	snapshot["visible_glyph"] = "污染"
	var component: Dictionary = snapshot["component"]
	component["id"] = "polluted_component"
	var recipe: Dictionary = snapshot["recipe"]
	recipe["ability_id"] = "polluted_ability"
	var attack: Dictionary = recipe["attack"]
	attack["id"] = "polluted_attack"
	var active_weapon: Dictionary = snapshot["active_weapon"]
	active_weapon["id"] = "polluted_active"

	var fresh: Dictionary = _loadout.get_snapshot()
	assert_eq(fresh.get("visible_glyph", ""), "零")
	assert_eq((fresh.get("component", {}) as Dictionary).get("id", ""), "rain")
	assert_eq((fresh.get("recipe", {}) as Dictionary).get("ability_id", ""), "reset_burst")
	assert_eq(
		((fresh.get("recipe", {}) as Dictionary).get("attack", {}) as Dictionary).get("id", ""),
		"reset_burst"
	)
	assert_eq((fresh.get("active_weapon", {}) as Dictionary).get("id", ""), "reset_burst")


func test_每次有效狀態轉換只發出一次loadout_changed() -> void:
	watch_signals(_loadout)

	_loadout.equip_component_id("rain")
	assert_signal_emit_count(_loadout, "loadout_changed", 1, "CORE→FUSED 應只送一次")

	_loadout.equip_component_id("fire")
	assert_signal_emit_count(_loadout, "loadout_changed", 2, "FUSED→HELD 應只再送一次")

	_loadout.eject_component()
	assert_signal_emit_count(_loadout, "loadout_changed", 3, "HELD→CORE 應只再送一次")


func test_無效component_id不改狀態也不發signal() -> void:
	var before: Dictionary = _loadout.get_snapshot()
	watch_signals(_loadout)

	var replaced: Dictionary = _loadout.equip_component_id("不存在的部件")

	assert_true(replaced.is_empty())
	assert_eq(_loadout.get_snapshot(), before)
	assert_signal_emit_count(_loadout, "loadout_changed", 0)


func _release_inputs() -> void:
	for action: StringName in [
		&"move_left",
		&"move_right",
		&"jump",
		&"fire",
		&"interact",
		&"eject_component",
	]:
		if Input.is_action_pressed(action):
			Input.action_release(action)
