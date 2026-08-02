## 敵人基類（Task 3.2）
##
## 資料驅動：所有數值來自 enemies.json，由 setup() 灌入。
## AI 行為掛在子節點（EnemyAI*），本體只負責物理與傷害結算。
##
## ⚠️ 移動只在這裡呼叫一次 move_and_slide()。AI 子節點只負責**決定 velocity**，
## 不自己 apply_gravity/move_and_slide——原計劃讓 AI 節點自己移動，一旦本體
## 或第二個 AI 節點也移動就會重複位移、互相打架。
class_name Enemy
extends Character

signal defeated(enemy: Enemy)

@onready var hanzi_sprite: HanziSprite = $HanziSprite
## Task 2.7d：敵人的近戰揮擊。與玩家共用同一個 MeleeAttack 元件，
## 只有 mask 與 profile 不同（敵人不消彈、不打斷）。
@onready var melee_attack: MeleeAttack = get_node_or_null(^"MeleeAttack") as MeleeAttack

@export var ai_type: String = "patrol_ranged"
@export var char_data: Dictionary = {}

## 接觸傷害的冷卻（秒），避免貼身時每一物理幀都扣血
@export var touch_damage_cooldown: float = 0.8

## 前搖時字形往攻擊方向傾斜的角度（弧度）
const TELEGRAPH_TILT := 0.32
## 前搖的染色。與 stationary_aoe 的蓄力色一致，玩家只要學一次「橙色＝要出招了」。
const TELEGRAPH_COLOR := Color(1.0, 0.45, 0.25)

var _touch_cooldown_left: float = 0.0
var _ai: Node = null
var _telegraph_tween: Tween


func _ready() -> void:
	super()
	if melee_attack != null:
		melee_attack.swing_started.connect(_on_swing_started)
		melee_attack.swing_finished.connect(_on_swing_finished)
	if not char_data.is_empty():
		_apply_data()


## 由 EnemySpawner 在 add_child 之前或之後呼叫皆可
func setup(data: Dictionary) -> void:
	char_data = data
	if is_node_ready():
		_apply_data()


func _apply_data() -> void:
	element = String(char_data.get("element", "neutral"))
	max_hp = int(char_data.get("hp", 30))
	hp = max_hp
	speed = float(char_data.get("speed", 60))
	ai_type = String(char_data.get("ai", "patrol_ranged"))

	if hanzi_sprite != null:
		hanzi_sprite.character_text = String(char_data.get("char", "敵"))
		# 敵人身上必須看得出屬性，否則玩家只能靠背字表決定要換哪個部件
		hanzi_sprite.set_element_color(element)

	hp_changed.emit(hp, max_hp)
	_attach_ai()


## 依 ai_type 掛上對應的行為腳本
func _attach_ai() -> void:
	if _ai != null and is_instance_valid(_ai):
		_ai.queue_free()
		_ai = null

	var script_path := ""
	match ai_type:
		"patrol_ranged":
			script_path = "res://scripts/enemy_ai_patrol.gd"
		"chase_melee":
			script_path = "res://scripts/enemy_ai_chase.gd"
		"stationary_aoe":
			script_path = "res://scripts/enemy_ai_stationary.gd"
		_:
			push_warning("Enemy: 未知的 ai_type「%s」，退回 patrol_ranged" % ai_type)
			script_path = "res://scripts/enemy_ai_patrol.gd"

	_ai = Node.new()
	_ai.name = "AI"
	_ai.set_script(load(script_path))
	add_child(_ai)


func _physics_process(delta: float) -> void:
	_touch_cooldown_left = maxf(0.0, _touch_cooldown_left - delta)

	apply_gravity(delta)
	if _ai != null and is_instance_valid(_ai) and _ai.has_method(&"decide_velocity"):
		velocity.x = _ai.decide_velocity(self, delta)
	move_and_slide()

	_check_touch_damage()


## 貼到玩家身上就造成傷害。用 move_and_slide 的碰撞結果判定，
## 不必額外掛 Area2D。
func _check_touch_damage() -> void:
	# 有自己揮擊的敵人不再造成接觸傷害（Task 2.7d）。
	# 既然預兆可讀，接觸傷害只會變成「讀對了預兆卻還是被蹭到血」的噪音。
	# patrol_ranged 與 stationary_aoe 保留接觸傷害，作為玩家貼臉貼太久的反制。
	if has_own_melee():
		return
	if _touch_cooldown_left > 0.0:
		return
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is Character and collider is not Enemy:
			(collider as Character).take_damage(get_contact_damage(), element)
			_touch_cooldown_left = touch_damage_cooldown
			return


