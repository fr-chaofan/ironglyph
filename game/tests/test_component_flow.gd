## 敵人死亡 → 部件掉落 → 預覽／拾取／交換／彈出的整合流程（Task 2.6）
##
## 使用真實 TestRoom、EnemySpawner、ComponentDropper 與 Player 場景；
## 直接呼叫碰撞callback與try_collect，避免用真實鍵盤時序造成脆弱測試。
extends GutTest

const TestRoomScene := preload("res://scenes/test_room.tscn")
const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")
const FusionResolverScript := preload("res://scripts/fusion_resolver.gd")
const ComponentPickupScript := preload("res://scripts/component_pickup.gd")

const SPAWNER_CASES := [
	[&"SpawnFusionRain", "rain"],
	[&"SpawnHeldMountain", "mountain"],
	[&"SpawnHeldWood", "wood"],
]

var _room: Node2D
var _player: Node2D
var _loadout
var _dropper
var _display: WeaponGlyphDisplay


func before_each() -> void:
	_release_inputs()

	_room = TestRoomScene.instantiate()
	add_child_autofree(_room)
	await wait_physics_frames(3)

	_player = _room.get_node(^"Player") as Node2D
	_loadout = _player.get_node(^"GlyphLoadout")
	_display = _player.get_node(^"WeaponGlyphDisplay") as WeaponGlyphDisplay
	_dropper = _room.get_node(^"EnemySpawners")
	_display.switch_duration = 0.0

	# 測試直接驅動死亡；停掉AI與重生，避免等待期間產生無關攻擊或新敵人。
	for child: Node in _dropper.get_children():
		if child is not EnemySpawner:
			continue
		var spawner := child as EnemySpawner
		spawner.respawn_delay = 0.0
		if spawner.current_enemy != null:
			spawner.current_enemy.set_physics_process(false)


func after_each() -> void:
	_release_inputs()


func test_每個EnemySpawner死亡只掉一個且重複通知或傷害不加倍() -> void:
	for test_case: Array in SPAWNER_CASES:
		var spawner := _dropper.get_node(NodePath(String(test_case[0]))) as EnemySpawner
		var enemy := spawner.current_enemy
		var before := _get_pickups().size()

		assert_not_null(enemy, "%s 應已有敵人" % test_case[0])
		if enemy == null:
			continue

		enemy.take_damage(99999, "neutral")
		# Character 的死亡去重應擋掉重複傷害；Dropper meta 應擋掉重送callback。
		enemy.take_damage(99999, "neutral")
		_dropper._on_enemy_defeated(enemy)
		await wait_process_frames(1)

		var pickups := _get_pickups()
		assert_eq(
			pickups.size(),
			before + 1,
			"%s 每次死亡必須恰好新增一個拾取物" % test_case[0]
		)
		if pickups.size() > before:
			var pickup: Variant = pickups[-1]
			var component: Dictionary = pickup.get("component")
			assert_eq(component.get("id", ""), test_case[1])


func test_rain拾取物顯示令加雨融合成零的預覽() -> void:
	var pickup: Variant = await _defeat_and_get_pickup(&"SpawnFusionRain")
	assert_not_null(pickup)
	if pickup == null:
		return

	pickup.call(&"_on_body_entered", _player)
	var hint := pickup.get_node(^"Hint") as Label
	var preview: Dictionary = _loadout.preview_component_id("rain")

	assert_true(hint.visible)
	assert_eq(hint.text, "E：雨 + 令 → 零")
	assert_eq(preview.get("mode", ""), "fused")
	assert_eq(preview.get("visible_glyph", ""), "零")
	assert_eq(
		(preview.get("active_weapon", {}) as Dictionary).get("id", ""),
		"scattering_rain"
	)


