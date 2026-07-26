# 部首闯字 (working title) — 7天实施计划

> **For Hermes:** 用 subagent-driven-development 配合本计划逐任务执行；游戏开发验证方式为"在Godot编辑器/导出build中运行并目视确认"，而非pytest单元测试（除纯逻辑模块如伤害计算外）。

**Goal:** 用 Godot 4 + GodotSteam，在7天内做出一个完整可玩、可提交Steam审核的横版闯关游戏：主角/敌人为渲染汉字，武器基于部首拆解，五行相克为核心平衡机制。

**Architecture:** 场景树驱动的2D平台/射击架构。`Player`/`Enemy`共用基类`Character.gd`（继承`CharacterBody2D`），汉字通过`Label`节点+自定义字体渲染而非Sprite2D精灵。武器/五行数据全部外置为`.tres`资源(Resource)或JSON，方便后续批量扩充而不改代码。关卡用Godot自带`TileMap`+手摆场景。伤害计算走纯函数（无节点依赖），可单元测试。

**Tech Stack:** Godot 4.3+ (GDScript), GodotSteam插件, Make Me a Hanzi数据集(JSON), Noto Sans TC字体, Kenney.nl/OpenGameArt素材, Sonniss/freesound音效。

**项目路径：** `/opt/data/home/projects/hanzi-runner-game/game/`

---

## Day 1: 项目骨架 + 核心移动 + 汉字渲染 + 镜头

### Task 1.1: 初始化Godot项目结构

**Objective:** 建立标准目录结构和project.godot配置

**Files:**
- Create: `game/project.godot`
- Create: `game/scenes/` `game/scripts/` `game/data/` `game/assets/fonts/` `game/assets/sfx/` `game/assets/art/`

**Step 1:** 用Godot 4命令行初始化项目（headless模式）：
```bash
mkdir -p game/scenes game/scripts game/data game/assets/{fonts,sfx,art,music}
cd game
godot4 --headless --path . --editor --quit  # 生成project.godot骨架
```

**Step 2:** 编辑`project.godot`设置窗口分辨率为横版闯关常见比例：
```ini
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[physics]
2d/default_gravity=980
```

**Verify:** `godot4 --headless --path . --check-only` 无报错

---

### Task 1.2: 下载并接入 Make Me a Hanzi 数据集

**Objective:** 拿到"字→部首→笔画路径"数据，供后续所有汉字渲染/拆解使用

**Files:**
- Create: `game/data/hanzi_decomposition.json`（从makemeahanzi仓库转换/裁剪出项目需要的字）

**Step 1:** 抓取数据集（graphics.txt / dictionary.txt）：
```python
# 在agent环境执行，非Godot内
import urllib.request, json
url = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt"
urllib.request.urlretrieve(url, "/tmp/mmh_dictionary.txt")
```

**Step 2:** 转换为项目用的精简JSON（只保留立项需要的字集：见Task 2.1的敌字/武器表），存到`game/data/hanzi_decomposition.json`，结构：
```json
{
  "淼": {"decomposition": ["水","水","水"], "strokes": [...svg paths...]},
  "河": {"decomposition": ["氵","可"], "strokes": [...]}
}
```

**Verify:** `python3 -c "import json; d=json.load(open('game/data/hanzi_decomposition.json')); print(len(d))"` 输出条目数 > 0

---

### Task 1.3: Character基类 + Player移动/跳跃/开火骨架

**Objective:** 横版角色控制器，支持左右移动、跳跃、开火输入

**Files:**
- Create: `game/scripts/character.gd`
- Create: `game/scripts/player.gd`
- Create: `game/scenes/player.tscn`

**Step 1:** 基类：
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

**Step 3:** 场景`player.tscn`节点结构：
```
Player (CharacterBody2D, script=player.gd)
├── CollisionShape2D
├── HanziLabel (Label, text="我", font=NotoSansTC, font_size=64)
├── WeaponManager (Node, script=weapon_manager.gd — Day 2创建)
└── Camera2D
```

