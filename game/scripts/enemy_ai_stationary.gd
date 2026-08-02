## 定點範圍攻擊 AI（Task 3.2）
##
## 完全不移動（speed 為 0），週期性放出一圈範圍傷害。
extends Node

@export var aoe_radius: float = 130.0
@export var pulse_interval: float = 2.0
## 蓄力時間：放招前先有預兆，玩家才有機會退出範圍
@export var telegraph_time: float = 0.5

## 被近戰打斷後的硬直（秒）。玩家可以在這段時間再補一下。
@export var stagger_time: float = 0.35

## 蓄力時的警示色。
##
## ⚠️ 用 `self_modulate` 而不是 `modulate`：`HanziSprite.flash_hit()` 受擊閃紅用的是
## `modulate`，兩者若共用同一個屬性，蓄力中被打一下就會互相把對方的 tween 蓋掉。
## CanvasItem 的這兩個屬性是相乘的，各自獨立 tween 不會打架。
const CHARGE_COLOR := Color(1.0, 0.45, 0.25)
## 硬直時的顏色。玩家要看得出「現在可以免費打它」。
const STAGGER_COLOR := Color(0.5, 0.62, 0.8)
## 蓄力時字形放大到多少。原本是 1.25，實機驗證時肉眼分辨不出來。
const CHARGE_SCALE := Vector2(1.4, 1.4)

var _cooldown: float = 0.0
var _telegraph_left: float = 0.0
var _stagger_left: float = 0.0
var _initialised: bool = false
var _telegraph_tween: Tween


func is_charging() -> bool:
	return _telegraph_left > 0.0


## 被近戰打斷蓄力（Task 2.7c）。回傳是否真的打斷了什麼。
##
## **只有近戰打得斷，遠程不行**——這是「為什麼要靠近錘／灶」的唯一答案，
## 見 `docs/COMBAT.md` 3.6。
##
## ⚠️ 一定要 kill 掉蓄力的 tween 並把字形縮放復原。`_start_telegraph()` 用 tween
## 把字形放大到 1.25 當預兆，被打斷時若不處理，敵人會**永遠停在放大狀態**——
## 與 `HanziSprite.flash_hit()` 的「連續受擊要先 kill 前一個 tween」是同一類問題。
func interrupt(enemy: Enemy) -> bool:
	if _telegraph_left <= 0.0:
		return false

	_telegraph_left = 0.0
	_stagger_left = stagger_time

	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = null

	if enemy != null and is_instance_valid(enemy):
		if enemy.hanzi_sprite != null and is_instance_valid(enemy.hanzi_sprite):
			enemy.hanzi_sprite.scale = Vector2.ONE
			# 硬直期間染成另一個顏色，玩家才看得出「現在可以免費打它」——
			# 只把縮放彈回去的話，實機上根本分辨不出有沒有打斷成功
			enemy.hanzi_sprite.self_modulate = STAGGER_COLOR
		DamagePopup.show_text(enemy, "打斷！", DamagePopup.INTERRUPT_COLOR, 30)
	return true


func decide_velocity(enemy: Enemy, delta: float) -> float:
	if not _initialised:
		_initialised = true
		_cooldown = randf_range(0.0, pulse_interval)

	if _stagger_left > 0.0:
		# 硬直期間不蓄力也不放招，但 pulse_interval 的冷卻照常走——
		# 否則玩家站著無限打斷就能把敵人永久鎖死
		_stagger_left = maxf(0.0, _stagger_left - delta)
		_cooldown = maxf(0.0, _cooldown - delta)
		if _stagger_left <= 0.0:
			_restore_tint(enemy)
		return 0.0

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
	var sprite := enemy.hanzi_sprite
	sprite.self_modulate = Color.WHITE
	# 保留參考，被打斷時要 kill 掉，否則字形會卡在放大＋染色狀態
	_telegraph_tween = sprite.create_tween()
	_telegraph_tween.tween_property(sprite, "scale", CHARGE_SCALE, telegraph_time)
	_telegraph_tween.parallel().tween_property(sprite, "self_modulate", CHARGE_COLOR, telegraph_time)
	_telegraph_tween.chain().tween_property(sprite, "scale", Vector2.ONE, 0.15)
	_telegraph_tween.parallel().tween_property(sprite, "self_modulate", Color.WHITE, 0.15)


func _restore_tint(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.hanzi_sprite != null and is_instance_valid(enemy.hanzi_sprite):
		enemy.hanzi_sprite.self_modulate = Color.WHITE


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
