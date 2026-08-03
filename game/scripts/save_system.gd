## 存檔系統（autoload 名稱：SaveSystem，Task 4.0b）
##
## 這是階段四/五/六共用的唯一存檔真相源：
## - checkpoint（座標＋節點路徑）：Task 4.1由 checkpoint.gd 呼叫 set_checkpoint()
## - has_ever_hoarded（隱藏真結局判定旗標）：Task 5.4由 Boss「仁」的「賜俸」／Phase 2.1
##   選擇呼叫 mark_hoarded()；一旦寫入true即永久鎖死，不會被之後的 set_checkpoint() 覆蓋回false
## - current_level_index／unlocked_weapons：Task 6.3擴充，本Task先只留欄位形狀一致的擴充點
##
## ⚠️ 全域唯一規則：所有「貪／爭／接住」分支只呼叫 mark_hoarded()，不建立第二個
## GameState autoload，也不在別處直接寫 has_ever_hoarded。階段五 Task 5.3b 會在Boss
## 開工前複驗這份契約。
extends Node

const SAVE_PATH := "user://savegame.json"

## 隱藏真結局「命」判定旗標：見 docs/PROTAGONIST-令.md 第5-6節。
## 一旦在「賜俸」選貪/爭，或 Boss 戰 Phase 2.1「命」中途顯現選「接住」，
## 永久標記為 true，隱藏真結局資格自此鎖死。本欄位是記憶體快取，
## 但必須隨 save_game() 一併寫入存檔，避免中途離線後重開遺失判定。
var has_ever_hoarded: bool = false

## checkpoint：{"path": String, "x": float, "y": float}；未存檔過則為空字典
var checkpoint: Dictionary = {}


func _ready() -> void:
	# autoload啟動時先同步舊存檔，避免首次checkpoint以預設false覆蓋歷史true。
	load_game()


## 讀取磁碟上的原始存檔資料，不觸碰目前記憶體欄位。
## 檔案不存在、空白或格式錯誤時一律安全回退為空字典，不丟例外、不中斷遊戲。
func _read_save_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveSystem: 無法開啟 %s（錯誤碼 %d），視為無存檔" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}

	var text := f.get_as_text()
	f.close()

	if text.strip_edges().is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: %s 內容非合法JSON物件，視為無存檔" % SAVE_PATH)
		return {}

	return parsed as Dictionary


## 從磁碟載入存檔並同步到記憶體欄位（has_ever_hoarded / checkpoint）。
## 回傳原始資料字典，供 Task 6.3 擴充讀取 current_level_index / unlocked_weapons 等欄位。
func load_game() -> Dictionary:
	var data := _read_save_data()
	has_ever_hoarded = bool(data.get("has_ever_hoarded", false))
	checkpoint = data.get("checkpoint", {}) as Dictionary
	return data


## 把目前記憶體欄位（has_ever_hoarded / checkpoint）疊加進傳入的 data 後寫入磁碟。
## 用 duplicate(true) 是因為呼叫端常常是 _read_save_data() 剛讀出來的字典，
## 直接原地修改容易和呼叫端後續邏輯打架；快照後再寫，語意更清楚。
func save_game(data: Dictionary) -> void:
	var snapshot := data.duplicate(true)
	snapshot["has_ever_hoarded"] = has_ever_hoarded
	snapshot["checkpoint"] = checkpoint

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: 無法寫入 %s（錯誤碼 %d）" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(snapshot))
	f.close()


## Task 4.1由 checkpoint.gd 直接呼叫。不依賴尚未建立的 LevelManager，
## 只保存本階段已知的節點路徑與座標；level索引由Task 6.3擴充時再疊加。
func set_checkpoint(node_path: NodePath, pos: Vector2) -> void:
	var data := _read_save_data()
	checkpoint = {"path": str(node_path), "x": pos.x, "y": pos.y}
	save_game(data)


## 供Boss「仁」的「賜俸」貪/爭分支與Phase 2.1「命」選「接住」呼叫。
## 先讀舊資料、不改動目前記憶體旗標，設true後才寫回——避免用
## save_game(load_game()) 這種寫法在讀取失敗時把記憶體的true意外沖掉。
func mark_hoarded() -> void:
	var data := _read_save_data()
	has_ever_hoarded = true
	save_game(data)
