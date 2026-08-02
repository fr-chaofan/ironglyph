# 《合金文字機甲》IRONGLYPH — 實施計劃

> ⚠️ 語言規範：本專案所有文字內容一律使用繁體中文，詳見 `docs/GDD.md` 第0節。

> **For Hermes:** 用 subagent-driven-development 配合本計劃逐任務執行；遊戲開發驗證方式為"在Godot編輯器/匯出build中執行並目視確認"，而非pytest單元測試（除純邏輯模組如傷害計算外）。

**Goal:** 用 Godot 4 + GodotSteam，做出一個完整可玩、可提交Steam稽核的橫版闖關遊戲：主角/敵人為渲染漢字，武器基於部首拆解，五行相剋為核心平衡機制，並完整實作主線劇情（序章教程→水域/火山/森林/礦山四關→終章終極Boss「仁」，含隱藏真結局「命」）。主線劇情細節見 `docs/STORY.md`、`docs/PROTAGONIST-令.md`、`docs/BOSS-仁.md`。

**Architecture:** 場景樹驅動的2D平臺/射擊架構。`Player`/`Enemy`共用基類`Character.gd`（繼承`CharacterBody2D`），漢字透過`Label`節點+自定義字型渲染而非Sprite2D精靈。武器/五行資料全部外接為`.tres`資源(Resource)或JSON，方便後續批次擴充而不改程式碼。關卡用Godot自帶`TileMap`+手擺場景。傷害計算走純函式（無節點依賴），可單元測試。

**Tech Stack:** **Godot 4.5.2-stable** (GDScript), GodotSteam GDExtension 4.20.1 (Steamworks 1.64), GUT 9.5.0, Make Me a Hanzi資料集(JSON), Noto Sans TC字型, Kenney.nl/OpenGameArt素材, Sonniss/freesound音效。

> **版本鎖定：** 三者版本互相綁定，不可各自升級——GodotSteam GDExtension需Godot 4.4+，GUT則是每個Godot minor版本對應一個特定版本（4.5.x → 9.5.0）。升級Godot時必須同步確認另兩者的對應版本。詳見`docs/SETUP-WINDOWS.md`。

**專案路徑：**
- 整合者機器（Windows + WSL2）：`C:\dev\ironglyph\game\` = `/mnt/c/dev/ironglyph/game/`
- 其他Logic Worker機器：各自clone路徑下的`ironglyph/game/`

---

## 階段一：專案骨架 + 核心移動 + 漢字渲染 + 鏡頭

> **✅ 階段一全部完成。** 執行順序與原文編號不同——原文把 Task 1.3b（Input Map）排在 1.3 之後，
> 但 1.3b 自己標註為「阻斷性前置依賴」，且 1.3 的程式碼直接呼叫 `move_left`/`jump`/`fire` 這些
> action。同理 1.6（碰撞層）必須在 `player.tscn` 設 `collision_layer` 之前完成。
>
> **實際執行順序：1.3b → 1.6 → 1.4 → 1.3 → 1.5**
>
> 額外產出（原計劃沒有、但 Task 1.3 的 Verify「F5執行場景」需要）：
> `game/scenes/test_room.tscn` —— 含地面、平台與 Player 實例的手動驗證場景，
> 已設為 `run/main_scene`。階段四正式關卡上線後可刪除。
>
> 測試：`test_character.gd` + `test_player.gd`，共28項測試106個assert全過。

### Task 1.1: 初始化Godot專案結構

**Objective:** 建立標準目錄結構和project.godot配置

**Files:**
- Create: `game/project.godot`
- Create: `game/scenes/` `game/scripts/` `game/data/` `game/assets/fonts/` `game/assets/sfx/` `game/assets/art/`

> **✅ 此Task已完成**（PR #2，於整合者機器實機執行）。以下步驟已按實際執行情況修正，供其他機器重建或日後參考。

**Step 1:** 建立目錄結構並**手動撰寫**`project.godot`：

> ⚠️ **不能用命令列生成`project.godot`。** 原本寫的 `godot4 --headless --path . --editor --quit` 無效——該指令要求`project.godot`**已經存在**才能開啟專案，在空目錄執行只會印出版本號後結束，不會產生任何檔案。Godot沒有提供「從無到有建立專案」的CLI，只能由Project Manager的GUI或手寫設定檔。

```bash
mkdir -p game/scenes game/scripts game/data game/tests game/assets/{fonts,sfx,art,music}
```

然後手動建立`game/project.godot`（完整內容見已合併的PR #2）：
```ini
config_version=5

[application]
config/name="IRONGLYPH"
run/main_scene=""
config/features=PackedStringArray("4.5", "Forward Plus")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[physics]
2d/default_gravity=980.0

[rendering]
renderer/rendering_method="forward_plus"
```

**Step 2:** 讓Godot匯入專案、產生`.godot/`快取與`.uid`檔：
```bash
godot4 --headless --path game --import
```

**Verify:**

> ⚠️ **`--check-only`不能單獨使用。** 原本寫的 `godot4 --headless --path . --check-only` 會報 `Couldn't detect whether to run the editor, the project manager or a specific project. Aborting.`——`--check-only`是「只做語法檢查不執行」的修飾旗標，必須搭配`-s <腳本>`或`--script`使用。

改用一支探測腳本確認設定確實被讀進來（跑完即可刪除）：
```bash
cat > game/probe.gd <<'GDEOF'
extends SceneTree
func _init() -> void:
	print("renderer: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("viewport: ", ProjectSettings.get_setting("display/window/size/viewport_width"))
	print("gravity: ", ProjectSettings.get_setting("physics/2d/default_gravity"))
	quit()
GDEOF
godot4 --headless --path game -s probe.gd
rm game/probe.gd game/probe.gd.uid
```
應輸出 `forward_plus` / `1280` / `980.0`，且`--import`過程無ERROR。

---

### Task 1.2: 下載並接入 Make Me a Hanzi 資料集 + 建立 HanziData 單例

**Objective:** 拿到"字→部首→筆畫路徑"資料，供後續所有漢字渲染/拆解使用。**注意：Make Me a Hanzi實際是兩個檔案**——`dictionary.txt`（含character/decomposition/pinyin/radical等欄位）和`graphics.txt`（含strokes筆畫SVG路徑、medians中軸點），兩者需分別抓取再合併，欄位不要混淆。

> **✅ 此Task與Task 1.2b已完成**（於整合者機器實機執行）。實際實作與下方原始草稿有兩點差異：
>
> 1. **抽成可重跑的腳本** `tools/build_hanzi_data.py`，而非一次性貼上的程式碼片段。Task 1.2b的覆蓋率檢查已內建在同一支腳本裡（不需另外跑一遍），且會快取下載的30MB資料檔。日後字表變動只要改腳本裡的`NEEDED_CHARS`再重跑。
> 2. **多存了`radical`與`medians`兩個欄位**。`radical`供部首武器機制直接查詢；`medians`（筆畫中軸點）供Task 3.4崩解特效決定碎片飛散方向，比只有SVG path好用。
>
> **覆蓋率結果：23/23全部覆蓋。** 但初次執行時原字表中的「燄」查無——它是「焰」的異體字，資料集只收「焰」。依專案決策不做近似字替換，已將「燄」從字表移除，並補上同為火屬性、資料集有收錄的「焚」以維持每屬性4隻敵人的對稱。「焚」拆解為`⿱林火`，其中「林」本身也是木屬性敵字，部首武器機制因此多一個跨屬性互動。下方字表與Task 5.1敵人表均已同步更新。
>
> 驗證：`game/tests/test_hanzi_data.gd`（GUT，9項測試69個assert全過），含一項掃描全部字檢查拆解式不含自我循環定義。

**Files:**
- Create: `game/data/hanzi_decomposition.json`（合併後的精簡JSON）
- Create: `game/scripts/hanzi_data.gd` (autoload單例，命名為`HanziData`)
- Create: `tools/build_hanzi_data.py`（產生上述JSON的腳本，含覆蓋率檢查）
- Create: `game/tests/test_hanzi_data.gd`（GUT測試）

**Step 1:** 抓取兩個資料檔並合併：
```python
# 在agent環境執行，非Godot內
import urllib.request, json

urllib.request.urlretrieve(
    "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt",
    "/tmp/mmh_dictionary.txt")
urllib.request.urlretrieve(
    "https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt",
    "/tmp/mmh_graphics.txt")

# dictionary.txt: 每行一個JSON物件，含 character/decomposition/radical/pinyin
# graphics.txt: 每行一個JSON物件，含 character/strokes(SVG path陣列)/medians

needed_chars = set("我淼焱森河海湖雨焰炎灶焚鋼針劍錘樹藤林巖石山塵")  # 從Task 2.1/3.1/5.1字表彙總

dict_data = {}
with open("/tmp/mmh_dictionary.txt", encoding="utf-8") as f:
    for line in f:
        d = json.loads(line)
        if d["character"] in needed_chars:
            dict_data[d["character"]] = {"decomposition": d.get("decomposition", "")}

graphics_data = {}
with open("/tmp/mmh_graphics.txt", encoding="utf-8") as f:
    for line in f:
        g = json.loads(line)
        if g["character"] in needed_chars:
            graphics_data[g["character"]] = {"strokes": g.get("strokes", [])}

merged = {}
for ch in needed_chars:
    merged[ch] = {
        "decomposition": dict_data.get(ch, {}).get("decomposition", ""),
        "strokes": graphics_data.get(ch, {}).get("strokes", [])
    }

with open("game/data/hanzi_decomposition.json", "w", encoding="utf-8") as f:
    json.dump(merged, f, ensure_ascii=False, indent=2)
```

**Step 2:** 結構範例（`decomposition`是拆解字串，採用IDS漢字描述字元標準如"⿰氵可"表示左右結構；`strokes`是SVG path字串陣列）：
```json
{
  "河": {"decomposition": "⿰氵可", "strokes": ["M67,89 ... Z", "..."]},
  "淼": {"decomposition": "...", "strokes": ["...", "...", "..."]}
}
```

**⚠️ 注意：** 上方"淼"的`decomposition`具體值刻意留空/省略——"淼"是三個"水"疊加的複合結構，正確的IDS拆解字串需要從資料集實際查詢取得，不應該由人工/AI憑印象編造（容易寫出邏輯錯誤的自我循環定義，例如誤寫成含有"淼"自身的拆解式）。所有敵字/Boss字的真實`decomposition`與`strokes`值，一律以Task 1.2 Step 1實際抓取、合併後的`hanzi_decomposition.json`為準，不要手動編輯或臆測。

**Step 3:** 建立`HanziData`單例（供Task 3.4筆畫崩解特效等後續所有Task呼叫）：
```gdscript
# game/scripts/hanzi_data.gd (autoload singleton "HanziData")
extends Node

var data: Dictionary = {}

func _ready() -> void:
    var f = FileAccess.open("res://data/hanzi_decomposition.json", FileAccess.READ)
    if f:
        data = JSON.parse_string(f.get_as_text())

func get_strokes(character: String) -> Array:
    if data.has(character):
        return data[character].get("strokes", [])
    return []

func get_decomposition(character: String) -> String:
    if data.has(character):
        return data[character].get("decomposition", "")
    return ""
```

**Step 4:** 在`project.godot`的`[autoload]`小節註冊：
```ini
[autoload]
HanziData="*res://scripts/hanzi_data.gd"
```
**⚠️ 注意：此階段（階段一）只有`hanzi_data.gd`已經建立，因此`[autoload]`只註冊`HanziData`一項。** `ElementSystem`（階段二Task 2.1建立）、`SaveSystem`（階段四Task 4.0b建立）、`LevelManager`（階段四Task 4.3建立）**都不要在這裡提前寫入**——把尚未建立的腳本路徑寫進`[autoload]`會導致Godot啟動時找不到檔案而報錯，使階段一的`--check-only`驗證直接失敗。正確做法是：每個模組完成對應腳本後，由整合者在`[autoload]`小節**追加**一行（Task 2.1完成後追加`ElementSystem`；Task 4.0b完成後追加`SaveSystem`；Task 4.3完成後追加`LevelManager`）。每次只新增一行，不要整段覆寫，避免蓋掉其他人已註冊的autoload。

**Verify:** `python3 -c "import json; d=json.load(open('game/data/hanzi_decomposition.json')); print(len(d))"` 輸出條目數 > 0；Godot內執行`print(HanziData.get_strokes("淼"))`能列印出非空陣列

**⚠️ 風險提示：** 若`needed_chars`中有字在Make Me a Hanzi資料集找不到（生僻Boss字常見問題），`merged[ch]`會得到空陣列——必須在這一步就跑一次覆蓋率檢查（見下方Task 1.2b），而不是等到階段三/五用到時才發現。

---

### Task 1.2b: 資料集覆蓋率驗證（阻斷性檢查，必須在階段一完成）

**Objective:** 確認所有計劃使用的敵字/Boss字都能在Make Me a Hanzi資料集中查到，且字形為繁體

**Step 1:**
```python
import json

needed_chars = "我淼焱森河海湖雨焰炎灶焚鋼針劍錘樹藤林巖石山塵"
found = set()
with open("/tmp/mmh_dictionary.txt", encoding="utf-8") as f:
    for line in f:
        d = json.loads(line)
        if d["character"] in needed_chars:
            found.add(d["character"])

missing = set(needed_chars) - found
print("缺失字:", missing if missing else "無，全部覆蓋")
```

**Verify:** `missing`集合為空。若有缺失字，需要為缺失字手動準備筆畫資料（可用Godot內建`Font.get_glyph_contours()` API即時取字形輪廓做替代方案），或替換為資料集有收錄的近似字

---

### Task 1.3: Character基類 + Player移動/跳躍/開火骨架

**Objective:** 橫版角色控制器，支援左右移動、跳躍、開火輸入

> **✅ 已完成。** 實作與下方草稿的三點差異，都是為了讓階段一能獨立跑通、不必等階段二：
>
> 1. **`ElementSystem` 尚未存在。** 草稿的 `take_damage()` 直接呼叫 `ElementSystem.get_multiplier()`，
>    但該單例要到階段二 Task 2.1 才建立，照抄會在第一次受擊時就崩潰。改成
>    `get_element_multiplier()`，用 `get_node_or_null("/root/ElementSystem")` 探測：
>    找不到就回傳中性倍率 1.0。Task 2.1 註冊單例後會自動改走真正的相剋表，**不需要回頭改這裡**。
> 2. **`WeaponManager` 尚未存在。** 同理，`_try_fire()` 會先確認節點存在且有 `fire` 方法，
>    階段一按開火鍵靜默略過。
> 3. **重力改讀 `ProjectSettings`** 而非草稿的 `const GRAVITY = 980.0`。寫死的話日後調整
>    `physics/2d/default_gravity` 角色不會跟著變，兩邊會不同步。
>
> 另補了 `hp_changed` / `died` 兩個訊號（HUD與敵人死亡結算都會用到），並在 `take_damage()`
> 開頭加上 `if hp <= 0: return` —— 否則同一幀多發子彈打中將死目標時 `die()` 會跑很多次。

**Files:**
- Create: `game/scripts/character.gd`
- Create: `game/scripts/player.gd`
- Create: `game/scenes/player.tscn`
- Create: `game/scenes/test_room.tscn`（Verify用的手動測試場景）
- Create: `game/tests/test_character.gd` `game/tests/test_player.gd`（GUT）

**Step 1:** 基類：
```gdscript
# game/scripts/character.gd
class_name Character
extends CharacterBody2D

@export var speed: float = 220.0
@export var jump_velocity: float = -420.0
@export var max_hp: int = 100
@export var element: String = "neutral"  # water/fire/metal/wood/earth/neutral

var hp: int
const GRAVITY = 980.0

func _ready() -> void:
    hp = max_hp

func apply_gravity(delta: float) -> void:
    if not is_on_floor():
        velocity.y += GRAVITY * delta

func take_damage(amount: int, attacker_element: String) -> void:
    var multiplier = ElementSystem.get_multiplier(attacker_element, element)
    hp -= int(amount * multiplier)
    if hp <= 0:
        die()

func die() -> void:
    queue_free()
```

**Step 2:** Player控制：

**⚠️ 設計修正：漢字不可水平鏡像翻轉** —— 像素精靈常用`scale.x = sign(dir)`來翻轉朝向，但漢字鏡像後字形會變成無法辨識的反字（例如"我"字左右鏡像後不是"我"）。改用獨立的朝向指示器（腳下箭頭/三角形圖示），漢字本體永遠正向顯示：

```gdscript
# game/scripts/player.gd
extends Character

@onready var hanzi_label: Label = $HanziLabel
@onready var weapon_manager: Node = $WeaponManager
@onready var direction_indicator: Node2D = $DirectionIndicator  # 朝向指示器，非文字本體

var facing_dir: float = 1.0

func _physics_process(delta: float) -> void:
    apply_gravity(delta)

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

    var dir := Input.get_axis("move_left", "move_right")
    velocity.x = dir * speed
    if dir != 0:
        facing_dir = sign(dir)
        direction_indicator.scale.x = facing_dir  # 只翻轉指示器，不翻轉漢字本體

    if Input.is_action_pressed("fire"):
        weapon_manager.fire(facing_dir)

    move_and_slide()
```

**Step 3:** 場景`player.tscn`節點結構：
```
Player (CharacterBody2D, script=player.gd)
├── CollisionShape2D
├── HanziLabel (Label, text="我", font=NotoSansTC, font_size=64)  # 永不翻轉
├── DirectionIndicator (Node2D/Sprite2D，簡單箭頭或三角形，可翻轉)
├── WeaponManager (Node, script=weapon_manager.gd — 階段二建立)
└── Camera2D
```

**Verify:** F5執行場景，方向鍵移動、空格跳躍，"我"字本體不變形，僅腳下/身側指示器隨方向翻轉

---

### Task 1.3b: Input Map 設定（阻斷性前置依賴）

**Objective:** 定義所有Input Action，Task 1.3起大量程式碼依賴這些action名稱，必須提前建立

