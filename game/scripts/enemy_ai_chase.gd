## 追擊 + 近戰 AI（Task 3.2）
##
## 朝玩家水平接近，靠接觸傷害輸出（接觸判定在 enemy.gd 的 _check_touch_damage）。
extends Node

## 玩家進入這個距離才開始追，否則原地待命
@export var detect_range: float = 520.0
## 貼到這麼近就不再前進，避免一直推擠玩家
@export var stop_distance: float = 36.0
## 高度差超過這個值就放棄追擊（沒有跳躍能力，追了也上不去）
@export var give_up_height: float = 260.0


func decide_velocity(enemy: Enemy, _delta: float) -> float:
	var player := EnemyAIShared.find_player(enemy)
	if player == null:
		return 0.0

	var offset: Vector2 = player.global_position - enemy.global_position
	if absf(offset.x) > detect_range or absf(offset.y) > give_up_height:
		return 0.0
	if absf(offset.x) <= stop_distance:
		return 0.0

	return signf(offset.x) * enemy.speed
