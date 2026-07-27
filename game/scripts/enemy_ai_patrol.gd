## 巡邏 + 遠程 AI（Task 3.2）
##
## 在起點左右來回巡邏；玩家進入射程且高度接近時停下開火。
extends Node

## 從起點往兩側各走多遠
@export var patrol_range: float = 150.0
## 玩家進入這個水平距離內就開火
@export var fire_range: float = 420.0
## 高度差超過這個值就不開火（子彈只走水平，打不到）
@export var vertical_tolerance: float = 80.0
@export var fire_interval: float = 1.6

var _start_x: float = 0.0
var _direction: float = 1.0
var _fire_cooldown: float = 0.0
var _initialised: bool = false


func decide_velocity(enemy: Enemy, delta: float) -> float:
	if not _initialised:
		_start_x = enemy.global_position.x
		_initialised = true
		# 錯開各敵人的第一次開火，避免整排同時射
		_fire_cooldown = randf_range(0.0, fire_interval)

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	var player := EnemyAIShared.find_player(enemy)
	if player != null:
		var offset: Vector2 = player.global_position - enemy.global_position
		if absf(offset.x) <= fire_range and absf(offset.y) <= vertical_tolerance:
			# 進入射程就停下來開火，邊走邊射會讓玩家很難預判
			if _fire_cooldown <= 0.0:
				_fire_cooldown = fire_interval
				var dir := Vector2(signf(offset.x) if not is_zero_approx(offset.x) else 1.0, 0.0)
				EnemyAIShared.spawn_enemy_bullet(enemy, dir, enemy.get_contact_damage(), enemy.element)
			return 0.0

	# 走到巡邏邊界就折返
	if absf(enemy.global_position.x - _start_x) > patrol_range:
		_direction = signf(_start_x - enemy.global_position.x)
	# 撞牆也折返
	elif enemy.is_on_wall():
		_direction *= -1.0

	return _direction * enemy.speed