func test_body_entered加try_collect可模擬E並把rain融合成零() -> void:
	var pickup: Variant = await _defeat_and_get_pickup(&"SpawnFusionRain")
	assert_not_null(pickup)
	if pickup == null:
		return

	pickup.call(&"_on_body_entered", _player)
	assert_true(bool(pickup.call(&"try_collect")), "進入範圍後直接try_collect應等同按E")

	var snapshot: Dictionary = _loadout.get_snapshot()
	assert_eq(snapshot.get("mode", ""), "fused")
	assert_eq(snapshot.get("visible_glyph", ""), "零")
	assert_eq((snapshot.get("component", {}) as Dictionary).get("id", ""), "rain")
	assert_eq(_player.get_node(^"HanziSprite").text, "零")
	assert_false(_display.visible)

	await wait_process_frames(2)
	assert_false(is_instance_valid(pickup), "空槽吸收後世界拾取物應被釋放")


func test_E輸入會吸收範圍內的rain() -> void:
	var pickup: Variant = await _defeat_and_get_pickup(&"SpawnFusionRain")
	assert_not_null(pickup)
	if pickup == null:
		return

	pickup.call(&"_on_body_entered", _player)
	Input.action_press(&"interact")
	await wait_process_frames(2)
	Input.action_release(&"interact")
	await wait_process_frames(2)

	assert_eq(_loadout.get_snapshot().get("mode", ""), "fused")
	assert_eq(_player.get_node(^"HanziSprite").text, "零")
	assert_false(is_instance_valid(pickup), "E吸收後原拾取物應被釋放")


func test_替換時同一pickup變成舊rain而不增加節點() -> void:
	_loadout.equip_component_id("rain")
	var pickup: Variant = await _spawn_pickup("mountain", Vector2(80, 120))
	assert_not_null(pickup)
	if pickup == null:
		return

	pickup.call(&"_on_body_entered", _player)
	var before := _get_pickups().size()
	assert_true(bool(pickup.call(&"try_collect")))

	assert_true(is_instance_valid(pickup), "有舊部件時拾取物應原地morph，不可被刪掉")
	assert_eq(_get_pickups().size(), before, "交換不得另外生成第二個拾取物")
	var morphed_component: Dictionary = pickup.get("component")
	assert_eq(morphed_component.get("id", ""), "rain", "同一拾取物應改成被換下的rain")
	assert_eq(pickup.get_node(^"Glyph").text, "雨")

	var snapshot: Dictionary = _loadout.get_snapshot()
	assert_eq(snapshot.get("mode", ""), "held")
	assert_eq((snapshot.get("component", {}) as Dictionary).get("id", ""), "mountain")
	assert_eq(snapshot.get("visible_glyph", ""), "令")
	assert_eq((snapshot.get("active_weapon", {}) as Dictionary).get("id", ""), "tu")


func test_eject_signal由dropper轉成恰好一個世界pickup() -> void:
	_loadout.equip_component_id("mountain")
	var before := _get_pickups().size()
	var ejected: Dictionary = _loadout.eject_component()
	var eject_position := _player.global_position

	# 等價於GlyphLoadout收到Q後送出的signal；直接emit避免鍵盤frame時序脆弱。
	_loadout.component_ejected.emit(ejected.duplicate(true), eject_position)
	await wait_process_frames(1)

	var pickups := _get_pickups()
	assert_eq(pickups.size(), before + 1)
	if pickups.size() <= before:
		return

	var pickup: Variant = pickups[-1]
	var component: Dictionary = pickup.get("component")
	assert_eq(component.get("id", ""), "mountain")
	assert_eq(pickup.global_position, eject_position)
	assert_eq(_loadout.get_snapshot().get("mode", ""), "core")


func test_Q輸入會彈出目前部件並回到CORE() -> void:
	_loadout.equip_component_id("mountain")
	var before := _get_pickups().size()

	Input.action_press(&"eject_component")
	await wait_process_frames(2)
	Input.action_release(&"eject_component")
	await wait_process_frames(2)

	assert_eq(_loadout.get_snapshot().get("mode", ""), "core")
	assert_eq(_player.get_node(^"HanziSprite").text, "令")
	var pickups := _get_pickups()
	assert_eq(pickups.size(), before + 1, "Q每次只應彈出一個世界部件")
	if pickups.size() > before:
		var pickup: Variant = pickups[-1]
		var component: Dictionary = pickup.get("component")
		assert_eq(component.get("id", ""), "mountain")
		pickup.call(&"_on_body_entered", _player)
		assert_false(
			bool(pickup.call(&"try_collect")),
			"Q彈出的部件必須有短暫防重拾鎖，不能在同一位置立即吸回"
		)
		await wait_seconds(0.25)
		assert_true(
			bool(pickup.call(&"try_collect")),
			"防重拾鎖結束後應可正常再次吸收"
		)