> **✅ 已完成，且已提前到 Task 1.3 之前執行**（本Task自己標註為阻斷性前置依賴，卻被排在依賴它的1.3後面）。
>
> ⚠️ **下方的 `Object(InputEventKey,"physical_keycode":65)` 簡寫無法被 Godot 解析**，
> 專案啟動時該action會靜默變成沒有綁定任何按鍵。`project.godot` 裡的 `Object(...)`
> 必須列出 InputEventKey 的完整屬性（`device`/`alt_pressed`/`keycode`/`key_label`/
> `unicode`/`location`/`echo`/`script` 等），實際格式見已合併的 `game/project.godot`。
> 最省事的做法還是在編輯器 Project Settings → Input Map 面板點一點，讓Godot自己寫。
>
> 用 `physical_keycode` 而非 `keycode` 是刻意的：非QWERTY版面（Dvorak/AZERTY）的玩家
> 按下的仍是同一個實體位置的鍵。

**Files:**
- Modify: `game/project.godot`（`[input]`小節）

**Step 1:**
```ini
[input]
move_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":65)]
}
move_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":68)]
}
jump={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":32)]
}
fire={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":74)]
}
weapon_next={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":69)]
}
weapon_prev={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":81)]
}
pause={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":4194305)]
}
```
（鍵位：A/D移動，Space跳躍，J開火，Q/E切換武器，Esc暫停；也可以直接在Godot編輯器Project Settings > Input Map面板裡手動新增，等效於編輯這段設定）

**Verify:** Godot編輯器 Project Settings > Input Map 面板能看到全部7個action且各綁定一個按鍵

---

### Task 1.4: 字型渲染系統封裝

**Objective:** 統一的"用漢字生成角色視覺"元件，供Player和所有Enemy複用

> **✅ 已完成。**

**Files:**
- Create: `game/scripts/hanzi_sprite.gd`
- Create: `game/assets/fonts/NotoSansTC-Bold.otf`（下載思源黑體繁體版）

**Step 1:** 下載字型。

> ⚠️ **原草稿的URL會404**，兩處都錯：`Sans/OTF/TraditionalChinese/` 底下的檔名是
> `NotoSansCJKtc-Bold.otf`（不是 `NotoSansTC-Bold.otf`），且那是17MB的全CJK字型。
>
> 改用 **`Sans/SubsetOTF/TC/NotoSansTC-Bold.otf`（5.6MB）**——繁中子集版，涵蓋本專案
> 全部用字與UI文字綽綽有餘，入版控與匯出build都省下11MB。

```bash
curl -sL -o game/assets/fonts/NotoSansTC-Bold.otf \
  https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/TC/NotoSansTC-Bold.otf
```

**Step 2:** 封裝元件（描邊發光、受擊抖動）：
```gdscript
# game/scripts/hanzi_sprite.gd
extends Label
class_name HanziSprite

@export var character_text: String = "字":
    set(v):
        character_text = v
        text = v

func flash_hit() -> void:
    var tween = create_tween()
    tween.tween_property(self, "modulate", Color(1,0.3,0.3), 0.05)
    tween.tween_property(self, "modulate", Color(1,1,1), 0.1)

func shatter_and_die() -> void:
    # 階段三詳細實現：按筆畫拆分成多個Label碎片飛散
    queue_free()
```

**Verify:** 場景內替換`character_text`，字形跟隨變化，受擊時短暫變紅

---

### Task 1.5: 橫版鏡頭跟隨

**Objective:** Camera2D平滑跟隨玩家，限制在關卡邊界內

> **✅ 已完成。** 額外加了 `has_bounds` 旗標與 `clear_level_bounds()`：未套用邊界前 Godot 的
> `limit_*` 是預設的正負一億（等同不限制），有旗標才能區分「還沒設定」與「設定成很大的範圍」，
> 階段四 LevelManager 載入關卡時會用到。

**Files:**
- Modify: `game/scenes/player.tscn`（Camera2D子節點配置）
- Create: `game/scripts/camera_bounds.gd`

**Step 1:**
```gdscript
# game/scripts/camera_bounds.gd
extends Camera2D

func set_level_bounds(rect: Rect2) -> void:
    limit_left = int(rect.position.x)
    limit_right = int(rect.position.x + rect.size.x)
    limit_top = int(rect.position.y)
    limit_bottom = int(rect.position.y + rect.size.y)

func _ready() -> void:
    position_smoothing_enabled = true
    position_smoothing_speed = 8.0
```

**Verify:** 玩家移動到關卡邊緣時鏡頭停止跟隨，不露出關卡外空白

---

### Task 1.6: 基礎碰撞層設定

**Objective:** 定義Player/Enemy/Bullet/Ground的物理層，避免後續碰撞漏判

> **✅ 已完成，且已提前到 Task 1.3 之前執行**（`player.tscn` 要設 `collision_layer` 就得先有層定義）。
>
> 注意層號與位元值的換算：`layer_1` 是 bit 0，位元值 **1**；`layer_2` = 2、`layer_3` = 4、
> `layer_4` = 8、`layer_5` = 16。Player 設 `collision_layer = 2`（player）、
> `collision_mask = 5`（ground 1 + enemy 4），刻意不含 `player_bullet`(8)，否則自己的子彈會打到自己。
> 這條已寫成測試 `test_碰撞層為player且不與自己的子彈碰撞`。

**Files:**
- Modify: `game/project.godot`（Layer Names配置）

**Step 1:**
```ini
[layer_names]
2d_physics/layer_1="ground"
2d_physics/layer_2="player"
2d_physics/layer_3="enemy"
2d_physics/layer_4="player_bullet"
2d_physics/layer_5="enemy_bullet"
```

**Verify:** Player碰撞層設為layer_2，只與layer_1/layer_3碰撞，檢查Inspector面板配置正確

**階段一完成後提交（milestone commit）：**
```bash
cd game && git init && git add -A && git commit -m "phase1: project skeleton, hanzi rendering, player movement, camera"
```

---

## 階段二：部首武器系統 + 五行相剋

> **✅ 原定階段二內容已完成**（Task 2.1/2.2/2.3/2.4）。測試累計66項311個assert全過。
>
> **✅ Task 2.5 是後續新增的顯示強化，現已完成實作。** 新增11項測試；
> 全套測試目前為93項、512個assert全過。
> Task 2.6現已完成最小範圍設計：主角音核「令」與敵人掉落部件形成單槽
> `CORE/FUSED/HELD`循環。它仍屬階段二功能擴充，但依賴階段三的敵人死亡signal，
> 因此實際排在階段三完成、階段四開始前，作為「Phase 3.5 integration gate」。
>
> ⚠️ **Task 2.3 的子彈碰撞訊號接錯了**，照抄會導致「子彈能生成、能飛，但永遠打不到任何人」——
> 詳見該Task下方說明。這正是原文Verify裡自己警告的那個坑，但原文給的解法本身是錯的。

### Task 2.0: 安裝 GUT 測試框架（Task 2.1單元測試的前置依賴）

**Objective:** Task 2.1要用GUT寫純邏輯單元測試，必須先安裝這個外掛，否則`-s addons/gut/gut_cmdln.gd`會找不到檔案

> **✅ 此Task已完成**（PR #2，GUT 9.5.0已入版控並在`[editor_plugins]`啟用）。clone repo後不需重跑Step 1/2，直接跳到Task 2.1寫測試即可。以下步驟保留供版本升級時參考。
>
> 已驗證：`godot4 --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` 能正常啟動GUT並回報 "Nothing was run"（`tests/`目前為空）。

**Files:**
- Create: `game/addons/gut/`

**Step 1:** 下載GUT外掛。

> **版本必須對應Godot版本。** 本專案用Godot 4.5.2，對應 **GUT 9.5.0**。不要用AssetLib安裝（目前上架的是對應Godot 4.6.x的9.6.1），也不要用`releases/latest`（會抓到對應4.7.x的版本）。對應表見 https://github.com/bitwes/Gut 的readme。
>
> 整合者機器上已預先下載一份於 `C:\Tools\gut\addons\gut`，若在該機器操作可直接複製，跳過下載。

```bash
curl -sL -o /tmp/gut.zip https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip
unzip -q /tmp/gut.zip -d /tmp/gut_extract
mkdir -p game/addons
cp -r /tmp/gut_extract/Gut-9.5.0/addons/gut game/addons/gut
# 驗證版本：應輸出 version="9.5.0"
grep version game/addons/gut/plugin.cfg
```

**Step 2:** 在Godot編輯器 Project Settings > Plugins 面板啟用GUT外掛（或直接在`project.godot`的`[editor_plugins]`小節加入`res://addons/gut/plugin.cfg`）

**Step 3:** 建立測試目錄：
```bash
mkdir -p game/tests
```

**Verify:** `godot4 --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` 執行後回報"0 tests"而非"檔案不存在"錯誤（此時tests目錄還是空的，先確認命令本身能跑通）

---

### Task 2.1: 五行相剋資料表 + 純邏輯單元測試

**Objective:** 建立`ElementSystem` autoload單例，五行剋制倍率計算可獨立測試

> **✅ 已完成。**
>
> ⚠️ **倍率 1.5 / 0.6 是待playtest調校的初始值，不是定案。** 這兩個數字直接決定「換對武器」的
> 收益大小：太接近1.0，玩家不會想切武器，相剋機制形同虛設；差距太大則變成不換武器就打不動，
> 切武器從策略變成雜務。調整時只改 `res://data/elements.json`，不需要動腳本。見 Task 8.1 playtest。
>
> 額外加了 `has_advantage()` / `get_counter_to()`——後者供HUD提示玩家「該換哪個屬性的武器」。
>
> 測試除了原文的三項，另加：相剋環完整性（每個屬性恰好剋一個、恰好被一個剋，形成單一循環而非
> 分岔或自剋）、以及 `beats` 與 `loses_to` 的互相一致性——`loses_to` 是可從 `beats` 推導的冗餘
> 資料，兩邊寫不一致會產生「A剋B、但B也剋A」的矛盾。

**Files:**
- Create: `game/scripts/element_system.gd` (autoload)
- Create: `game/data/elements.json`

**Step 1:** 資料表：
```json
{
  "relations": {
    "water": {"beats": "fire", "loses_to": "earth"},
    "fire": {"beats": "metal", "loses_to": "water"},
    "metal": {"beats": "wood", "loses_to": "fire"},
    "wood": {"beats": "earth", "loses_to": "metal"},
    "earth": {"beats": "water", "loses_to": "wood"}
  },
  "advantage_multiplier": 1.5,
  "disadvantage_multiplier": 0.6
}
```

**Step 2:** 邏輯：
```gdscript
# game/scripts/element_system.gd (autoload singleton "ElementSystem")
extends Node

var relations: Dictionary = {}
var advantage_mult: float = 1.5
var disadvantage_mult: float = 0.6

func _ready() -> void:
    var f = FileAccess.open("res://data/elements.json", FileAccess.READ)
    var data = JSON.parse_string(f.get_as_text())
    relations = data["relations"]
    advantage_mult = data["advantage_multiplier"]
    disadvantage_mult = data["disadvantage_multiplier"]

func get_multiplier(attacker: String, defender: String) -> float:
    if attacker == "neutral" or defender == "neutral":
        return 1.0
    if relations.has(attacker) and relations[attacker]["beats"] == defender:
        return advantage_mult
    if relations.has(attacker) and relations[attacker]["loses_to"] == defender:
        return disadvantage_mult
    return 1.0
```

**Step 3：** 在`project.godot`的`[autoload]`小節**追加**一行（不要覆寫Task 1.2已註冊的`HanziData`）：
```ini
[autoload]
HanziData="*res://scripts/hanzi_data.gd"
ElementSystem="*res://scripts/element_system.gd"
```

**Step 4 (test):** 用GUT測試框架（`addons/gut`）寫純邏輯測試：
```gdscript
# game/tests/test_element_system.gd
extends GutTest

func test_water_beats_fire():
    assert_eq(ElementSystem.get_multiplier("water", "fire"), 1.5)

func test_fire_loses_to_water():
    assert_eq(ElementSystem.get_multiplier("fire", "water"), 0.6)

func test_neutral_always_normal():
    assert_eq(ElementSystem.get_multiplier("neutral", "water"), 1.0)
```

**Verify:** `godot4 --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` 全部透過

---

### Task 2.2: 部首武器資料表（10個武器）

**Objective:** 定義資源化的武器資料，非硬編碼

> **✅ 已完成，資料照原文未改。** 測試補了幾項資料完整性檢查：欄位齊全、id不重複、屬性值合法、
> 以及**五行各屬性都有對應武器**——缺任一屬性的武器，玩家就沒辦法剋制對應屬性的敵人。

**Files:**
- Create: `game/data/weapons.json`

**Step 1:**
```json
[
  {"id":"shui","radical":"氵","element":"water","name":"水波彈","damage":8,"fire_rate":0.4,"projectile":"wave","range":"medium"},
  {"id":"huo","radical":"灬","element":"fire","name":"火球","damage":12,"fire_rate":0.6,"projectile":"fireball_aoe","range":"medium"},
  {"id":"jin","radical":"釒","element":"metal","name":"暗器","damage":6,"fire_rate":0.15,"projectile":"blade","range":"long"},
  {"id":"mu","radical":"木","element":"wood","name":"藤蔓刺","damage":10,"fire_rate":0.5,"projectile":"vine","range":"short"},
  {"id":"tu","radical":"土","element":"earth","name":"石撞","damage":15,"fire_rate":0.8,"projectile":"rock","range":"short"},
  {"id":"gong","radical":"弓","element":"neutral","name":"基礎弓箭","damage":7,"fire_rate":0.3,"projectile":"arrow","range":"long"},
  {"id":"dao","radical":"刂","element":"neutral","name":"近戰刀","damage":14,"fire_rate":0.35,"projectile":"melee","range":"melee"},
  {"id":"shou","radical":"扌","element":"neutral","name":"手雷","damage":20,"fire_rate":1.0,"projectile":"grenade_aoe","range":"medium"},
  {"id":"bing","radical":"冫","element":"water","name":"冰錐","damage":9,"fire_rate":0.45,"projectile":"ice_shard","range":"medium"},
  {"id":"shi","radical":"石","element":"earth","name":"碎石彈","damage":11,"fire_rate":0.5,"projectile":"pebble","range":"medium"}
]
```

**Verify:** JSON.parse_string成功載入10條記錄

---

### Task 2.3: WeaponManager + 武器切換

**Objective:** Player持有的武器管理器，Q/E切換武器，讀取weapons.json生成子彈

> **✅ 已完成。** 修正一個會讓整個戰鬥系統失效的錯誤，另補三處。
>
> ### ⚠️ 子彈接錯碰撞訊號（照抄會「打不到人」）
>
> 原文 Step 2 用 `area_entered`、Step 3 也要求連接 `area_entered`：
> ```gdscript
> func _on_area_entered(area: Node) -> void:
>     if area.get_parent() is Character:
> ```
> 但 `Character` 繼承 `CharacterBody2D`（屬於 `PhysicsBody2D`），而 **Area2D 的 `area_entered`
> 只會對其他 Area2D 觸發，對 PhysicsBody2D 永遠不會觸發**。照抄的結果是子彈能生成、能飛、
> 能撞到東西，但傷害永遠不會結算。
>
> 正解是接 **`body_entered`**，並直接判斷 `body is Character`（不需要 `get_parent()`——
> 撞到的就是角色本身，不是它的子節點）。已寫成測試
> `test_子彈用body_entered而非area_entered` 守住。
>
> ### 其他三處補強
>
> | 問題 | 處理 |
> |---|---|
> | **子彈永不消失** | 原文的子彈打空後會一直往畫面外飛且永不釋放，一場戰鬥累積成千上萬個節點。加了 `max_lifetime`（預設3秒）自動釋放，並讓子彈打到地形也消失（否則會穿牆） |
> | **武器清單為空時除以零** | `current_index % weapons.size()` 在載入失敗時會除以零。`cycle_weapon()` 開頭擋掉空清單 |
> | **子彈掛在 Player 底下** | 原文 `get_tree().current_scene.add_child()` 方向正確，但補上 `current_scene` 為 null 時（單元測試環境）退回場景樹根節點。子彈絕不能掛在 Player 底下——會跟著角色移動，且角色死亡 `queue_free` 時會把空中的子彈一起帶走 |
>
> 另加 `muzzle_offset`（子彈生成點前移，避免一出生就卡在自己的碰撞體裡）與 `weapon_changed` 訊號
> （供HUD更新），以及 `game/scripts/debug_weapon_label.gd` —— 原文Verify要求的「臨時debug label」，
> 已掛在 `test_room.tscn` 左上角，Q/E切換時即時顯示武器名/部首/屬性/傷害。

**Files:**
- Create: `game/scripts/weapon_manager.gd`
- Create: `game/scenes/projectiles/bullet_base.tscn`
- Create: `game/scripts/bullet.gd`

**Step 1:**
```gdscript
# game/scripts/weapon_manager.gd
extends Node

var weapons: Array = []
var current_index: int = 0
var cooldown: float = 0.0

func _ready() -> void:
    var f = FileAccess.open("res://data/weapons.json", FileAccess.READ)
    weapons = JSON.parse_string(f.get_as_text())

func _process(delta: float) -> void:
    cooldown = max(0.0, cooldown - delta)
    if Input.is_action_just_pressed("weapon_next"):
        current_index = (current_index + 1) % weapons.size()
    if Input.is_action_just_pressed("weapon_prev"):
        current_index = (current_index - 1 + weapons.size()) % weapons.size()

func fire(direction: float = 1.0) -> void:
    if cooldown > 0.0:
        return
    var w = weapons[current_index]
    cooldown = w["fire_rate"]
    var bullet_scene = preload("res://scenes/projectiles/bullet_base.tscn")
    var bullet = bullet_scene.instantiate()
    bullet.setup(w["damage"], w["element"], get_parent().global_position, Vector2(direction, 0))
    get_tree().current_scene.add_child(bullet)
```