**Verify:** F5运行场景，方向键移动、空格跳跃、"我"字左右翻转跟随方向

---

### Task 1.4: 字体渲染系统封装

**Objective:** 统一的"用汉字生成角色视觉"组件，供Player和所有Enemy复用

**Files:**
- Create: `game/scripts/hanzi_sprite.gd`
- Create: `game/assets/fonts/NotoSansTC-Bold.ttf`（下载思源黑体繁体版）

**Step 1:** 下载字体：
```bash
python3 -c "
import urllib.request
urllib.request.urlretrieve(
  'https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansTC-Bold.otf',
  'game/assets/fonts/NotoSansTC-Bold.otf')
"
```

**Step 2:** 封装组件（描边发光、受击抖动）：
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
    # Day 3详细实现：按笔画拆分成多个Label碎片飞散
    queue_free()
```

**Verify:** 场景内替换`character_text`，字形跟随变化，受击时短暂变红

---

### Task 1.5: 横版镜头跟随

**Objective:** Camera2D平滑跟随玩家，限制在关卡边界内

**Files:**
- Modify: `game/scenes/player.tscn`（Camera2D子节点配置）
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

**Verify:** 玩家移动到关卡边缘时镜头停止跟随，不露出关卡外空白

---

### Task 1.6: 基础碰撞层设置

**Objective:** 定义Player/Enemy/Bullet/Ground的物理层，避免后续碰撞漏判

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

**Verify:** Player碰撞层设为layer_2，只与layer_1/layer_3碰撞，检查Inspector面板配置正确

**Day 1 End-of-day commit:**
```bash
cd game && git init && git add -A && git commit -m "day1: project skeleton, hanzi rendering, player movement, camera"
```

---

## Day 2: 部首武器系统 + 五行相克

### Task 2.1: 五行相克数据表 + 纯逻辑单元测试

**Objective:** 建立`ElementSystem` autoload单例，五行克制倍率计算可独立测试

**Files:**
- Create: `game/scripts/element_system.gd` (autoload)
- Create: `game/data/elements.json`

**Step 1:** 数据表：
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

**Step 2:** 逻辑：
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

**Step 3 (test):** 用GUT测试框架（`addons/gut`）写纯逻辑测试：
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

**Verify:** `godot4 --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` 全部通过

---

### Task 2.2: 部首武器数据表（10个武器）

**Objective:** 定义资源化的武器数据，非硬编码

**Files:**
- Create: `game/data/weapons.json`

**Step 1:**
```json
[
  {"id":"shui","radical":"氵","element":"water","name":"水波弹","damage":8,"fire_rate":0.4,"projectile":"wave","range":"medium"},
  {"id":"huo","radical":"灬","element":"fire","name":"火球","damage":12,"fire_rate":0.6,"projectile":"fireball_aoe","range":"medium"},
  {"id":"jin","radical":"钅","element":"metal","name":"暗器","damage":6,"fire_rate":0.15,"projectile":"blade","range":"long"},
  {"id":"mu","radical":"木","element":"wood","name":"藤蔓刺","damage":10,"fire_rate":0.5,"projectile":"vine","range":"short"},
  {"id":"tu","radical":"土","element":"earth","name":"石撞","damage":15,"fire_rate":0.8,"projectile":"rock","range":"short"},
  {"id":"gong","radical":"弓","element":"neutral","name":"基础弓箭","damage":7,"fire_rate":0.3,"projectile":"arrow","range":"long"},
  {"id":"dao","radical":"刂","element":"neutral","name":"近战刀","damage":14,"fire_rate":0.35,"projectile":"melee","range":"melee"},
  {"id":"shou","radical":"扌","element":"neutral","name":"手雷","damage":20,"fire_rate":1.0,"projectile":"grenade_aoe","range":"medium"},
  {"id":"bing","radical":"冫","element":"water","name":"冰锥","damage":9,"fire_rate":0.45,"projectile":"ice_shard","range":"medium"},
  {"id":"shi","radical":"石","element":"earth","name":"碎石弹","damage":11,"fire_rate":0.5,"projectile":"pebble","range":"medium"}
]
```

**Verify:** JSON.parse_string成功加载10条记录

---

### Task 2.3: WeaponManager + 武器切换

**Objective:** Player持有的武器管理器，Q/E切换武器，读取weapons.json生成子弹

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

**Verify:** 按Q/E切换武器名在UI显示变化（临时debug label），按fire键生成子弹并飞行、命中测试假人扣血

---

### Task 2.4: 武器手感打磨（后坐力/开火动画/描边色）

**Objective:** 每种武器按五行有不同的颜色/粒子反馈，避免武器手感雷同

**Files:**
- Modify: `game/scripts/bullet.gd`（按element着色）

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

**Verify:** 10种武器子弹颜色区分明显，肉眼可辨认元素归属

**Day 2 End-of-day commit:**
```bash
git add -A && git commit -m "day2: radical weapon system, five-element damage calc, weapon switching"
```

---

## Day 3: 敌字系统 + AI + 死亡特效

### Task 3.1: 敌字数据表（20种）

**Objective:** 定义敌人字、五行归属、AI类型、血量/伤害

**Files:**
- Create: `game/data/enemies.json`

**Step 1:** 示例（完整20条，按5行×4个铺开）：
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
  {"char":"岩","element":"earth","ai":"stationary_aoe","hp":65,"damage":19,"speed":0},
  {"char":"石","element":"earth","ai":"chase_melee","hp":30,"damage":12,"speed":55},
  {"char":"山","element":"earth","ai":"patrol_ranged","hp":42,"damage":13,"speed":45},
  {"char":"塵","element":"earth","ai":"chase_melee","hp":20,"damage":6,"speed":140}
]
```

