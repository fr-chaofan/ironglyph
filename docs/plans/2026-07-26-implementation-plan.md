# 《合金文字機甲》IRONGLYPH — 實施計劃

> ⚠️ 語言規範：本專案所有文字內容一律使用繁體中文，詳見 `docs/GDD.md` 第0節。

> **For Hermes:** 用 subagent-driven-development 配合本計劃逐任務執行；遊戲開發驗證方式為"在Godot編輯器/匯出build中執行並目視確認"，而非pytest單元測試（除純邏輯模組如傷害計算外）。

**Goal:** 用 Godot 4 + GodotSteam，做出一個完整可玩、可提交Steam稽核的橫版闖關遊戲：主角/敵人為渲染漢字，武器基於部首拆解，五行相剋為核心平衡機制。

**Architecture:** 場景樹驅動的2D平臺/射擊架構。`Player`/`Enemy`共用基類`Character.gd`（繼承`CharacterBody2D`），漢字透過`Label`節點+自定義字型渲染而非Sprite2D精靈。武器/五行資料全部外接為`.tres`資源(Resource)或JSON，方便後續批次擴充而不改程式碼。關卡用Godot自帶`TileMap`+手擺場景。傷害計算走純函式（無節點依賴），可單元測試。

**Tech Stack:** Godot 4.3+ (GDScript), GodotSteam外掛, Make Me a Hanzi資料集(JSON), Noto Sans TC字型, Kenney.nl/OpenGameArt素材, Sonniss/freesound音效。

**專案路徑：** `/opt/data/home/projects/ironglyph/game/`

---

## 階段一：專案骨架 + 核心移動 + 漢字渲染 + 鏡頭

### Task 1.1: 初始化Godot專案結構

**Objective:** 建立標準目錄結構和project.godot配置

**Files:**
- Create: `game/project.godot`
- Create: `game/scenes/` `game/scripts/` `game/data/` `game/assets/fonts/` `game/assets/sfx/` `game/assets/art/`

**Step 1:** 用Godot 4命令列初始化專案（headless模式）：
```bash
mkdir -p game/scenes game/scripts game/data game/assets/{fonts,sfx,art,music}
cd game
godot4 --headless --path . --editor --quit  # 生成project.godot骨架
```

**Step 2:** 編輯`project.godot`設定視窗解析度為橫版闖關常見比例：
```ini
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[physics]
2d/default_gravity=980
```

**Verify:** `godot4 --headless --path . --check-only` 無報錯

---

### Task 1.2: 下載並接入 Make Me a Hanzi 資料集 + 建立 HanziData 單例

**Objective:** 拿到"字→部首→筆畫路徑"資料，供後續所有漢字渲染/拆解使用。**注意：Make Me a Hanzi實際是兩個檔案**——`dictionary.txt`（含character/decomposition/pinyin/radical等欄位）和`graphics.txt`（含strokes筆畫SVG路徑、medians中軸點），兩者需分別抓取再合併，欄位不要混淆。

**Files:**
- Create: `game/data/hanzi_decomposition.json`（合併後的精簡JSON）
- Create: `game/scripts/hanzi_data.gd` (autoload單例，命名為`HanziData`)

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

needed_chars = set("我淼焱森河海湖雨焰炎灶燄鋼針劍錘樹藤林巖石山塵")  # 從Task 2.1/3.1/5.1字表彙總

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

**Step 2:** 結構範例（`decomposition`是拆解字串如"⿰氵可"，`strokes`是SVG path字串陣列）：
```json
{
  "淼": {"decomposition": "⿱水淼", "strokes": ["M123,45 ... Z", "..."]},
  "河": {"decomposition": "⿰氵可", "strokes": ["M67,89 ... Z", "..."]}
}
```

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
ElementSystem="*res://scripts/element_system.gd"
LevelManager="*res://scripts/level_manager.gd"
SaveSystem="*res://scripts/save_system.gd"
```
（`ElementSystem`/`LevelManager`/`SaveSystem`在階段二/四/六建立時對應加入，此處先佔位統一管理，避免後續各Task各自為政漏掉autoload註冊）

**Verify:** `python3 -c "import json; d=json.load(open('game/data/hanzi_decomposition.json')); print(len(d))"` 輸出條目數 > 0；Godot內執行`print(HanziData.get_strokes("淼"))`能列印出非空陣列

**⚠️ 風險提示：** 若`needed_chars`中有字在Make Me a Hanzi資料集找不到（生僻Boss字常見問題），`merged[ch]`會得到空陣列——必須在這一步就跑一次覆蓋率檢查（見下方Task 1.2b），而不是等到階段三/五用到時才發現。

---

### Task 1.2b: 資料集覆蓋率驗證（阻斷性檢查，必須在階段一完成）

**Objective:** 確認所有計劃使用的敵字/Boss字都能在Make Me a Hanzi資料集中查到，且字形為繁體

**Step 1:**
```python
import json

