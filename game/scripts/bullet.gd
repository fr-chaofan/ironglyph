## 子彈（Task 2.3 / 2.4）
##
## 玩家武器與Boss彈幕共用。方向統一用 Vector2——玩家子彈只有水平分量，
## Boss彈幕（階段五）用任意角度，兩者不需要分叉邏輯。
class_name Bullet
extends Area2D

## Task 2.4：按五行著色，讓玩家一眼看出屬性歸屬
const ELEMENT_COLORS := {
	"water": Color(0.3, 0.6, 1.0),
	"fire": Color(1.0, 0.4, 0.2),
	"metal": Color(0.8, 0.8, 0.9),
	"wood": Color(0.3, 0.8, 0.3),
	"earth": Color(0.6, 0.4, 0.2),
	"neutral": Color(1.0, 1.0, 1.0),
}

@export var speed: float = 500.0

## 存活上限（秒）。沒有這個的話，打空的子彈會一直往畫面外飛且永不釋放，
## 一場戰鬥下來累積成千上萬個節點。
@export var max_lifetime: float = 3.0

var damage: int = 0
var element: String = "neutral"
var direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0


func _ready() -> void:
	# ⚠️ 用 body_entered 而非 area_entered。
	# Character 繼承 CharacterBody2D（PhysicsBody2D），Area2D 的 area_entered
	# 只會對其他 Area2D 觸發，對 PhysicsBody2D 永遠不會觸發——照原計劃寫成
	# area_entered 的話，子彈能生成、能飛，但永遠打不到任何人。
	body_entered.connect(_on_body_entered)


func setup(dmg: int, elem: String, spawn_pos: Vector2, dir: Vector2) -> void:
	damage = dmg
	element = elem
	direction = dir.normalized()
	global_position = spawn_pos
	modulate = ELEMENT_COLORS.get(elem, Color.WHITE)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta

	_age += delta
	if _age >= max_lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Character:
		(body as Character).take_damage(damage, element)
	# 打到地形（沒有 take_damage 的 StaticBody2D）也要消失，不能穿牆
	queue_free()
