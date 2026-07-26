## 五行相剋倍率（autoload 名稱：ElementSystem，Task 2.1）
##
## 相剋環：水剋火、火剋金、金剋木、木剋土、土剋水。
##
## ⚠️ 倍率 1.5 / 0.6 是**待playtest調校的初始值**，不是定案。
## 這兩個數字直接決定「換對武器」的收益大小：太接近1.0玩家不會想切武器，
## 相剋機制形同虛設；差距太大則變成不換武器就打不動，切武器從策略變成雜務。
## 調整時改 res://data/elements.json 即可，不需要動這支腳本。
## 見 GDD.md 第4節與實施計劃 Task 8.1 playtest 驗證。
extends Node

const DATA_PATH := "res://data/elements.json"
const NEUTRAL := "neutral"

## 所有非中性的屬性
const ELEMENTS: Array[String] = ["water", "fire", "metal", "wood", "earth"]

var relations: Dictionary = {}
var advantage_mult: float = 1.5
var disadvantage_mult: float = 0.6


func _ready() -> void:
	load_data()


func load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("ElementSystem: 無法開啟 %s（錯誤碼 %d）" % [DATA_PATH, FileAccess.get_open_error()])
		return

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ElementSystem: %s 解析失敗" % DATA_PATH)
		return

	relations = parsed.get("relations", {})
	advantage_mult = float(parsed.get("advantage_multiplier", 1.5))
	disadvantage_mult = float(parsed.get("disadvantage_multiplier", 0.6))


## 攻擊方屬性對防守方屬性的傷害倍率。
## 中性、同屬、或查不到的屬性一律回傳 1.0。
func get_multiplier(attacker: String, defender: String) -> float:
	if attacker == NEUTRAL or defender == NEUTRAL:
		return 1.0
	if not relations.has(attacker):
		return 1.0

	var relation: Dictionary = relations[attacker]
	if relation.get("beats", "") == defender:
		return advantage_mult
	if relation.get("loses_to", "") == defender:
		return disadvantage_mult
	return 1.0


## attacker 是否剋 defender
func has_advantage(attacker: String, defender: String) -> bool:
	if not relations.has(attacker):
		return false
	return relations[attacker].get("beats", "") == defender


## 此屬性剋誰；查無回傳空字串
func get_countered_by(element: String) -> String:
	if not relations.has(element):
		return ""
	return relations[element].get("beats", "")


## 誰剋此屬性（供UI提示「換這個屬性的武器」）；查無回傳空字串
func get_counter_to(element: String) -> String:
	for attacker: String in relations:
		if relations[attacker].get("beats", "") == element:
			return attacker
	return ""