**（注意：Task 1.3已將`facing_dir`改為獨立變數而非讀取`hanzi_label.scale.x`，`fire()`需要呼叫方傳入方向，對應Player._physics_process()裡的`weapon_manager.fire(facing_dir)`呼叫。`bullet.setup()`的方向參數統一用`Vector2`——玩家子彈只在水平方向上有速度分量`Vector2(direction, 0)`，Boss彈幕（階段五）則用任意角度的`Vector2`，兩者共用同一套`bullet.gd`不需要分叉邏輯）**

**Step 2:**
```gdscript
# game/scripts/bullet.gd
extends Area2D

var damage: int
var element: String
var speed: float = 500.0
var direction: Vector2 = Vector2.RIGHT

func setup(dmg: int, elem: String, spawn_pos: Vector2, dir: Vector2) -> void:
    damage = dmg
    element = elem
    direction = dir.normalized()
    global_position = spawn_pos

func _physics_process(delta: float) -> void:
    position += direction * speed * delta

func _on_area_entered(area: Node) -> void:
    if area.get_parent() is Character:
        area.get_parent().take_damage(damage, element)
    queue_free()
```

**Step 3（容易漏掉的一步）：** 在Godot編輯器裡開啟`bullet_base.tscn`，選中根節點Area2D，在Inspector的Node > Signals分頁裡把`area_entered`訊號連接到`_on_area_entered`函式（或在`_ready()`裡用程式碼連接：`area_entered.connect(_on_area_entered)`）。同時設定該Area2D的Collision Layer為`player_bullet`(layer 4)，Collision Mask勾選`enemy`(layer 3)，確保只偵測到敵人而不會偵測到其他子彈或地形。

**Verify:** 按Q/E切換武器名在UI顯示變化（臨時debug label），按fire鍵生成子彈並飛行、命中測試假人扣血（若沒有連接signal，命中不會有任何反應——這是最容易漏掉導致"子彈能生成但打不到人"的坑）

---

### Task 2.4: 武器手感打磨（後坐力/開火動畫/描邊色）

**Objective:** 每種武器按五行有不同的顏色/粒子反饋，避免武器手感雷同

> **✅ 顏色部分已完成**，`ELEMENT_COLORS` 直接併入 `bullet.gd` 的 `setup()`。
> 已測試五個屬性的顏色互不相同。
>
> **後坐力與開火動畫尚未做**——那需要實際手感調校，屬於整合者在有display的機器上的工作
> （見本文件開頭的協作分工），不適合headless盲調。

**Files:**
- Modify: `game/scripts/bullet.gd`（按element著色）

**Step 1:**
```gdscript
const ELEMENT_COLORS = {
    "water": Color(0.3, 0.6, 1.0),
    "fire": Color(1.0, 0.4, 0.2),
    "metal": Color(0.8, 0.8, 0.9),
    "wood": Color(0.3, 0.8, 0.3),
    "earth": Color(0.6, 0.4, 0.2),
    "neutral": Color(1.0, 1.0, 1.0)
}
# 在setup()中: modulate = ELEMENT_COLORS.get(elem, Color.WHITE)
```

**Verify:** 10種武器子彈顏色區分明顯，肉眼可辨認元素歸屬

---

### Task 2.5: 場景內武器字形顯示（✅ 已完成）

**Objective:** 在玩家身旁以世界座標顯示目前裝備的部首字形；切換武器與改變朝向時即時更新，同時保持漢字可辨識、元素配色一致

> **範圍界線：** 此Task只負責「目前武器是什麼」的場景內視覺回饋。
> 不修改傷害、射速、彈種、掉落或組字配方；部件組合成完整漢字的升級系統保留給Task 2.6。

**Files:**
- Create: `game/scripts/weapon_glyph_display.gd`
- Create: `game/tests/test_weapon_glyph_display.gd`
- Modify: `game/scripts/player.gd`（只轉送既有`facing_dir`）
- Modify: `game/scenes/player.tscn`（僅限整合者）

不修改`weapon_manager.gd`、`weapons.json`、`hanzi_sprite.gd`、`test_room.tscn`、`project.godot`或字型資產。

**Scene結構（整合者）：**
```text
Player
├── HanziSprite
├── DirectionIndicator
├── WeaponManager
└── WeaponGlyphDisplay (Node2D, weapon_glyph_display.gd)
    └── Glyph (Label, NotoSansTC-Bold.otf)
```

`WeaponGlyphDisplay`必須是Player的世界座標子節點，不可放在HUD的`CanvasLayer`內；
也不可掛在會以負`scale.x`翻轉的`DirectionIndicator`底下，否則部首會變成鏡像反字。

**Behaviour contract:**

1. 監聽既有`WeaponManager.weapon_changed(weapon, index)`，不為此新增另一套切換狀態。
   連接signal後還要主動呼叫一次`get_current_weapon()`；無論兩個兄弟節點的`_ready()`先後順序如何，
   初始武器都必須顯示。
2. 顯示文字優先讀取可選的`display_glyph`；欄位不存在或為空時退回既有`radical`。
   目前`weapons.json`不必新增欄位：
   ```gdscript
   var glyph_text := String(weapon.get("display_glyph", ""))
   if glyph_text.is_empty():
       glyph_text = String(weapon.get("radical", ""))
   ```
3. 顏色按`weapon.element`取用既有`Bullet.ELEMENT_COLORS`，確保手持字形、子彈與未來圖鑑使用同一套辨識色。
4. `set_facing(direction)`只把整個`Node2D`移到玩家左側或右側，永遠不可用負`scale.x`鏡像Label。
   `player.gd`只在既有朝向改變分支呼叫此方法；不要新增會漏掉`super()`的Player `_ready()`。
5. Q/E切換時播放短促的淡入＋等比縮放Tween。快速連續切換前必須kill並重設舊Tween，
   避免動畫堆疊後卡在透明、錯色或異常縮放狀態。
6. 使用普通runtime腳本，不加`@tool`；場景可用預設文字提供editor preview。
   Player發出`died`時隱藏顯示，避免目前死亡placeholder只移除HanziSprite後留下懸浮武器。

**Automated Verify:**
- Player場景包含世界座標`WeaponGlyphDisplay`，且Label使用專案繁中字型
- 初始顯示`氵`；切到下一把立即顯示`灬`並套用火屬色
- 10把武器皆能顯示；未提供`display_glyph`時正確fallback到`radical`
- 面向左右時字形位於對應側、文字不變且`scale.x`始終大於0
- 快速連續切換後Tween能收斂到正確文字、顏色與正常縮放
- WeaponManager缺失時不崩潰；Player死亡後字形隱藏

**Manual Verify:** 在`test_room.tscn`移動、跳躍並連按Q/E：
字形跟隨玩家、移到面向側但不鏡像；切換動畫清楚且不遮住「我」；
元素顏色與實際射出的子彈一致，原有左上角debug label仍正常更新。

---

> **整合者補充（合併 PR #11 時）：** 原實作的 `_owner_dead` 旗標一旦設起來就沒有東西會清掉它，
> 玩家死亡後武器字形會**永遠隱藏**。目前遊戲還沒有復活流程，所以摸不到；但階段四 Task 4.1 的
> 存檔點復活會是第一個觸發情境，屆時就是真的bug。已補上 `revive()` 供復活流程呼叫，並加測試守住。
>
> 另註記流程問題：本Task修改了 `player.tscn`，而 `COLLABORATION.md` 第25-26行規定只有整合者能碰
> `.tscn`。改動本身正確且已由整合者驗證合併，但這條界線需要澄清是「完全不碰」還是「可提交、由整合者審」。

---

### Task 2.6: 「令」× 部件合體與手持fallback（Phase 3.5 integration gate）

**Objective:** 把階段二「永久持有十把武器並循環切換」改為敵人掉落驅動的單槽玩法：
主角以音核「令」開始；相容部件融合成完整字並取得專屬能力，不相容部件則在身旁手持，
沿用既有五行武器。此Task依賴階段三已完成的`Enemy.defeated` /
`EnemySpawner.enemy_defeated`，必須在階段四開始製作正式關卡前穩定介面。

> **Vertical-slice範圍：** 首個PR只實作`雨＋令→零`。`釒＋令→鈴`、
> `艹＋令→苓`、`冫＋令→冷`、`王＋令→玲`、`耳＋令→聆`以及其他配方全部deferred。
> 不在本PR製作額外配方、狀態效果、音效、關卡、存檔、圖鑑或Boss掉落。

**Files（預定）：**
- Create: `game/data/components.json`
- Create: `game/data/fusion_recipes.json`
- Create: `game/scripts/fusion_resolver.gd`
- Create: `game/scripts/glyph_loadout.gd`
- Create: `game/scripts/component_pickup.gd`
- Create: `game/scripts/component_dropper.gd`
- Create/Modify: 對應GUT測試、`tools/build_hanzi_data.py`與產生出的漢字資料
- Modify: `game/data/enemies.json`（只新增引用`components.json`的`drop_component_id`）
- Modify: `game/scripts/weapon_manager.gd`
- Modify: `game/scripts/weapon_glyph_display.gd`
- Modify: `game/scripts/player.gd`
- Integrator only: `game/scenes/player.tscn`
- Integrator only: `game/scenes/component_pickup.tscn`
- Integrator only: `game/scenes/test_room.tscn`
- Integrator only: `game/project.godot`

#### 單一狀態來源

`GlyphLoadout`是唯一裝備狀態來源；`WeaponManager`退回「武器資料目錄＋攻擊執行器」角色，
不可再讓`current_index`、`WeaponGlyphDisplay`或其他節點各自保存另一套有效裝備。

| 狀態 | 主角字形 | `WeaponGlyphDisplay` | 攻擊 |
|---|---|---|---|
| `CORE` | 令 | 隱藏 | 中性基礎攻擊 |
| `FUSED` | 配方的`result_glyph` | 隱藏 | 配方的`ability_id` |
| `HELD` | 令 | 顯示部件的`display_glyph` | 部件的`fallback_weapon_id` |

玩家只有一個部件槽：

1. 每筆敵人資料以`drop_component_id`引用`components.json`；`ComponentDropper`監聽既有
   `EnemySpawner.enemy_defeated`後生成**恰好一個**`ComponentPickup`，不修改或重寫
   `Enemy.die()`。
2. 玩家進入拾取範圍後按`E`（`interact`）取得部件。
3. `FusionResolver`以`core_glyph + component_id`查詢人工校對的配方：
   - 查到配方：進入`FUSED`
   - 查無配方：進入`HELD`
4. 已有部件時拾取新部件，舊部件先彈出成世界拾取物；任何時刻只允許一個有效部件。
5. 按`Q`（`eject_component`）彈出目前部件並回到`CORE`。
6. 彈出的拾取物需有短暫防重拾機制，避免同一幀立即被原玩家撿回。

Task 2.5原本的Q/E永久武器循環在此Task後停止作為正式玩法；它的測試與debug提示必須更新為
「E拾取／Q彈出」。`WeaponGlyphDisplay`仍遵守世界座標、元素配色與永不鏡像的既有規則。

#### Curated data contract

配方以穩定的`component_id`為key，不直接用顯示字形當ID。這能處理`釒`資料來源與`金`
fallback顯示之間的正規化，也避免位置變體或字型缺字影響配方判定。

`components.json`以目前敵字可能掉落的部首建立catalog；下方是starter recipe使用的`rain`條目。
其他條目只提供`HELD` fallback，不得在本PR增加第二條融合配方：

```json
[
  {
    "id": "rain",
    "source_radicals": ["雨"],
    "display_glyph": "雨",
    "element": "water",
    "fallback_weapon_id": "shui"
  }
]
```

`fusion_recipes.json`在本PR中只能有一條：

```json
[
  {
    "core_glyph": "令",
    "component_id": "rain",
    "result_glyph": "零",
    "layout": "top_bottom",
    "ability_id": "reset_burst",
    "attack": {
      "id": "reset_burst",
      "radical": "雨",
      "name": "歸零爆發",
      "element": "water",
      "damage": 5,
      "fire_rate": 0.9,
      "projectile": "wave",
      "range": "medium",
      "pattern": "radial",
      "projectile_count": 8
    }
  }
]
```

不可把`core_glyph`與`display_glyph`做字串串接，也不可從Unicode、IDS或讀音自動猜測結果字；
未列入配方表的一律走`HELD`。

#### 「零」的starter ability

`reset_burst`從玩家中心等角發射8發水屬性子彈，沿用既有`Bullet`碰撞、生命週期、五行倍率與
元素顏色。傷害／冷卻可由資料調整，但行為必須與`HELD`狀態的普通水波彈肉眼可區分；
不得為了此能力另外複製一套傷害或碰撞公式。

#### Definition of Done

- 玩家開局字形是「令」，狀態為`CORE`，身旁無部件，並有可用的中性基礎攻擊
- 擊敗「雨」只生成一個`rain`拾取物；按E後主角變成「零」並隱藏外置部件
- 「零」開火產生8方向水屬性環形彈幕，仍使用既有五行傷害與子彈碰撞
- 拾取不相容部件後主角回到「令」，外置顯示該部件，攻擊使用正確的fallback武器
- 按Q或替換部件會彈出舊部件並回到正確狀態，不重複掉落、不立即自動撿回
- `GlyphLoadout`是唯一有效裝備狀態；正式玩法不再能Q/E循環全部十把武器
- 「令」「零」均有Make Me a Hanzi筆畫資料與Noto Sans TC字形；玩家／融合字死亡特效不退化
- 玩家死亡時不留下懸浮部件；新Player實例從`CORE`開始
- 不修改任何Phase 4正式關卡、checkpoint/save、圖鑑、Boss或額外融合配方

**Automated Verify:**
- `components.json`的ID唯一、欄位完整、元素合法，所有`fallback_weapon_id`都存在
- `fusion_recipes.json`只有`令 + rain → 零`，所有component／ability引用有效
- Resolver對starter recipe回傳「零」，對未知component穩定回傳無配方
- `CORE → FUSED → HELD → CORE`與替換／彈出狀態轉換皆正確，每次只發出一次狀態變更
- 每次敵人死亡恰好生成一個拾取物；死亡signal重複或同幀傷害不會複製掉落
- `FUSED`隱藏外置字形；`HELD`顯示正確部件與元素色，面向左右時文字不變且`scale.x > 0`
- `reset_burst`恰好生成8發方向不同的水屬性Bullet，且不會打到玩家自己
- 載入Player場景時字形為「令」；HanziData與font coverage包含「令」「零」
- 原有GUT全套、JSON解析與Godot headless場景載入全部通過

**Manual Verify:** 在`test_room.tscn`放置至少「雨」與一種不相容敵字：

1. F6/F5啟動後確認主角是「令」，身旁沒有預設的「氵」
2. 擊敗「雨」，靠近掉落物按E，確認「令」變「零」
3. 按J確認8方向水彈清楚可辨，且不傷到玩家
4. 拾取不相容部件，確認變回「令」、部件顯示在面向側且不鏡像，J使用fallback攻擊
5. 按Q確認部件彈出並回到`CORE`；再次拾取、快速替換、死亡後均無殘影或控制台錯誤

**原階段二完成後提交（Task 2.1-2.4 milestone commit，已完成）：**
```bash
git add -A && git commit -m "phase2: radical weapon system, five-element damage calc, weapon switching"
```

---

### Task 2.7: 近戰／遠程分離（Phase 4.0.5 gate）

> **✅ 全部完成（2.7a／2.7b／2.7c／2.7d）。** 測試累計254項2426個assert全過。
> 實作與設計的差異都記在 `docs/COMBAT.md` 的變更記錄：判定改用即時形狀查詢因此不需要新增碰撞層、
> 近戰 profile 獨立成 `data/melee.json`、`chase_melee` 實際有八隻而非設計初版寫的五隻。

**Objective:** 把玩家的單一攻擊動詞拆成「J 遠程（借來的部件能力）＋ K 近戰（令自己的字核能力）」，
並把敵人的 `chase_melee` 從「會走路的接觸傷害」改造為前搖／判定／後搖三段式揮擊。

> **完整設計見 [`docs/COMBAT.md`](../COMBAT.md)**——含業界方案對照（Metal Slug 接觸感應式近戰／
> Dead Cells 雙武器欄／Hollow Knight 骨釘＋下劈）、四種 loadout 狀態的 J/K 分派表、
> 68px 安全揮擊窗口的推導、逐條實作陷阱與測試策略。此處只記錄排期與範圍。

**為什麼是 Phase 4.0.5 gate（必須排在 Task 4.1a 之前）：**

1. 序章教程關的 `TutorialTriggers` 要依序教移動／跳躍／開火／E／Q，戰鬥動詞若在關卡做完後
   才改，整條教學動線要重做。
2. **下劈（pogo）讓「敵人站在深淵上方」變成一條過關捷徑**——水域關（4.1）的平台間距與敵人
   擺位必須建立在已定案的戰鬥動詞之上，否則要重排兩次。
3. `weapons.json` 的 `range`／`projectile` 欄位目前是**死資料**（`dao` 標著 `melee` 卻生成飛行
   子彈），關卡難度曲線若建立在「十把武器只有傷害與射速差別」的現況上，等射程真正生效後
   會整個失準。

**四個PR的拆分：**

| PR | 內容 | 可獨立驗證 |
|---|---|---|
| 2.7a ✅ | `attack_type` 資料欄位 + `Bullet` 讀 `range` 換算射程上限（short 180／medium 420／long 720 px）；近戰武器按 J 退回基礎弓而不是丟出飛刀 | 武器射程開始有差別，近戰刀不再是飛的 |
| 2.7b ✅ | `MeleeAttack` 元件（三段式、即時形狀查詢）+ `melee`(K) + `move_down`(S) + 令筆擊 + 筆畫揮擊視覺 + 下劈彈起 | test_room 按 K 打死假人；空中 S+K 踩著敵人彈起 |
| 2.7c ✅ | `GlyphLoadout` 的 J/K 分派 + 刀刃筆擊(金) + 打斷蓄力 + 掉落吸附（消彈已在 2.7b 隨判定一起完成） | 撿「刂」後 K 變強且 J 退回弓；揮擊能消「河」的子彈、打斷「錘」的蓄力 |
| 2.7d ✅ | 敵人三段式近戰 + `enemies.json` 的 `melee` 區塊（八隻 `chase_melee`）+ 取消接觸傷害 | 「劍」揮擊前有明顯預兆，後搖可以免費反打一下 |

