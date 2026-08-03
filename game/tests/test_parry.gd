## 回鋒（彈反）
##
## 近戰判定窗的**前段**打到敵彈就把它打回去，後段照舊消彈。
## 命名取自書法的回鋒——筆畫收尾時反向回轉筆尖。
##
## 在此之前近戰對敵彈只有一種結果：`queue_free()`。整個判定窗都消彈，
## 代表按 K 的時機完全不影響結果，遠程敵人變成純粹的「站定挨打或繞開」。
##
## ⚠️ 這裡大量使用**自訂 profile**（windup 0、active 1.0）而不是真的 令筆擊。
## 真 profile 的判定窗只有 0.12s，測試要在裡面精準落點就得跟物理影格搶時間；
## 把窗拉長之後，「前段／後段」用 `_physics_process()` 手動推進即可穩定重現。
extends GutTest

const PlayerScene := preload("res://scenes/player.tscn")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")

## 判定窗拉長到 1 秒，回鋒窗維持與 令筆擊 相同的 0.06s
const SLOW_PROFILE := {
	"id": "test_slow", "name": "測試", "glyph": "令", "element": "neutral",
	"damage": 10, "cooldown": 2.0, "windup": 0.0, "active": 1.0,
	"reach": 58, "parry_window": 0.06, "hitbox": [72, 56],
}

var _player: Node2D
var _melee: MeleeAttack


func before_each() -> void:
	_player = PlayerScene.instantiate()
	add_child_autofree(_player)
	_player.global_position = Vector2.ZERO
	_melee = _player.get_node(^"MeleeAttack") as MeleeAttack
	_melee.show_arc = false
	# 位置必須是確定的：開著物理處理的話玩家會一直下墜，判定框跟著跑掉
	_player.set_physics_process(false)
	await wait_physics_frames(2)


func _spawn_enemy_bullet(offset: Vector2, shooter: Node2D = null) -> Bullet:
	var bullet: Bullet = BulletScene.instantiate()
	bullet.collision_layer = EnemyAIShared.ENEMY_BULLET_LAYER
	bullet.collision_mask = EnemyAIShared.ENEMY_BULLET_MASK
	bullet.speed = 0.0
	bullet.position = _player.global_position + offset
	bullet.shooter = shooter
	add_child_autofree(bullet)
	bullet.setup(5, "fire", _player.global_position + offset, Vector2.RIGHT)
	await wait_physics_frames(1)
	return bullet


func _spawn_enemy(offset: Vector2, element: String = "water") -> Enemy:
	var enemy: Enemy = EnemyScene.instantiate()
	enemy.position = _player.global_position + offset
	enemy.set_physics_process(false)
	add_child_autofree(enemy)
	enemy.setup({
		"char": "河", "element": element, "ai": "patrol_ranged",
		"hp": 300, "damage": 0, "speed": 0,
	})
	await wait_physics_frames(1)
	return enemy


## 在**後段**判定打到子彈：先把回鋒窗空推過去，再放子彈進場。
## 這正是實機上「按太早」的樣子——揮出去的時候子彈還沒飛到。
func _swing_then_late_bullet() -> Bullet:
	_melee.swing(1.0, SLOW_PROFILE)
	_melee._physics_process(0.1)  # 0.1 > parry_window 0.06
	return await _spawn_enemy_bullet(Vector2(80, 0))


# ---- 兩種結果 ----

func test_前段打到敵彈是彈反而不是消彈() -> void:
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))

	watch_signals(_melee)
	_melee.swing(1.0, SLOW_PROFILE)  # windup 0 → 當幀進判定，elapsed = 0

	assert_signal_emit_count(_melee, "bullet_parried", 1)
	assert_signal_emit_count(_melee, "bullet_blocked", 0, "彈反成功就不該同時算消彈")
	assert_false(bullet.is_queued_for_deletion(), "彈反的子彈要留在場上，不是被打掉")


func test_後段打到敵彈只消彈() -> void:
	# 後段仍然消彈是刻意的：彈反是**獎勵層**，不是生存必需。
	# 失手就吃彈的話，遠程敵人會從「可以硬吃一下」變成瞬間致命。
	watch_signals(_melee)
	var bullet: Bullet = await _swing_then_late_bullet()
	await wait_physics_frames(2)

	assert_signal_emit_count(_melee, "bullet_blocked", 1)
	assert_signal_emit_count(_melee, "bullet_parried", 0, "過了回鋒窗就只能消彈")
	# ⚠️ 這裡不能直接呼叫 is_queued_for_deletion()——await 了兩幀之後，
	# queue_free 的子彈很可能**已經真的被釋放**，對已釋放的實例呼叫方法會噴錯。
	assert_false(is_instance_valid(bullet) and not bullet.is_queued_for_deletion())