**Verify:** JSON加载20条，按element分组各4个

---

### Task 3.2: Enemy基类 + 三种AI行为树（巡逻/追击/远程/定点AOE）

**Objective:** 用状态机实现4种AI行为，数据驱动生成不同敌人

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

**Step 2 (巡逻AI示例，其余两种同结构不同逻辑):**
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

**Verify:** 场景内放置一个"河"敌人，运行后左右巡逻150px范围内往返

---

### Task 3.3: 敌人生成器 (EnemySpawner)

**Objective:** 关卡内按点位/波次生成敌人，从enemies.json按key取数据

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

**Verify:** 在关卡场景放5个EnemySpawner节点，各自设置不同enemy_char，运行后生成对应敌人且属性正确（打印hp/damage确认）

---

### Task 3.4: 笔画崩解死亡特效

**Objective:** 敌人死亡时字形按笔画拆散飞出，视觉爽感核心卖点

**Files:**
- Modify: `game/scripts/hanzi_sprite.gd`

**Step 1:** 利用Day1.2的笔画SVG路径数据，用`Line2D`或多个小`Label`模拟碎片：
```gdscript
func shatter_and_die() -> void:
    var strokes = HanziData.get_strokes(text)  # 从hanzi_decomposition.json取
    for stroke_path in strokes:
        var fragment = Label.new()
        fragment.text = "﹒"  # 简化：用笔画点位近似，或用Polygon2D渲染真实path
        fragment.global_position = global_position + Vector2(randf_range(-10,10), randf_range(-10,10))
        get_tree().current_scene.add_child(fragment)
        var tween = fragment.create_tween()
        var random_dir = Vector2(randf_range(-100,100), randf_range(-200,-50))
        tween.tween_property(fragment, "position", fragment.position + random_dir, 0.6)
        tween.parallel().tween_property(fragment, "modulate:a", 0.0, 0.6)
        tween.tween_callback(fragment.queue_free)
    queue_free()
```

