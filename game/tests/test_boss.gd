## Boss 基類：多階段狀態機（Task 5.1）
extends GutTest

const BossScript := preload("res://scripts/boss.gd")
const EnemyScene := preload("res://scenes/enemy_base.tscn")
const BOSSES_DATA_PATH := "res://data/bosses.json"

var _bosses_data: Array = []


func before_all() -> void:
	var f := FileAccess.open(BOSSES_DATA_PATH, FileAccess.READ)
	assert_not_null(f, "bosses.json 應該存在且可開啟")
	if f != null:
		_bosses_data = JSON.parse_string(f.get_as_text())
		f.close()


## 用 enemy_base.tscn 換上 boss.gd 腳本，取得 HanziSprite / MeleeAttack 等子節點結構，
## 不需要另外做一個 boss 專用場景（本任務範圍不動 .tscn）。
##
## ⚠️ 場景根節點原本掛的是 enemy.gd，instantiate() 回傳的靜態型別是 Enemy，
## 不能直接指派給 Boss 型別的變數（會在賦值當下就被引擎擋下來）。
## 要先用 Node 接住、換腳本，再轉型成 Boss。
func _make_boss(data: Dictionary) -> Boss:
	var node: Node = EnemyScene.instantiate()
	node.set_script(BossScript)
	add_child_autofree(node)
	var boss := node as Boss
	boss.setup_boss(data)
	return boss


func _淼_data() -> Dictionary:
	return {"char": "淼", "element": "water", "hp": 300, "phases": 3, "sub_radicals": ["水", "水", "水"], "level": 1}


# ---- bosses.json 資料表 ----

func test_共3隻boss() -> void:
	assert_eq(_bosses_data.size(), 3)


func test_每筆欄位齊全且合法() -> void:
	for data: Dictionary in _bosses_data:
		for key: String in ["char", "element", "hp", "phases", "sub_radicals", "level"]:
			assert_true(data.has(key), "boss %s 缺欄位 %s" % [data.get("char", "?"), key])
		assert_gt(int(data["hp"]), 0, "%s 的 hp 應為正" % data["char"])
		assert_gt(int(data["phases"]), 0, "%s 的 phases 應為正" % data["char"])
		assert_eq(
			int(data["sub_radicals"].size()), int(data["phases"]),
			"%s 的 sub_radicals 數量應等於 phases" % data["char"]
		)
		assert_gt(int(data["level"]), 0, "%s 的 level 應為正" % data["char"])


func test_終極boss仁不在本檔案() -> void:
	for data: Dictionary in _bosses_data:
		assert_ne(String(data["char"]), "仁", "「仁」是Task 5.4的特殊boss，不應出現在bosses.json")


func test_三隻boss字元符合規格() -> void:
	var chars := []
	for data: Dictionary in _bosses_data:
		chars.append(data["char"])
	assert_has(chars, "淼")
	assert_has(chars, "焱")
	assert_has(chars, "森")


# ---- Boss 本體：階段狀態機 ----

func test_setup_boss灌入資料() -> void:
	var boss := _make_boss(_淼_data())
	assert_eq(boss.element, "water")
	assert_eq(boss.max_hp, 300)
	assert_eq(boss.hp, 300)
	assert_eq(boss.max_phases, 3)
	assert_eq(boss.sub_radicals, ["水", "水", "水"])
	assert_eq(boss.phase, 1, "一開始應在phase 1")


func test_初始狀態沒有BossAttackPatterns子節點時不崩潰() -> void:
	# Task 5.2 的 boss_attack_patterns.gd 平行開發中，這裡確認即使沒有這個子節點，
	# Boss 本體照樣能建立與運作（get_node_or_null 安全寫法）。
	var boss := _make_boss(_淼_data())
	assert_null(boss.get_node_or_null(^"BossAttackPatterns"))
	boss.take_damage(50, "neutral")
	assert_eq(boss.hp, 250)


func test_hp降到2_3閾值進入phase2() -> void:
	# max_hp=300, 3階段，每階段100血。降到200（含）就該進入phase 2
	var boss := _make_boss(_淼_data())
	boss.take_damage(100, "neutral")  # hp: 300 -> 200
	await wait_physics_frames(1)  # enter_phase 用 call_deferred
	assert_eq(boss.hp, 200)
	assert_eq(boss.phase, 2, "hp剛好等於200這個閾值，應該進入phase 2")


func test_hp降到1_3閾值進入phase3() -> void:
	var boss := _make_boss(_淼_data())
	boss.take_damage(100, "neutral")  # -> 200, phase 2
	await wait_physics_frames(1)
	boss.take_damage(100, "neutral")  # -> 100, phase 3
	await wait_physics_frames(1)
	assert_eq(boss.hp, 100)
	assert_eq(boss.phase, 3, "hp剛好等於100這個閾值，應該進入phase 3")