**需要新增的 Input Action：** `melee`(K)、`move_down`(S)。
S 與 Task 4.0 的 `menu_down` 不衝突——對話期間整棵樹暫停，玩家無法揮擊。

**需要新增的碰撞層：** 無。2.7b 實作時判定改用即時形狀查詢，判定框不再是場景裡的碰撞體，
`[layer_names]` 完全不必動——原規劃的 layer 6/7 取消，理由見 `docs/COMBAT.md` 6.2。

**⚠️ 對後續Task的連鎖影響：**
- **Task 4.1a** 教學動線增加 K 與下劈；近戰對峙用「劍」（0.45s前搖）教，水域關再用「針」
  （0.18s前搖）考同一套技能
- **Task 4.1/4.2** 平台間距與敵人擺位需假設玩家可能有下劈資源
- **Task 5.1** Boss 可直接複用同一個 `MeleeAttack` 元件（玩家與敵人已共用），不必第三次實作
- **Task 5.4** 「爭（格擋彈反）」的機制雛形就是 2.7c 的消彈，屆時把「消滅」升級為「反射」即可

---

## 階段三：敵字系統 + AI + 死亡特效

> **✅ 階段三全部完成**（Task 3.1/3.2/3.3/3.4）。測試累計106項671個assert全過。
>
> 兩處結構性調整見 Task 3.2；Task 3.4 的筆畫崩解改用真實筆畫資料，見該Task說明。

### Task 3.1: 敵字資料表（20種）

**Objective:** 定義敵人字、五行歸屬、AI型別、血量/傷害

**Files:**
- Create: `game/data/enemies.json`

**Step 1:** 示例（完整20條，按5行×4個鋪開）：
```json
[
  {"char":"河","element":"water","ai":"patrol_ranged","hp":30,"damage":8,"speed":80},
  {"char":"海","element":"water","ai":"chase_melee","hp":45,"damage":12,"speed":60},
  {"char":"湖","element":"water","ai":"patrol_ranged","hp":25,"damage":6,"speed":90},
  {"char":"雨","element":"water","ai":"stationary_aoe","hp":20,"damage":10,"speed":0},
  {"char":"焰","element":"fire","ai":"chase_melee","hp":35,"damage":14,"speed":100},
  {"char":"炎","element":"fire","ai":"patrol_ranged","hp":30,"damage":10,"speed":70},
  {"char":"灶","element":"fire","ai":"stationary_aoe","hp":40,"damage":16,"speed":0},
  {"char":"焚","element":"fire","ai":"chase_melee","hp":38,"damage":13,"speed":95},
  {"char":"鋼","element":"metal","ai":"patrol_ranged","hp":50,"damage":15,"speed":50},
  {"char":"針","element":"metal","ai":"chase_melee","hp":22,"damage":9,"speed":130},
  {"char":"劍","element":"metal","ai":"chase_melee","hp":40,"damage":18,"speed":110},
  {"char":"錘","element":"metal","ai":"stationary_aoe","hp":60,"damage":20,"speed":0},
  {"char":"樹","element":"wood","ai":"stationary_aoe","hp":55,"damage":11,"speed":0},
  {"char":"藤","element":"wood","ai":"patrol_ranged","hp":28,"damage":8,"speed":75},
  {"char":"森","element":"wood","ai":"chase_melee","hp":48,"damage":14,"speed":65},
  {"char":"林","element":"wood","ai":"patrol_ranged","hp":26,"damage":7,"speed":80},
  {"char":"巖","element":"earth","ai":"stationary_aoe","hp":65,"damage":19,"speed":0},
  {"char":"石","element":"earth","ai":"chase_melee","hp":30,"damage":12,"speed":55},
  {"char":"山","element":"earth","ai":"patrol_ranged","hp":42,"damage":13,"speed":45},
  {"char":"塵","element":"earth","ai":"chase_melee","hp":20,"damage":6,"speed":140}
]
```

**Verify:** JSON載入20條，按element分組各4個

---

### Task 3.2: Enemy基類 + 三種AI行為樹（巡邏/追擊/遠程/定點AOE）

**Objective:** 用狀態機實現4種AI行為，資料驅動生成不同敵人

> **✅ 已完成，但改了兩處結構。**
>
> ### 1. AI 子節點不自己移動
>
> 原文的 `enemy_ai_patrol.gd` 在自己的 `_physics_process` 裡呼叫
> `enemy.apply_gravity()` 與 `enemy.move_and_slide()`。一旦本體也移動（或日後掛第二個
> AI 節點），同一幀就會被移動多次、互相打架。
>
> 改為：**AI 只負責決定速度**（實作 `decide_velocity(enemy, delta) -> float`），
> 重力與 `move_and_slide()` 統一在 `enemy.gd` 呼叫一次。
>
> ### 2. `take_damage()` 不重複實作傷害公式
>
> 原文在 `enemy.gd` 裡把倍率計算、扣血、死亡判定整套重寫了一遍。這會漏掉基類已經
> 處理好的東西（`hp` 夾在0、`hp_changed`/`died` 訊號、同幀多發子彈的死亡去重），
> 而且日後改傷害公式要改兩個地方。
>
> 改為呼叫 `super()` 後再判斷 `hp > 0` 才閃紅——原文擔心的「死亡時 flash_hit 操作到
> 正在銷毀的節點」問題，這個順序同樣能避免，而且不必複製公式。
>
> ### AI 實際行為
>
> | 型別 | 行為 |
> |---|---|
> | `patrol_ranged` | 起點左右巡邏；玩家進入水平射程且高度接近時**停下開火**。撞牆也會折返。各敵人首次開火時間隨機錯開，避免整排同時射 |
> | `chase_melee` | 水平接近玩家，靠接觸傷害輸出（接觸判定用 `move_and_slide` 的碰撞結果，不必額外掛 Area2D）。高度差過大就放棄追擊——沒有跳躍能力，追了也上不去 |
> | `stationary_aoe` | 完全不移動，週期性放範圍傷害。放招前有 0.5 秒**蓄力預兆**（字會脹大），玩家才有機會退出範圍 |
>
> ⚠️ **敵人子彈必須改碰撞層**：與玩家子彈共用 `bullet_base.tscn`，但要設成
> `enemy_bullet` 層(16)、mask 打 `player`(2)。沿用玩家子彈的層會導致敵人互相誤傷
> 且打不到玩家。速度也調慢為 320（玩家子彈 500），玩家才閃得掉。

**Files:**
- Create: `game/scripts/enemy.gd`
- Create: `game/scripts/enemy_ai_patrol.gd`
- Create: `game/scripts/enemy_ai_chase.gd`
- Create: `game/scripts/enemy_ai_stationary.gd`

**Step 1:**
```gdscript
# game/scripts/enemy.gd
extends Character
class_name Enemy

@export var ai_type: String = "patrol_ranged"
@export var char_data: Dictionary = {}
@onready var hanzi_label: HanziSprite = $HanziLabel

func setup(data: Dictionary) -> void:
    char_data = data
    hanzi_label.character_text = data["char"]
    element = data["element"]
    max_hp = data["hp"]
    hp = max_hp
    speed = data["speed"]
    ai_type = data["ai"]

func take_damage(amount: int, attacker_element: String) -> void:
    # 注意：不能先呼叫 super.take_damage() 再呼叫 flash_hit() ——
    # 如果這一下正好把敵人打死，super.take_damage()內部會觸發die()->shatter_and_die()->queue_free()，
    # 敵人節點已經在銷毀佇列裡，此後再對它做flash_hit()會報錯或產生視覺衝突。
    # 正確順序：先判斷是否會死，若不會死才閃紅；死亡交給die()/shatter_and_die()統一處理死亡視覺。
    var multiplier = ElementSystem.get_multiplier(attacker_element, element)
    var actual_damage = int(amount * multiplier)
    var will_die = (hp - actual_damage) <= 0
    hp -= actual_damage
    if will_die:
        die()
    else:
        hanzi_label.flash_hit()

func die() -> void:
    hanzi_label.shatter_and_die()
    queue_free()
```

**Step 2 (巡邏AI示例，其餘兩種同結構不同邏輯):**
```gdscript
# game/scripts/enemy_ai_patrol.gd
extends Node

@export var patrol_range: float = 150.0
var start_x: float
var dir: float = 1.0

func _ready() -> void:
    start_x = get_parent().global_position.x

func _physics_process(delta: float) -> void:
    var enemy = get_parent()
    enemy.velocity.x = dir * enemy.speed
    if abs(enemy.global_position.x - start_x) > patrol_range:
        dir *= -1
    enemy.apply_gravity(delta)
    enemy.move_and_slide()
```

**Verify:** 場景內放置一個"河"敵人，執行後左右巡邏150px範圍內往返

---

### Task 3.3: 敵人生成器 (EnemySpawner)

**Objective:** 關卡內按點位/波次生成敵人，從enemies.json按key取資料

> **✅ 已完成。** 資料表改為**靜態快取**——原文每個生成器都會把 enemies.json 讀一遍，
> 一關放20個生成器就讀20次。另加 `respawn_delay`（測試場景用來反覆驗證）與
> `spawn_on_ready`（關閉後可由外部控制波次生成，供階段四關卡使用）。

**Files:**
- Create: `game/scripts/enemy_spawner.gd`
- Create: `game/scenes/enemy_base.tscn`

**Step 1:**
```gdscript
# game/scripts/enemy_spawner.gd
extends Node2D

@export var enemy_char: String = "河"
var enemy_data_table: Dictionary = {}

func _ready() -> void:
    var f = FileAccess.open("res://data/enemies.json", FileAccess.READ)
    var list = JSON.parse_string(f.get_as_text())
    for e in list:
        enemy_data_table[e["char"]] = e
    spawn()

func spawn() -> void:
    var scene = preload("res://scenes/enemy_base.tscn")
    var enemy = scene.instantiate()
    add_child(enemy)
    enemy.setup(enemy_data_table[enemy_char])
```

**Verify:** 在關卡場景放5個EnemySpawner節點，各自設定不同enemy_char，執行後生成對應敵人且屬性正確（列印hp/damage確認）

---

### Task 3.4: 筆畫崩解死亡特效

**Objective:** 敵人死亡時字形按筆畫拆散飛出，視覺爽感核心賣點

> **✅ 已完成，但用的是真實筆畫而非原文的近似碎片。**
>
> 原文的做法是灑幾個 `"﹒"` 字元當碎片，跟「筆畫崩解」關係不大——字是什麼、幾筆，
> 看起來都一樣。
>
> 改用 Task 1.2 存下來的 **`medians`（每筆的中軸點序列）**，一筆一條 `Line2D` 畫出來，
> 所以「山」炸成3根、「巖」炸成23根，形狀就是那個字真正的筆畫。不需要解析 SVG path，
> medians 本身就是現成的點序列——這也是當初 Task 1.2 多存這個欄位的原因。
>
> 每一筆朝**自己相對於字心的方向**飛出，整個字看起來是炸開而不是所有碎片往同一邊飄。
>
> 座標系：Make Me a Hanzi 用 1024 單位字身框且 y 軸朝上（與螢幕相反）。實作上不去猜它的
> 基線慣例，改用「算出所有點的實際外框再置中」，對任何字都穩定。
>
> 沒有筆畫資料的字（UI用字、資料集未收錄）退回整字淡出，不會直接消失或報錯。

**Files:**
- Modify: `game/scripts/hanzi_sprite.gd`

**Step 1:** 利用階段一Task 1.2的筆畫SVG路徑資料，用`Line2D`或多個小`Label`模擬碎片：
```gdscript
func shatter_and_die() -> void:
    var strokes = HanziData.get_strokes(text)  # 從hanzi_decomposition.json取
    for stroke_path in strokes:
        var fragment = Label.new()
        fragment.text = "﹒"  # 簡化：用筆畫點位近似，或用Polygon2D渲染真實path
        fragment.global_position = global_position + Vector2(randf_range(-10,10), randf_range(-10,10))
        get_tree().current_scene.add_child(fragment)
        var tween = fragment.create_tween()
        var random_dir = Vector2(randf_range(-100,100), randf_range(-200,-50))
        tween.tween_property(fragment, "position", fragment.position + random_dir, 0.6)
        tween.parallel().tween_property(fragment, "modulate:a", 0.0, 0.6)
        tween.tween_callback(fragment.queue_free)
    queue_free()
```

**Verify:** 擊殺敵人後原地字形消失，若干碎片飛散並淡出，無殘留節點（用Godot遠端場景樹檢查節點數不增長）

**階段三完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase3: enemy system, 4 AI behaviors, 20 enemy chars, shatter death effect"
```

---

## 階段四：關卡設計（序章 + 4關 + 終章）

> **⚠️ 前置依賴：Task 2.7（近戰／遠程分離）必須先完成。** 關卡的教學動線、平台間距與敵人
> 擺位都建立在戰鬥動詞之上；下劈（pogo）一旦存在，「敵人站在深淵上方」就等於一條過關捷徑。
> 詳見 Task 2.7 與 [`docs/COMBAT.md`](../COMBAT.md)。

> **⚠️ 範圍更新（隨主線劇情定版同步修改）：** 原計劃只有「4關」，未涵蓋`docs/STORY.md`第4節章節流程表定案的**序章「字界殘頁」**（教程關）與**終章「崩筆祭壇」**（終Boss「仁」戰鬥關）。本階段新增Task 4.0（對話/演出框架，序章與終章共同依賴的阻斷性前置任務）、Task 4.0b（存檔基礎切片，水域存檔點與終Boss旗標共同依賴）、Task 4.1a（序章關卡）、Task 4.4（終章關卡）。執行順序：**4.0 → 4.0b → 4.1a → 4.1 → 4.2 → 4.3 → 4.4**（4.0b必須早於第一個checkpoint；4.4需等Task 4.3的LevelManager與階段五Task 5.4的Boss「仁」都就緒才能整合，實際上是「Phase 5.4 integration gate」，見階段五說明）。

### Task 4.0: 對話／演出框架（阻斷性前置依賴）

> **✅ 已完成。** 新增29項測試（`test_dialogue_box.gd` / `test_cutscene_player.gd` / `test_dialogue_data.gd`），
> 全專案累計172項2187個assert全過。實作與下方草稿有六點差異，前兩點是照抄會直接壞掉的：
>
> 1. **`DialogueBox` 必須設 `process_mode = PROCESS_MODE_ALWAYS`。** 草稿在 `play()` 裡設
>    `get_tree().paused = true`，但沒把自己排除在暫停之外——對話框本身跟著停住後，
>    `_unhandled_input` 收不到推進鍵、打字機也不會跑，遊戲會**永久卡死在第一句對話**，
>    只能關掉重開。這是照抄草稿必踩的第一個坑。
> 2. **結束時還原成播放前的暫停狀態，而不是無條件 `paused = false`。** 階段六的暫停選單
>    若在暫停中觸發對話（例如選單裡看圖鑑說明），草稿的寫法會把暫停選單一起解除。
> 3. **補上草稿 Step 2 文字有寫、程式碼卻沒實作的打字機**，並定義「打字未完成時按推進鍵
>    只補完整句、不換句」的兩段式行為。推進時會 `set_input_as_handled()`——否則最後一句
>    按下去會在解除暫停的同一幀順便開一槍。
> 4. **選項UI做成可直接用的最小版本**（W/S 移游標、J 確認）。草稿把選項UI整個留給Task 5.4
>    決定，但資料流沒有可執行的參考實作等於還是得重寫一次；這裡先做出來，Task 5.4 只需要改視覺。
>    ⚠️ 選項是**直向清單**，實機驗證後確認上下鍵才是直覺綁定，因此在 `project.godot` 的
>    `[input]` 新增了 `menu_up`(W) / `menu_down`(S) 兩個 action——這是本PR唯一改動
>    `project.godot` 的地方，見 `COLLABORATION.md` 第2.2節。原本的 A/D（`move_left`/
>    `move_right`）一併保留，兩種按法都能動。推進／確認仍沿用 `fire`，不另外綁鍵。
>    `[input]` 是手寫的，事件字串打錯會安靜地變成「action存在但沒綁任何按鍵」，
>    因此 `test_dialogue_box.gd` 直接斷言 `menu_up`/`menu_down` 的 physical keycode 是 W/S。
> 5. **`CutscenePlayer` 改成「步驟資料 + cue signal」而不是一堆 `play_xxx()` 硬編函式。**
>    過場用 `[{"type":"dialogue"},{"type":"wait"},{"type":"signal"}]` 描述時序，特效由關卡端
>    接 `cue` 掛上——演出框架不認得任何特效，Task 4.4/5.4 的白光與筆畫反向崩解才不會反過來
>    寫死在框架裡。`play_ending_zhu_descent()` 保留為這套步驟資料的一個組合。
>    ⚠️ 對話缺檔時 `dialogue_finished` 是**同步**送出的，過場若無條件 `await` 那個 signal 會
>    永遠等下去，因此 await 前一律先問 `is_active()`。
> 6. **台詞資料表加了CI檢查**（`test_dialogue_data.gd`）：schema、id與檔名一致、字型字形涵蓋、
>    簡體字偵測。台詞是純資料且多人並行編輯，缺字形只會安靜地顯示成豆腐方框、簡體字則完全
>    不會報錯（GDD第0節語言規範），這兩種錯不在CI擋就只能等實機肉眼抓。
>
> **手動驗證入口：** `test_room.tscn` 已掛上 `DialogueBox` + `CutscenePlayer`，F5後按
> **T**（播「仁」的開場七句）、**Y**（同一段台詞＋貪/爭/棄的通用選項UI原型，選擇結果會印在左上HUD）、
> **U**（終章「主」降臨過場：降光cue → 1秒停頓 → 劃清責任的台詞 → 取回亻cue）。
> 這三個是測試場景的除錯捷徑，用原始keycode而非Input Action；Y只驗證通用選項元件，
> **不代表Task 5.4的「賜俸」會使用選單**。正式招式必須撒出可拾取／彈反／閃避的實體520錢幣。
>
> **本Task的台詞資料只放了 `boss_ren_intro.json` 與 `ending_zhu_descent.json`**（草稿Step 1
> 的範例本身就是仁的開場白）；序章的 `prologue_awakening` / `prologue_guide_tutorial` 屬於
> Task 4.1a的檔案清單，不在這裡預先建立。

**Objective:** 建立一套可供序章教程NPC、Boss開場白、「賜俸」前後台詞、Phase 2.1／終章選項、終章「主」劃清責任與共同尾聲共用的最小對話/過場系統。這是純UI+資料驅動元件，不含關卡/Boss邏輯本身。

**為什麼是阻斷性前置依賴：** 序章教程需要NPC對話框，終Boss「仁」的開場五連頭銜白、Phase 2.1「命」的接住/放手二選一、「賜俸」前後反饋、終章「主」的責任台詞與二的共同尾聲，全部要用同一套元件，不應該讓每個Task各自兜一套簡陋的Label顯示邏輯。「賜俸」的貪／爭／棄由場上實際行為判定，不由本UI代選。

**Files:**
- Create: `game/scripts/dialogue_box.gd` (`class_name DialogueBox`)
- Create: `game/scenes/ui/dialogue_box.tscn`
- Create: `game/scripts/cutscene_player.gd` (`class_name CutscenePlayer`)
- Create: `game/data/dialogue/` 目錄（各關卡/Boss台詞JSON，繁體中文，見下方schema）

**Step 1:** 台詞資料schema（純JSON，逐行辨識度高，方便多人協作編輯不衝突）：
```json
{
  "id": "boss_ren_intro",
  "lines": [
    {"speaker": "仁", "text": "「住口！站在你面前的是——」"},
    {"speaker": "仁", "text": "「六書正統的嫡傳嫡出，」"},
    {"speaker": "仁", "text": "「部首萬象盟的欽定准入者；」"},
    {"speaker": "仁", "text": "「水域、火山、森林三域的『征服者』，」"},
    {"speaker": "仁", "text": "「『天下共主』之相與『人字旁』太古神器的唯一持有者……」"},
    {"speaker": "仁", "text": "「……仁！」"},
    {"speaker": "仁", "text": "「跪下，見證朕的完整。」"}
  ]
}
```

**Step 2:** `DialogueBox`（顯示一句、支援打字機效果、等待玩家按鍵推進，暫停時凍結戰鬥）：
```gdscript
# game/scripts/dialogue_box.gd
extends CanvasLayer
class_name DialogueBox

