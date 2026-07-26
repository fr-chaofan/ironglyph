# 《合金文字機甲》IRONGLYPH — 7天實施計劃

> ⚠️ 語言規範：本專案所有文字內容一律使用繁體中文，詳見 `docs/GDD.md` 第0節。

> **For Hermes:** 用 subagent-driven-development 配合本計劃逐任務執行；遊戲開發驗證方式為"在Godot編輯器/匯出build中執行並目視確認"，而非pytest單元測試（除純邏輯模組如傷害計算外）。

**Goal:** 用 Godot 4 + GodotSteam，在7天內做出一個完整可玩、可提交Steam稽核的橫版闖關遊戲：主角/敵人為渲染漢字，武器基於部首拆解，五行相剋為核心平衡機制。

**Architecture:** 場景樹驅動的2D平臺/射擊架構。`Player`/`Enemy`共用基類`Character.gd`（繼承`CharacterBody2D`），漢字透過`Label`節點+自定義字型渲染而非Sprite2D精靈。武器/五行資料全部外接為`.tres`資源(Resource)或JSON，方便後續批次擴充而不改程式碼。關卡用Godot自帶`TileMap`+手擺場景。傷害計算走純函式（無節點依賴），可單元測試。

**Tech Stack:** Godot 4.3+ (GDScript), GodotSteam外掛, Make Me a Hanzi資料集(JSON), Noto Sans TC字型, Kenney.nl/OpenGameArt素材, Sonniss/freesound音效。

**專案路徑：** `/opt/data/home/projects/hanzi-runner-game/game/`

---

## Day 1: 專案骨架 + 核心移動 + 漢字渲染 + 鏡頭

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

### Task 1.2: 下載並接入 Make Me a Hanzi 資料集

**Objective:** 拿到"字→部首→筆畫路徑"資料，供後續所有漢字渲染/拆解使用

**Files:**
- Create: `game/data/hanzi_decomposition.json`（從makemeahanzi倉庫轉換/裁剪出專案需要的字）

**Step 1:** 抓取資料集（graphics.txt / dictionary.txt）：
```python
# 在agent環境執行，非Godot內
import urllib.request, json
url = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt"
urllib.request.urlretrieve(url, "/tmp/mmh_dictionary.txt")
```

**Step 2:** 轉換為專案用的精簡JSON（只保留立項需要的字集：見Task 2.1的敵字/武器表），存到`game/data/hanzi_decomposition.json`，結構：
```json
{
  "淼": {"decomposition": ["水","水","水"], "strokes": [...svg paths...]},
  "河": {"decomposition": ["氵","可"], "strokes": [...]}
}
```

**Verify:** `python3 -c "import json; d=json.load(open('game/data/hanzi_decomposition.json')); print(len(d))"` 輸出條目數 > 0

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
```gdscript
# game/scripts/player.gd
extends Character

@onready var hanzi_label: Label = $HanziLabel
@onready var weapon_manager: Node = $WeaponManager

func _physics_process(delta: float) -> void:
    apply_gravity(delta)

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

    var dir := Input.get_axis("move_left", "move_right")
    velocity.x = dir * speed
    if dir != 0:
        hanzi_label.scale.x = sign(dir) * abs(hanzi_label.scale.x)

    if Input.is_action_pressed("fire"):
        weapon_manager.fire()

    move_and_slide()
```

**Step 3:** 場景`player.tscn`節點結構：
```
Player (CharacterBody2D, script=player.gd)
├── CollisionShape2D
├── HanziLabel (Label, text="我", font=NotoSansTC, font_size=64)
├── WeaponManager (Node, script=weapon_manager.gd — Day 2建立)
└── Camera2D
```

**Verify:** F5執行場景，方向鍵移動、空格跳躍、"我"字左右翻轉跟隨方向

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
    # Day 3詳細實現：按筆畫拆分成多個Label碎片飛散
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

**Day 1 End-of-day commit:**
```bash
cd game && git init && git add -A && git commit -m "day1: project skeleton, hanzi rendering, player movement, camera"
```

---

## Day 2: 部首武器系統 + 五行相剋

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

