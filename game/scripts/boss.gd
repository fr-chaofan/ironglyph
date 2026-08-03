## Boss 基類：多階段狀態機（Task 5.1）
##
## 繼承 Enemy。血量降到各階段門檻時觸發 enter_phase()，讓子節點
## BossAttackPatterns（Task 5.2，平行開發中）拆解出對應部首發動子武器攻擊。
##
## ⚠️ BossAttackPatterns 是另一支平行任務的腳本，開發本檔案時它可能還不存在於
## 專案裡。這裡刻意**不對它的型別做靜態標注**（不寫 `: BossAttackPatterns`），
## 只用 `get_node_or_null()` + `has_method()` 的安全寫法呼叫，避免因為對方的
## 腳本檔案還沒進來就讓整個專案編譯失敗。等 Task 5.2 併入後，把型別標注加回去
## 即可拿到型別檢查，這裡不用改呼叫邏輯。
class_name Boss
extends Enemy

## 目前所在階段，從 1 開始
var phase: int = 1
## 總階段數，由 bosses.json 的 "phases" 灌入
var max_phases: int = 3
## 各階段拆解出來的部首，依序對應 phase 1 / 2 / 3...
## 若階段數超過陣列長度，enter_phase() 會夾到最後一個元素而不是報錯。
var sub_radicals: Array = []

## 子節點若存在的話會是 Task 5.2 的 BossAttackPatterns。刻意不寫死型別，見上方註解。
@onready var attack_patterns: Node = get_node_or_null(^"BossAttackPatterns")


## 疊加在 Enemy.setup() 之上，灌入 Boss 專屬欄位。
func setup_boss(data: Dictionary) -> void:
	setup(data)
	max_phases = maxi(1, int(data.get("phases", 3)))
	sub_radicals = data.get("sub_radicals", [])
	phase = 1


## 覆寫 Enemy.take_damage：先判斷這一下傷害會不會讓階段往前推進，
## 再把實際扣血／受擊特效／死亡判斷整個交給 Enemy.take_damage 統一處理。
##
## ⚠️ 簽名要跟 Enemy.take_damage 完全一致（含 min_multiplier 預設參數），
## 否則 override 不會生效，會被當成新方法而不是覆寫。
func take_damage(amount: int, attacker_element: String, min_multiplier: float = 0.0) -> void:
	var multiplier := maxf(get_element_multiplier(attacker_element, element), min_multiplier)
	var actual_damage := int(amount * multiplier)
	var hp_after := hp - actual_damage
	var will_die := hp_after <= 0

	# 死亡的這一下不再判斷階段轉換——boss 都要死了，沒有「下一階段」可言。
	# 這也避免 die() 的 queue_free 流程跟 call_deferred("enter_phase", ...) 搶著動同一個
	# 正在銷毀的節點。
	if not will_die:
		var expected_phase := _phase_for_hp(hp_after)
		# 只允許階段往前推進，不允許倒退：就算計算浮動誤差把 expected_phase 算低了，
		# 已經進入的階段也不會被打回去。
		if expected_phase > phase:
			phase = expected_phase
			# 延後到本幀傷害處理完再觸發，避免 enter_phase 裡的 flash_hit
			# 跟 Enemy.take_damage 裡的 flash_hit 在同一幀互相蓋 tween。
			call_deferred(&"enter_phase", phase)

	# 交給 Enemy.take_damage 統一處理扣血／受擊特效／死亡判斷，
	# 避免在這裡重複實作一次扣血邏輯而跟基類邏輯兜不起來。
	super(amount, attacker_element, min_multiplier)


## 依剩餘血量 hp_after 算出「應該在第幾階段」。
##
## 用 max_hp 平均切成 max_phases 等份，hp **降到**第 k 份門檻（含剛好等於門檻值）
## 時進入第 k+1 階段。例：max_hp=300、max_phases=3 → 每階段 100 血：
## - hp_after > 200：phase 1
## - 100 < hp_after <= 200：phase 2（剛好等於 200 就算「降到 2/3 閾值」，進入 phase 2）
## - hp_after <= 100：phase 3（剛好等於 100 就算「降到 1/3 閾值」，進入 phase 3）
##
## ⚠️ 門檻用「<=」而不是「<」：血量剛好打到門檻值這一下，就是「降到 2/3、1/3 閾值」
## 本身，玩家期待看到轉階段的正是這一下，不能因為浮點數誤差而漏跳或多跳一階
## （見 Task 5.1 驗收標準）。這個門檻的取捨已在測試裡明確覆蓋邊界值。
func _phase_for_hp(hp_after: int) -> int:
	if max_phases <= 1:
		return 1

	var computed_phase := 1
	for p in range(2, max_phases + 1):
		# 進入第 p 階段所需的血量門檻：整個血條依階段數等分後，從上往下數第 (p-1) 條分隔線
		var threshold := float(max_hp) * float(max_phases - p + 1) / float(max_phases)
		if hp_after <= threshold:
			computed_phase = p

	return clampi(computed_phase, 1, max_phases)


## 進入新階段：字形閃一下受擊特效，並讓 BossAttackPatterns（若已存在）
## 拆解出該階段對應的部首，發動子武器攻擊。
func enter_phase(p: int) -> void:
	if is_instance_valid(hanzi_sprite):
		hanzi_sprite.flash_hit()

	var radical := ""
	if not sub_radicals.is_empty():
		var idx := clampi(p - 1, 0, sub_radicals.size() - 1)
		radical = String(sub_radicals[idx])

	if attack_patterns != null and is_instance_valid(attack_patterns) \
			and attack_patterns.has_method(&"spawn_phase_attack"):
		attack_patterns.call(&"spawn_phase_attack", p, radical, element, global_position)
