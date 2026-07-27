## 定點範圍攻擊 AI（Task 3.2）
##
## 完全不移動（speed 為 0），週期性放出一圈範圍傷害。
extends Node

@export var aoe_radius: float = 130.0
@export var pulse_interval: float = 2.0
## 蓄力時間：放招前先有預兆，玩家才有機會退出範圍
@export var telegraph_time: float = 0.5

var _cooldown: float = 0.0
var _telegraph_left: float = 0.0
var _initialised: bool = false


func decide_velocity(enemy: Enemy, delta: float) -> float:
	if not _initialised:
		_initialised = true
		_cooldown = randf_range(0.0, pulse_interval)

	if _telegraph_left > 0.0:
		_telegraph_left = maxf(0.0, _telegraph_left - delta)
		if _telegraph_left <= 0.0:
			_fire_pulse(enemy)
		return 0.0

	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0:
		var player := EnemyAIShared.find_player(enemy)
		if player != null and enemy.global_position.distance_to(player.global_position) <= aoe_radius * 1.5:
			_cooldown = pulse_interval
			_telegraph_left = telegraph_time
			_start_telegraph(enemy)

	return 0.0  # 定點型永遠不移動


func _start_telegraph(enemy: Enemy) -> void:
	if enemy.hanzi_sprite == null or not is_instance_valid(enemy.hanzi_sprite):
		return
	var tween := enemy.hanzi_sprite.create_tween()
	tween.tween_property(enemy.hanzi_sprite, "scale", Vector2(1.25, 1.25), telegraph_time)
	tween.tween_property(enemy.hanzi_sprite, "scale", Vector2.ONE, 0.15)


## 對範圍內的玩家造成傷害。用距離判定而非 Area2D——
## 這樣不必為了一個瞬間的判定多維護一個節點與碰撞層。
func _fire_pulse(enemy: Enemy) -> void:
	var player := EnemyAIShared.find_player(enemy)
	if player == null:
		return
	if enemy.global_position.distance_to(player.global_position) > aoe_radius:
		return
	if player.has_method(&"take_damage"):
		player.take_damage(enemy.get_contact_damage(), enemy.element)