**Verify:** 击杀敌人后原地字形消失，若干碎片飞散并淡出，无残留节点（用Godot远程场景树检查节点数不增长）

**Day 3 End-of-day commit:**
```bash
git add -A && git commit -m "day3: enemy system, 4 AI behaviors, 20 enemy chars, shatter death effect"
```

---

## Day 4: 关卡设计（4关）

### Task 4.1: TileMap关卡基础 — 水域关

**Objective:** 用Godot TileMap搭建第一关地形，含存档点

**Files:**
- Create: `game/scenes/levels/level_01_water.tscn`
- Create: `game/scripts/checkpoint.gd`
- Create: `game/assets/art/tileset_water.png`（从OpenGameArt/Kenney取水域主题tileset）

**Step 1:** 场景结构：
```
Level01 (Node2D)
├── TileMap (水域主题地形)
├── Background (Parallax2D，水域背景图)
├── PlayerSpawn (Marker2D)
├── EnemySpawners (Node2D, 多个EnemySpawner子节点，enemy_char设为河/海/湖/雨)
├── Checkpoints (Node2D, 多个Area2D+checkpoint.gd)
├── LevelExit (Area2D, 触发进入下一关)
└── CameraBounds (Rect2定义)
```

**Step 2:**
```gdscript
# game/scripts/checkpoint.gd
extends Area2D

func _on_body_entered(body: Node) -> void:
    if body is Player:
        SaveSystem.set_checkpoint(get_path(), global_position)
```

**Verify:** 玩家从PlayerSpawn开始，能走到LevelExit触发场景切换，中途经过Checkpoint触发存档

---

### Task 4.2: 火山关 / 森林关 / 矿山关

**Objective:** 复制Task 4.1结构，替换tileset美术+enemy_char+背景音乐，共3关

**Files:**
- Create: `game/scenes/levels/level_02_fire.tscn`
- Create: `game/scenes/levels/level_03_wood.tscn`
- Create: `game/scenes/levels/level_04_earth.tscn`

**Step 1:** 每关的EnemySpawner全部指向对应五行的敌字（火山关全用fire系4个字，以此类推），保证"关卡主题=五行区块"贯彻到底

**Verify:** 依次通关4关，每关敌人元素与关卡主题一致，武器克制策略在对应关卡内明显生效（用克制武器一击伤害肉眼可辨高于非克制武器）

---

### Task 4.3: 关卡管理器 LevelManager (autoload)

**Objective:** 统一管理关卡切换、存档点复活、关卡间过渡动画

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

**Verify:** LevelExit触发`LevelManager.next_level()`，4关顺序切换，最后一关后进入胜利画面

**Day 4 End-of-day commit:**
```bash
git add -A && git commit -m "day4: four themed levels, checkpoints, level manager"
```

---

## Day 5: Boss战（3只复合字Boss）

### Task 5.1: Boss基类 + 多阶段状态机

**Objective:** Boss不同于普通敌人——有阶段转换、拆解出子武器攻击玩家

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
    # 每阶段召唤对应部首子弹幕，攻击模式升级
    spawn_sub_radical_attack(sub_radicals[p - 1] if p - 1 < sub_radicals.size() else sub_radicals[-1])

func spawn_sub_radical_attack(radical: String) -> void:
    pass  # Task 5.2实现具体弹幕模式
```

**Verify:** Boss血量降到2/3、1/3阈值时触发`enter_phase`，打印phase切换日志确认阈值正确

---

### Task 5.2: 三种Boss弹幕/攻击模式

**Objective:** 淼(水弹幕环形)、焱(火焰追踪弹)、森(藤蔓地刺)，各阶段强度递增

**Files:**
- Create: `game/scripts/boss_attack_patterns.gd`

**Step 1（示例：淼的环形水弹）:**
```gdscript
func spawn_ring_attack(origin: Vector2, count: int, element: String) -> void:
    var bullet_scene = preload("res://scenes/projectiles/bullet_base.tscn")
    for i in range(count):
        var angle = (TAU / count) * i
        var bullet = bullet_scene.instantiate()
        bullet.setup_directional(15, element, origin, Vector2(cos(angle), sin(angle)))
        get_tree().current_scene.add_child(bullet)
