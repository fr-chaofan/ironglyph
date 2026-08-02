## 追擊 + 近戰 AI（Task 3.2；Task 2.7d 改造為三段式揮擊）
##
## 朝玩家水平接近，進入攻擊距離後揮擊：**前搖 → 判定 → 後搖**。
##
## Task 2.7d 之前這一型只是「一團會走路的接觸傷害」——沒有前搖可讀、沒有後搖可懲罰，
## 傷害靠碰撞體重疊觸發，站位變成推擠而不是對峙。玩家在 2.7b 拿到有節奏的近戰之後，
## 這個不對稱會直接毀掉近戰手感：你的攻擊有節奏，敵人的沒有。
## 詳見 `docs/COMBAT.md` 1.2 與 4.1。
extends Node

## 玩家進入這個距離才開始追，否則原地待命
@export var detect_range: float = 520.0
## 進入這個水平距離就停下揮擊。**必須小於玩家近戰的最遠命中距離（120px）**，
## 否則玩家站在自己的安全窗口外緣永遠打不贏對拼。
@export var attack_range: float = 96.0
## 高度差超過這個值就不揮擊（判定框只有 56 高，揮了也打不到）
@export var vertical_tolerance: float = 60.0
## 高度差超過這個值就放棄追擊（沒有跳躍能力，追了也上不去）
@export var give_up_height: float = 260.0

## 沒有 melee 資料時的預設節奏
const DEFAULT_WINDUP := 0.30
const DEFAULT_ACTIVE := 0.12
const DEFAULT_RECOVERY := 0.35
const DEFAULT_REACH := 58.0


func decide_velocity(enemy: Enemy, _delta: float) -> float:
	var melee := enemy.melee_attack

	# 前搖／判定／後搖期間一律定住。**後搖不動就是玩家的懲罰窗口**——
	# 揮空之後還能立刻退開的話，「讀預兆再反打」就沒有獎勵可言。
	if melee != null and is_instance_valid(melee) and not melee.can_swing():
		return 0.0

	var player := EnemyAIShared.find_player(enemy)
	if player == null:
		return 0.0

	var offset: Vector2 = player.global_position - enemy.global_position
	if absf(offset.x) > detect_range or absf(offset.y) > give_up_height:
		return 0.0

	if absf(offset.x) <= attack_range:
		if melee != null and is_instance_valid(melee) and absf(offset.y) <= vertical_tolerance:
			var direction := signf(offset.x) if not is_zero_approx(offset.x) else 1.0
			melee.swing(direction, build_profile(enemy))
		return 0.0

	return signf(offset.x) * enemy.speed


## 由 enemies.json 的 melee 區塊組出近戰 profile。
## 傷害沿用既有的 `damage` 欄位——同一隻敵人揮擊與接觸的威脅值本來就該一致。
func build_profile(enemy: Enemy) -> Dictionary:
	var melee_data: Variant = enemy.char_data.get("melee", {})
	var data: Dictionary = melee_data if typeof(melee_data) == TYPE_DICTIONARY else {}

	var windup := float(data.get("windup", DEFAULT_WINDUP))
	var active := float(data.get("active", DEFAULT_ACTIVE))
	var recovery := float(data.get("recovery", DEFAULT_RECOVERY))

	return {
		"id": "enemy_swing",
		"name": "揮擊",
		"glyph": String(enemy.char_data.get("char", "")),
		"element": enemy.element,
		"damage": enemy.get_contact_damage(),
		"windup": windup,
		"active": active,
		# MeleeAttack 的 cooldown 是「從揮出到能再揮」的總時長，後搖是它扣掉前搖與判定的餘額
		"cooldown": windup + active + recovery,
		"reach": float(data.get("reach", DEFAULT_REACH)),
		"hitbox": data.get("hitbox", [72, 56]),
	}