needed_chars = "我淼焱森河海湖雨焰炎灶燄鋼針劍錘樹藤林巖石山塵"
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

**Files:**
- Create: `game/scripts/character.gd`
- Create: `game/scripts/player.gd`
- Create: `game/scenes/player.tscn`

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

**Files:**
- Create: `game/scripts/hanzi_sprite.gd`
- Create: `game/assets/fonts/NotoSansTC-Bold.ttf`（下載思源黑體繁體版）

**Step 1:** 下載字型：
```bash
python3 -c "
import urllib.request
urllib.request.urlretrieve(
  'https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansTC-Bold.otf',
  'game/assets/fonts/NotoSansTC-Bold.otf')
"
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

### Task 2.0: 安裝 GUT 測試框架（Task 2.1單元測試的前置依賴）

**Objective:** Task 2.1要用GUT寫純邏輯單元測試，必須先安裝這個外掛，否則`-s addons/gut/gut_cmdln.gd`會找不到檔案

**Files:**
- Create: `game/addons/gut/`

**Step 1:** 下載GUT外掛（GitHub Release zip）：
```python
import urllib.request, zipfile, os

urllib.request.urlretrieve(
    "https://github.com/bitwes/Gut/releases/latest/download/gut.zip",
    "/tmp/gut.zip")
with zipfile.ZipFile("/tmp/gut.zip") as z:
    z.extractall("/tmp/gut_extract")
# 解压后找到addons/gut目录，复制到game/addons/gut/
os.makedirs("game/addons", exist_ok=True)
# 具体路径视zip内部结构而定，通常是 /tmp/gut_extract/addons/gut
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

**Step 3 (test):** 用GUT測試框架（`addons/gut`）寫純邏輯測試：
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

**階段二完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase2: radical weapon system, five-element damage calc, weapon switching"
```

---

## 階段三：敵字系統 + AI + 死亡特效

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
  {"char":"燄","element":"fire","ai":"chase_melee","hp":38,"damage":13,"speed":95},
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

## 階段四：關卡設計（4關）

### Task 4.1: TileMap關卡基礎 — 水域關

**Objective:** 用Godot TileMap搭建第一關地形，含存檔點

**Files:**
- Create: `game/scenes/levels/level_01_water.tscn`
- Create: `game/scripts/checkpoint.gd`
- Create: `game/assets/art/tileset_water.png`（從OpenGameArt/Kenney取水域主題tileset）

**Step 1:** 場景結構：
```
Level01 (Node2D)
├── TileMap (水域主題地形)
├── Background (Parallax2D，水域背景圖)
├── PlayerSpawn (Marker2D)
├── EnemySpawners (Node2D, 多個EnemySpawner子節點，enemy_char設為河/海/湖/雨)
├── Checkpoints (Node2D, 多個Area2D+checkpoint.gd)
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

**Verify:** 玩家從PlayerSpawn開始，能走到LevelExit觸發場景切換，中途經過Checkpoint觸發存檔

---

### Task 4.2: 火山關 / 森林關 / 礦山關

**Objective:** 複製Task 4.1結構，替換tileset美術+enemy_char+背景音樂，共3關

**Files:**
- Create: `game/scenes/levels/level_02_fire.tscn`
- Create: `game/scenes/levels/level_03_wood.tscn`
- Create: `game/scenes/levels/level_04_earth.tscn`

**Step 1:** 每關的EnemySpawner全部指向對應五行的敵字（火山關全用fire系4個字，以此類推），保證"關卡主題=五行區塊"貫徹到底

**Verify:** 依次通關4關，每關敵人元素與關卡主題一致，武器剋制策略在對應關卡內明顯生效（用剋制武器一擊傷害肉眼可辨高於非剋制武器）

---

### Task 4.3: 關卡管理器 LevelManager (autoload)

**Objective:** 統一管理關卡切換、存檔點復活、關卡間過渡動畫

**Files:**
- Create: `game/scripts/level_manager.gd` (autoload)

