## 關卡管理器（autoload 名稱建議：LevelManager，Task 4.3）
##
## 統一管理序章＋4關＋終章共6個場景的索引與切換，以及「回到序章」功能。
## ⚠️ 範圍邊界：終章（level_05_final_altar）之後「仁」戰勝→隱藏結局判定→
## level_06_epilogue→victory_screen 這一整段特殊流程屬於Task 5.4/4.4，
## 不在本Task實作範圍內。next_level() 在到達 levels 陣列末端時只做最基本的
## victory_screen 回退；未來的專用controller可以直接呼叫 load_level() 或
## get_tree().change_scene_to_file() 接管終章分支，不需要修改這支腳本。
##
## ⚠️ 本檔案尚未在 project.godot 的 [autoload] 註冊——依專案多人協作紀律，
## 由 Integrator 手動加入一行：LevelManager="*res://scripts/level_manager.gd"
extends Node

const VICTORY_SCREEN_PATH := "res://scenes/ui/victory_screen.tscn"

## 序章＋4關＋終章共6個場景。這些檔案目前尚未全數建立（Task 4.1a/4.1/4.2/4.4
## 陸續補齊），本清單只是路徑索引，不要求對應.tscn已存在才能完成本Task。
var levels: Array = [
	"res://scenes/levels/level_00_prologue.tscn",
	"res://scenes/levels/level_01_water.tscn",
	"res://scenes/levels/level_02_fire.tscn",
	"res://scenes/levels/level_03_wood.tscn",
	"res://scenes/levels/level_04_earth.tscn",
	"res://scenes/levels/level_05_final_altar.tscn",
]
var current_level_index: int = 0


## 依索引切換到指定關卡。index 超出 levels 範圍（或 levels 為空）時記錄錯誤、
## 保持 current_level_index 不變、不嘗試切換場景，避免崩潰。
func load_level(index: int) -> void:
	if levels.is_empty():
		push_error("LevelManager: levels 清單為空，無法載入索引 %d" % index)
		return
	if index < 0 or index >= levels.size():
		push_error("LevelManager: 索引 %d 超出 levels 範圍（共 %d 關）" % [index, levels.size()])
		return

	current_level_index = index
	_change_scene(levels[index])


## 前往下一關；若已在 levels 最後一關，退回 victory_screen（真結局分支流程
## 由未來的專用controller接管，見檔案頭註解，本腳本不寫死終章特殊邏輯）。
func next_level() -> void:
	if levels.is_empty():
		push_error("LevelManager: levels 清單為空，無法前往下一關")
		return

	if current_level_index + 1 < levels.size():
		load_level(current_level_index + 1)
	else:
		_change_scene(VICTORY_SCREEN_PATH)


## 供其他系統（例如Task 6.3存檔持久化）查詢目前關卡路徑。
## current_level_index 越界或 levels 為空時回傳空字串，不崩潰。
func get_current_level_path() -> String:
	if current_level_index < 0 or current_level_index >= levels.size():
		return ""
	return levels[current_level_index]


## 重置為序章，供存檔系統未來「新遊戲」功能呼叫。
func reset_to_prologue() -> void:
	if levels.is_empty():
		push_error("LevelManager: levels 清單為空，無法重置到序章")
		return
	load_level(0)


## 實際切換場景。場景檔案目前尚未全數建立，先以 ResourceLoader.exists()
## 擋掉不存在的路徑，避免 change_scene_to_file 在場景檔缺席或非場景樹環境
## （例如單元測試）下噴錯甚至讓遊戲崩潰。
func _change_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("LevelManager: 場景檔案不存在：%s" % path)
		return

	var tree := get_tree()
	if tree == null:
		push_error("LevelManager: 目前不在場景樹中，無法切換場景：%s" % path)
		return

	tree.change_scene_to_file(path)
