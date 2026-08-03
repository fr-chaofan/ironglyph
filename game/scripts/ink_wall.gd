## 墨牆：坽壘命中處立起的一道短命屏障。
##
## 「坽」是堤岸——這是全場唯一的**防禦**性招式：擋住敵方子彈，
## 讓玩家有機會換位或補血，而不是又一種傷害。
##
## ⚠️ 只擋 `enemy_bullet` 層。擋玩家自己的子彈的話，立起牆等於把自己封死。
class_name InkWall
extends StaticBody2D

## 撐幾秒
@export var duration: float = 3.5
## 能擋幾發子彈。有上限才不會變成無敵掩體。
@export var block_limit: int = 3

var _hits_left: int = 0
var _sensor: Area2D


static func spawn(parent: Node, world_position: Vector2, config: Dictionary, color: Color) -> InkWall:
	if parent == null or not is_instance_valid(parent):
		return null

	var wall := InkWall.new()
	wall.duration = float(config.get("duration", 3.5))
	wall.block_limit = int(config.get("hp", 3))
	var raw: Variant = config.get("size", [26, 96])
	var size := Vector2(26.0, 96.0)
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		size = Vector2(float(raw[0]), float(raw[1]))
	wall._build(size, color)

	parent.add_child(wall)
	wall.global_position = world_position
	return wall


func _build(size: Vector2, color: Color) -> void:
	_hits_left = block_limit
	# 牆本身不參與碰撞層——擋子彈交給下面的感應區，
	# 否則玩家會被自己立的牆卡住走不過去。
	collision_layer = 0
	collision_mask = 0

	var visual := ColorRect.new()
	visual.size = size
	visual.position = -size * 0.5
	visual.color = Color(color.r, color.g, color.b, 0.75)
	add_child(visual)

	_sensor = Area2D.new()
	# 只偵測 enemy_bullet(16)，不碰玩家與玩家子彈
	_sensor.collision_layer = 0
	_sensor.collision_mask = 16
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	_sensor.add_child(shape)
	add_child(_sensor)
	_sensor.area_entered.connect(_on_bullet_entered)

	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(visual, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


func _on_bullet_entered(area: Area2D) -> void:
	if area is not Bullet:
		return
	area.queue_free()
	_hits_left -= 1
	if _hits_left <= 0:
		queue_free()