func test_沒有回鋒窗的profile不能彈反() -> void:
	# parry_window 缺省為 0，舊 profile 不會憑空獲得彈反能力
	var no_parry := SLOW_PROFILE.duplicate()
	no_parry.erase("parry_window")
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))

	watch_signals(_melee)
	_melee.swing(1.0, no_parry)

	assert_signal_emit_count(_melee, "bullet_parried", 0)
	assert_true(bullet.is_queued_for_deletion(), "不能彈反就退回消彈，不是放它過去")


# ---- 彈反之後的子彈 ----

func test_彈反後換到玩家陣營() -> void:
	# ⚠️ 只調頭不換層的話，子彈飛回去對敵人毫無作用——這是最容易漏的一半
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	_melee.swing(1.0, SLOW_PROFILE)
	# 碰撞層走 set_deferred（物理查詢期間不可同步改），要等一幀才真的換過去
	await wait_physics_frames(1)

	assert_eq(bullet.collision_layer, Bullet.PLAYER_BULLET_LAYER, "應該變成玩家子彈")
	assert_eq(bullet.collision_mask, Bullet.PLAYER_BULLET_MASK, "應該改打敵人與地形")
	assert_eq(bullet.shooter, _player, "回血之類的結算要算在彈反的人頭上")


func test_彈反會調頭打回原射手() -> void:
	# 純粹反向的話，斜射的子彈會被彈進地板
	var enemy: Enemy = await _spawn_enemy(Vector2(200, -160))
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0), enemy)
	bullet.direction = Vector2.LEFT

	_melee.swing(1.0, SLOW_PROFILE)

	var expected := (enemy.global_position - bullet.global_position).normalized()
	assert_almost_eq(bullet.direction.x, expected.x, 0.01)
	assert_almost_eq(bullet.direction.y, expected.y, 0.01, "要瞄回射手，不是水平反向")


func test_射手已經死掉時退回單純反向() -> void:
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	bullet.direction = Vector2.LEFT

	_melee.swing(1.0, SLOW_PROFILE)

	assert_almost_eq(bullet.direction.x, 1.0, 0.01, "沒有射手就原路打回去")


func test_彈反改成筆擊的屬性() -> void:
	# ⚠️ 保留敵人的屬性看似公平，實際上最常見的情況是把火彈打回火敵——
	# 同屬性沒有相剋加成，打回去像撓癢。改成筆擊的屬性，設定上也才對：
	# 你用你的字改寫了他的字。
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	assert_eq(bullet.element, "fire", "前置條件：這是一發火屬敵彈")

	var dao := MeleeAttack.get_profile("dao_slash")
	_melee.swing(1.0, _long_window(dao))

	assert_eq(bullet.element, "metal", "刀刃筆擊彈反出去的是金屬性")


func test_彈反傷害是原傷害的倍數() -> void:
	# 用倍數而不是固定值：階段五 Boss 的重彈自動變重，不必逐關調
	var scale := float(MeleeAttack.get_parry_settings().get("damage_scale", 2.0))
	assert_gt(scale, 1.0, "彈反該比原本更痛，否則沒有理由冒險")

	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	_melee.swing(1.0, SLOW_PROFILE)

	assert_eq(bullet.damage, int(round(5.0 * scale)))


func test_彈反不會把敵人的技能帶回去() -> void:
	# ⚠️ 目前敵彈沒有 ability，但階段五 Boss 會有。屆時「打斷蓄力」帶著新的
	# shooter 反過來作用在敵人身上，會變成無法預期的白送。
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	bullet.ability = {"interrupt": true, "heal": 99}

	_melee.swing(1.0, SLOW_PROFILE)

	assert_true(bullet.ability.is_empty(), "回鋒還回去的是一筆乾淨的墨")


func test_彈反重置射程計時() -> void:
	# 不重置的話，飛了大半程才被彈反的子彈會在半路蒸發
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	bullet.max_distance = 300.0
	bullet._travelled = 290.0
	bullet._age = bullet.max_lifetime - 0.05

	_melee.swing(1.0, SLOW_PROFILE)
	bullet.speed = 400.0
	await wait_physics_frames(3)

	assert_false(bullet.is_queued_for_deletion(), "彈反等於重新出膛，射程要從頭算")


