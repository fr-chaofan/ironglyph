## 三種敵人AI共用的工具（Task 3.2）
##
## 敵人子彈與玩家子彈共用 bullet_base.tscn，但**碰撞層必須改掉**：
## 玩家子彈在 player_bullet 層、打 enemy；敵人子彈要在 enemy_bullet 層、打 player。
## 沿用玩家子彈的層會導致敵人互相誤傷、且打不到玩家。
class_name EnemyAIShared
extends RefCounted

const BULLET_SCENE := preload("res://scenes/projectiles/bullet_base.tscn")

## layer_5 = enemy_bullet = 位元值 16
const ENEMY_BULLET_LAYER := 16
## 打 player(2) 與 ground(1)
const ENEMY_BULLET_MASK := 3


## 找到玩家。回傳 null 代表場上沒有玩家（例如單元測試或玩家已死亡）。
static func find_player(from: Node) -> Node2D:
	var players := from.get_tree().get_nodes_in_group(&"player")
	if not players.is_empty() and is_instance_valid(players[0]):
		return players[0] as Node2D
	return null


## 生成一發敵人子彈
static func spawn_enemy_bullet(shooter: Node2D, direction: Vector2, damage: int, element: String) -> Bullet:
	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.collision_layer = ENEMY_BULLET_LAYER
	bullet.collision_mask = ENEMY_BULLET_MASK
	bullet.speed = 320.0  # 比玩家子彈(500)慢，玩家才閃得掉

	var spawn_pos: Vector2 = shooter.global_position + direction.normalized() * 40.0
	bullet.setup(damage, element, spawn_pos, direction)

	var parent := shooter.get_tree().current_scene
	if parent == null:
		parent = shooter.get_tree().root
	parent.add_child(bullet)
	return bullet