func test_hp在閾值之上不觸發階段轉換() -> void:
	var boss := _make_boss(_淼_data())
	boss.take_damage(99, "neutral")  # -> 201，還沒到200的閾值
	await wait_physics_frames(1)
	assert_eq(boss.hp, 201)
	assert_eq(boss.phase, 1, "hp還在201，尚未降到閾值，應維持phase 1")


func test_邊界值剛好高於閾值一點不誤觸發() -> void:
	var boss := _make_boss(_淼_data())
	boss.take_damage(99, "neutral")  # -> 201
	await wait_physics_frames(1)
	boss.take_damage(1, "neutral")   # -> 200，這一下才觸發
	await wait_physics_frames(1)
	assert_eq(boss.hp, 200)
	assert_eq(boss.phase, 2, "hp從201降到200的這一下應該觸發phase 2")


func test_一次重擊直接跨過phase2進入phase3() -> void:
	# 一刀砍到只剩50血（低於1/3閾值），應該直接落在phase 3，不會卡在phase 2
	var boss := _make_boss(_淼_data())
	boss.take_damage(250, "neutral")  # -> 50
	await wait_physics_frames(1)
	assert_eq(boss.hp, 50)
	assert_eq(boss.phase, 3, "一次大量傷害應該能跨階段直接進入phase 3")


func test_phase不會倒退() -> void:
	# 進入phase 2之後，之後每一下傷害都不應該讓phase退回1
	var boss := _make_boss(_淼_data())
	boss.take_damage(150, "neutral")  # -> 150, 進入phase 2
	await wait_physics_frames(1)
	assert_eq(boss.phase, 2)

	# 手動把phase調高後隨便補一刀小傷害，確認不會被算低的expected_phase打回去
	boss.phase = 3
	boss.take_damage(1, "neutral")
	await wait_physics_frames(1)
	assert_eq(boss.phase, 3, "phase不應該倒退")


func test_死亡的這一下不觸發enter_phase() -> void:
	var boss := _make_boss(_淼_data())
	# 死亡特效（筆畫崩解）預設要 0.7 秒才會清乾淨，縮短它讓測試不用真的等那麼久，
	# 也避免殘留的碎片節點漏到其他測試腳本裡（GUT 是同一棵場景樹跑完所有測試）。
	if is_instance_valid(boss.hanzi_sprite):
		boss.hanzi_sprite.shatter_duration = 0.05
	boss.take_damage(299, "neutral")  # -> 1, 進入phase 3
	await wait_physics_frames(1)
	assert_eq(boss.phase, 3)

	watch_signals(boss)
	boss.take_damage(999, "neutral")  # 打死，will_die分支要生效，不應該再觸發enter_phase
	# ⚠️ 不要在這裡 await：die() 內部的 queue_free 是延遲釋放，但 defeated 訊號
	# 在 take_damage 呼叫的當下就已經同步發出。await 之後節點可能已經被釋放，
	# 這時候再對它呼叫 assert_signal_emitted 會直接讓引擎崩潰（存取已釋放節點）。
	assert_signal_emitted(boss, "defeated")
	# 讓崩解動畫跑完再進入下一個測試，避免碎片節點殘留污染其他測試腳本
	# （例如 test_brush_glyph.gd 會斷言場上沒有殘留的 stroke_fragment）。
	await wait_seconds(0.2)


func test_死亡時不會有殘留節點錯誤() -> void:
	var boss := _make_boss(_淼_data())
	if is_instance_valid(boss.hanzi_sprite):
		boss.hanzi_sprite.shatter_duration = 0.05
	boss.take_damage(9999, "neutral")
	await wait_physics_frames(3)
	assert_false(is_instance_valid(boss), "boss死亡後本體應被釋放")
	await wait_seconds(0.2)


func test_較小boss焱在正確血量進入phase2() -> void:
	var data := {"char": "焱", "element": "fire", "hp": 350, "phases": 3, "sub_radicals": ["火", "火", "火"], "level": 2}
	var boss := _make_boss(data)
	# max_hp=350, 每階段約116.67。2/3閾值 = 350 * 1/3 ≈ 116.67 -> ceil用<=判斷
	# 降到 hp <= 233.33 時應進入phase2
	boss.take_damage(120, "neutral")  # 350 -> 230
	await wait_physics_frames(1)
	assert_eq(boss.hp, 230)
	assert_eq(boss.phase, 2, "hp降到230，低於233.33的2/3閾值，應進入phase2")


func test_受五行相剋影響下的階段判斷() -> void:
	# water boss被剋制屬性打，傷害會被放大，階段判斷要用實際扣血後的hp，不是原始amount
	var boss := _make_boss(_淼_data())
	boss.take_damage(50, "earth")  # 土剋水 x1.5 -> 實際傷害75, hp: 300 -> 225
	await wait_physics_frames(1)
	assert_eq(boss.hp, 225)
	assert_eq(boss.phase, 1, "225還沒到200的閾值")

	boss.take_damage(20, "earth")  # 實際傷害30, hp: 225 -> 195
	await wait_physics_frames(1)
	assert_eq(boss.hp, 195)
	assert_eq(boss.phase, 2, "195已經低於200的閾值，應進入phase2")
