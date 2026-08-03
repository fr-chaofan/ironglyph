## Boss 彈幕/攻擊模式（Task 5.2）
##
## 驗證 `spawn_phase_attack` 依部首正確分派、環形彈幕數量公式、
## 強度倍率隨階段遞增、未知部首回退到預設環形彈幕，
## 以及生成的子彈都正確掛進場景樹、測試後不殘留。
##
## ⚠️ `BossAttackPatterns` 依 `bullet.gd`/`enemy_ai_shared.gd` 既有慣例，
## 一律把子彈掛在 `get_tree().current_scene` 底下——這在 GUT 執行環境裡是
## 整個測試回合共用的同一個場景節點，`queue_free()` 也要等下一影格才真正生效。
## 因此本檔一律用「生成前後的節點差集」而非「場上總數」來斷言，
## 並在每個測試結束前把自己生成的子彈釋放乾淨，避免汙染下一個測試。
extends GutTest

const BossAttackPatternsScript := preload("res://scripts/boss_attack_patterns.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var _patterns: BossAttackPatterns


func before_each() -> void:
	_patterns = BossAttackPatternsScript.new()
	add_child_autofree(_patterns)


func _scene_root() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	return scene


## 目前場上所有 Bullet 的 instance id 快照，用來跟生成後的狀態做差集。
func _bullet_ids_snapshot() -> Dictionary:
	var ids := {}
	for child: Node in _scene_root().get_children():
		if child is Bullet:
			ids[child.get_instance_id()] = true
	return ids


## `before` 快照之後新出現的 Bullet 節點。
func _new_bullets_since(before: Dictionary) -> Array:
	var result: Array = []
	for child: Node in _scene_root().get_children():
		if child is Bullet and not before.has(child.get_instance_id()):
			result.append(child)
	return result


## 釋放這一批子彈並等它們真正從場景樹消失，避免殘留影響下一個斷言/測試。
func _free_bullets(bullets: Array) -> void:
	for bullet: Node in bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	await wait_physics_frames(2)


# ---- spawn_ring_attack：水彈幕環形 ----

func test_ring攻擊數量按公式計算() -> void:
	for phase in range(1, 4):
		var count := 8 + phase * 4
		var before := _bullet_ids_snapshot()
		_patterns.spawn_ring_attack(Vector2.ZERO, count, "water", 1.0)
		var spawned := _new_bullets_since(before)
		assert_eq(spawned.size(), count, "phase %d 環形彈幕數量應為 %d" % [phase, count])
		await _free_bullets(spawned)


func test_ring攻擊子彈均勻分佈一整圈() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ring_attack(Vector2.ZERO, 4, "water", 1.0)
	var bullets := _new_bullets_since(before)
	assert_eq(bullets.size(), 4)

	var directions: Array = []
	for bullet: Bullet in bullets:
		directions.append(bullet.direction)

	# 4 發應該分別朝 0°/90°/180°/270°，彼此不重複
	for i in directions.size():
		for j in range(i + 1, directions.size()):
			assert_gt(
				(directions[i] as Vector2).distance_to(directions[j] as Vector2), 0.5,
				"環形彈幕的方向不應重複"
			)
	await _free_bullets(bullets)


func test_ring攻擊傷害隨強度倍率縮放() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ring_attack(Vector2.ZERO, 4, "water", 1.0)
	var base_bullets := _new_bullets_since(before)
	var base_damage: int = (base_bullets[0] as Bullet).damage
	await _free_bullets(base_bullets)

	before = _bullet_ids_snapshot()
	_patterns.spawn_ring_attack(Vector2.ZERO, 4, "water", 2.0)
	var doubled_bullets := _new_bullets_since(before)
	var doubled_damage: int = (doubled_bullets[0] as Bullet).damage
	await _free_bullets(doubled_bullets)

	assert_eq(base_damage, 15, "intensity=1.0 時基礎傷害應為 15")
	assert_eq(doubled_damage, 30, "intensity=2.0 時傷害應翻倍")


# ---- spawn_tracking_attack：火焰追蹤彈 ----

func test_tracking攻擊生成正確數量() -> void:
	for phase in range(1, 4):
		var count := 3 + phase
		var before := _bullet_ids_snapshot()
		_patterns.spawn_tracking_attack(Vector2.ZERO, count, "fire", 1.0)
		var spawned := _new_bullets_since(before)
		assert_eq(spawned.size(), count, "phase %d 追蹤彈數量應為 %d" % [phase, count])
		await _free_bullets(spawned)


func test_tracking攻擊沒有玩家時退回預設方向() -> void:
	# before_each 沒有生成玩家，場上不存在 group "player"
	var before := _bullet_ids_snapshot()
	_patterns.spawn_tracking_attack(Vector2.ZERO, 3, "fire", 1.0)
	var bullets := _new_bullets_since(before)
	assert_eq(bullets.size(), 3)
	for bullet: Bullet in bullets:
		# 扇形散射以 Vector2.RIGHT 為中心，x 分量應維持正向
		assert_gt(bullet.direction.x, 0.0, "找不到玩家時應以 Vector2.RIGHT 為散射中心")
	await _free_bullets(bullets)


func test_tracking攻擊朝玩家方向散射() -> void:
	var player := PlayerScene.instantiate()
	add_child_autofree(player)
	player.global_position = Vector2(0, -300)  # 玩家在正上方

	var before := _bullet_ids_snapshot()
	_patterns.spawn_tracking_attack(Vector2.ZERO, 3, "fire", 1.0)
	var bullets := _new_bullets_since(before)
	assert_eq(bullets.size(), 3)
	for bullet: Bullet in bullets:
		# 散射角度只有 28°，朝上的分量應明顯為負（Y 軸向下為正的 2D 座標系）
		assert_lt(bullet.direction.y, 0.0, "追蹤彈應朝玩家方向（正上方）散射")
	await _free_bullets(bullets)


func test_tracking攻擊傷害隨強度倍率縮放() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_tracking_attack(Vector2.ZERO, 3, "fire", 1.0)
	var base_bullets := _new_bullets_since(before)
	var base_damage: int = (base_bullets[0] as Bullet).damage
	await _free_bullets(base_bullets)

	before = _bullet_ids_snapshot()
	_patterns.spawn_tracking_attack(Vector2.ZERO, 3, "fire", 1.5)
	var scaled_bullets := _new_bullets_since(before)
	var scaled_damage: int = (scaled_bullets[0] as Bullet).damage
	await _free_bullets(scaled_bullets)

	assert_eq(base_damage, 20, "intensity=1.0 時基礎傷害應為 20")
	assert_eq(scaled_damage, 30, "intensity=1.5 時傷害應為 30")


# ---- spawn_ground_spike_attack：藤蔓地刺 ----

func test_ground_spike立即生成的一發() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ground_spike_attack(Vector2.ZERO, 1, "wood", 1.0)
	var spawned := _new_bullets_since(before)
	assert_eq(spawned.size(), 1, "count=1 時應立即生成，不需等待 timer")
	assert_eq(spawned[0].direction, Vector2.UP, "地刺應向上突刺")
	await _free_bullets(spawned)


func test_ground_spike按延遲依序生成() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ground_spike_attack(Vector2.ZERO, 4, "wood", 1.0)
	# 剛呼叫完時，只有 delay=0 的第一發立即生成
	assert_eq(_new_bullets_since(before).size(), 1, "生成當幀應只有第一發立即出現")

	await wait_seconds(0.6)
	var spawned := _new_bullets_since(before)
	assert_eq(spawned.size(), 4, "等待足夠時間後，四發地刺應全部生成")
	await _free_bullets(spawned)


func test_ground_spike傷害隨強度倍率縮放() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ground_spike_attack(Vector2.ZERO, 1, "wood", 1.0)
	var base_bullets := _new_bullets_since(before)
	var base_damage: int = (base_bullets[0] as Bullet).damage
	await _free_bullets(base_bullets)

	before = _bullet_ids_snapshot()
	_patterns.spawn_ground_spike_attack(Vector2.ZERO, 1, "wood", 2.0)
	var doubled_bullets := _new_bullets_since(before)
	var doubled_damage: int = (doubled_bullets[0] as Bullet).damage
	await _free_bullets(doubled_bullets)

	assert_eq(base_damage, 18, "intensity=1.0 時基礎傷害應為 18")
	assert_eq(doubled_damage, 36, "intensity=2.0 時傷害應翻倍")


func test_ground_spike沿x軸分佈於目標範圍內() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ground_spike_attack(Vector2.ZERO, 3, "wood", 1.0)
	await wait_seconds(0.6)
	var bullets := _new_bullets_since(before)
	assert_eq(bullets.size(), 3)

	var xs: Array = []
	for bullet: Bullet in bullets:
		xs.append(bullet.global_position.x)
	xs.sort()
	# 三發應該分佈在不同 x 座標，而非全部疊在同一點
	assert_lt(xs[0], xs[2], "地刺應沿 x 軸展開，而非全部生成在同一個位置")
	await _free_bullets(bullets)


# ---- spawn_phase_attack：統一入口分派與強度遞增 ----

func test_水部首分派到ring攻擊且數量正確() -> void:
	for phase in range(1, 4):
		var expected := 8 + phase * 4
		var before := _bullet_ids_snapshot()
		_patterns.spawn_phase_attack(phase, "水", "water", Vector2.ZERO)
		var spawned := _new_bullets_since(before)
		assert_eq(spawned.size(), expected, "phase %d 水部首彈幕數量應為 %d" % [phase, expected])
		await _free_bullets(spawned)


func test_火部首分派到tracking攻擊且數量正確() -> void:
	for phase in range(1, 4):
		var expected := 3 + phase
		var before := _bullet_ids_snapshot()
		_patterns.spawn_phase_attack(phase, "火", "fire", Vector2.ZERO)
		var spawned := _new_bullets_since(before)
		assert_eq(spawned.size(), expected, "phase %d 火部首追蹤彈數量應為 %d" % [phase, expected])
		await _free_bullets(spawned)


func test_木部首分派到ground_spike攻擊且數量正確() -> void:
	for phase in range(1, 4):
		var expected := 4 + phase * 2
		var before := _bullet_ids_snapshot()
		_patterns.spawn_phase_attack(phase, "木", "wood", Vector2.ZERO)
		# 最後一根地刺的延遲是 (count-1) * stagger，等待要蓋過最大的 count(10)
		await wait_seconds(0.12 * float(expected) + 0.3)
		var spawned := _new_bullets_since(before)
		assert_eq(spawned.size(), expected, "phase %d 木部首地刺數量應為 %d" % [phase, expected])
		await _free_bullets(spawned)


func test_未知部首回退到預設環形彈幕() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_phase_attack(2, "金", "metal", Vector2.ZERO)
	var spawned := _new_bullets_since(before)
	# 預設分支固定呼叫 spawn_ring_attack(origin, 8, ...)，不吃階段公式
	assert_eq(spawned.size(), 8, "未知部首應退回預設環形彈幕，數量固定為8")
	await _free_bullets(spawned)


func test_強度倍率隨階段正確遞增並反映在傷害上() -> void:
	var expected_intensity := {1: 1.0, 2: 1.5, 3: 2.0}
	for phase in range(1, 4):
		var before := _bullet_ids_snapshot()
		_patterns.spawn_phase_attack(phase, "水", "water", Vector2.ZERO)
		var spawned := _new_bullets_since(before)
		var bullet: Bullet = spawned[0]
		var expected_damage := int(15 * float(expected_intensity[phase]))
		assert_eq(
			bullet.damage, expected_damage,
			"phase %d 的強度倍率應為 %.1f，反映在傷害 %d 上" % [phase, expected_intensity[phase], expected_damage]
		)
		await _free_bullets(spawned)


func test_階段2和3的彈幕密度或傷害都高於階段1() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_phase_attack(1, "水", "water", Vector2.ZERO)
	var phase1_bullets := _new_bullets_since(before)
	var phase1_count := phase1_bullets.size()
	var phase1_damage: int = (phase1_bullets[0] as Bullet).damage
	await _free_bullets(phase1_bullets)

	before = _bullet_ids_snapshot()
	_patterns.spawn_phase_attack(2, "水", "water", Vector2.ZERO)
	var phase2_bullets := _new_bullets_since(before)
	var phase2_count := phase2_bullets.size()
	var phase2_damage: int = (phase2_bullets[0] as Bullet).damage
	await _free_bullets(phase2_bullets)

	before = _bullet_ids_snapshot()
	_patterns.spawn_phase_attack(3, "水", "water", Vector2.ZERO)
	var phase3_bullets := _new_bullets_since(before)
	var phase3_count := phase3_bullets.size()
	var phase3_damage: int = (phase3_bullets[0] as Bullet).damage
	await _free_bullets(phase3_bullets)

	assert_gt(phase2_count, phase1_count, "階段2彈幕密度應高於階段1")
	assert_gt(phase3_count, phase2_count, "階段3彈幕密度應高於階段2")
	assert_gt(phase2_damage, phase1_damage, "階段2傷害應高於階段1")
	assert_gt(phase3_damage, phase2_damage, "階段3傷害應高於階段2")


# ---- 生成節點的掛載位置 ----

func test_生成的子彈都掛進場景樹() -> void:
	var before := _bullet_ids_snapshot()
	_patterns.spawn_ring_attack(Vector2.ZERO, 5, "water", 1.0)
	var bullets := _new_bullets_since(before)
	var scene := _scene_root()
	for bullet: Bullet in bullets:
		assert_eq(bullet.get_parent(), scene, "子彈應直接掛在 current_scene 底下")
	await _free_bullets(bullets)
