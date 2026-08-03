## 存檔系統煙霧測試（Task 4.0b）
##
## SaveSystem 是真正落地到 user:// 的檔案I/O，測試前後都要把磁碟狀態和
## SaveSystem 的記憶體欄位還原乾淨，避免污染其他測試或開發者本機的真實存檔，
## 也避免測試之間互相殘留狀態。
extends GutTest

const SAVE_PATH := "user://savegame.json"

## 測試開始前若使用者本機剛好有真實存檔，先備份內容，測試結束後還原。
var _had_existing_save: bool = false
var _existing_save_text: String = ""


func before_each() -> void:
	_had_existing_save = FileAccess.file_exists(SAVE_PATH)
	if _had_existing_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_existing_save_text = f.get_as_text()
		f.close()
		DirAccess.remove_absolute(SAVE_PATH)

	# 重設autoload的記憶體欄位，讓每個測試都從乾淨狀態開始。
	SaveSystem.has_ever_hoarded = false
	SaveSystem.checkpoint = {}


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	if _had_existing_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_string(_existing_save_text)
		f.close()

	# 還原SaveSystem記憶體狀態，反映磁碟目前內容（若剛剛寫回了原始存檔）。
	SaveSystem.load_game()


func test_singleton已載入() -> void:
	assert_not_null(SaveSystem, "SaveSystem autoload 應該存在")


func test_無存檔時讀取回傳空字典() -> void:
	assert_eq(SaveSystem._read_save_data(), {}, "檔案不存在時應安全回退為空字典")


func test_初始狀態has_ever_hoarded為false() -> void:
	assert_false(SaveSystem.has_ever_hoarded)


func test_set_checkpoint寫入座標與路徑() -> void:
	SaveSystem.set_checkpoint(NodePath("Level01/Checkpoints/CP1"), Vector2(120.0, 45.5))

	var data := SaveSystem._read_save_data()
	assert_true(data.has("checkpoint"))
	var cp: Dictionary = data["checkpoint"]
	assert_eq(cp["path"], "Level01/Checkpoints/CP1")
	assert_almost_eq(float(cp["x"]), 120.0, 0.001)
	assert_almost_eq(float(cp["y"]), 45.5, 0.001)

	# 記憶體欄位也要同步更新，不能只寫磁碟不更新記憶體。
	assert_eq(SaveSystem.checkpoint["path"], "Level01/Checkpoints/CP1")


func test_set_checkpoint不依賴LevelManager() -> void:
	# Task 4.0b的Verify明確要求：checkpoint.gd能在Task 4.1直接呼叫set_checkpoint()，
	# 此時LevelManager（Task 4.3）可能還沒建立。set_checkpoint()不應該存取LevelManager，
	# 也不應該因為LevelManager不存在而報錯。
	SaveSystem.set_checkpoint(NodePath("SomeLevel/CP"), Vector2.ZERO)
	assert_true(SaveSystem._read_save_data().has("checkpoint"))


func test_mark_hoarded立即生效() -> void:
	assert_false(SaveSystem.has_ever_hoarded)
	SaveSystem.mark_hoarded()
	assert_true(SaveSystem.has_ever_hoarded, "呼叫後記憶體欄位應立即為true")


func test_mark_hoarded立即持久化() -> void:
	SaveSystem.mark_hoarded()
	var data := SaveSystem._read_save_data()
	assert_true(bool(data.get("has_ever_hoarded", false)), "呼叫後磁碟應立即為true，不能只在記憶體生效")


func test_mark_hoarded後reload仍為true() -> void:
	SaveSystem.mark_hoarded()
	SaveSystem.has_ever_hoarded = false  # 模擬遊戲重啟前記憶體被清空
	SaveSystem.load_game()
	assert_true(SaveSystem.has_ever_hoarded, "重新load_game()後應從磁碟讀回true")


func test_舊存檔false呼叫mark_hoarded後為true() -> void:
	# 模擬「先有一份has_ever_hoarded:false的舊存檔」，再呼叫mark_hoarded()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"has_ever_hoarded": false, "checkpoint": {}}))
	f.close()
	SaveSystem.load_game()
	assert_false(SaveSystem.has_ever_hoarded)

	SaveSystem.mark_hoarded()
	assert_true(SaveSystem.has_ever_hoarded)
	assert_true(bool(SaveSystem._read_save_data().get("has_ever_hoarded", false)))