func test_pickup主字與外置字永遠保持正向scale() -> void:
	var pickup: Variant = await _spawn_pickup("mountain", Vector2(80, 120))
	assert_not_null(pickup)
	if pickup == null:
		return

	var pickup_glyph := pickup.get_node(^"Glyph") as Label
	assert_gt(pickup.scale.x, 0.0)
	assert_gt(pickup_glyph.scale.x, 0.0)

	pickup.call(&"_on_body_entered", _player)
	assert_true(bool(pickup.call(&"try_collect")))

	var main_glyph := _player.get_node(^"HanziSprite") as HanziSprite
	var external_glyph := _display.get_node(^"Glyph") as Label
	_display.set_facing(-1.0)

	assert_eq(_loadout.get_snapshot().get("mode", ""), "held")
	assert_eq(main_glyph.text, "令")
	assert_eq(external_glyph.text, "山")
	assert_true(_display.visible)
	assert_lt(_display.position.x, 0.0, "朝左只應換側")
	assert_gt(main_glyph.scale.x, 0.0, "主字不可鏡像")
	assert_gt(_display.scale.x, 0.0, "外置顯示容器不可鏡像")
	assert_gt(external_glyph.scale.x, 0.0, "外置部件字不可鏡像")


func test_真實子彈碰撞擊殺延後掉落且沒有physics_flush錯誤() -> void:
	var spawner := _dropper.get_node(^"SpawnFusionRain") as EnemySpawner
	var enemy := spawner.current_enemy
	var before := _get_pickups().size()

	assert_not_null(enemy, "rain spawner 應已有敵人")
	if enemy == null:
		return

	# 不能直接呼叫 take_damage：bug 只會在 Area2D.body_entered 的 physics
	# query callback 內同步 add_child(Area2D) 時發生。
	var bullet := BulletScene.instantiate() as Bullet
	_room.add_child(bullet)
	bullet.setup(99999, "neutral", enemy.global_position, Vector2.ZERO)
	await wait_physics_frames(3)
	await wait_process_frames(1)

	var pickups := _get_pickups()
	assert_eq(pickups.size(), before + 1, "真實碰撞死亡也只能生成一個部件")
	if pickups.size() > before:
		var component: Dictionary = pickups[-1].get("component")
		assert_eq(component.get("id", ""), "rain")
	assert_engine_error(0, "掉落 Area2D 不得在 flushing physics queries 時啟用碰撞")

	# HanziSprite 把死亡碎片掛在 current_scene，而不是 TestRoom 子樹；
	# 等待這次真實擊殺的動畫自行清乾淨，避免污染後續以全局碎片數驗證的 enemy tests。
	await wait_seconds(0.8)


func _defeat_and_get_pickup(spawner_name: StringName):
	var before := _get_pickups().size()
	var spawner := _dropper.get_node_or_null(NodePath(String(spawner_name))) as EnemySpawner
	if spawner == null or spawner.current_enemy == null:
		return null

	spawner.current_enemy.take_damage(99999, "neutral")
	await wait_process_frames(1)
	var pickups := _get_pickups()
	if pickups.size() != before + 1:
		return null
	return pickups[-1]


func _spawn_pickup(component_id: String, world_position: Vector2):
	var resolver = FusionResolverScript.new()
	var component: Dictionary = resolver.get_component(component_id)
	if component.is_empty():
		return null
	var pickup: Variant = _dropper.call(&"_spawn_pickup", component, world_position)
	await wait_process_frames(1)
	return pickup


func _get_pickups() -> Array:
	var pickups: Array = []
	for child: Node in _dropper.get_children():
		if child.get_script() == ComponentPickupScript or child.is_in_group(&"component_pickup"):
			pickups.append(child)
	return pickups


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
