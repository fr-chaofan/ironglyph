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
## Task 2.7b：近戰揮擊。K 是「令」自己的字核能力，與 J 的部件遠程互不取代。
@onready var melee_attack: MeleeAttack = get_node_or_null(^"MeleeAttack") as MeleeAttack
## Task 2.6 的裝備狀態真相源；Task 2.7c 起也負責分派 J/K 兩個動詞的 profile。
@onready var glyph_loadout: Node = get_node_or_null(^"GlyphLoadout")

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
## 死亡後保留 Player 節點，讓筆畫崩解與未來的關卡 controller 能完成收尾；
## 但此狀態是 terminal，不可再移動、跳躍、開火或參與碰撞。
var is_dead: bool = false


func _ready() -> void:
	super()
	# 敵人AI 透過這個群組找玩家，不用寫死節點路徑——關卡場景結構改變時不會壞掉
	add_to_group(&"player")

	# ⚠️ **主角不可以用純白。** 五行配色裡「金＝白」（GDD 2.3），純白的主角會與
	# 金屬性敵人（鋼／針／劍／錘）在畫面上撞色——實機驗證時「劍」看起來就和主角一樣白。
	#
	# 這與 GDD 2.3 記錄的中性子彈撞色是**同一個坑的另一半**：當初的正解是
	# 「把中性移開白色，而不是去改金屬色破壞五行慣例」。主角是 neutral，
	# 中性的定案色就是洋紅，走同一套色表即可，不另立第三種規則。
	#
	# 附帶好處：主角的中性遠程「弓」打出的子彈也是洋紅，攻擊與角色同色。
	hanzi_sprite.set_element_color(element)

	if melee_attack != null:
		melee_attack.pogo_bounced.connect(_on_pogo_bounced)
		melee_attack.hit_landed.connect(_on_melee_hit_landed)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

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

	if InputMap.has_action(&"melee") and Input.is_action_just_pressed(&"melee"):
		_try_melee()

	move_and_slide()


## K 近戰。空中按住 S 是下劈（pogo）——落地時按 S 沒有意義，
## 腳下就是地板，判定框只會掃到地形。
func _try_melee() -> bool:
	if is_dead or melee_attack == null:
		return false

	var wants_down := (
		not is_on_floor()
		and InputMap.has_action(&"move_down")
		and Input.is_action_pressed(&"move_down")
	)
	# profile 由 GlyphLoadout 依裝備狀態分派：CORE/HELD投射類是令筆擊、
	# FUSED 染上融合字屬性、手持「刂」則換成刀刃筆擊。
	return melee_attack.swing(facing_dir, _get_melee_profile(), wants_down)


## 近戰命中的打擊感。遠程刻意沒有——近戰要「重」，兩者才有手感上的區別。
func _on_melee_hit_landed(_target: Node, _damage: int) -> void:
	GameFeel.hit_stop(self)
	GameFeel.shake(self, 5.0)


func _get_melee_profile() -> Dictionary:
	if glyph_loadout == null or not glyph_loadout.has_method(&"get_melee_profile"):
		return {}
	return glyph_loadout.call(&"get_melee_profile")


## 下劈命中後彈起。
##
## ⚠️ 這個 callback 在 `MeleeAttack._physics_process()` 裡送出，而子節點的
## `_physics_process` 跑在 Player 之後——也就是**本幀的 `apply_gravity()` 與
## `move_and_slide()` 都已經跑完了**。因此這裡設的 `velocity.y` 會完整保留到
## 下一幀才被套用，不會當幀就被重力吃掉。若哪天把揮擊判定移回 Player 自己的
## `_physics_process`，順序就必須重新檢查。
func _on_pogo_bounced(bounce_velocity: float) -> void:
	if is_dead:
		return
	velocity.y = bounce_velocity
	# 踩著敵人可以重新取得二段跳，這是下劈作為位移手段的核心
	_jumps_used = 0


func _try_fire() -> void:
	if is_dead:
		return
	# 階段一還沒有 WeaponManager，靜默略過；階段二 Task 2.2 接上後自動生效
	if weapon_manager != null and weapon_manager.has_method(&"fire"):
		weapon_manager.fire(facing_dir)


func take_damage(amount: int, attacker_element: String) -> void:
	super(amount, attacker_element)
	if hp > 0:
		hanzi_sprite.flash_hit()
		# 自己被打到震得比打到別人更重——玩家要立刻知道「這下是我在挨打」
		GameFeel.shake(self, 9.0, 0.24)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	velocity = Vector2.ZERO
	# 死亡當幀若正在揮擊，判定框必須立刻失效——否則屍體還會再打出一下
	if melee_attack != null and is_instance_valid(melee_attack):
		melee_attack.cancel()
	set_physics_process(false)
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	remove_from_group(&"player")
	if direction_indicator != null:
		direction_indicator.hide()

	# 死亡可能發生在 Area2D 的 body_entered callback；物理查詢 flush 期間不可同步
	# 修改碰撞狀態，因此統一 deferred。移除 player group 與停用 physics 已先同步完成。
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	var collision_shape := get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred(&"disabled", true)

	died.emit()
	# 玩家死亡走筆畫崩解特效（階段三 Task 3.4 實作細節），不直接 queue_free；
	# Player 本體暫留給關卡 controller 決定何時重生或切換場景。
	if hanzi_sprite != null and is_instance_valid(hanzi_sprite):
		hanzi_sprite.shatter_and_die()

	# died listeners 與 shatter 必須先同步完成；之後停用整個 subtree，避免
	# GlyphLoadout 等子節點仍在 _process() 接收 Q／其他 gameplay input。
	process_mode = Node.PROCESS_MODE_DISABLED
