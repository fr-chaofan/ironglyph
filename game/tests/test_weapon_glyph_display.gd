## Task 2.5 世界空間武器字形顯示 × Task 2.6 單槽裝備整合。
##
## 完整融合字顯示在主 HanziSprite；旁側 Glyph 只顯示 HELD 部件。
## 無論哪種狀態，漢字都不可因朝向而鏡像。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")

var _player: Node2D
var _display: WeaponGlyphDisplay
var _glyph: Label
var _wm: WeaponManager
var _loadout: Node
var _sprite: HanziSprite


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(2)

	_display = _player.get_node(^"WeaponGlyphDisplay")
	_glyph = _display.get_node(^"Glyph")
	_wm = _player.get_node(^"WeaponManager")
	_loadout = _player.get_node(^"GlyphLoadout")
	_sprite = _player.get_node(^"HanziSprite")


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func test_顯示器掛在Player世界空間而不是HUD() -> void:
	assert_eq(_display.get_parent(), _player, "WeaponGlyphDisplay 必須是 Player 的直接子節點")
	assert_true(_display is Node2D)
	assert_true(_glyph is Label)

	var ancestor: Node = _display.get_parent()
	while ancestor != null:
		assert_false(ancestor is CanvasLayer, "武器字形的祖先不可有 HUD CanvasLayer")
		ancestor = ancestor.get_parent()


func test_CORE顯示令並隱藏外置部件() -> void:
	assert_eq(_loadout.get_snapshot().get("mode", ""), "core")
	assert_eq(_sprite.text, "令")
	assert_eq(_wm.get_current_weapon().get("id", ""), "gong")
	assert_false(_display.visible)
	assert_eq(_glyph.text, "")


func test_HELD保持令並顯示氵與水屬色() -> void:
	_loadout.equip_component_id("water")
	await _wait_for_switch_animation()

	assert_eq(_loadout.get_snapshot().get("mode", ""), "held")
	assert_eq(_sprite.text, "令")
	assert_eq(_wm.get_current_weapon().get("id", ""), "shui")
	assert_true(_display.visible)
	assert_eq(_glyph.text, "氵")
	_assert_display_rgb(
		ComponentGlyph.wash(Bullet.ELEMENT_COLORS["water"]), "HELD 水部件")


func test_FUSED顯示零並隱藏外置部件() -> void:
	_loadout.equip_component_id("rain")
	await wait_process_frames(2)

	assert_eq(_loadout.get_snapshot().get("mode", ""), "fused")
	assert_eq(_sprite.text, "零")
	assert_eq(_wm.get_current_weapon().get("id", ""), "reset_burst")
	assert_false(_display.visible)
	assert_eq(_glyph.text, "")


func test_金部使用可渲染的金而不是缺字的釒() -> void:
	_loadout.equip_component_id("metal")
	await _wait_for_switch_animation()

	assert_eq(_sprite.text, "令")
	assert_eq(_glyph.text, "金")
	assert_ne(_glyph.text, "釒")
	_assert_display_rgb(
		ComponentGlyph.wash(Bullet.ELEMENT_COLORS["metal"]), "HELD 金部件")


func test_左右朝向只換邊不鏡像字形() -> void:
	_loadout.equip_component_id("water")
	await _wait_for_switch_animation()
	var original_text := _glyph.text

	Input.action_press(&"move_left")
	await wait_physics_frames(3)
	Input.action_release(&"move_left")
	assert_lt(_display.position.x, 0.0)
	assert_gt(_display.scale.x, 0.0)
	assert_gt(_glyph.scale.x, 0.0)
	assert_gt(_sprite.scale.x, 0.0)
	assert_eq(_glyph.text, original_text)

	Input.action_press(&"move_right")
	await wait_physics_frames(3)
	Input.action_release(&"move_right")
	assert_gt(_display.position.x, 0.0)
	assert_gt(_display.scale.x, 0.0)
	assert_gt(_glyph.scale.x, 0.0)
	assert_gt(_sprite.scale.x, 0.0)


func test_快速替換部件後動畫收斂到最後狀態() -> void:
	var resolver := FusionResolverScript.new()
	var component_ids := ["water", "fire", "wood", "stone"]
	for index in range(17):
		_loadout.equip_component_id(component_ids[index % component_ids.size()])

	await _wait_for_switch_animation()
	var expected := resolver.get_component(component_ids[16 % component_ids.size()])
	assert_eq(_loadout.get_snapshot().get("mode", ""), "held")
	assert_eq(_glyph.text, expected.get("display_glyph", ""))
	assert_true(_display.visible)
	assert_gt(_display.scale.x, 0.0)
	assert_almost_eq(_glyph.modulate.a, 1.0, 0.01)


func test_Player死亡時立即隱藏且復活後按loadout恢復() -> void:
	_loadout.equip_component_id("wood")
	await _wait_for_switch_animation()
	assert_true(_display.visible)

	_player.died.emit()
	await wait_process_frames(2)
	assert_false(_display.visible)
	assert_eq(_glyph.text, "")

	_display.revive()
	await _wait_for_switch_animation()
	assert_true(_display.visible)
	assert_eq(_glyph.text, "木")


func test_缺少Loadout與WeaponManager時安全隱藏() -> void:
	var owner := Node2D.new()
	add_child_autofree(owner)

	var display := WeaponGlyphDisplay.new()
	var glyph := Label.new()
	glyph.name = "Glyph"
	display.add_child(glyph)
	owner.add_child(display)
	await wait_process_frames(2)

	assert_false(display.visible)
	assert_eq(glyph.text, "")
	assert_gt(display.scale.x, 0.0)


func _wait_for_switch_animation() -> void:
	await wait_seconds(0.35)
	await wait_process_frames(2)


func _assert_display_rgb(expected: Color, context: String) -> void:
	var actual := _effective_glyph_color()
	assert_almost_eq(actual.r, expected.r, 0.01, "%s 的紅色分量不符" % context)
	assert_almost_eq(actual.g, expected.g, 0.01, "%s 的綠色分量不符" % context)
	assert_almost_eq(actual.b, expected.b, 0.01, "%s 的藍色分量不符" % context)


func _effective_glyph_color() -> Color:
	var color := _glyph.get_theme_color(&"font_color")
	color = _multiply_rgb(color, _glyph.self_modulate)
	color = _multiply_rgb(color, _glyph.modulate)
	color = _multiply_rgb(color, _display.self_modulate)
	color = _multiply_rgb(color, _display.modulate)
	return color


func _multiply_rgb(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)