signal dialogue_finished

@onready var label: Label = $Panel/Label
@onready var speaker_label: Label = $Panel/SpeakerLabel

var lines: Array = []
var current_index: int = 0

func play(dialogue_id: String) -> void:
    var f = FileAccess.open("res://data/dialogue/%s.json" % dialogue_id, FileAccess.READ)
    if not f:
        push_warning("dialogue not found: " + dialogue_id)
        dialogue_finished.emit()
        return
    var data = JSON.parse_string(f.get_as_text())
    lines = data.get("lines", [])
    current_index = 0
    visible = true
    get_tree().paused = true
    _show_line()

func _show_line() -> void:
    if current_index >= lines.size():
        _finish()
        return
    var line = lines[current_index]
    speaker_label.text = line.get("speaker", "")
    label.text = line.get("text", "")

func advance() -> void:
    current_index += 1
    _show_line()

func _finish() -> void:
    visible = false
    get_tree().paused = false
    dialogue_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("fire"):  # 沿用開火鍵推進對話，不新增按鍵
        advance()
```

**Step 3:** `CutscenePlayer`（給無互動的純演出過場用，如終章「主」降臨；跟`DialogueBox`是組合關係，過場本身可以插入對話）：
```gdscript
# game/scripts/cutscene_player.gd
extends Node
class_name CutscenePlayer

signal cutscene_finished

func play_ending_zhu_descent() -> void:
    # 具體演出實作見Task 4.4/5.4：純白光效+筆畫崩解特效反向播放+DialogueBox播放「主」劃清責任的台詞
    pass
```

**Step 4:** 選擇型對話（供Phase 2.1接住／放手及終章接受／放下使用，是`DialogueBox`的擴充變體，不是新元件；Y鍵的貪／爭／棄只保留為通用UI測試資料）：
```gdscript
# 在dialogue_box.gd追加
signal choice_made(choice_id: String)

func play_choice(dialogue_id: String, choices: Array) -> void:
    # choices範例: [{"id":"catch","label":"接住"}, {"id":"release","label":"放手"}]
    # 本函式只負責真正需要菜單的敘事選擇；「賜俸」由ShangfengCoin的實體互動決定：
    # 選擇後emit choice_made(choice_id)，呼叫端（BossRen）自行處理增益/減益邏輯
    pass
```

**Verify:** 用一個假的`test_dialogue.json`（3句話）在測試場景播放，按開火鍵能逐句推進，播放期間`get_tree().paused`為true且玩家無法移動，播完後自動恢復

---

### Task 4.0b: 存檔基礎切片（checkpoint／隱藏旗標共同前置）

**Objective:** 在第一個正式關卡建立checkpoint之前，先提供可用的`SaveSystem` autoload。此切片同時保存
checkpoint座標與`has_ever_hoarded`；後者在階段五才由「賜俸」消費，但必須從一開始就是同一個真相源，
不得到Boss階段再補第二套旗標。

**Files:**
- Create: `game/scripts/save_system.gd`
- Create: `game/tests/test_save_system.gd`
- Modify: `game/project.godot`（由Integrator只在`[autoload]`追加`SaveSystem`）

**Step 1:** 讀取原始JSON與更新記憶體旗標分離；`set_checkpoint()`不依賴尚未建立的`LevelManager`，
只保存本階段已知的節點路徑與座標。`mark_hoarded()`必須先讀舊資料、再設true並立即寫回：

```gdscript
extends Node

const SAVE_PATH := "user://savegame.json"

var has_ever_hoarded: bool = false

func _ready() -> void:
    load_game()  # autoload啟動時先同步舊存檔，避免首次checkpoint以預設false覆蓋歷史true

func _read_save_data() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        return {}
    var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
    var text := f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func load_game() -> Dictionary:
    var data := _read_save_data()
    has_ever_hoarded = bool(data.get("has_ever_hoarded", false))
    return data

func save_game(data: Dictionary) -> void:
    var snapshot := data.duplicate(true)
    snapshot["has_ever_hoarded"] = has_ever_hoarded
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(snapshot))
    f.close()

func set_checkpoint(node_path: NodePath, pos: Vector2) -> void:
    var data := _read_save_data()
    data["checkpoint"] = {"path": str(node_path), "x": pos.x, "y": pos.y}
    save_game(data)

func mark_hoarded() -> void:
    var data := _read_save_data()  # 不改寫目前記憶體旗標
    has_ever_hoarded = true
    save_game(data)
