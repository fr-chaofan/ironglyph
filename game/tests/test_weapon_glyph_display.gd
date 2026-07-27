## 世界空間武器字形顯示（Task 2.5）
##
## 武器字形是 Player 身上的視覺元件，不是 HUD。它必須跟隨玩家、依朝向換邊，
## 但漢字本身永遠保持正向。切換動畫也必須能承受快速連按而回到穩定狀態。
extends GutTest

var PlayerScene := preload("res://scenes/player.tscn")

var _player: Node2D
var _display: Node2D
var _glyph: Label
var _wm: WeaponManager


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	await wait_physics_frames(2)

	_display = _player.get_node(^"WeaponGlyphDisplay")
	_glyph = _display.get_node(^"Glyph")
	_wm = _player.get_node(^"WeaponManager")


func after_each() -> void:
	for action: StringName in [&"move_left", &"move_right"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func test_顯示器掛在Player世界空間而不是HUD() -> void:
	assert_eq(_display.get_parent(), _player, "WeaponGlyphDisplay 必須是 Player 的直接子節點")
	assert_true(_display is Node2D, "世界空間顯示器應是 Node2D")
	assert_true(_glyph is Label, "WeaponGlyphDisplay 應以 Glyph Label 顯示字形")

	var ancestor: Node = _display.get_parent()
	while ancestor != null:
		assert_false(ancestor is CanvasLayer, "武器字形的祖先不可有 HUD CanvasLayer")
		ancestor = ancestor.get_parent()


func test_初始訊號不論ready順序都會同步水武器() -> void:
	# WeaponManager 可能在 Display 之前或之後 ready；顯示器不能依賴只收到一次的初始訊號。
	await _wait_for_switch_animation()

	assert_eq(_wm.current_index, 0)
	assert_eq(_glyph.text, "氵", "首幀應主動同步目前武器，不能因 ready 順序漏掉初始訊號")
	assert_true(_display.visible)
	_assert_display_rgb(Bullet.ELEMENT_COLORS["water"], "初始水武器")


func test_切換到下一把會顯示灬與火屬性色() -> void:
	_wm.cycle_weapon(1)
	await _wait_for_switch_animation()

	assert_eq(_wm.current_index, 1)
	assert_eq(_glyph.text, "灬")
	_assert_display_rgb(Bullet.ELEMENT_COLORS["fire"], "火武器")


func test_全部10把武器的字形顏色與字型涵蓋都正確() -> void:
	assert_eq(_wm.weapons.size(), 10, "本測試固定涵蓋目前的 10 把武器")

	var font: Font = _glyph.get_theme_font(&"font")
	assert_not_null(font, "Glyph Label 必須配置專案中文字型")
	if font == null:
		return

	for weapon: Dictionary in _wm.weapons:
		_display.call(&"set_weapon", weapon)
		await _wait_for_switch_animation()

		var radical := String(weapon.get("radical", ""))
		var element := String(weapon.get("element", "neutral"))
		assert_eq(_glyph.text, radical, "武器 %s 應顯示自己的部首" % weapon.get("id", "?"))
		_assert_display_rgb(
			Bullet.ELEMENT_COLORS.get(element, Color.WHITE),
			"武器 %s" % weapon.get("id", "?")
		)

		for i in radical.length():
			assert_true(
				font.has_char(radical.unicode_at(i)),
				"武器 %s 的字形「%s」不在 Glyph 使用的字型裡" % [weapon.get("id", "?"), radical]
			)


func test_往前切換會繞回石武器() -> void:
	_wm.cycle_weapon(-1)
	await _wait_for_switch_animation()

	assert_eq(_wm.current_index, 9)
	assert_eq(_glyph.text, "石")
	_assert_display_rgb(Bullet.ELEMENT_COLORS["earth"], "反向繞回的石武器")


func test_左右朝向只換邊不鏡像字形() -> void:
	await _wait_for_switch_animation()
	var original_text := _glyph.text

	Input.action_press(&"move_left")
	await wait_physics_frames(3)
	Input.action_release(&"move_left")
	assert_lt(_display.position.x, 0.0, "朝左時武器應移到玩家左側")
	assert_gt(_display.scale.x, 0.0, "換到左側不能用負 scale.x")
	assert_gt(_glyph.scale.x, 0.0, "漢字本身永遠保持正向")
	assert_eq(_glyph.text, original_text, "換朝向不應改變目前武器字形")

	Input.action_press(&"move_right")
	await wait_physics_frames(3)
	Input.action_release(&"move_right")
	assert_gt(_display.position.x, 0.0, "朝右時武器應回到玩家右側")
	assert_gt(_display.scale.x, 0.0, "朝右時顯示器不可鏡像")
	assert_gt(_glyph.scale.x, 0.0, "朝右時字形不可鏡像")


func test_display_glyph優先於radical供未來組字使用() -> void:
	_display.call(&"set_weapon", {
		"display_glyph": "河",
		"radical": "氵",
		"element": "water",
	})
	await _wait_for_switch_animation()

	assert_eq(_glyph.text, "河", "組字系統提供 display_glyph 後應優先顯示完整字")
	_assert_display_rgb(Bullet.ELEMENT_COLORS["water"], "未來組字顯示")


func test_快速切換17次後收斂到最後一把且動畫狀態復原() -> void:
	await _wait_for_switch_animation()
	var settled_scale := _display.scale
	assert_almost_eq(_display.modulate.a, 1.0, 0.01, "初始動畫結束後應完全可見")

	for i in range(17):
		_wm.cycle_weapon(1)

	await _wait_for_switch_animation()
	var expected: Dictionary = _wm.get_current_weapon()
	var expected_element := String(expected.get("element", "neutral"))

	assert_eq(_wm.current_index, 7, "從第 0 把前進 17 次應停在第 7 把")
	assert_eq(_glyph.text, "扌")
	assert_eq(_glyph.text, expected.get("radical", ""))
	_assert_display_rgb(Bullet.ELEMENT_COLORS.get(expected_element, Color.WHITE), "快速切換後")
	assert_almost_eq(_display.scale.x, settled_scale.x, 0.01, "快速切換後 X 縮放應復原")
	assert_almost_eq(_display.scale.y, settled_scale.y, 0.01, "快速切換後 Y 縮放應復原")
	assert_almost_eq(_display.modulate.a, 1.0, 0.01, "快速切換後不應停在半透明狀態")
	assert_almost_eq(_glyph.modulate.a, 1.0, 0.01, "Glyph 不應殘留半透明")


func test_空武器會隱藏清空而有效武器可恢復() -> void:
	_display.call(&"set_weapon", {})
	await wait_process_frames(2)

	assert_false(_display.visible, "空武器不應留下舊字形")
	assert_eq(_glyph.text, "", "空武器必須清掉舊文字")

	var water: Dictionary = _wm.weapons[0]
	_display.call(&"set_weapon", water)
	await _wait_for_switch_animation()

	assert_true(_display.visible, "重新收到有效武器後應恢復顯示")
	assert_eq(_glyph.text, "氵")
	_assert_display_rgb(Bullet.ELEMENT_COLORS["water"], "空武器恢復後")
	assert_gt(_display.scale.x, 0.0)
	assert_almost_eq(_display.modulate.a, 1.0, 0.01)


func test_Player死亡時武器字形立即隱藏() -> void:
	_player.died.emit()
	await wait_process_frames(2)

	assert_false(_display.visible, "Player 死亡後不可留下懸浮武器字形")
	assert_eq(_glyph.text, "")


func test_缺少WeaponManager時安全隱藏() -> void:
	var owner := Node2D.new()
	add_child_autofree(owner)

	var display := WeaponGlyphDisplay.new()
	var glyph := Label.new()
	glyph.name = "Glyph"
	display.add_child(glyph)
	owner.add_child(display)
	await wait_process_frames(2)

	assert_false(display.visible, "找不到 WeaponManager 時應保持隱藏")
	assert_eq(glyph.text, "")
	assert_gt(display.scale.x, 0.0, "缺少 manager 也不可產生鏡像縮放")


func _wait_for_switch_animation() -> void:
	# 預設動畫很短；留兩倍以上餘裕並補 process frames，避免在 tween 中途取樣。
	await wait_seconds(0.35)
	await wait_process_frames(2)


func _assert_display_rgb(expected: Color, context: String) -> void:
	var actual := _effective_glyph_color()
	assert_almost_eq(actual.r, expected.r, 0.01, "%s 的紅色分量不符" % context)
	assert_almost_eq(actual.g, expected.g, 0.01, "%s 的綠色分量不符" % context)
	assert_almost_eq(actual.b, expected.b, 0.01, "%s 的藍色分量不符" % context)


func _effective_glyph_color() -> Color:
	# 容許實作把元素色放在 Label font_color、Label modulate 或父 Node2D；
	# 測試的是最後畫面色彩，不把 UI 實作鎖死在其中一種 property。
	var color := _glyph.get_theme_color(&"font_color")
	color = _multiply_rgb(color, _glyph.self_modulate)
	color = _multiply_rgb(color, _glyph.modulate)
	color = _multiply_rgb(color, _display.self_modulate)
	color = _multiply_rgb(color, _display.modulate)
	return color


func _multiply_rgb(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)


func test_復活後字形能重新顯示() -> void:
	# _owner_dead 一旦設起來就沒有東西會清掉它。階段四存檔點復活是第一個
	# 會觸發的情境，屆時沒有 revive() 就會變成「復活後武器字形永遠不見」。
	var player := PlayerScene.instantiate()
	add_child_autofree(player)
	await wait_physics_frames(2)

	var display: WeaponGlyphDisplay = player.get_node(^"WeaponGlyphDisplay")
	assert_true(display.visible, "初始應顯示")

	player.died.emit()
	await wait_physics_frames(1)
	assert_false(display.visible, "死亡後應隱藏")

	display.revive()
	await wait_physics_frames(1)
	assert_true(display.visible, "復活後應重新顯示")
	assert_eq(display.get_node(^"Glyph").text, "氵", "應恢復成目前武器的部首")
