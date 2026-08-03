## 關卡管理器測試（Task 4.3）
## 場景檔案（level_00~05、victory_screen）目前尚未建立，change_scene_to_file
## 內部已用 ResourceLoader.exists() 擋掉並 push_error，因此這裡用 assert_push_error
## 把預期中的錯誤訊息消化掉，只驗證 current_level_index / get_current_level_path()
## 等狀態變化，不驗證真的切換了場景。
extends GutTest

const LevelManagerScript := preload("res://scripts/level_manager.gd")


func _make_manager() -> Node:
	var manager: Node = LevelManagerScript.new()
	add_child_autofree(manager)
	return manager


func test_初始索引為0() -> void:
	var manager := _make_manager()
	assert_eq(manager.current_level_index, 0)


func test_levels清單包含序章加4關加終章共6個場景() -> void:
	var manager := _make_manager()
	assert_eq(manager.levels.size(), 6, "序章+4關+終章共6個場景")


# ---- next_level ----

func test_next_level在正常範圍內遞增索引() -> void:
	var manager := _make_manager()
	manager.current_level_index = 0
	manager.next_level()
	assert_eq(manager.current_level_index, 1)
	assert_push_error("場景檔案不存在", "場景尚未建立時應報錯但不阻止索引更新")


func test_next_level連續呼叫依序遞增到底() -> void:
	var manager := _make_manager()
	for i in range(manager.levels.size() - 1):
		manager.next_level()
		assert_eq(manager.current_level_index, i + 1)
	assert_push_error(manager.levels.size() - 1, "每次切換都會因場景檔尚未建立而報錯一次")


func test_next_level在最後一關時不越界() -> void:
	var manager := _make_manager()
	manager.current_level_index = manager.levels.size() - 1
	manager.next_level()
	assert_eq(
		manager.current_level_index,
		manager.levels.size() - 1,
		"已在最後一關時 next_level 不應再遞增 current_level_index（終章特殊流程留給未來controller）"
	)
	assert_push_error("場景檔案不存在", "victory_screen 尚未建立時應報錯但不崩潰")


func test_next_level於空levels不崩潰() -> void:
	var manager := _make_manager()
	manager.levels = []
	manager.current_level_index = 0
	manager.next_level()
	assert_push_error("levels 清單為空", "空清單應報錯而非崩潰")


# ---- load_level ----

func test_load_level設定current_level_index() -> void:
	var manager := _make_manager()
	manager.load_level(3)
	assert_eq(manager.current_level_index, 3)
	assert_push_error("場景檔案不存在", "場景尚未建立時應報錯但不阻止索引更新")


func test_load_level索引越界時保持原值且不崩潰() -> void:
	var manager := _make_manager()
	manager.current_level_index = 2
	manager.load_level(99)
	assert_eq(manager.current_level_index, 2, "越界索引不應改變 current_level_index")
	assert_push_error("超出", "應對越界索引發出錯誤訊息")


func test_load_level負索引時保持原值且不崩潰() -> void:
	var manager := _make_manager()
	manager.current_level_index = 1
	manager.load_level(-1)
	assert_eq(manager.current_level_index, 1, "負索引不應改變 current_level_index")
	assert_push_error("超出", "負索引也應被視為越界並報錯")


func test_load_level於空levels不崩潰() -> void:
	var manager := _make_manager()
	manager.levels = []
	manager.load_level(0)
	assert_push_error("levels 清單為空", "空清單應報錯而非崩潰")


# ---- get_current_level_path ----

func test_get_current_level_path與索引一致() -> void:
	var manager := _make_manager()
	manager.load_level(2)
	assert_eq(manager.get_current_level_path(), manager.levels[2])
	assert_push_error("場景檔案不存在", "場景尚未建立時應報錯但不阻止索引更新")


func test_get_current_level_path索引越界時回傳空字串() -> void:
	var manager := _make_manager()
	manager.current_level_index = 999
	assert_eq(manager.get_current_level_path(), "", "索引越界時應回傳空字串而非崩潰")


func test_get_current_level_path於空levels回傳空字串() -> void:
	var manager := _make_manager()
	manager.levels = []
	assert_eq(manager.get_current_level_path(), "")


# ---- reset_to_prologue ----

func test_reset_to_prologue回到第0關() -> void:
	var manager := _make_manager()
	manager.load_level(4)
	manager.reset_to_prologue()
	assert_eq(manager.current_level_index, 0)
	assert_push_error(2, "load_level(4) 與 reset_to_prologue 各因場景未建立報錯一次")


func test_reset_to_prologue於空levels不崩潰() -> void:
	var manager := _make_manager()
	manager.levels = []
	manager.reset_to_prologue()
	assert_push_error("levels 清單為空", "空清單應報錯而非崩潰")