func fire() -> void:
    if cooldown > 0.0:
        return
    var w = weapons[current_index]
    cooldown = w["fire_rate"]
    var bullet_scene = preload("res://scenes/projectiles/bullet_base.tscn")
    var bullet = bullet_scene.instantiate()
    bullet.setup(w["damage"], w["element"], get_parent().global_position, get_parent().hanzi_label.scale.x)
    get_tree().current_scene.add_child(bullet)
```

**Step 2:**
```gdscript
# game/scripts/bullet.gd
extends Area2D

var damage: int
var element: String
var speed: float = 500.0
var direction: float = 1.0

func setup(dmg: int, elem: String, spawn_pos: Vector2, dir: float) -> void:
    damage = dmg
    element = elem
    direction = dir
    global_position = spawn_pos

func _physics_process(delta: float) -> void:
    position.x += speed * direction * delta

func _on_area_entered(area: Node) -> void:
    if area.get_parent() is Character:
        area.get_parent().take_damage(damage, element)
    queue_free()
```

**Verify:** 按Q/E切換武器名在UI顯示變化（臨時debug label），按fire鍵生成子彈並飛行、命中測試假人扣血

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

**Day 2 End-of-day commit:**
```bash
git add -A && git commit -m "day2: radical weapon system, five-element damage calc, weapon switching"
```

---

## Day 3: 敵字系統 + AI + 死亡特效

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
    super.take_damage(amount, attacker_element)
    hanzi_label.flash_hit()

func die() -> void:
    hanzi_label.shatter_and_die()
    super.die()
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

**Step 1:** 利用Day1.2的筆畫SVG路徑資料，用`Line2D`或多個小`Label`模擬碎片：
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

**Day 3 End-of-day commit:**
```bash
git add -A && git commit -m "day3: enemy system, 4 AI behaviors, 20 enemy chars, shatter death effect"
```

---

## Day 4: 關卡設計（4關）

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

**Day 4 End-of-day commit:**
```bash
git add -A && git commit -m "day4: four themed levels, checkpoints, level manager"
```

---

## Day 5: Boss戰（3只複合字Boss）

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

var phase: int = 1
var max_phases: int = 3
var sub_radicals: Array = []

func setup_boss(data: Dictionary) -> void:
    setup(data)
    max_phases = data["phases"]
    sub_radicals = data["sub_radicals"]

func take_damage(amount: int, attacker_element: String) -> void:
    super.take_damage(amount, attacker_element)
    var phase_threshold = float(max_hp) / max_phases
    var expected_phase = max_phases - int(hp / phase_threshold)
    if expected_phase > phase and phase < max_phases:
        phase = expected_phase
        enter_phase(phase)

func enter_phase(p: int) -> void:
    hanzi_label.flash_hit()
    # 每階段召喚對應部首子彈幕，攻擊模式升級
    spawn_sub_radical_attack(sub_radicals[p - 1] if p - 1 < sub_radicals.size() else sub_radicals[-1])

func spawn_sub_radical_attack(radical: String) -> void:
    pass  # Task 5.2實現具體彈幕模式
```

**Verify:** Boss血量降到2/3、1/3閾值時觸發`enter_phase`，列印phase切換日誌確認閾值正確

---

### Task 5.2: 三種Boss彈幕/攻擊模式

**Objective:** 淼(水彈幕環形)、焱(火焰追蹤彈)、森(藤蔓地刺)，各階段強度遞增

**Files:**
- Create: `game/scripts/boss_attack_patterns.gd`

**Step 1（示例：淼的環形水彈）:**
```gdscript
func spawn_ring_attack(origin: Vector2, count: int, element: String) -> void:
    var bullet_scene = preload("res://scenes/projectiles/bullet_base.tscn")
    for i in range(count):
        var angle = (TAU / count) * i
        var bullet = bullet_scene.instantiate()
        bullet.setup_directional(15, element, origin, Vector2(cos(angle), sin(angle)))
        get_tree().current_scene.add_child(bullet)
```

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

**Day 5 End-of-day commit:**
```bash
git add -A && git commit -m "day5: boss base class, 3-phase state machine, 3 bosses with unique attacks, screen shake"
```

---

## Day 6: UI / 選單 / 音訊 / 存檔

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

**Verify:** 開啟圖鑑，10個武器條目全部按weapons.json資料渲染，元素顏色與Day2.4一致

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

**Day 6 End-of-day commit:**
```bash
git add -A && git commit -m "day6: main menu, pause, weapon codex, save system, audio integration"
```