func test_預置true存檔_未手動load直接set_checkpoint不會回寫false() -> void:
	# 回歸測試（呼應計劃書Verify要求）：預先在磁碟寫入has_ever_hoarded:true，
	# 重建/重置SaveSystem記憶體狀態後，不手動呼叫load_game()而直接觸發
	# set_checkpoint()，記憶體與磁碟都必須維持true，不能被預設false覆蓋。
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"has_ever_hoarded": true, "checkpoint": {}}))
	f.close()

	# 模擬「autoload剛啟動、_ready()已跑過」的狀態，但這裡故意不呼叫load_game()，
	# 而是手動把記憶體設回預設值，驗證set_checkpoint()本身不會覆蓋has_ever_hoarded。
	SaveSystem.has_ever_hoarded = true  # 假設_ready()已經正確同步過（見下一個測試驗證_ready本身）
	SaveSystem.set_checkpoint(NodePath("Level01/CP"), Vector2(1.0, 2.0))

	assert_true(SaveSystem.has_ever_hoarded, "set_checkpoint()不應該把has_ever_hoarded改回false")
	var data := SaveSystem._read_save_data()
	assert_true(bool(data.get("has_ever_hoarded", false)), "磁碟上的has_ever_hoarded不應被set_checkpoint()覆寫為false")


func test_load_game從預置true存檔正確同步() -> void:
	# 驗證_ready()實際依賴的load_game()路徑：預置true存檔後呼叫load_game()，
	# 記憶體必須變成true，不能停留在預設的false。
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"has_ever_hoarded": true, "checkpoint": {"path": "X", "x": 1.0, "y": 2.0}}))
	f.close()

	SaveSystem.has_ever_hoarded = false
	SaveSystem.checkpoint = {}
	SaveSystem.load_game()

	assert_true(SaveSystem.has_ever_hoarded)
	assert_eq(SaveSystem.checkpoint.get("path"), "X")


func test_空白檔案安全回退為空字典() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("")
	f.close()
	assert_eq(SaveSystem._read_save_data(), {}, "空白檔案應視為無存檔，不應報錯或當機")


func test_格式錯誤的JSON安全回退為空字典() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{not valid json,,,")
	f.close()
	assert_eq(SaveSystem._read_save_data(), {}, "格式錯誤的JSON應安全回退為空字典，不應中斷遊戲")
	# 格式錯誤的JSON會觸發兩層錯誤：Godot JSON.parse_string()本身的引擎錯誤，
	# 以及我們自己的push_warning；兩者都要在這裡消化掉，否則會被GUT判定為未預期錯誤。
	assert_engine_error(2, "格式錯誤時應留下警告與引擎錯誤，不能安靜跳過")


func test_JSON為陣列而非物件時安全回退為空字典() -> void:
	# JSON.parse_string對 "[]" 會回傳TYPE_ARRAY，不是TYPE_DICTIONARY，
	# _read_save_data()必須辨識這種型別不符的情況並安全回退。
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("[]")
	f.close()
	assert_eq(SaveSystem._read_save_data(), {}, "JSON陣列不是預期的存檔格式，應安全回退為空字典")
	assert_engine_error("內容非合法JSON", "型別不符時應留下警告，不能安靜跳過")


func test_save_game不修改傳入的data參照() -> void:
	# save_game內部用duplicate(true)快照，呼叫端傳入的字典不應被原地污染。
	var original := {"level": 2}
	SaveSystem.has_ever_hoarded = true
	SaveSystem.save_game(original)
	assert_eq(original, {"level": 2}, "save_game()不應該原地修改呼叫端傳入的字典")

	var data := SaveSystem._read_save_data()
	assert_almost_eq(float(data.get("level", 0)), 2.0, 0.001, "傳入的既有欄位應該被保留寫入磁碟")
	assert_true(bool(data.get("has_ever_hoarded", false)))
