## 子彈（Task 2.3 / 2.4）
##
## 玩家武器與Boss彈幕共用。方向統一用 Vector2——玩家子彈只有水平分量，
## Boss彈幕（階段五）用任意角度，兩者不需要分叉邏輯。
class_name Bullet
extends Area2D

## Task 2.4：按五行著色，讓玩家一眼看出屬性歸屬。
##
## 顏色一律來自 `data/palette.json`——全遊戲只有那一份色板，
## 字形、子彈、刀氣、傷害數字、UI 都讀它。
##
## 改成宣紙底之後整組色都換過：深底時用的高飽和亮色在紙上會糊掉，
## 現在是能壓在紙上的深色顏料（靛藍／朱砂／銀灰／石綠／藤黃／焦墨）。
static var ELEMENT_COLORS: Dictionary = Palette.elements()

## `weapons.json` 的 `range` 欄位換算成實際飛行距離（像素）。
##
## Task 2.7a 之前這個欄位是死資料——十把武器只有傷害與射速的差別，
## 「暗器(long)」與「藤蔓刺(short)」的射程完全一樣。
const RANGE_DISTANCES := {
	"short": 180.0,
	"medium": 420.0,
	"long": 720.0,
}

@export var speed: float = 500.0

## 存活上限（秒）。沒有這個的話，打空的子彈會一直往畫面外飛且永不釋放，
## 一場戰鬥下來累積成千上萬個節點。
@export var max_lifetime: float = 3.0

## 飛行距離上限（像素）。0 表示不限距離，只受 max_lifetime 約束。
##
## ⚠️ 這是**距離**上限而不是換算成時間的存活上限：兩者在等速直線下等價，
## 但日後若加入減速／追蹤彈，距離才是設計者真正想控制的量。
@export var max_distance: float = 0.0

var damage: int = 0
var element: String = "neutral"
var direction: Vector2 = Vector2.RIGHT

var _age: float = 0.0
var _travelled: float = 0.0


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


## 依 `weapons.json` 的 `range` 值設定飛行距離上限。
## 未知或 "melee" 一律回到不限距離——近戰武器不該走到生成子彈這條路，
## 真的走到了也讓它照舊飛，不要靜默變成射程 0 的啞彈。
func set_range(range_name: String) -> void:
	max_distance = float(RANGE_DISTANCES.get(range_name, 0.0))


func _physics_process(delta: float) -> void:
	var step := speed * delta
	position += direction * step

	_travelled += absf(step)
	if max_distance > 0.0 and _travelled >= max_distance:
		queue_free()
		return

	_age += delta
	if _age >= max_lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Character:
		(body as Character).take_damage(damage, element)
	# 打到地形（沒有 take_damage 的 StaticBody2D）也要消失，不能穿牆
	queue_free()