func get_contact_damage() -> int:
	return int(char_data.get("damage", 5))


## 這隻敵人是否有自己的揮擊（而不是靠接觸傷害）。
func has_own_melee() -> bool:
	if melee_attack == null or not is_instance_valid(melee_attack):
		return false
	return typeof(char_data.get("melee", null)) == TYPE_DICTIONARY


## 揮擊前搖的視覺預兆：字形往攻擊方向**傾斜**並染色。
##
## ⚠️ 用 rotation 而不是負的 scale.x。漢字水平鏡像後會變成無法辨識的反字，
## 這是全專案的鐵律（見 hanzi_sprite.gd）。傾斜是旋轉，不違反。
##
## ⚠️ 染色用 self_modulate：flash_hit() 受擊閃紅用的是 modulate，
## 共用同一個屬性的話，前搖中被打一下就會互相把對方的 tween 蓋掉。
func _on_swing_started(profile: Dictionary, _vertical: int) -> void:
	if hanzi_sprite == null or not is_instance_valid(hanzi_sprite):
		return

	_kill_telegraph_tween()
	var windup := maxf(0.05, float(profile.get("windup", 0.3)))
	var tilt := TELEGRAPH_TILT * melee_attack.facing

	_telegraph_tween = hanzi_sprite.create_tween()
	_telegraph_tween.tween_property(hanzi_sprite, "rotation", tilt, windup)
	_telegraph_tween.parallel().tween_property(
		hanzi_sprite, "self_modulate", TELEGRAPH_COLOR, windup
	)


func _on_swing_finished() -> void:
	_kill_telegraph_tween()
	if hanzi_sprite == null or not is_instance_valid(hanzi_sprite):
		return
	_telegraph_tween = hanzi_sprite.create_tween()
	_telegraph_tween.tween_property(hanzi_sprite, "rotation", 0.0, 0.12)
	_telegraph_tween.parallel().tween_property(hanzi_sprite, "self_modulate", Color.WHITE, 0.12)


func _kill_telegraph_tween() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = null


## 被近戰打斷蓄力（Task 2.7c）。回傳是否真的打斷了什麼。
##
## 只有 `stationary_aoe` 有蓄力可打斷；其他 AI 沒有 `interrupt()` 就安靜回傳 false。
func interrupt_charge() -> bool:
	if _ai == null or not is_instance_valid(_ai) or not _ai.has_method(&"interrupt"):
		return false
	return _ai.call(&"interrupt", self)


## 目前是否在蓄力。供近戰判定與測試查詢。
func is_charging() -> bool:
	if _ai == null or not is_instance_valid(_ai) or not _ai.has_method(&"is_charging"):
		return false
	return _ai.call(&"is_charging")


func take_damage(amount: int, attacker_element: String) -> void:
	var multiplier := get_element_multiplier(attacker_element, element)
	var before := hp

	# ⚠️ 順序很重要：先 super() 結算，只有**沒死**才閃紅。
	# 若這一下正好打死，super() 內部已觸發 die() → shatter_and_die() → queue_free()，
	# 此時再對節點做 flash_hit() 會操作到正在銷毀的節點。
	super(amount, attacker_element)

	if hp > 0 and is_instance_valid(hanzi_sprite):
		hanzi_sprite.flash_hit()
		DamagePopup.show_damage(self, before - hp, multiplier)


func die() -> void:
	# 死亡當幀若正在揮擊，判定框必須立刻失效——否則屍體還會再打出一下
	if melee_attack != null and is_instance_valid(melee_attack):
		melee_attack.cancel()
	_kill_telegraph_tween()
	defeated.emit(self)
	died.emit()
	# 死亡視覺統一交給筆畫崩解；shatter_and_die() 內部會 queue_free 掉 HanziSprite，
	# 本體要自己釋放
	if is_instance_valid(hanzi_sprite):
		hanzi_sprite.shatter_and_die()
	queue_free()