func test_彈反的子彈真的打得死敵人() -> void:
	var enemy: Enemy = await _spawn_enemy(Vector2(200, 0), "wood")
	enemy.max_hp = 40
	enemy.hp = 40
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0), enemy)

	_melee.swing(1.0, SLOW_PROFILE)
	await wait_physics_frames(1)
	bullet.speed = 600.0
	await wait_physics_frames(20)

	assert_lt(enemy.hp, 40, "彈反出去的子彈要能真的打到敵人身上")


# ---- 邊界 ----

func test_不會彈反玩家自己的子彈() -> void:
	# player_bullet 層不在 block_mask 裡，根本走不到彈反那條路
	var bullet: Bullet = BulletScene.instantiate()
	bullet.speed = 0.0
	bullet.position = Vector2(80, 0)
	add_child_autofree(bullet)
	bullet.setup(5, "neutral", Vector2(80, 0), Vector2.RIGHT)
	await wait_physics_frames(1)

	watch_signals(_melee)
	_melee.swing(1.0, SLOW_PROFILE)

	assert_signal_emit_count(_melee, "bullet_parried", 0)
	assert_eq(bullet.direction, Vector2.RIGHT, "自己的子彈不該被自己打回來")


func test_敵人不能彈反() -> void:
	# 近戰敵人能把玩家的子彈打回來的話，遠程流直接報廢
	var enemy: Enemy = await _spawn_enemy(Vector2(400, 0))
	var enemy_melee := enemy.get_node_or_null(^"MeleeAttack") as MeleeAttack
	assert_not_null(enemy_melee, "前置條件：敵人身上有近戰元件")
	if enemy_melee == null:
		return

	assert_false(enemy_melee.can_parry, "敵人不可以彈反")
	assert_eq(enemy_melee.block_mask, 0, "敵人連消彈都不行")


func test_下劈彈反照樣彈起來() -> void:
	# 消彈本來就能踩著彈跳；彈反不該反而失去這個位移手段
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(0, 52))

	watch_signals(_melee)
	_melee.swing(1.0, SLOW_PROFILE, MeleeAttack.Vertical.DOWN)
	# 下劈的前搖來自 pogo 區塊（0.06s），會蓋掉 SLOW_PROFILE 的 0——推過去才進判定
	_melee._physics_process(0.07)

	assert_signal_emit_count(_melee, "bullet_parried", 1)
	assert_signal_emit_count(_melee, "pogo_bounced", 1, "彈反也要能踩著跳")


func test_一次揮擊同一發子彈只結算一次() -> void:
	# 彈反之後子彈還留在判定框裡；不去重的話會被反覆彈反、傷害倍數疊到爆表
	var bullet: Bullet = await _spawn_enemy_bullet(Vector2(80, 0))
	var scale := float(MeleeAttack.get_parry_settings().get("damage_scale", 2.0))

	watch_signals(_melee)
	_melee.swing(1.0, SLOW_PROFILE)
	_melee._physics_process(0.01)
	_melee._physics_process(0.01)

	assert_signal_emit_count(_melee, "bullet_parried", 1)
	assert_eq(bullet.damage, int(round(5.0 * scale)), "傷害不可以疊加")


# ---- 資料 ----

func test_刀刃筆擊的回鋒窗比令筆擊寬() -> void:
	# 「刂」除了穿透之外的第二層價值：彈反更好按，屬性也更有用（金剋木）
	var ling := float(MeleeAttack.get_profile("ling_slash").get("parry_window", 0.0))
	var dao := float(MeleeAttack.get_profile("dao_slash").get("parry_window", 0.0))

	assert_gt(ling, 0.0, "基礎筆擊就該能彈反——彈反是操作技術，不是掉落運氣")
	assert_gt(dao, ling, "刀刃筆擊的窗要更寬")


func test_回鋒窗必須短於判定窗() -> void:
	# 兩者相等的話整個判定窗都能彈反，時機就完全不重要了
	for id: String in ["ling_slash", "dao_slash"]:
		var profile := MeleeAttack.get_profile(id)
		assert_lt(
			float(profile.get("parry_window", 0.0)),
			float(profile.get("active", 0.0)),
			"%s 的回鋒窗吃掉了整個判定窗，時機失去意義" % id
		)


## 把真 profile 的判定窗拉長，好在測試裡穩定落點；回鋒窗維持原值。
func _long_window(profile: Dictionary) -> Dictionary:
	var copy := profile.duplicate(true)
	copy["windup"] = 0.0
	copy["active"] = 1.0
	return copy