```

**Step 2:** 由Integrator在`project.godot`的`[autoload]`小節追加：

```ini
SaveSystem="*res://scripts/save_system.gd"
```

**Verify:** `checkpoint.gd`可在Task 4.1直接呼叫`set_checkpoint()`，存檔JSON包含path/x/y；不存在、
空白或格式錯誤的存檔會安全回退為空字典。另以`has_ever_hoarded: false`舊存檔呼叫
`mark_hoarded()`，立即與reload後皆為true。回歸測試還必須預置true存檔、重建SaveSystem後不手動呼叫
`load_game()`而直接觸發`set_checkpoint()`；記憶體與磁碟都必須保持true，不能被預設false覆蓋。

---

### Task 4.1a: 序章「字界殘頁」（教程關）

**Objective:** 玩家第一次接觸操作的關卡，帶出令甦醒、發現殘缺、遇到引路者NPC的開場劇情（見`docs/STORY.md`第4節章節流程表）

**Files:**
- Create: `game/scenes/levels/level_00_prologue.tscn`
- Create: `game/scripts/guide_npc.gd`
- Create: `game/data/dialogue/prologue_awakening.json`、`game/data/dialogue/prologue_guide_tutorial.json`
- Create: `game/data/dialogue/story_prologue_workshop.json`（舊作坊、空藥匣與「名」匾額，只呈現線索、不提前解答）

**Step 1:** 場景結構（比照Task 4.1但更短、無存檔點壓力，純教程動線）：
```
LevelPrologue (Node2D)
├── TileMap (簡化的「殘頁」主題地形，不需要正式tileset，可用中性灰階素材頂上，日後美術可替換)
├── PlayerSpawn (Marker2D)
├── GuideNPC (Area2D + guide_npc.gd，觸發`prologue_awakening`對話：令甦醒、發現殘缺卩）
├── TutorialTriggers (Node2D，多個Area2D依序觸發移動/跳躍/開火/E拾取/Q彈出教學提示，各自對應`docs/PROTAGONIST-令.md`第1節「可是我會」的自我認知橋段)
├── FirstComponentDrop (手動放置一個部件掉落物，供玩家練習E/Q循環，不依賴敵人死亡signal)
├── OldWorkshopEvidence (Area2D，必經但不強制停留；顯示空藥匣與被刮去金旁的「名」匾額)
└── LevelExit (Area2D，觸發`LevelManager.next_level()`進入水域關)
```

**Step 2:** 引路者NPC：
```gdscript
# game/scripts/guide_npc.gd
extends Area2D

@export var dialogue_id: String = "prologue_awakening"
@onready var dialogue_box: DialogueBox = get_tree().current_scene.get_node("DialogueBox")

func _on_body_entered(body: Node) -> void:
    if body is Player:
        dialogue_box.play(dialogue_id)
```

**Verify:** 從PlayerSpawn開始，觸發引路者對話後能依序完成移動/跳躍/開火/E/Q教學，走到LevelExit進入水域關

---

### Task 4.1: TileMap關卡基礎 — 水域關

**Objective:** 用Godot TileMap搭建第一關地形，含存檔點

**Files:**
- Create: `game/scenes/levels/level_01_water.tscn`
- Create: `game/scripts/checkpoint.gd`
- Create: `game/assets/art/tileset_water.png`（從OpenGameArt/Kenney取水域主題tileset）
- Create: `game/data/dialogue/story_water_requisition.json`（仁的第一張「平亂後十倍奉還」徵用告示）

**Step 1:** 場景結構：
```
Level01 (Node2D)
├── TileMap (水域主題地形)
├── Background (Parallax2D，水域背景圖)
├── PlayerSpawn (Marker2D)
├── EnemySpawners (Node2D, 多個EnemySpawner子節點，enemy_char設為河/海/湖/雨)
├── Checkpoints (Node2D, 多個Area2D+checkpoint.gd)
├── MandatoryStoryEvidence (Area2D，第一次讀取`story_water_requisition`後才開啟後續動線)
├── LevelExit (Area2D, 觸發進入下一關)
└── CameraBounds (Rect2定義)
```

**Step 2:**
```gdscript
# game/scripts/checkpoint.gd
extends Area2D

func _on_body_entered(body: Node) -> void:
    if body is Player:
        SaveSystem.set_checkpoint(get_path(), global_position)
```

**Verify:** 玩家從PlayerSpawn開始，必定讀到第一張徵用告示，能走到LevelExit觸發場景切換，中途經過Checkpoint觸發存檔

---

### Task 4.2: 火山關 / 森林關 / 礦山關

**Objective:** 複製Task 4.1結構，替換tileset美術+enemy_char+背景音樂，共3關；**礦山關為無Boss過渡關**（見`docs/STORY.md`第4節章節流程表），不放置Boss戰場景，改為稀有部件掉率提升

**Files:**
- Create: `game/scenes/levels/level_02_fire.tscn`
- Create: `game/scenes/levels/level_03_wood.tscn`
- Create: `game/scenes/levels/level_04_earth.tscn`
- Create: `game/data/dialogue/story_fire_father_echo.json`（仁第一次以「朕」回家）
- Create: `game/data/dialogue/story_wood_ling_echo.json`（祖母、最後一劑苓草與空藥床）
- Create: `game/data/dialogue/story_mine_ming_echo.json`（父親「銘→名」與賜俸鑄印真相）
- Modify: `game/data/fusion_recipes.json`（以既有`component_id: "grass"`加入完整配方`艹＋令→苓`與`ling_bind` attack profile）
- Modify: `tools/build_hanzi_data.py`、`game/data/hanzi_decomposition.json`（將「苓」加入生成字表與產物）
- Modify: `game/tests/test_fusion_resolver.gd`、`game/tests/test_glyph_loadout.gd`、`game/tests/test_weapon_manager.gd`、`game/tests/test_component_flow.gd`（配方數、HanziData、FUSED顯示、有效攻擊與Q彈出回歸）

**Step 1:** 每關的EnemySpawner全部指向對應五行的敵字（火山關全用fire系4個字，以此類推），保證「關卡主題=五行區塊」貫徹到底。

同時加入不可漏收的線性證物鏈，每章最多一段8–12秒無操作墨影，避免長篇說明：

- 火山：父親未寄出的信／回聲——仁第一次自稱「朕」，父親答「你叫我父親，不必叫臣」。
- 森林：苓草藥方、祖母等待與下一房間的空床；玩家以`艹＋令→苓`救助仍活著的病人後Q歸還，空床不發生變化。
- 礦山：父親主動阻止、二親手按住亻的真相；作坊由「銘」剝成「名」，賜俸錢幣正面保留「520」、翻面露出同一枚「銘」印。

森林關的「苓」不是只有演出、沒有戰鬥能力的半成品。沿用現有resolver資料契約新增完整配方：

```json
{
  "core_glyph": "令",
  "component_id": "grass",
  "result_glyph": "苓",
  "layout": "top_bottom",
  "ability_id": "ling_bind",
  "attack": {
    "id": "ling_bind",
    "radical": "艹",
    "name": "苓草束",
    "element": "wood",
    "attack_type": "projectile",
    "damage": 7,
    "fire_rate": 0.65,
    "projectile": "vine",
    "range": "medium",
    "pattern": "single",
    "projectile_count": 1
  }
}
```

`grass`已存在於`components.json`，不新增第二個部件ID。`苓`必須先加入`tools/build_hanzi_data.py`的
`NEEDED_CHARS`並重建`hanzi_decomposition.json`；測試不再斷言「唯一配方」，改為精確驗證「零」與「苓」
兩條curated recipe。`GlyphLoadout`進入FUSED時主字顯示「苓」、外置艹隱藏且J可正常發射`ling_bind`；
Q後彈出同一個grass部件並恢復「令」。把苓交給醫者是森林場景的專用Q結果，不讓一般戰鬥Q具備全域治療效果。

**Step 2（礦山關差異化）：** 礦山關（`level_04_earth.tscn`）的`EnemySpawner`額外設定`drop_rate_multiplier`（沿用Task 2.6/`component_dropper.gd`既有的部件掉落機制，只加一個倍率參數，不新增掉落系統）：
```gdscript
# 在礦山關的EnemySpawner Inspector面板設定，或於場景腳本內：
enemy_spawner.drop_rate_multiplier = 2.0  # 稀有部件掉率提升為其他關卡的2倍，呼應「為終局囤配方」的關卡定位
```
`component_dropper.gd`需要新增讀取此倍率的邏輯（`drop_chance *= spawner.drop_rate_multiplier if spawner else 1.0`），其餘3關維持預設倍率1.0不受影響。**礦山關不建立Boss戰場景**，`LevelExit`直接觸發`LevelManager.next_level()`進入終章，不經過Task 5.3的Boss arena流程。

**Verify:** 依次通關3關，每關敵人元素與關卡主題一致，武器剋制策略在對應關卡內明顯生效（用剋制武器一擊傷害肉眼可辨高於非剋制武器）；三段核心證物均不可繞過；`艹＋令→苓`能進入FUSED、使用有效的`ling_bind`並Q回令，森林劇情歸還能幫助活人但不改變祖母空床；礦山能清楚讀出「銘→名」；額外驗證礦山關部件掉落頻率肉眼可辨高於其他關卡，且關卡末尾無Boss戰觸發

---

### Task 4.3: 關卡管理器 LevelManager (autoload)

**Objective:** 統一管理關卡切換、存檔點復活、關卡間過渡動畫，**範圍擴充為序章+4關+終章共6個場景**

**Files:**
- Create: `game/scripts/level_manager.gd` (autoload)

**Step 1:**
```gdscript
extends Node

var levels: Array = [
    "res://scenes/levels/level_00_prologue.tscn",
    "res://scenes/levels/level_01_water.tscn",
    "res://scenes/levels/level_02_fire.tscn",
    "res://scenes/levels/level_03_wood.tscn",
    "res://scenes/levels/level_04_earth.tscn",
    "res://scenes/levels/level_05_final_altar.tscn"
]
var current_level_index: int = 0

func load_level(index: int) -> void:
    current_level_index = index
    get_tree().change_scene_to_file(levels[index])

func next_level() -> void:
    if current_level_index + 1 < levels.size():
        load_level(current_level_index + 1)
    else:
        get_tree().change_scene_to_file("res://scenes/ui/victory_screen.tscn")
```

**⚠️ 注意：** 終章（`level_05_final_altar.tscn`）走完後不是簡單`next_level()`到victory_screen——它會先播放Task 5.4的主取回亻過場；符合`has_ever_hoarded == false`者在此插入「命」的最終選擇，之後所有路線都載入`level_06_epilogue.tscn`完成二的三個Q鍵歸還節點與共同消失尾聲，最後才切到victory_screen。整段不透過`next_level()`，因為條件演出與共用尾聲需要由Task 5.4明確編排。

**Step 2：** 在`project.godot`的`[autoload]`小節**追加**一行（不要覆寫先前已註冊的`HanziData`/`ElementSystem`）：
```ini
[autoload]
HanziData="*res://scripts/hanzi_data.gd"
ElementSystem="*res://scripts/element_system.gd"
LevelManager="*res://scripts/level_manager.gd"
```

**Verify:** LevelExit觸發`LevelManager.next_level()`，序章→4關依序切換；礦山關（第5個場景索引）走完直接進終章而非Boss arena；終章擊敗「仁」後依序完成主降臨→可選「命」演出→所有路線共用二之尾聲（全程非`next_level()`），最終進入勝利畫面

**階段四完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase4: prologue + four themed levels + final altar, checkpoints, level manager, dialogue framework"
```

---

### Task 4.4: 終章「崩筆祭壇」關卡

**Objective:** 搭建終章關卡場景骨架，串接終Boss「仁」的完整戰鬥流程（詳見階段五Task 5.4）

**前置依賴：** Task 4.0（對話框架）+ Task 4.3（LevelManager）+ 階段五Task 5.4（Boss「仁」邏輯本體）。**本Task只負責關卡場景骨架與整合掛載，Boss本身的戰鬥/台詞/選擇邏輯屬於Task 5.4範圍**，兩者實際上是同一個「Phase 5.4 integration gate」的一體兩面，建議由同一位整合者連續完成，避免場景掛載和Boss邏輯出現介面不對齊的問題。

**Files:**
- Create: `game/scenes/levels/level_05_final_altar.tscn`
- Create: `game/scenes/levels/level_06_epilogue.tscn`（不加入`LevelManager.levels`，僅由Task 5.4結局流程載入）

**Step 1:** 場景結構：
```
LevelFinalAltar (Node2D)
├── TileMap (祭壇主題地形，無五行歸屬的中性色調，呼應「僭越五行體系之外」的美術定位)
├── PlayerSpawn (Marker2D)
├── BossRen (Boss場景實例，script=boss_ren.gd，見Task 5.4)
├── DialogueBox (CanvasLayer，供開場白／賜俸／Phase 2.1／主的責任台詞共用)
├── CutscenePlayer (Node，播放「主」取回亻與可選「命」演出)
└── (無LevelExit——終章結束由Task 5.4手動載入共同尾聲，不透過一般關卡出口)
```

`level_06_epilogue.tscn`只需小型線性動線，可復用序章舊作坊與終章祭壇素材：

```
LevelEpilogue (Node2D)
├── PlayerTwo (CharacterBody2D，顯示「二」；攻擊／拾取／融合全部停用)
├── GrandmotherMedicineBox (Area2D，第一個Q歸還點)
├── FatherWorkshop (Area2D，第二個Q歸還點)
├── EmptyAltarReturn (Area2D，物品欄為空時仍提示第三次Q)
├── DialogueBox (CanvasLayer)
└── EndingEpilogueController (Node，編排三個歸還狀態、時間跳切與最終轉場)
```

**Verify:** 從PlayerSpawn開始，進場觸發「仁」開場五連頭銜白（見Task 5.4），戰鬥流程正常運作；擊敗後正確進入主降臨與可選「命」演出，再載入尾聲場景。尾聲中二不能攻擊、拾取或融合，三個Q節點必須依序完成，最後才進入victory_screen

**階段四完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase4: prologue + four themed levels + final altar, checkpoints, level manager, dialogue framework"
```

---

## 階段五：Boss戰（4隻Boss——淼/焱/森 + 終極Boss「仁」）

> **⚠️ 範圍更新（隨主線劇情定版同步修改）：** 原計劃只有3隻一般Boss，未涵蓋終極Boss「仁」（`docs/BOSS-仁.md`完整設計）。新增Task 5.4，是本階段份量最重的任務——涉及雙元素三階段狀態機、開場演出、「賜俸」三選一、Phase 2.1「命」中途顯現、「主」取回亻，以及二的可操作歸還／消失尾聲，建議獨立分派、預留比其他Boss Task更多的實作與playtest時間。

### Task 5.1: Boss基類 + 多階段狀態機

**Objective:** Boss不同於普通敵人——有階段轉換、拆解出子武器攻擊玩家

**Files:**
- Create: `game/scripts/boss.gd`
- Create: `game/data/bosses.json`

**Step 1:**
```json
[
  {"char":"淼","element":"water","hp":300,"phases":3,"sub_radicals":["水","水","水"],"level":1},
  {"char":"焱","element":"fire","hp":350,"phases":3,"sub_radicals":["火","火","火"],"level":2},
  {"char":"森","element":"wood","hp":400,"phases":3,"sub_radicals":["木","木","木"],"level":3}
]
```

**⚠️ 注意：終極Boss「仁」不放進本檔案。** `bosses.json`統一給「單一部首 × 3階段強度遞增」這種一般Boss用；「仁」是雙元素/階段（Phase 1水+火、Phase 2金+木、Phase 3土+覺醒態全五行）且戰鬥流程含開場白/賜俸/Phase 2.1三個非純數值的敘事節點，硬塞進同一份資料表只會讓`sub_radicals`欄位語意分裂。「仁」的資料獨立放在`game/data/boss_ren.json`，見Task 5.4。

**Step 2:**
```gdscript
# game/scripts/boss.gd
extends Enemy
class_name Boss

@onready var attack_patterns: BossAttackPatterns = $BossAttackPatterns

var phase: int = 1
var max_phases: int = 3
var sub_radicals: Array = []

func setup_boss(data: Dictionary) -> void:
    setup(data)
    max_phases = data["phases"]
    sub_radicals = data["sub_radicals"]

func take_damage(amount: int, attacker_element: String) -> void:
    # Boss繼承自Enemy，Enemy.take_damage()已經處理了「先判斷會不會死、避免死亡後還操作已釋放節點」的邏輯。
    # 這裡只需要在呼叫父類邏輯「之前」算好階段轉換，因為一旦這次傷害導致死亡，就不需要再進入新階段了。
    var multiplier = ElementSystem.get_multiplier(attacker_element, element)
    var actual_damage = int(amount * multiplier)
    var will_die = (hp - actual_damage) <= 0

    if not will_die:
        # 用ceil計算「目前血量對應第幾階段」，避免浮點數整除邊界誤差。
        # 例：max_hp=300, max_phases=3 → 每階段100血。剩餘hp=200時應仍在phase 1（剛降到閾值），
        # hp=199時進入phase 2，hp=99時進入phase 3。
        var hp_after = hp - actual_damage
        var phase_size = float(max_hp) / max_phases
        var expected_phase = max_phases - ceili(hp_after / phase_size) + 1
        expected_phase = clampi(expected_phase, 1, max_phases)
        if expected_phase > phase:
            phase = expected_phase
            call_deferred("enter_phase", phase)  # 延後到本幀傷害處理完再觸發，避免與super.take_damage內的flash_hit衝突

    super.take_damage(amount, attacker_element)  # 交給Enemy.take_damage統一處理扣血/受擊特效/死亡判斷

func enter_phase(p: int) -> void:
    hanzi_label.flash_hit()
    # 每階段召喚對應部首子彈幕，攻擊模式升級
    var radical = sub_radicals[p - 1] if p - 1 < sub_radicals.size() else sub_radicals[-1]
    attack_patterns.spawn_phase_attack(p, radical, element, global_position)
```

**（節點結構補充：`Boss`場景需要一個子節點`BossAttackPatterns`掛載`boss_attack_patterns.gd`，見Task 5.2）**

**Verify:** Boss血量降到2/3、1/3閾值時觸發`enter_phase`，列印phase切換日誌確認閾值正確（用整數邊界值如hp剛好等於閾值時測試，確認不會因浮點誤差重複觸發或跳過階段）

---

### Task 5.2: 三種Boss彈幕/攻擊模式

**Objective:** 淼(水彈幕環形)、焱(火焰追蹤彈)、森(藤蔓地刺)，各階段強度遞增

**Files:**
- Create: `game/scripts/boss_attack_patterns.gd`

**Step 1:** `BossAttackPatterns`是掛載在每個Boss場景下的子節點（`class_name BossAttackPatterns`），`Boss.gd`透過`@onready var attack_patterns: BossAttackPatterns = $BossAttackPatterns`取得引用並呼叫，兩者是**父子節點組合關係**，不是繼承關係：

```gdscript
# game/scripts/boss_attack_patterns.gd
extends Node
class_name BossAttackPatterns

# 統一入口：依階段編號分派到對應彈幕模式，強度隨階段遞增
func spawn_phase_attack(phase: int, radical: String, element: String, origin: Vector2) -> void:
    var intensity_multiplier = 1.0 + (phase - 1) * 0.5  # phase 1=1.0x, phase 2=1.5x, phase 3=2.0x
    match radical:
        "水":
            spawn_ring_attack(origin, 8 + phase * 4, element, intensity_multiplier)
        "火":
            spawn_tracking_attack(origin, 3 + phase, element, intensity_multiplier)
        "木":
            spawn_ground_spike_attack(origin, 4 + phase * 2, element, intensity_multiplier)
        _:
            spawn_ring_attack(origin, 8, element, intensity_multiplier)  # 預設環形彈幕

func spawn_ring_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
    var bullet_scene = preload("res://scenes/projectiles/bullet_base.tscn")
    for i in range(count):
        var angle = (TAU / count) * i
        var bullet = bullet_scene.instantiate()
        bullet.setup(int(15 * intensity), element, origin, Vector2(cos(angle), sin(angle)))
        get_tree().current_scene.add_child(bullet)

func spawn_tracking_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
    pass  # 追蹤彈邏輯：實作時可用bullet的_physics_process裡動態朝向玩家位置調整方向

func spawn_ground_spike_attack(origin: Vector2, count: int, element: String, intensity: float = 1.0) -> void:
    pass  # 地刺邏輯：在玩家腳下一定範圍內按時間差生成向上突刺的Area2D
```

**（`bullet.setup()`使用Task 2.3已統一的`Vector2`方向參數，Boss彈幕與Player子彈共用同一套`bullet.gd`，全方向彈幕與左右直線彈道都能正確處理，不需要額外型別轉換）**

**Verify:** 每個Boss3個階段攻擊模式肉眼可辨不同，且階段2/3傷害或彈幕密度高於階段1

---

### Task 5.3: Boss戰場景 + 螢幕震動/粒子

**Objective:** 每個Boss關卡末尾場景，含入場動畫、螢幕震動反饋

**Files:**
- Create: `game/scenes/bosses/boss_arena_water.tscn`
- Create: `game/scripts/screen_shake.gd`

**Step 1:**
```gdscript
# game/scripts/screen_shake.gd (掛在Camera2D上)
extends Camera2D

func shake(duration: float, strength: float) -> void:
    var timer = 0.0
    var tween = create_tween()
    while timer < duration:
        offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
        await get_tree().create_timer(0.03).timeout
        timer += 0.03
    offset = Vector2.ZERO
```

**Verify:** Boss進入新階段/死亡時螢幕震動明顯，無卡頓或震動殘留（戰鬥結束offset歸零）

**階段五（一般Boss部分）完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase5a: boss base class, 3-phase state machine, 3 bosses with unique attacks, screen shake"
```

---

### Task 5.3b: 隱藏結局旗標契約複驗（Task 5.4 blocking gate）

**Objective:** Boss「仁」開工前複驗Task 4.0b已交付的`SaveSystem`契約；此Task不建立autoload，
只阻止Boss接到不存在、未持久化或另起一套的旗標上。階段六Task 6.3再於同一腳本擴充關卡索引與武器資料。

**Files:**
- Verify/Modify if needed: `game/scripts/save_system.gd`
- Verify/Modify if needed: `game/tests/test_save_system.gd`
- Do not modify: `game/project.godot`（Task 4.0b已註冊；此處不得重複新增或改名）

**Verify:** `SaveSystem`已載入且公開`has_ever_hoarded`／`mark_hoarded()`；以false舊存檔呼叫後，
記憶體與reload後都為true；再呼叫`set_checkpoint()`仍保持true。Task 5.4只能使用這一份API，
不得新增`GameState`或第二份同名旗標。任一條不成立就停止Boss實作，先回修Task 4.0b。

---

### Task 5.4: 終極Boss「仁」——雙元素三階段 + 敘事節點（本階段份量最重的Task）

**Objective:** 實作`docs/BOSS-仁.md`定義的完整終Boss戰：開場五連頭銜白 → Phase 1（水+火）→ Phase 2（金+木）→ **Phase 2.1「命」中途顯現（條件觸發）** → Phase 3（土+覺醒態，全五行）→ 「賜俸」簽名招式（Phase 1→2、Phase 2→3轉場各觸發一次）→ 擊敗後「主」取回亻 → 可選「命」最終抉擇 → 所有路線共用二的可操作歸還／消失尾聲

**前置依賴：** Task 4.0（對話框架，開場白／賜俸／Phase 2.1都要用）+ Task 4.0b（`SaveSystem`唯一旗標源）+ Task 5.1（Boss基類）+ Task 5.2（攻擊模式，仁需要同時複用全部五種）+ Task 5.3b（旗標契約複驗gate）+ `docs/PROTAGONIST-令.md`第5–6節（判定邏輯）。**不依賴**Task 5.3的screen_shake（可選複用，非必要）。

**Files:**
- Create: `game/scripts/boss_ren.gd` (`class_name BossRen`, `extends Boss`)
- Create: `game/data/boss_ren.json`
- Create: `game/scripts/shangfeng_coin.gd`（`class_name ShangfengCoin`，`extends Bullet`；實體拾取／彈反／閃避判定）
- Create: `game/scenes/projectiles/shangfeng_coin.tscn`（Integrator掛載；正面520、背面銘）
- Create: `game/tests/test_boss_ren.gd`、`game/tests/test_shangfeng_coin.gd`
- Modify: `game/data/dialogue/boss_ren_intro.json`（Task 4.0已建立；對齊最終五連頭銜白，不得另建同名檔）
- Create: `game/data/dialogue/boss_ren_shangfeng.json`（「賜俸」台詞）
- Create: `game/data/dialogue/boss_ren_phase21_ming.json`（Phase 2.1「命」顯現台詞）
- Modify: `game/data/dialogue/ending_zhu_descent.json`（Task 4.0已建立；把舊版「卸下」台詞改為「主」只劃清神器與責任，不包含赦免）
- Create: `game/data/dialogue/ending_ming_final.json`（僅`has_ever_hoarded == false`時出現的接受／放下選擇）
- Create: `game/data/dialogue/ending_two_epilogue.json`（祖母藥匣／父親作坊／空祭壇、三次語言縮減與歸還簿）
- Create: `game/scripts/ending_epilogue_controller.gd`（控制二的禁用能力狀態、三個Q節點與共同收尾）
- Modify: `game/tests/test_dialogue_data.gd`（新台詞schema／繁中／字形與舊版赦免措辭回歸）

**Step 1:** `boss_ren.json`資料結構（雙元素/階段，`sub_radicals`改為每階段一組陣列）：
```json
{
  "char": "仁",
  "element": "neutral",
  "hp": 600,
  "phases": 3,
  "phase_radicals": [
    ["水", "火"],
    ["金", "木"],
    ["土", "水", "火", "金", "木"]
  ],
  "shangfeng_before_phases": [2, 3],
  "shangfeng": {
    "coin_count": 12,
    "front_text": "520",
    "back_text": "銘",
    "fall_speed": 180.0,
    "lifetime": 4.0
  }
}
```

`front_text`／`back_text`是敘事契約，不是可隨意替換的裝飾字串：正面必須固定顯示`520`，
只有錢幣翻到背面時才顯示父親作坊的`銘`印。

**Step 2:** 建立真正的`ShangfengCoin` 2D投射物，而不是用對話選單或純粒子代替招式：

- `shangfeng_coin.tscn`根節點為`Area2D`並掛`shangfeng_coin.gd`，碰撞層沿用enemy bullet；
  兩個不鏡像的Label疊在同一位置，`Front.text == "520"`、`Back.text == "銘"`。
- `ShangfengCoin extends Bullet`，讓既有`MeleeAttack`的enemy-bullet即時形狀查詢能擋到它；
  但覆寫玩家碰撞結果，不造成一般傷害：碰到玩家送出`resolved("greed")`，被
  `MeleeAttack.bullet_blocked`命中時送出`resolved("fight")`，壽命結束且從未互動才送出
  `resolved("release")`。
- 翻面用2D縮放／時間相位表現：前半圈顯示520，`scale.x`收至0後切換背面銘再展開；
  不可水平鏡像漢字本身。金色`CPUParticles2D`只能做尾跡，不能承擔碰撞或分支判定。
- 每輪由`BossRen`生成12枚扇形下落錢幣並只接受第一個決定性互動：任一枚被拾取即「貪」，
  任一枚被彈反即「爭」；全部自然退場且玩家未碰、未彈才是「棄」。結果確定後清掉其餘錢幣，
  避免同一輪同時寫入兩個分支。

**Step 3:** `BossRen`繼承`Boss`，覆寫`enter_phase()`同時召喚雙元素攻擊，並插入實體「賜俸」與Phase 2.1觸發點：
```gdscript
# game/scripts/boss_ren.gd
extends Boss
class_name BossRen

@onready var dialogue_box: DialogueBox = get_tree().current_scene.get_node("DialogueBox")

const SHANGFENG_COIN_SCENE := preload("res://scenes/projectiles/shangfeng_coin.tscn")
const RADICAL_TO_ELEMENT := {"水": "water", "火": "fire", "金": "metal", "木": "wood", "土": "earth"}

var phase_radicals: Array = []
var shangfeng_before_phases: Array = []
var shangfeng_done_phases: Array = []  # 記錄已觸發過賜俸的phase轉場，避免重複觸發
var shangfeng_target_phase: int = 0
var shangfeng_config: Dictionary = {}
var active_shangfeng_coins: Array[ShangfengCoin] = []
var unresolved_shangfeng_coins: int = 0
var shangfeng_round_resolved: bool = false

func setup_boss_ren(data: Dictionary) -> void:
    setup(data)
    max_phases = int(data["phases"])
    phase_radicals = data["phase_radicals"]
    shangfeng_before_phases = data["shangfeng_before_phases"]
    shangfeng_config = data["shangfeng"].duplicate(true)

func _ready() -> void:
    super._ready()
    # DialogueBox缺檔時會同步emit，所有ONE_SHOT signal都必須先連、再開始播放。
    dialogue_box.dialogue_finished.connect(_on_intro_finished, CONNECT_ONE_SHOT)
    dialogue_box.play("boss_ren_intro")  # 開場五連頭銜白播完後才啟動Phase 1彈幕

    var player := get_tree().get_first_node_in_group(&"player") as Node
    var melee: MeleeAttack = null
    if player != null:
        melee = player.get_node_or_null(^"MeleeAttack") as MeleeAttack
    if melee != null:
        melee.bullet_blocked.connect(_on_player_blocked_bullet)

func _on_intro_finished() -> void:
    enter_phase(1)

func enter_phase(p: int) -> void:
    hanzi_label.flash_hit()
    # 轉場先完成賜俸，期間不混入下一階段的一般彈幕；實際行為結果落定後才開新phase。
    if p in shangfeng_before_phases and not p in shangfeng_done_phases:
        shangfeng_done_phases.append(p)
        shangfeng_target_phase = p
        call_deferred("_trigger_shangfeng")
        return
    _spawn_phase_patterns(p)

func _spawn_phase_patterns(p: int) -> void:
    var radicals = phase_radicals[p - 1] if p - 1 < phase_radicals.size() else phase_radicals[-1]
    for radical in radicals:
        # 「仁」的判定框刻意做「錯位」——色彩偏移+判定框比視覺框小10-15%，
        # 呼應docs/BOSS-仁.md第3節「名不副實」的視覺定位。具體shader參數由整合者調
        var attack_element: String = RADICAL_TO_ELEMENT.get(radical, "neutral")
        attack_patterns.spawn_phase_attack(p, radical, attack_element, global_position)

func _trigger_shangfeng() -> void:
    # 台詞播完才真正撒幣；這裡沒有play_choice，貪／爭／棄只由場上操作決定。
    dialogue_box.dialogue_finished.connect(_spawn_shangfeng_coins, CONNECT_ONE_SHOT)
    dialogue_box.play("boss_ren_shangfeng")

func _spawn_shangfeng_coins() -> void:
    shangfeng_round_resolved = false
    active_shangfeng_coins.clear()
    unresolved_shangfeng_coins = int(shangfeng_config.get("coin_count", 12))
    for i in range(unresolved_shangfeng_coins):
        var coin := SHANGFENG_COIN_SCENE.instantiate() as ShangfengCoin
        coin.resolved.connect(_on_shangfeng_coin_resolved)
        coin.setup_shangfeng(shangfeng_config, global_position, i, unresolved_shangfeng_coins)
        get_tree().current_scene.add_child(coin)
        active_shangfeng_coins.append(coin)

func _on_player_blocked_bullet(bullet: Node) -> void:
    if bullet is ShangfengCoin and active_shangfeng_coins.has(bullet):
        (bullet as ShangfengCoin).resolve(&"fight")

func _on_shangfeng_coin_resolved(result: StringName) -> void:
    if shangfeng_round_resolved:
        return
    if result == &"release":
        unresolved_shangfeng_coins -= 1
        if unresolved_shangfeng_coins > 0:
            return  # 「棄」必須等全部錢幣自然退場才成立
    shangfeng_round_resolved = true
    for coin in active_shangfeng_coins:
        if is_instance_valid(coin):
            coin.cancel_without_result()
    active_shangfeng_coins.clear()
    _apply_shangfeng_result(result)

func _apply_shangfeng_result(result: StringName) -> void:
    match result:
        &"greed":
            SaveSystem.mark_hoarded()
            # 立即增益 + 3秒後「人情壓頂」減益，具體buff/debuff數值見docs/BOSS-仁.md「實作備註」
        &"fight":
            SaveSystem.mark_hoarded()
            # 既有MeleeAttack判定精準彈反，觸發仁長硬直與承傷提升
        &"release":
            pass  # 純走位閃避，計入「風格分」

    _spawn_phase_patterns(shangfeng_target_phase)
    # 第一場賜俸結果完全落定後，仍未曾貪／爭者才看得到Phase 2.1。
    if shangfeng_target_phase == 2 and not SaveSystem.has_ever_hoarded:
        call_deferred("_trigger_ming_appearance")

func _trigger_ming_appearance() -> void:
    dialogue_box.choice_made.connect(_on_ming_choice, CONNECT_ONE_SHOT)
    dialogue_box.play_choice("boss_ren_phase21_ming", [
        {"id": "catch", "label": "接住"},
        {"id": "release", "label": "放手"}
    ])

func _on_ming_choice(choice_id: String) -> void:
    if choice_id == "catch":
        SaveSystem.mark_hoarded()
        # Phase 2剩餘時間傷害+30%/攻速+20%，Phase 3開場自動消散並解除，見docs/BOSS-仁.md「實作備註」
    # "release"：不做任何事，has_ever_hoarded維持false

func die() -> void:
    # 覆寫死亡流程：不走Enemy.die()的筆畫崩解特效，改播主取回亻過場
    var cutscene: CutscenePlayer = get_tree().current_scene.get_node("CutscenePlayer")
    cutscene.cutscene_finished.connect(_on_ending_finished, CONNECT_ONE_SHOT)
    cutscene.play_ending_zhu_descent()

func _on_ending_finished() -> void:
    if not SaveSystem.has_ever_hoarded:
        dialogue_box.choice_made.connect(_on_final_ming_choice, CONNECT_ONE_SHOT)
        dialogue_box.play_choice("ending_ming_final", [
            {"id": "accept", "label": "接受"},
            {"id": "release", "label": "放下"}
        ])
        return
    _open_two_epilogue()

func _on_final_ming_choice(choice_id: String) -> void:
    # accept：關卡端接cue把令顯示為「命」；release：保持「令」。沿用CutscenePlayer既有
    # play_steps API，直接await整段步驟，避免先播放、後等待而漏接同步完成signal。
    var cutscene: CutscenePlayer = get_tree().current_scene.get_node("CutscenePlayer")
    var cue_name := "ming_accept" if choice_id == "accept" else "ming_release"
    await cutscene.play_steps([
        {"type": "signal", "name": cue_name},
        {"type": "wait", "seconds": 1.0}
    ])
    _open_two_epilogue()

func _open_two_epilogue() -> void:
    get_tree().change_scene_to_file("res://scenes/levels/level_06_epilogue.tscn")
```

**⚠️ 注意：** `has_ever_hoarded`只有`SaveSystem`一個真相源；所有「貪／爭／接住」分支一律呼叫`SaveSystem.mark_hoarded()`並立即持久化，不得新增`GameState`或第二份同名旗標。Phase 2.1必須等待第一場賜俸結果落定後才判定資格。

**Step 4:** Boss場景節點結構（`level_05_final_altar.tscn`內的`BossRen`實例）：
```
BossRen (CharacterBody2D, script=boss_ren.gd, extends Boss)
├── HanziLabel (Label, text="仁")
├── BossAttackPatterns (Node, script=boss_attack_patterns.gd)
└── CollisionShape2D
```

**Verify:**
1. 進場自動播放開場五連頭銜白，播完後Phase 1（水+火雙元素彈幕）自動開始
2. Phase 1→2轉場由仁實際撒出12枚可碰撞錢幣；每枚正面清楚顯示「520」，縮至側面後才翻成背面的「銘」，任何時刻都不把漢字水平鏡像。不是以DialogueBox菜單代選
3. 同一輪實體錢幣三種行為分支正確：碰到任一枚判定貪（增益後3秒減益）；K近戰彈反任一枚判定爭（Boss長硬直）；全部錢幣自然退場才判定棄（風格分加成）。每輪恰好結算一次，貪／爭立即清除殘幣，棄不能由單枚漏接提前觸發
4. 第一場賜俸結果落定後，只有實際完成「棄」且`has_ever_hoarded`仍為false才觸發「命」中途顯現；選「接住」立即強化並持久化`true`，選「放手」無變化。貪／爭／接住任一條路都不得看見最終「命」選擇
5. Phase 2→3轉場再次實際撒出同一套520／銘錢幣，不得退化為選單或純粒子演出
6. Phase 3為全五行覺醒態，亻的傀儡線能辨認出二自己寫下的借據／頭銜；血量歸零後不播放一般筆畫崩解，改為`CutscenePlayer`播放主取回亻過場
7. `boss_ren_intro.json`與`ending_zhu_descent.json`是在原檔上修改；故意令台詞缺檔時仍能進入Phase 1，不會因先播放後連signal而永久卡住。主的現行台詞不得殘留舊版「卸下即釋懷／赦免」語意
8. 只有兩次賜俸均選棄、Phase 2.1選放手，主離場後才播放「命」最終選擇；接受時令清楚顯示為「命」，放下時保持「令」，兩段視覺不同但結束後均載入同一個`level_06_epilogue.tscn`
9. 尾聲中控制字為二且攻擊／拾取／融合停用；苓草能供活人使用但不改變空床，金能重鑄工具但不恢復「銘」，空物品欄的第三次Q顯示「沒有東西可以歸還」
10. 三次時間跳切後二的台詞由完整背出事實縮減到「還沒天明」，最終只以空凳與歸還簿呈現缺席，再跳轉victory_screen；任何路線都不出現受害者原諒或二完成救贖的演出

---

## 階段六：UI / 選單 / 音訊 / 存檔

### Task 6.1: 主選單 + 暫停選單

**Files:**
- Create: `game/scenes/ui/main_menu.tscn`
- Create: `game/scenes/ui/pause_menu.tscn`
- Create: `game/scripts/pause_menu.gd`

**Step 1:**
```gdscript
# game/scripts/pause_menu.gd
extends Control

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        get_tree().paused = not get_tree().paused
        visible = get_tree().paused
```

**Verify:** ESC鍵暫停/恢復遊戲，選單UI正確顯示/隱藏，暫停時敵人/子彈全部靜止

---

### Task 6.2: 武器圖鑑介面

**Objective:** 展示已解鎖的10個部首武器，含元素圖示和描述

**Files:**
- Create: `game/scenes/ui/weapon_codex.tscn`
- Create: `game/scripts/weapon_codex.gd`

**Verify:** 開啟圖鑑，10個武器條目全部按weapons.json資料渲染，元素顏色與階段二Task 2.4一致

---

### Task 6.3: 存檔系統 (SaveSystem)

**Objective:** 在Task 4.0b已建立、Task 5.3b已複驗的`SaveSystem`基礎切片上，擴充當前關卡與已解鎖武器；checkpoint路徑／座標與`has_ever_hoarded`已存在，只能擴充，不能另起一套

**Files:**
- Modify: `game/scripts/save_system.gd`（autoload已由Task 4.0b建立／註冊）
- Modify: `game/tests/test_save_system.gd`

**Step 1:**
```gdscript
extends Node

const SAVE_PATH = "user://savegame.json"

var has_ever_hoarded: bool = false  # 見docs/PROTAGONIST-令.md第5-6節：一旦在「賜俸」選貪/爭，或Boss戰
                                     # Phase 2.1「命」中途顯現選「接住」，永久標記為true，
                                     # 隱藏真結局資格自此鎖死；本場作用域內是記憶體變數，
                                     # 但必須隨save_game()一併寫入存檔，避免中途離線後重開遺失判定

func _ready() -> void:
    load_game()  # 保留Task 4.0b的啟動契約；不得延後到第一次開選單或手動讀檔才同步

func _read_save_data() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        return {}
    var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
    var text := f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func save_game(data: Dictionary) -> void:
    var snapshot := data.duplicate(true)
    snapshot["has_ever_hoarded"] = has_ever_hoarded
    var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(snapshot))
    f.close()

func load_game() -> Dictionary:
    var data := _read_save_data()
    has_ever_hoarded = bool(data.get("has_ever_hoarded", false))
    return data

func set_checkpoint(node_path: NodePath, pos: Vector2) -> void:
    var data := _read_save_data()
    data["checkpoint"] = {"path": str(node_path), "x": pos.x, "y": pos.y}
    data["level"] = LevelManager.current_level_index
    save_game(data)

func mark_hoarded() -> void:
    var data := _read_save_data()  # 先讀、不改記憶體，再設true；不可寫成save_game(load_game())
    has_ever_hoarded = true
    save_game(data)  # 立即持久化，Task 5.4的BossRen在「賜俸」／Phase 2.1選擇後直接呼叫本函式
```

**⚠️ 注意：** Task 5.4與本Task統一以`SaveSystem`為唯一真相源；Boss的「貪／爭／接住」分支只呼叫`mark_hoarded()`，不新增`GameState`autoload，也不直接維護第二份旗標。

**Step 2：** 確認Task 4.0b已在`project.godot`註冊`SaveSystem`；本Task不得重複新增另一個autoload或改名。

**Verify:** 存檔點觸發後關閉遊戲重開，從存檔點位置+對應關卡恢復，而非從頭開始；以舊存檔`has_ever_hoarded: false`呼叫`mark_hoarded()`後，立即與重載後都必須為true；預置true後重啟、未手動load就先觸發checkpoint也不得回寫false；在「賜俸」選擇「貪」後存檔重開仍為true

---

### Task 6.4: 音效/BGM接入

**Objective:** 接入免費素材庫音效+配樂，4個關卡各配BGM，武器/受擊/死亡音效

**Files:**
- Modify: 各武器/敵人/關卡場景，新增`AudioStreamPlayer2D`節點
- Download音效到 `game/assets/sfx/` 和 `game/assets/music/`

**Step 1:** 從Kenney.nl / Sonniss GDC包下載並歸類武器音效(10個)、受擊音效(1-2個通用)、死亡碎裂音效(1個)、4個關卡BGM、Boss戰BGM(1-3個可共用)

**Verify:** 每次開火/命中/死亡/切關都有對應音效，音量無爆音或明顯失衡

**階段六完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase6: main menu, pause, weapon codex, save system, audio integration"
```

---

## 階段七：Steamworks整合 + 打包匯出

### Task 7.0: 安裝 Godot Export Templates（阻斷性前置依賴）

**Objective:** 匯出Windows/Mac/Linux build需要對應的export templates（與Godot編輯器版本號完全一致），這是官方獨立分發的二進位包，體積約1.3GB，必須提前下載安裝，否則Task 7.4匯出會直接失敗報錯"範本未安裝"

> **整合者機器上此步驟已完成**（已安裝於 `%APPDATA%\Godot\export_templates\4.5.2.stable\`）。以下指令供其他機器或版本升級時使用。

**Step 1:**
```bash
# 確認目前使用的Godot確切版本號（含patch版本），應為 4.5.2.stable
godot4 --version

# 下載對應版本的export templates（版本號需與上一行輸出完全一致）
curl -sL -o /tmp/export_templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.5.2-stable/Godot_v4.5.2-stable_export_templates.tpz

# 解壓到Godot期望的路徑
#   Linux/WSL:  ~/.local/share/godot/export_templates/4.5.2.stable/
#   Windows:    %APPDATA%\Godot\export_templates\4.5.2.stable\
# .tpz實際上是zip格式，unzip可直接處理
mkdir -p ~/.local/share/godot/export_templates/4.5.2.stable/
unzip -q /tmp/export_templates.tpz -d /tmp/templates_extract/
cp -r /tmp/templates_extract/templates/* ~/.local/share/godot/export_templates/4.5.2.stable/

# 驗證：應輸出 4.5.2.stable
cat ~/.local/share/godot/export_templates/4.5.2.stable/version.txt
```

**Verify:** Godot編輯器選單 Editor > Manage Export Templates 顯示目前版本範本狀態為「已安裝」，而非「缺少範本」

---

### Task 7.1: GodotSteam外掛接入

**Objective:** 接入Steamworks成就/雲存檔基礎功能

> **⚠️ Step 1（外掛安裝）已在PR #2提前完成** —— 因為整合者機器設置時順手裝了。GodotSteam GDExtension 4.20.1已入版控並在`[editor_plugins]`啟用，已驗證`ClassDB.class_exists("Steam")`回傳`true`。
>
> **Step 2（`steam_appid.txt`）每台機器要自己建**——該檔案刻意不入版控（是Valve公開測試ID，正式App ID稽核透過後才替換），clone後需自行執行 `echo 480 > game/steam_appid.txt`。
>
> **Step 3以後（autoload、成就、雲存檔）尚未做**，仍是本Task的實際工作範圍。
>
> 另注意：入庫的外掛已裁剪非目標平臺二進位（見`game/addons/godotsteam/PLATFORMS-NOTE.md`），Task 7.3/7.4若要匯出Mac/Linux以外的平臺需先補回。

**Step 1:** 下載GodotSteam GDExtension外掛。

> **來源已變更：GodotSteam搬遷到Codeberg。** GitHub上的`GodotSteam/GodotSteam`現在只是指向Codeberg的空殼repo，其releases提供的是「重新編譯過的Godot引擎執行檔」，**不是**這裡要的`addons/godotsteam`外掛。外掛版只在Codeberg發布，tag以`-gde`結尾。
>
> 版本對應：本專案用Godot 4.5.2 → **GodotSteam GDExtension 4.20.1**（Steamworks 1.64，支援Godot 4.4+）。
>
> 整合者機器上已預先下載一份於 `C:\Tools\godotsteam\addons\godotsteam`，若在該機器操作可直接複製，跳過下載。

```bash
curl -sL -o /tmp/godotsteam.zip \
  https://codeberg.org/godotsteam/godotsteam/releases/download/v4.20.1-gde/godotsteam-4.20.1-gdextension-plugin-4.4.zip
# zip內已是 addons/godotsteam/... 結構，直接對著 game/ 解壓即可
unzip -q -o /tmp/godotsteam.zip -d game/
ls game/addons/godotsteam/godotsteam.gdextension
```

**Step 2（容易漏掉，本地測試連不上Steam的常見原因）：** 在`game/`專案根目錄（與`project.godot`同層，之後也要放在匯出build的.exe同層）建立`steam_appid.txt`，內容只有一行：
```
480
```
這個檔案讓Godot執行時能在**沒有透過Steam客戶端啟動遊戲**的情況下，也初始化Steamworks API（用測試App ID 480，Valve官方公開提供給所有開發者測試用，正式上架前需替換為真實App ID）。缺少這個檔案時，`Steam.steamInit()`在本地直接執行exe會靜默失敗。

**Step 3:**
```gdscript
# 在project.godot autoload加入 Steam.gd
extends Node
var app_id: int = 480  # 佔位測試ID，正式需替換為申請到的真實App ID

func _ready() -> void:
    Steam.steamInit()
    if Steam.isSteamRunning():
        print("Steam connected: ", Steam.getPersonaName())
    else:
        print("Steam未執行或steam_appid.txt缺失，成就/雲存檔功能將不可用")
```

**Verify:** 本地Steam客戶端執行時，遊戲啟動列印出Steam使用者名稱（用測試App ID 480驗證整合通路，正式AppID需等Steamworks稽核透過後替換）；確認`game/steam_appid.txt`檔案存在且內容正確

---

### Task 7.2: 成就系統接入（可選，視時間）

**Files:**
- Modify: Steam.gd，新增解鎖成就呼叫

**Step 1:**
```gdscript
func unlock_achievement(id: String) -> void:
    Steam.setAchievement(id)
    Steam.storeStats()
```

**Verify:** 通關第一關後呼叫`unlock_achievement("LEVEL_1_CLEAR")`，Steam客戶端成就面板顯示解鎖（需App ID已配置對應成就）

---

### Task 7.3: 匯出Windows Build

**Objective:** 生成可提交Steamworks的可執行檔案

**Files:**
- Create: `game/export_presets.cfg`

**前置依賴：** Task 7.0（export templates已安裝）

**Step 1:**
```bash
godot4 --headless --export-release "Windows Desktop" builds/windows/ironglyph.exe
```

**Step 2:** 把`steam_appid.txt`複製到build輸出目錄，與`.exe`同層：
```bash
cp game/steam_appid.txt builds/windows/steam_appid.txt
```

**Verify:** 生成的`.exe`在Wine或Windows環境下能正常啟動並進入主選單

**階段七完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase7: steamworks integration, export templates, windows build export"
```

---

## 階段八：全流程測試打磨 + Steam店鋪素材

> **調整說明：** 原計劃把「Steamworks接入」「全流程測試+bug修復」「build匯出」「店鋪素材」全部塞進同一階段，經review後拆分——手感/難度調優和完整通關測試往往比寫程式碼本身耗時更長，不應該和Steam技術整合擠在一起。現拆為階段七（技術整合+匯出）與階段八（測試打磨+上架準備）兩個獨立階段。

### Task 8.1: 全流程測試 + Bug修復

**Objective:** 從主選單到通關4關+3Boss+勝利畫面完整走一遍，記錄並修復阻斷性bug

**Step 1:** 製作測試checklist：
```
[ ] 主選單→開始遊戲→序章「字界殘頁」載入正常，引路者NPC對話與教學觸發正確
[ ] 10種武器切換、傷害剋制倍率生效（包含五行剋制的「剋」與「被剋」兩個方向都要試）
[ ] 20種敵人AI行為符合預期，無卡死/穿牆
[ ] 序章+4關全部可通關，存檔點正常；礦山關部件掉率提升肉眼可辨且無Boss戰觸發
[ ] 3個一般Boss戰（淼/焱/森）全部可擊敗，3階段轉換正常，血量邊界值不會跳過或重複觸發階段
[ ] 終極Boss「仁」完整流程：開場五連頭銜白→Phase 1（水+火）→仁實際撒出正面520／背面銘的錢幣彈幕（碰取＝貪、K彈反＝爭、全部閃避＝棄，三種實體行為各測一次，不使用選單代選）→Phase 2（金+木，藥盞／刻刀家庭意象）→Phase 2.1「命」中途顯現二選一（「接住」與「放手」各測一次，驗證`has_ever_hoarded`旗標正確寫入）→第二次實體「賜俸」→Phase 3（全五行覺醒態，自寫文字形成傀儡線）→擊敗後主取回亻
[ ] 結局共同尾聲：不符合隱藏條件者直接進入、符合者完成「命」接受／放下後進入同一個`level_06_epilogue.tscn`；控制二依序完成苓草、金、空物品欄三次Q，無攻擊／拾取／融合；時間跳切與歸還簿播放完才跳轉victory_screen
[ ] 隱藏真結局路徑：全程「賜俸」選棄＋Phase 2.1選放手，通關`has_ever_hoarded`應仍為false；接受／放下卩都只改變令，不跳過或改寫二的共同尾聲
[ ] 暫停選單、武器圖鑑正常開啟關閉
[ ] 音效/BGM無缺失或報錯
[ ] 存檔讀取在重啟後正確恢復（含`has_ever_hoarded`旗標持久化）
[ ] Steam連線狀態正常（本地測試環境，steam_appid.txt存在）
[ ] 子彈命中判定正常（bullet的area_entered訊號已連接，見Task 2.3）
```

**Verify:** checklist全部打勾，無Godot控制檯報錯（`godot4 --headless` 跑一遍場景載入檢查stderr為空）

**⚠️ 提醒：** 這一步在沒有GPU/display的agent環境裡只能做到"headless跑一遍場景載入不報錯"，真正的手感/視覺/難度曲線驗證需要在本地有display的Godot環境裡由人工完成——見專案README關於環境分工的說明。

---

### Task 8.2: Steam店鋪素材準備

**Objective:** 準備提交所需的最低素材集，**全部文字內容使用繁體中文**

**Files:**
- Create: `docs/steam_assets/` 存放膠囊圖、截圖、預告片腳本

**Step 1:** 錄製Task 8.1測試流程影片作為預告片素材基礎，用免費工具剪輯30-60秒預告
**Step 2:** 至少5張不同關卡/Boss戰截圖
**Step 3:** 完成IARC分級問卷（Steamworks後臺線上填寫，幾分鐘完成）
**Step 4:** 撰寫店鋪頁面文案（繁體中文）：遊戲簡介、特色條列、系統需求

**Verify:** Steamworks後臺「店鋪頁面」checklist無紅色缺失項，可提交稽核佇列

**階段七完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase7: steamworks integration, full playtest pass, windows build export"
git tag v0.1.0-milestone-complete
```

---

## 執行方式建議

按 `subagent-driven-development` 模式逐階段執行：每個階段作為一個批次，階段內的Task可視依賴關係並行或序列分派給subagent，每個Task完成後做spec compliance檢查（對照本計劃的Verify標準）+ 場景實際執行驗證。

**關鍵風險點（提前預警）：**
1. Task 1.2 資料集裁剪 — 需要你確認最終敵字/Boss字清單是否都在Make Me a Hanzi覆蓋範圍內（待驗證事項，見GDD.md第7節）
2. Task 3.4 筆畫崩解特效 — 視覺效果需要人工過目調整引數（飛散速度/碎片數量），不是純程式碼能一次到位的
3. Task 7.1 Steam App ID — 正式App ID需Steamworks稽核透過後才能拿到，階段七只能用測試ID(480)驗證整合通路，真正上線前需替換
4. 音效/BGM篩選（Task 6.4）— 免費庫素材質量參差，需要人工試聽挑選，不能完全交給AI自動選擇
5. **Task 5.4終極Boss「仁」— 本計劃份量最重的單一Task**，涉及對話框架（Task 4.0）、雙元素狀態機、三個戰中敘事節點（賜俸x2+Phase 2.1）、主取回亻與可操作共同尾聲，建議拆成「戰鬥數值／狀態機」「對話資料表」「結局演出／尾聲控制器」三個可並行的子任務分派給不同subagent，最後由整合者統一組裝，避免單一agent context塞爆
6. **Task 4.0對話框架是序章與終章共同的阻斷性前置依賴**，若延後開工會連帶卡住序章（Task 4.1a）與終章（Task 4.4/5.4）兩條線，建議在階段四一開工就優先排期

---

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-08-02 | **隨主線劇情v3同步實施計劃**：①序章至礦山加入不可漏收的家庭證物鏈與四份對話資料，森林加入完整配方`艹＋令→苓`；②Task 4.4新增不走LevelManager的`level_06_epilogue.tscn`；③Task 5.4加入正面520／背面銘的實體`ShangfengCoin`，貪／爭／棄由拾取／近戰彈反／全閃避決定而非選單，並把結局改為主只取回亻、可選「命」只影響令，之後所有路線控制二完成苓草／金／空物品欄三次Q並進入「還沒天明」語言循環；④Task 4.0b在首個checkpoint前建立唯一`SaveSystem`與隱藏旗標，Task 5.3b只做Boss接線前契約複驗，Task 6.3沿用並擴充；⑤Task 8.1新增共同尾聲與無赦免驗收，避免隱藏路線跳過二的後果 |
| 2026-08-01 | Task 4.0（對話／演出框架）完成。**草稿的 `DialogueBox` 有一個會讓遊戲永久卡死的錯誤**：`play()` 暫停整棵樹卻沒把對話框自己設成 `PROCESS_MODE_ALWAYS`，推進鍵與打字機跟著停擺，第一句話之後就再也動不了；另補上「結束時還原原本的暫停狀態」避免解除階段六的暫停選單。實作上補齊草稿只寫在文字裡的打字機（含「先補完整句、再換句」兩段式推進）、做出可直接用的選項UI（W/S移游標、J確認；選項是直向清單，實機驗證後新增`menu_up`/`menu_down`兩個action，A/D一併保留），並把 `CutscenePlayer` 從硬編函式改為「步驟資料＋cue signal」——特效由關卡端接cue，Task 4.4/5.4的白光與筆畫反向崩解不會反過來寫死進框架。新增 `test_dialogue_data.gd` 把台詞的schema／字型字形涵蓋／簡體字擋在CI（缺字形只會安靜顯示成豆腐方框，簡體字完全不報錯）。`test_room.tscn` 加上 T/Y/U 三個除錯捷徑供實機驗證 |
| 2026-07-30 | **隨主線劇情定版（`docs/STORY.md`/`docs/BOSS-仁.md`/`docs/PROTAGONIST-令.md`）同步更新開發計劃**：①階段四新增Task 4.0（對話/演出框架，阻斷性前置依賴）、Task 4.1a（序章「字界殘頁」教程關）、Task 4.4（終章「崩筆祭壇」關卡骨架）；Task 4.2礦山關明確定調為無Boss過渡關，改為稀有部件掉率提升；Task 4.3的LevelManager場景清單擴充為序章+4關+終章共6個場景，並補充終章結局分支不走一般`next_level()`流程的說明。②階段五新增Task 5.4（終極Boss「仁」完整實作：雙元素三階段、開場五連頭銜白、「賜俸」三選一x2、Phase 2.1「命」中途顯現、「主」降臨結局），標註為本計劃份量最重的單一Task；`bosses.json`與「仁」的資料表明確分離，避免schema混用。③Task 6.3的SaveSystem新增`has_ever_hoarded`隱藏結局判定旗標的讀寫與持久化，並註明與Task 5.4範例程式碼的`GameState`命名需在整合時對齊。④Task 8.1測試checklist新增序章教學、礦山關掉率、終Boss「仁」完整流程與隱藏結局路徑的驗收項。⑤執行方式建議新增兩項關鍵風險點（Task 5.4建議拆分並行、Task 4.0是雙向阻斷依賴需優先排期） |
| 2026-07-26 | 完成Task 2.6最小範圍設計：階段二功能擴充排在Phase 3與4之間；主角音核「令」使用單槽`CORE/FUSED/HELD`，starter recipe只收`雨＋令→零`與8方向水屬環形彈幕，其餘配方延後 |
| 2026-07-26 | 完成詳細實施計劃，共8個階段/33個Task，覆蓋核心系統到Steam打包全流程 |
| 2026-07-26 | 完成Task 2.5場景內武器字形顯示：使用世界座標元件監聽既有武器切換signal，按朝向換側但不鏡像，沿用元素配色並加入可取消的切換動畫；Task 2.6編號保留給部件組字與武器進化，避免顯示功能與玩法資料schema混在同一Task |
| 2026-07-26 | 修復邏輯bug：補上HanziData單例、資料集雙檔案欄位澄清、漢字不可鏡像翻轉設計修正、Input Map缺失、GUT安裝步驟、Enemy死亡競態條件、Boss階段公式、bullet訊號連接、Steam export templates/steam_appid.txt；移除「天」為單位的時間框架，改為流程階段劃分 |
| 2026-07-26 | Self-review後二次修復：`[autoload]`小節改為分階段追加註冊（原本一次性寫入尚未建立的`LevelManager`/`SaveSystem`會導致階段一`--check-only`失敗），移除"淼"字decomposition的錯誤示例資料（含自我循環定義），修正Task總數表述（28→33） |
| 2026-07-26 | 階段三完成（Task 3.1/3.2/3.3/3.4）。**Task 3.2 改了兩處結構**：①AI子節點原本自己呼叫 `apply_gravity`+`move_and_slide`，與本體重複移動，改為只回傳速度、由 `enemy.gd` 統一移動；②`take_damage()` 原本整套重寫傷害公式，會漏掉基類的 hp 夾值/訊號/死亡去重且要維護兩份，改為呼叫 `super()` 後判斷 `hp > 0` 才閃紅。**Task 3.4 的筆畫崩解改用真實筆畫**：原文灑通用碎片「﹒」，改用 Task 1.2 存的 medians 以 Line2D 逐筆畫出，「山」炸成3根、「巖」炸成23根。Task 3.3 資料表改靜態快取（原本每個生成器都重讀一次 JSON）。敵人子彈需改用 enemy_bullet 層且速度調慢，否則敵人互相誤傷且玩家閃不掉 |
| 2026-07-26 | 階段二完成（Task 2.1/2.2/2.3/2.4）。**修正一個會讓整個戰鬥系統失效的錯誤**：Task 2.3 的子彈用 `area_entered` 偵測命中，但 `Character` 繼承 `CharacterBody2D`（PhysicsBody2D），Area2D 的 `area_entered` 對 PhysicsBody2D 永遠不會觸發——照抄的結果是子彈能生成能飛但傷害永不結算。改用 `body_entered` 並直接判斷 `body is Character`。另補：子彈加存活上限（原本打空後永不釋放，會無限累積節點）與打到地形消失；`cycle_weapon()` 擋掉空武器清單避免除以零；子彈父節點在 `current_scene` 為 null 時退回場景樹根。五行倍率 1.5/0.6 沿用原文數值，標註為**待playtest調校的初始值**。Task 2.4 的顏色已做，後坐力/開火動畫留給整合者在有display的機器上調 |
| 2026-07-26 | 階段一完成（Task 1.3/1.3b/1.4/1.5/1.6）。**調整執行順序為 1.3b → 1.6 → 1.4 → 1.3 → 1.5**：1.3b自己標註為阻斷性前置依賴卻被排在依賴它的1.3之後，1.6同理（`player.tscn`要設`collision_layer`需先有層定義）。修正三處無效內容：①Task 1.4字型URL 404（目錄下的檔名是`NotoSansCJKtc-*`，改用5.6MB的`SubsetOTF/TC`繁中子集版）；②Task 1.3b的`Object(InputEventKey,...)`簡寫無法被解析，需列出完整屬性；③Task 1.3的`character.gd`直接呼叫尚未存在的`ElementSystem`與`WeaponManager`，改為執行期探測+中性倍率回退，階段二接上後自動生效。另新增`test_room.tscn`供Task 1.3的F5驗證，重力改讀ProjectSettings，補`hp_changed`/`died`訊號與死亡去重 |
| 2026-07-26 | Task 1.2/1.2b完成：資料集覆蓋率23/23。原字表的「燄」查無（「焰」的異體字，資料集只收「焰」），依決策不做近似字替換而移除，補上同屬火的「焚」維持每屬性4隻敵人對稱；「焚」拆解為`⿱林火`，「林」同為木屬性敵字，部首武器多一個跨屬性互動。Task 5.1敵人表同步更新。實作上把一次性程式碼片段抽成可重跑的`tools/build_hanzi_data.py`（內建覆蓋率檢查與下載快取），並多存`radical`/`medians`兩欄位供部首武器與崩解特效使用 |
| 2026-07-26 | Task 1.1實機執行後修正其指令錯誤：①Step 1的`godot4 --headless --path . --editor --quit`**無法從無到有生成`project.godot`**（該指令要求檔案已存在，Godot沒有建立專案的CLI），改為手動撰寫設定檔並補上`--import`步驟；②Verify的`--check-only`**不能單獨使用**（是修飾旗標，需搭配`-s <腳本>`），改用探測腳本讀回ProjectSettings驗證。另標註Task 2.0（GUT）與Task 7.1 Step 1（GodotSteam）已於PR #2提前完成，避免重複執行 |
| 2026-07-26 | 實機設置後修訂依賴版本與下載來源（原本的URL全部會失敗）：①引擎鎖定 **Godot 4.5.2**（原寫「4.3+」；GodotSteam現行外掛需4.4+，且整合者機器的RTX 5080晚於4.3發布）；②Task 7.1 GodotSteam來源改為 **Codeberg** 的`v4.20.1-gde`（GitHub repo已搬遷，其releases是引擎執行檔而非外掛，原URL不存在）；③Task 2.0 GUT改為指定 **9.5.0**（原用`releases/latest`會抓到對應Godot 4.7.x的版本；AssetLib上架版對應4.6.x，兩者都不相容4.5.2）；④Task 7.0 export templates URL更新為4.5.2並補上Windows路徑；⑤專案路徑改為整合者機器實際路徑 |
