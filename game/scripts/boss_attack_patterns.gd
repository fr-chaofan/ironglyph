## Boss 彈幕/攻擊模式（Task 5.2）
##
## 淼(水彈幕環形)、焱(火焰追蹤彈)、森(藤蔓地刺)——三個部首各自代表一種彈幕型態，
## 隨著 Boss 階段編號（1/2/3）強度遞增。這支腳本只負責「生成」這一層：
## 子彈本身的飛行、命中、視覺全部沿用既有的 `Bullet`（Task 2.x），
## 這裡不碰、也不需要碰 bullet.gd。
##
## 與 `Boss`（Task 5.1）是父子節點組合關係——`Boss` 場景底下掛一個
## `BossAttackPatterns` 子節點，階段切換時呼叫 `spawn_phase_attack()`。
## 兩邊各自獨立開發，互不繼承。
extends Node
class_name BossAttackPatterns

const BulletScene := preload("res://scenes/projectiles/bullet_base.tscn")

## 追蹤彈的扇形散射：既有 Bullet 沒有逐幀轉向玩家的能力（那屬於 bullet.gd
## 的功能範圍，Task 5.2 不修改 bullet.gd），所以用「多發子彈分散一個小扇形
## 角度朝玩家方向散射」來模擬追蹤感——玩家躲開其中一發正對著自己的彈，
## 兩側的彈仍然會逼近大概的路線，而不是所有彈全部走同一條線。
const TRACKING_SPREAD_ANGLE := deg_to_rad(28.0)

## 地刺依序從地面彈出，而不是同時出現——這裡用 `get_tree().create_timer`
## 對每一發做一個小延遲，時間差按下標遞增。
const GROUND_SPIKE_STAGGER: float = 0.12

## 地刺生成範圍：以目標（玩家或 origin）為中心左右各展開多遠。
const GROUND_SPIKE_SPREAD: float = 220.0


## 統一入口：依階段編號分派到對應彈幕模式，強度隨階段遞增
func spawn_phase_attack(phase: int, radical: String, element: String, origin: Vector2) -> void:
	var intensity_multiplier := 1.0 + (phase - 1) * 0.5  # phase 1=1.0x, phase 2=1.5x, phase 3=2.0x
	match radical:
		"水":
			spawn_ring_attack(origin, 8 + phase * 4, element, intensity_multiplier)
		"火":
			spawn_tracking_attack(origin, 3 + phase, element, intensity_multiplier)
		"木":
			spawn_ground_spike_attack(origin, 4 + phase * 2, element, intensity_multiplier)
		_:
			spawn_ring_attack(origin, 8, element, intensity_multiplier)  # 預設環形彈幕


## 淼：水彈幕環形——`count` 發子彈平均分佈一整圈，均速向外飛。
func spawn_ring_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
	for i in range(count):
		var angle := (TAU / count) * i
		var bullet := _spawn_bullet(
			int(15 * intensity), element, origin, Vector2(cos(angle), sin(angle))
		)
		_add_to_scene(bullet)


## 焱：火焰追蹤彈——朝玩家所在方向，以一個小扇形角度散射 `count` 發，
## 模擬「追蹤感」而不需要逐幀轉向（詳見上方常數的說明）。
## 場上沒有玩家時退回預設方向 Vector2.RIGHT。
func spawn_tracking_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
	var base_direction := _find_target_direction(origin, Vector2.RIGHT)
	var base_angle := base_direction.angle()

	for i in range(count):
		var angle := base_angle
		if count > 1:
			# 扇形均勻展開：i 從 0 到 count-1 對應 -half..+half
			var t := float(i) / float(count - 1)  # 0..1
			angle += lerp(-TRACKING_SPREAD_ANGLE * 0.5, TRACKING_SPREAD_ANGLE * 0.5, t)
		var direction := Vector2(cos(angle), sin(angle))
		var bullet := _spawn_bullet(int(20 * intensity), element, origin, direction)
		_add_to_scene(bullet)


## 森：藤蔓地刺——在玩家（或 origin，找不到玩家時）腳下一定範圍內，
## 沿 x 軸分佈 `count` 根地刺，各自延遲一小段時間依序「彈出」
## （用既有 Bullet 場景、方向 Vector2.UP 模擬向上突刺）。
func spawn_ground_spike_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
	var center := _find_target_position(origin)
	var damage := int(18 * intensity)

	if count <= 1:
		_spawn_ground_spike_at(center, damage, element, 0.0)
		return

	for i in range(count):
		var t := float(i) / float(count - 1)  # 0..1，均勻分佈整個範圍
		var x_offset := lerp(-GROUND_SPIKE_SPREAD * 0.5, GROUND_SPIKE_SPREAD * 0.5, t)
		var spike_pos := center + Vector2(x_offset, 0.0)
		var delay := float(i) * GROUND_SPIKE_STAGGER
		_spawn_ground_spike_at(spike_pos, damage, element, delay)


## 延遲 `delay` 秒後在 `pos` 生成一根向上突刺的地刺。
## delay 為 0 時立即生成，不必等一個 timer 週期。
func _spawn_ground_spike_at(pos: Vector2, damage: int, element: String, delay: float) -> void:
	if delay <= 0.0:
		var bullet := _spawn_bullet(damage, element, pos, Vector2.UP)
		_add_to_scene(bullet)
		return

	var tree := get_tree()
	if tree == null:
		# 沒有場景樹可用（理論上不該發生，保底立即生成不吃掉這發地刺）
		var fallback := _spawn_bullet(damage, element, pos, Vector2.UP)
		_add_to_scene(fallback)
		return

	var timer := tree.create_timer(delay)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		var bullet := _spawn_bullet(damage, element, pos, Vector2.UP)
		_add_to_scene(bullet)
	)


## 造一發子彈但不掛進場景樹——留給呼叫端決定何時、掛在哪裡加入，
## 方便 ground spike 的延遲生成復用同一套建構邏輯。
func _spawn_bullet(damage: int, element: String, spawn_pos: Vector2, direction: Vector2) -> Bullet:
	var bullet: Bullet = BulletScene.instantiate()
	bullet.setup(damage, element, spawn_pos, direction)
	return bullet


## 統一掛進 current_scene；測試環境或尚未有場景時退回 root，
## 避免在沒有 current_scene 的情境下直接崩潰（做法與 bullet.gd 的
## `_get_effect_parent()`一致）。
func _add_to_scene(bullet: Bullet) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var parent: Node = tree.current_scene
	if parent == null:
		parent = tree.root
	parent.add_child(bullet)


## 找場上第一個玩家節點的位置；找不到就回傳 origin 本身。
func _find_target_position(origin: Vector2) -> Vector2:
	var tree := get_tree()
	if tree == null:
		return origin
	var player := tree.get_first_node_in_group(&"player") as Node2D
	if player != null and is_instance_valid(player):
		return player.global_position
	return origin


## 算從 origin 朝玩家方向的單位向量；找不到玩家就回傳 fallback_direction。
func _find_target_direction(origin: Vector2, fallback_direction: Vector2) -> Vector2:
	var tree := get_tree()
	if tree == null:
		return fallback_direction
	var player := tree.get_first_node_in_group(&"player") as Node2D
	if player == null or not is_instance_valid(player):
		return fallback_direction
	var to_player := player.global_position - origin
	if to_player.is_zero_approx():
		return fallback_direction
	return to_player.normalized()
