## 玩家角色控制（Task 1.3）
##
## 左右移動、跳躍、開火。角色本體是「我」字。
extends Character

@onready var hanzi_sprite: HanziSprite = $HanziSprite
@onready var direction_indicator: Node2D = $DirectionIndicator
## WeaponManager 於階段二 Task 2.2 建立，階段一時此節點不存在，取到 null 是正常的
@onready var weapon_manager: Node = get_node_or_null(^"WeaponManager")

## 面向：1 = 右、-1 = 左。開火方向與朝向指示器都看這個值。
var facing_dir: float = 1.0


func _physics_process(delta: float) -> void:
	apply_gravity(delta)

	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_velocity

	var dir := Input.get_axis(&"move_left", &"move_right")
	velocity.x = dir * speed

	if not is_zero_approx(dir):
		facing_dir = signf(dir)
		# ⚠️ 只翻轉指示器，不翻轉 HanziSprite——漢字鏡像後會變成無法辨識的反字
		direction_indicator.scale.x = absf(direction_indicator.scale.x) * facing_dir

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