```

**Verify:** 每个Boss3个阶段攻击模式肉眼可辨不同，且阶段2/3伤害或弹幕密度高于阶段1

---

### Task 5.3: Boss战场景 + 屏幕震动/粒子

**Objective:** 每个Boss关卡末尾场景，含入场动画、屏幕震动反馈

**Files:**
- Create: `game/scenes/bosses/boss_arena_water.tscn`
- Create: `game/scripts/screen_shake.gd`

**Step 1:**
```gdscript
# game/scripts/screen_shake.gd (挂在Camera2D上)
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

**Verify:** Boss进入新阶段/死亡时屏幕震动明显，无卡顿或震动残留（战斗结束offset归零）

**Day 5 End-of-day commit:**
```bash
git add -A && git commit -m "day5: boss base class, 3-phase state machine, 3 bosses with unique attacks, screen shake"
```

---

## Day 6: UI / 菜单 / 音频 / 存档

### Task 6.1: 主菜单 + 暂停菜单

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

**Verify:** ESC键暂停/恢复游戏，菜单UI正确显示/隐藏，暂停时敌人/子弹全部静止

---

### Task 6.2: 武器图鉴界面

**Objective:** 展示已解锁的10个部首武器，含元素图标和描述

**Files:**
- Create: `game/scenes/ui/weapon_codex.tscn`
- Create: `game/scripts/weapon_codex.gd`

**Verify:** 打开图鉴，10个武器条目全部按weapons.json数据渲染，元素颜色与Day2.4一致

---

### Task 6.3: 存档系统 (SaveSystem)

**Objective:** 记录当前关卡、存档点位置、已解锁武器

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

**Verify:** 存档点触发后关闭游戏重开，从存档点位置+对应关卡恢复，而非从头开始

---

### Task 6.4: 音效/BGM接入

**Objective:** 接入免费素材库音效+配乐，4个关卡各配BGM，武器/受击/死亡音效

**Files:**
- Modify: 各武器/敌人/关卡场景，添加`AudioStreamPlayer2D`节点
- Download音效到 `game/assets/sfx/` 和 `game/assets/music/`

**Step 1:** 从Kenney.nl / Sonniss GDC包下载并归类武器音效(10个)、受击音效(1-2个通用)、死亡碎裂音效(1个)、4个关卡BGM、Boss战BGM(1-3个可共用)

**Verify:** 每次开火/命中/死亡/切关都有对应音效，音量无爆音或明显失衡

**Day 6 End-of-day commit:**
```bash
git add -A && git commit -m "day6: main menu, pause, weapon codex, save system, audio integration"
```

---

## Day 7: 打磨 + Steamworks接入 + 打包

### Task 7.1: GodotSteam插件接入

**Objective:** 接入Steamworks成就/云存档基础功能

**Files:**
- Create: `game/addons/godotsteam/`（下载GodotSteam预编译插件）
- Modify: `game/scripts/save_system.gd`（加云存档同步）

**Step 1:**
```bash
python3 -c "
import urllib.request
urllib.request.urlretrieve(
  'https://github.com/GodotSteam/GodotSteam/releases/latest/download/godotsteam-gdextension.zip',
  '/tmp/godotsteam.zip')
"
# 解压到 game/addons/godotsteam/
```

**Step 2:**
```gdscript
# 在project.godot autoload加入 Steam.gd
extends Node
var app_id: int = 480  # 占位测试ID，正式需替换为申请到的真实App ID

func _ready() -> void:
    Steam.steamInit()
    if Steam.isSteamRunning():
        print("Steam connected: ", Steam.getPersonaName())
```

