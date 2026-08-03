## Player 與 Enemy 的共用基類（Task 1.3）
##
## 移動用 CharacterBody2D，傷害計算走五行相剋倍率。
class_name Character
extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal died
## 進入無敵狀態時送出，供角色做閃爍等視覺回饋
signal invulnerability_started(duration: float)

@export var speed: float = 220.0
@export var jump_velocity: float = -420.0
@export var max_hp: int = 100
## water / fire / metal / wood / earth / neutral
@export var element: String = "neutral"

## 重力取自 project.godot 的 physics/2d/default_gravity，不要另外寫死數值，
## 否則調整專案重力時角色不會跟著變。
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)

## 受擊後的無敵時間（秒）。0 表示沒有無敵幀。
##
## ⚠️ **只給玩家用，敵人維持 0。** 敵人若有無敵幀，玩家的高射速武器與
## 穿透／連鎖技能會被大量吃掉，傷害計算整個亂掉。
@export var invulnerable_duration: float = 0.0

var hp: int
var _invulnerable_left: float = 0.0


func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


## `min_multiplier` 給「無視五行劣勢」用（砱穴）：把倍率的下限抬到 1.0，
## 優勢仍然吃得到。預設 0.0 等於不干預，既有呼叫端不受影響。
## 受擊後的短暫無敵是否還在
func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func _process(delta: float) -> void:
	_invulnerable_left = maxf(0.0, _invulnerable_left - delta)


func take_damage(amount: int, attacker_element: String, min_multiplier: float = 0.0) -> void:
	if hp <= 0:
		return  # 已經死了，避免同一幀多發子彈重複觸發 die()
	if _invulnerable_left > 0.0:
		# ⚠️ 沒有無敵幀的話，多個來源同一瞬間命中會把血條直接清空。
		# 測試場上十隻敵人全部命中一次是 109 傷，而玩家只有 100 血。
		return
	if invulnerable_duration > 0.0:
		_invulnerable_left = invulnerable_duration
		invulnerability_started.emit(invulnerable_duration)

	var multiplier := maxf(get_element_multiplier(attacker_element, element), min_multiplier)
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