---

## Day 7: 打磨 + Steamworks接入 + 打包

### Task 7.1: GodotSteam外掛接入

**Objective:** 接入Steamworks成就/雲存檔基礎功能

**Files:**
- Create: `game/addons/godotsteam/`（下載GodotSteam預編譯外掛）
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

**Step 2:**
```gdscript
# 在project.godot autoload加入 Steam.gd
extends Node
var app_id: int = 480  # 佔位測試ID，正式需替換為申請到的真實App ID

func _ready() -> void:
    Steam.steamInit()
    if Steam.isSteamRunning():
        print("Steam connected: ", Steam.getPersonaName())
```

**Verify:** 本地Steam客戶端執行時，遊戲啟動列印出Steam使用者名稱（用測試App ID 480驗證整合通路，正式AppID需等Steamworks稽核透過後替換）

---

### Task 7.2: 成就係統接入（可選，視時間）

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

### Task 7.3: 全流程測試 + Bug修復

**Objective:** 從主選單到通關4關+3Boss+勝利畫面完整走一遍，記錄並修復阻斷性bug

**Step 1:** 製作測試checklist：
```
[ ] 主選單→開始遊戲→關卡1載入正常
[ ] 4種武器切換、傷害剋制倍率生效
[ ] 20種敵人AI行為符合預期，無卡死/穿牆
[ ] 4關全部可通關，存檔點正常
[ ] 3個Boss戰全部可擊敗，3階段轉換正常
[ ] 暫停選單、武器圖鑑正常開啟關閉
[ ] 音效/BGM無缺失或報錯
[ ] 存檔讀取在重啟後正確恢復
[ ] Steam連線狀態正常（本地測試環境）
```

**Verify:** checklist全部打勾，無Godot控制檯報錯（`godot4 --headless` 跑一遍場景載入檢查stderr為空）

---

### Task 7.4: 匯出Windows Build

**Objective:** 生成可提交Steamworks的可執行檔案

**Files:**
- Create: `game/export_presets.cfg`

**Step 1:**
```bash
godot4 --headless --export-release "Windows Desktop" builds/windows/hanzi-runner.exe
```

**Verify:** 生成的`.exe`在Wine或Windows環境下能正常啟動並進入主選單

---

### Task 7.5: Steam店鋪素材準備（與開發並行，非阻斷項）

**Objective:** 準備提交所需的最低素材集

**Files:**
- Create: `docs/steam_assets/` 存放膠囊圖、截圖、預告片指令碼

**Step 1:** 錄製Day7測試流程影片作為預告片素材基礎，用免費工具剪輯30-60秒預告
**Step 2:** 至少5張不同關卡/Boss戰截圖
**Step 3:** 完成IARC分級問卷（Steamworks後臺線上填寫，幾分鐘完成）

**Verify:** Steamworks後臺"店鋪頁面"checklist無紅色缺失項，可提交稽核佇列

**Day 7 End-of-day commit:**
```bash
git add -A && git commit -m "day7: steamworks integration, full playtest pass, windows build export"
git tag v0.1.0-week1-complete
```

---

## 執行方式建議

按 `subagent-driven-development` 模式逐Day執行：每個Day作為一個批次，Day內的Task可視依賴關係並行或序列分派給subagent，每個Task完成後做spec compliance檢查（對照本計劃的Verify標準）+ 場景實際執行驗證。

**關鍵風險點（提前預警）：**
1. Task 1.2 資料集裁剪 — 需要你確認最終敵字/Boss字清單是否都在Make Me a Hanzi覆蓋範圍內（待驗證事項，見GDD.md第7節）
2. Task 3.4 筆畫崩解特效 — 視覺效果需要人工過目調整引數（飛散速度/碎片數量），不是純程式碼能一次到位的
3. Task 7.1 Steam App ID — 正式App ID需Steamworks稽核透過後才能拿到，Day7只能用測試ID(480)驗證整合通路，真正上線前需替換
4. 音效/BGM篩選（Task 6.4）— 免費庫素材質量參差，需要人工試聽挑選，不能完全交給AI自動選擇

---

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-07-26 | 完成7天詳細實施計劃，共7天/26個Task，覆蓋核心系統到Steam打包全流程 |