**Verify:** 本地Steam客户端运行时，游戏启动打印出Steam用户名（用测试App ID 480验证集成通路，正式AppID需等Steamworks审核通过后替换）

---

### Task 7.2: 成就系统接入（可选，视时间）

**Files:**
- Modify: Steam.gd，添加解锁成就调用

**Step 1:**
```gdscript
func unlock_achievement(id: String) -> void:
    Steam.setAchievement(id)
    Steam.storeStats()
```

**Verify:** 通关第一关后调用`unlock_achievement("LEVEL_1_CLEAR")`，Steam客户端成就面板显示解锁（需App ID已配置对应成就）

---

### Task 7.3: 全流程测试 + Bug修复

**Objective:** 从主菜单到通关4关+3Boss+胜利画面完整走一遍，记录并修复阻断性bug

**Step 1:** 制作测试checklist：
```
[ ] 主菜单→开始游戏→关卡1加载正常
[ ] 4种武器切换、伤害克制倍率生效
[ ] 20种敌人AI行为符合预期，无卡死/穿墙
[ ] 4关全部可通关，存档点正常
[ ] 3个Boss战全部可击败，3阶段转换正常
[ ] 暂停菜单、武器图鉴正常打开关闭
[ ] 音效/BGM无缺失或报错
[ ] 存档读取在重启后正确恢复
[ ] Steam连接状态正常（本地测试环境）
```

**Verify:** checklist全部打勾，无Godot控制台报错（`godot4 --headless` 跑一遍场景加载检查stderr为空）

---

### Task 7.4: 导出Windows Build

**Objective:** 生成可提交Steamworks的可执行文件

**Files:**
- Create: `game/export_presets.cfg`

**Step 1:**
```bash
godot4 --headless --export-release "Windows Desktop" builds/windows/hanzi-runner.exe
```

**Verify:** 生成的`.exe`在Wine或Windows环境下能正常启动并进入主菜单

---

### Task 7.5: Steam店铺素材准备（与开发并行，非阻断项）

**Objective:** 准备提交所需的最低素材集

**Files:**
- Create: `docs/steam_assets/` 存放胶囊图、截图、预告片脚本

**Step 1:** 录制Day7测试流程视频作为预告片素材基础，用免费工具剪辑30-60秒预告
**Step 2:** 至少5张不同关卡/Boss战截图
**Step 3:** 完成IARC分级问卷（Steamworks后台在线填写，几分钟完成）

**Verify:** Steamworks后台"店铺页面"checklist无红色缺失项，可提交审核队列

**Day 7 End-of-day commit:**
```bash
git add -A && git commit -m "day7: steamworks integration, full playtest pass, windows build export"
git tag v0.1.0-week1-complete
```

---

## 执行方式建议

按 `subagent-driven-development` 模式逐Day执行：每个Day作为一个批次，Day内的Task可视依赖关系并行或串行分派给subagent，每个Task完成后做spec compliance检查（对照本计划的Verify标准）+ 场景实际运行验证。

**关键风险点（提前预警）：**
1. Task 1.2 数据集裁剪 — 需要你确认最终敌字/Boss字清单是否都在Make Me a Hanzi覆盖范围内（待验证事项，见GDD.md第7节）
2. Task 3.4 笔画崩解特效 — 视觉效果需要人工过目调整参数（飞散速度/碎片数量），不是纯代码能一次到位的
3. Task 7.1 Steam App ID — 正式App ID需Steamworks审核通过后才能拿到，Day7只能用测试ID(480)验证集成通路，真正上线前需替换
4. 音效/BGM筛选（Task 6.4）— 免费库素材质量参差，需要人工试听挑选，不能完全交给AI自动选择

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-07-26 | 完成7天详细实施计划，共7天/26个Task，覆盖核心系统到Steam打包全流程 |
