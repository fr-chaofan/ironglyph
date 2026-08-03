## 掉落部件的存活時間
##
## 敵人會不斷重生，不設上限的話地上很快堆滿部件，玩家分不出哪個是剛掉的。
extends GutTest

const PickupScene := preload("res://scenes/component_pickup.tscn")

const WATER := {"id": "water", "display_glyph": "氵", "element": "water", "fallback_weapon_id": "shui"}
const FIRE := {"id": "fire", "display_glyph": "火", "element": "fire", "fallback_weapon_id": "huo"}


func _spawn() -> ComponentPickup:
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	pickup.setup(WATER)
	await wait_physics_frames(1)
	return pickup


func test_沒被撿走會消失() -> void:
	var pickup: ComponentPickup = await _spawn()
	assert_gt(pickup.lifetime, 0.0, "必須有存活上限")

	pickup._update_lifetime(pickup.lifetime + 0.1)
	assert_true(pickup.is_queued_for_deletion(), "超過存活時間必須消失")


func test_時間內不會消失() -> void:
	var pickup: ComponentPickup = await _spawn()
	pickup._update_lifetime(pickup.lifetime * 0.5)
	assert_false(pickup.is_queued_for_deletion())


func test_最後幾秒會閃爍預告() -> void:
	# 直接消失的話玩家會以為是 bug
	var pickup: ComponentPickup = await _spawn()
	pickup._update_lifetime(pickup.lifetime - pickup.expire_warning * 0.5)

	assert_lt(pickup.modulate.a, 1.0, "接近消失時應該在閃")
	assert_gt(pickup.modulate.a, 0.0, "閃爍不該閃到完全看不見")


func test_交換部件會重置倒數() -> void:
	# ⚠️ 交換是就地把同一個節點換成舊部件（不銷毀重生成）。
	# 不重置的話，換下來的部件會繼承前一個快到期的倒數，一放下就消失。
	var pickup: ComponentPickup = await _spawn()
	pickup._update_lifetime(pickup.lifetime - 0.5)
	assert_lt(pickup.modulate.a, 1.0, "前置條件：此時已經在閃了")

	pickup.setup(FIRE)
	assert_almost_eq(pickup.modulate.a, 1.0, 0.01, "換了部件就該從頭倒數")

	pickup._update_lifetime(pickup.lifetime - 1.0)
	assert_false(pickup.is_queued_for_deletion(), "重置後不該立刻消失")


func test_沒呼叫setup也不會立刻消失() -> void:
	# ⚠️ 倒數若只在 setup() 裡初始化，沒呼叫 setup 就進場景樹的拾取物
	# 會拿到 _life_left = 0，第一幀就消失。
	var pickup: ComponentPickup = PickupScene.instantiate()
	add_child_autofree(pickup)
	await wait_physics_frames(2)

	assert_false(pickup.is_queued_for_deletion(), "沒 setup 的拾取物不該立刻消失")


func test_lifetime設為0則永不消失() -> void:
	var pickup: ComponentPickup = await _spawn()
	pickup.lifetime = 0.0
	pickup._update_lifetime(999.0)
	assert_false(pickup.is_queued_for_deletion(), "0 表示永不消失，留給日後的關鍵道具")


func test_消失前仍然可以被撿走() -> void:
	# 閃爍只是預告，不該提前失去功能
	var pickup: ComponentPickup = await _spawn()
	pickup._update_lifetime(pickup.lifetime - pickup.expire_warning * 0.5)

	assert_false(pickup.component.is_empty(), "閃爍期間部件資料仍在")
	assert_false(pickup.is_queued_for_deletion())
