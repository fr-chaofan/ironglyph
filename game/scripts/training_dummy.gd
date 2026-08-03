## 訓練假人（僅供 test_room.tscn 手動驗證用）
##
## 正式敵人在階段三 Task 3.2 實作。這支腳本的存在只是為了讓階段二的
## 子彈/傷害/五行倍率**看得見**——沒有可以打的目標，這些都無法用眼睛驗證。
## 階段三敵人上線後，這支腳本與 test_room.tscn 一起刪除。
##
## 死亡後會在原地重生，方便反覆測試。
extends Character

@onready var hanzi_sprite: HanziSprite = $HanziSprite
@onready var info_label: Label = $InfoLabel

## 死亡後多久重生（秒）
@export var respawn_delay: float = 1.2

## 顯示用的字
@export var display_char: String = "焰"


func _ready() -> void:
	super()
	hanzi_sprite.character_text = display_char
	# ⚠️ 假人 extends Character 而不是 Enemy，拿不到 Enemy._apply_data() 的屬性著色。
	# 漏了這一行的話，同樣是火屬性，生成的「焰」是橙紅的、假人「焰」卻是白的——
	# 比全部都白還糟，玩家會以為顏色代表別的意思。
	hanzi_sprite.set_element_color(element)
	_refresh_label()
	hp_changed.connect(_on_hp_changed)


func _physics_process(delta: float) -> void:
	# 假人不移動，但要受重力站在地上
	apply_gravity(delta)
	move_and_slide()


func _on_hp_changed(_current: int, _maximum: int) -> void:
	_refresh_label()


func _refresh_label() -> void:
	info_label.text = "%s屬  %d/%d" % [element, hp, max_hp]


func take_damage(amount: int, attacker_element: String, min_multiplier: float = 0.0) -> void:
	var before := hp
	super(amount, attacker_element, min_multiplier)
	var dealt := before - hp

	if is_instance_valid(hanzi_sprite):
		hanzi_sprite.flash_hit()

	DamagePopup.show_damage(self, dealt, get_element_multiplier(attacker_element, element))


## 假人不會真的消失，倒地後原地重生，方便反覆測試
func die() -> void:
	died.emit()
	hanzi_sprite.modulate = Color(0.35, 0.35, 0.4)
	info_label.text = "%s屬  倒地" % element

	await get_tree().create_timer(respawn_delay).timeout

	if not is_instance_valid(self):
		return
	hp = max_hp
	hanzi_sprite.modulate = Color.WHITE
	hp_changed.emit(hp, max_hp)
