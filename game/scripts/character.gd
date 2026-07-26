## Player 與 Enemy 的共用基類（Task 1.3）
##
## 移動用 CharacterBody2D，傷害計算走五行相剋倍率。
class_name Character
extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal died

@export var speed: float = 220.0
@export var jump_velocity: float = -420.0
@export var max_hp: int = 100
## water / fire / metal / wood / earth / neutral
@export var element: String = "neutral"

## 重力取自 project.godot 的 physics/2d/default_gravity，不要另外寫死數值，
## 否則調整專案重力時角色不會跟著變。
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)

var hp: int


func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


func take_damage(amount: int, attacker_element: String) -> void:
	if hp <= 0:
		return  # 已經死了，避免同一幀多發子彈重複觸發 die()

	var multiplier := get_element_multiplier(attacker_element, element)
	hp -= int(amount * multiplier)
	hp = maxi(hp, 0)
	hp_changed.emit(hp, max_hp)

	if hp <= 0:
		die()


## 五行相剋倍率。
##
## ElementSystem 單例要到階段二 Task 2.1 才建立，在那之前一律回傳中性倍率 1.0。
## 這樣階段一就能跑通完整的受擊流程，而不必等階段二。
## Task 2.1 完成並在 [autoload] 註冊 ElementSystem 後，這個方法會自動改走真正的相剋表，
## 不需要再回來改這裡。
func get_element_multiplier(attacker_element: String, defender_element: String) -> float:
	var element_system := get_node_or_null(^"/root/ElementSystem")
	if element_system != null and element_system.has_method(&"get_multiplier"):
		return element_system.get_multiplier(attacker_element, defender_element)
	return 1.0


func die() -> void:
	died.emit()
	queue_free()