**Step 1:**
```gdscript
extends Node

var levels: Array = [
    "res://scenes/levels/level_01_water.tscn",
    "res://scenes/levels/level_02_fire.tscn",
    "res://scenes/levels/level_03_wood.tscn",
    "res://scenes/levels/level_04_earth.tscn"
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

**Verify:** LevelExit觸發`LevelManager.next_level()`，4關順序切換，最後一關後進入勝利畫面

**階段四完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase4: four themed levels, checkpoints, level manager"
```

---

## 階段五：Boss戰（3隻複合字Boss）

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

**階段五完成後提交（milestone commit）：**
```bash
git add -A && git commit -m "phase5: boss base class, 3-phase state machine, 3 bosses with unique attacks, screen shake"
```

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

**Objective:** 記錄當前關卡、存檔點位置、已解鎖武器

**Files:**
- Create: `game/scripts/save_system.gd` (autoload)

**Step 1:**
```gdscript
extends Node

const SAVE_PATH = "user://savegame.json"

func save_game(data: Dictionary) -> void:
    var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(data))

func load_game() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        return {}
    var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
    return JSON.parse_string(f.get_as_text())

func set_checkpoint(node_path: String, pos: Vector2) -> void:
    var data = load_game()
    data["checkpoint"] = {"path": node_path, "x": pos.x, "y": pos.y}
    data["level"] = LevelManager.current_level_index
    save_game(data)
```

**Verify:** 存檔點觸發後關閉遊戲重開，從存檔點位置+對應關卡恢復，而非從頭開始

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

**Objective:** 匯出Windows/Mac/Linux build需要對應的export templates（與Godot編輯器版本號完全一致），這是官方獨立分發的二進位包，體積約1-2GB，必須提前下載安裝，否則Task 7.4匯出會直接失敗報錯"範本未安裝"

**Step 1:**
```bash
# 確認目前使用的Godot確切版本號（含patch版本，如4.3.0.stable）
godot4 --version

# 下載對應版本的export templates（範例為4.3.0，需按實際版本替換URL）
python3 -c "
import urllib.request
urllib.request.urlretrieve(
    'https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz',
    '/tmp/export_templates.tpz')
"

# 解壓到Godot期望的路徑（Linux下通常是 ~/.local/share/godot/export_templates/4.3.stable/）
mkdir -p ~/.local/share/godot/export_templates/4.3.stable/
unzip /tmp/export_templates.tpz -d /tmp/templates_extract/
cp -r /tmp/templates_extract/templates/* ~/.local/share/godot/export_templates/4.3.stable/
```

**Verify:** Godot編輯器選單 Editor > Manage Export Templates 顯示目前版本範本狀態為「已安裝」，而非「缺少範本」

---

### Task 7.1: GodotSteam外掛接入

**Objective:** 接入Steamworks成就/雲存檔基礎功能

**Files:**
- Create: `game/addons/godotsteam/`（下載GodotSteam預編譯外掛）
- Create: `game/steam_appid.txt`（**本地測試必需**，內容僅一行`480`）
- Modify: `game/scripts/save_system.gd`（加雲存檔同步）

**Step 1:**
```bash
python3 -c "
import urllib.request
urllib.request.urlretrieve(
  'https://github.com/GodotSteam/GodotSteam/releases/latest/download/godotsteam-gdextension.zip',
  '/tmp/godotsteam.zip')
"
# 解壓到 game/addons/godotsteam/
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
[ ] 主選單→開始遊戲→關卡1載入正常
[ ] 10種武器切換、傷害剋制倍率生效（包含五行剋制的「剋」與「被剋」兩個方向都要試）
[ ] 20種敵人AI行為符合預期，無卡死/穿牆
[ ] 4關全部可通關，存檔點正常
[ ] 3個Boss戰全部可擊敗，3階段轉換正常，血量邊界值不會跳過或重複觸發階段
[ ] 暫停選單、武器圖鑑正常開啟關閉
[ ] 音效/BGM無缺失或報錯
[ ] 存檔讀取在重啟後正確恢復
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

---

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-07-26 | 完成詳細實施計劃，共8個階段/28個Task，覆蓋核心系統到Steam打包全流程 |
| 2026-07-26 | 修復邏輯bug：補上HanziData單例、資料集雙檔案欄位澄清、漢字不可鏡像翻轉設計修正、Input Map缺失、GUT安裝步驟、Enemy死亡競態條件、Boss階段公式、bullet訊號連接、Steam export templates/steam_appid.txt；移除「天」為單位的時間框架，改為流程階段劃分 |
