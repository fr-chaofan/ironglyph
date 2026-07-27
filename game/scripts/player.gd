## 玩家角色控制（Task 1.3）
##
## 左右移動、跳躍、開火。Task 2.6 起角色本體是聲符字核「令」。
extends Character

@onready var hanzi_sprite: HanziSprite = $HanziSprite
@onready var direction_indicator: Node2D = $DirectionIndicator
## WeaponManager 於階段二 Task 2.2 建立，階段一時此節點不存在，取到 null 是正常的
@onready var weapon_manager: Node = get_node_or_null(^"WeaponManager")
## Task 2.5：世界空間的武器字形顯示。只移動持握側，不鏡像漢字。
@onready var weapon_glyph_display: WeaponGlyphDisplay = get_node_or_null(^"WeaponGlyphDisplay")

## 面向：1 = 右、-1 = 左。開火方向與朝向指示器都看這個值。
var facing_dir: float = 1.0

## 可連續跳躍的次數。2 = 二段跳（落地跳 + 空中跳一次）。
## 單次跳躍高度為 jump_velocity² / (2 × gravity)，預設值約 90px；
## 二段跳讓玩家最高可達約兩倍，關卡高低差設計以此為上限。
@export var max_jumps: int = 2

## 空中跳的力道倍率。略弱於地面跳，讓兩段的手感有區別，
## 也避免二段跳變成「跳一次就上天」。
@export var air_jump_multiplier: float = 0.9

var _jumps_used: int = 0


func _ready() -> void:
	super()
	# 敵人AI 透過這個群組找玩家，不用寫死節點路徑——關卡場景結構改變時不會壞掉
	add_to_group(&"player")


func _physics_process(delta: float) -> void:
	var was_on_floor := is_on_floor()
	apply_gravity(delta)

	if was_on_floor:
		_jumps_used = 0

	if Input.is_action_just_pressed(&"jump") and _jumps_used < max_jumps:
		# 空中跳直接覆寫 velocity.y 而非疊加——下墜途中按二段跳應該立刻往上，
		# 而不是被既有的下墜速度抵銷掉
		var power := jump_velocity if _jumps_used == 0 else jump_velocity * air_jump_multiplier
		velocity.y = power
		_jumps_used += 1

	var dir := Input.get_axis(&"move_left", &"move_right")
	velocity.x = dir * speed

	if not is_zero_approx(dir):
		facing_dir = signf(dir)
		# ⚠️ 只翻轉指示器，不翻轉 HanziSprite——漢字鏡像後會變成無法辨識的反字
		direction_indicator.scale.x = absf(direction_indicator.scale.x) * facing_dir
		if weapon_glyph_display != null:
			weapon_glyph_display.set_facing(facing_dir)

	if Input.is_action_pressed(&"fire"):
		_try_fire()

	move_and_slide()


func _try_fire() -> void:
	# 階段一還沒有 WeaponManager，靜默略過；階段二 Task 2.2 接上後自動生效
	if weapon_manager != null and weapon_manager.has_method(&"fire"):
		weapon_manager.fire(facing_dir)


func take_damage(amount: int, attacker_element: String) -> void:
	super(amount, attacker_element)
	if hp > 0:
		hanzi_sprite.flash_hit()


func die() -> void:
	# 玩家死亡走筆畫崩解特效（階段三 Task 3.4 實作細節），不直接 queue_free
	died.emit()
	hanzi_sprite.shatter_and_die()
