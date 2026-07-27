## EnemySpawner 與世界部件拾取物之間的薄整合層（Task 2.6）。
##
## 掛在多個 EnemySpawner 的共同父節點上。只監聽既有 enemy_defeated signal，
## 不修改 Enemy / EnemySpawner 的死亡流程。
class_name ComponentDropper
extends Node2D

const PICKUP_SCENE_PATH := "res://scenes/component_pickup.tscn"
const DROP_META := &"_ironglyph_component_drop_spawned"
const FUSION_RESOLVER_SCRIPT := preload("res://scripts/fusion_resolver.gd")

@export var player_loadout_path: NodePath = ^"../Player/GlyphLoadout"

var _resolver = FUSION_RESOLVER_SCRIPT.new()
var _player_loadout: Node


func _ready() -> void:
	for child: Node in get_children():
		if child is not EnemySpawner:
			continue
		var spawner := child as EnemySpawner
		if not spawner.enemy_defeated.is_connected(_on_enemy_defeated):
			spawner.enemy_defeated.connect(_on_enemy_defeated)

	_player_loadout = get_node_or_null(player_loadout_path)
	if _player_loadout == null:
		_player_loadout = _find_player_loadout()
	if _player_loadout != null and _player_loadout.has_signal(&"component_ejected"):
		var callback := Callable(self, "_on_component_ejected")
		if not _player_loadout.is_connected(&"component_ejected", callback):
			_player_loadout.connect(&"component_ejected", callback)


func _on_enemy_defeated(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	# 同一個 spawner signal 若被錯誤重送也不可複製掉落物。
	if enemy.has_meta(DROP_META):
		return
	enemy.set_meta(DROP_META, true)

	# Enemy 在 signal 返回後立刻 queue_free；所有資料與座標必須在此同步保存。
	var char_data := enemy.char_data.duplicate(true)
	var component_id := String(char_data.get("drop_component_id", "")).strip_edges()
	var world_position := enemy.global_position
	if component_id.is_empty():
		return

	var component: Dictionary = _resolver.get_component(component_id)
	if component.is_empty():
		push_warning("ComponentDropper: 未知的 drop_component_id「%s」" % component_id)
		return
	_spawn_pickup(component, world_position)


func _on_component_ejected(component: Dictionary, world_position: Vector2) -> void:
	if component.is_empty():
		return
	_spawn_pickup(component.duplicate(true), world_position, true)


func _spawn_pickup(
	component: Dictionary,
	world_position: Vector2,
	lock_on_spawn: bool = false
) -> Node2D:
	var resource := load(PICKUP_SCENE_PATH)
	if resource is not PackedScene:
		push_error("ComponentDropper: 無法載入 %s" % PICKUP_SCENE_PATH)
		return null

	var instance := (resource as PackedScene).instantiate()
	if instance is not Node2D or not instance.has_method(&"setup"):
		push_error("ComponentDropper: %s 根節點必須使用 ComponentPickup" % PICKUP_SCENE_PATH)
		if instance != null:
			instance.queue_free()
		return null

	var pickup := instance as Node2D
	add_child(pickup)
	pickup.global_position = world_position
	pickup.call(&"setup", component.duplicate(true))
	if lock_on_spawn and pickup.has_method(&"arm_exchange_lock"):
		pickup.call(&"arm_exchange_lock")
	return pickup


func _find_player_loadout() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var players := tree.get_nodes_in_group(&"player")
	for player: Node in players:
		var candidate := player.get_node_or_null(^"GlyphLoadout")
		if candidate != null and candidate.has_signal(&"component_ejected"):
			return candidate
	return null
