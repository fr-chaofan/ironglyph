# 《合金文字機甲》IRONGLYPH — 多AI協作規範

> 本文件定義多個AI agent（Claude Code / Codex / Hermes subagent等）如何在同一個Godot專案上並行協作而不互相破壞。

---

## 0. 為什麼Godot專案的多人協作比一般程式碼專案更容易衝突

在規劃協作方式前必須先理解一個Godot特有的風險：

- **`.tscn`場景檔案是純文字格式，但結構是巢狀節點樹+ 資源引用，Git的逐行diff/merge演算法對它效果很差。** 兩個agent若同時修改同一個`.tscn`（哪怕改的是完全不同的節點屬性），Git合併時很容易產生「合併後檔案語法正確但邏輯損毀」的結果——Godot編輯器打開時可能不報錯，但節點連接關係已經錯亂，這種問題極難debug。
- **`.tres`資源檔案、`project.godot`（尤其是`[autoload]`和`[input]`小節）也有類似風險**，多人同時新增autoload或input action時容易互相覆蓋。
- 相對安全、可以放心並行編輯的是：**純GDScript檔案(`.gd`)、JSON資料表(`weapons.json`/`enemies.json`等)、Markdown文件**——這些是純文字、逐行語意清晰，Git合併能正確處理。

**結論：任務拆分必須以「誰碰場景檔案/project.godot」為第一分割準則，而不是單純按功能模組分。**

---

## 1. 角色分工模型

採用「單一場景整合者 + 多個邏輯實作者」模式，而非讓所有agent平權地隨意修改任何檔案：

| 角色 | 職責 | 可修改檔案範圍 |
|---|---|---|
| **整合者 (Integrator)** | 唯一有權修改`.tscn`場景檔案、`project.godot`、`.tres`資源；負責把各個agent產出的`.gd`腳本掛載進場景、連接signal、配置節點屬性 | 全部 |
| **邏輯實作者 (Logic Worker)** | 只寫`.gd`腳本、JSON資料表；不碰場景檔案。每個worker負責一個獨立子系統 | 限定在自己負責的`scripts/`子目錄 + 對應`data/`檔案 |
| **文件/資料維護者 (Data & Docs Worker)** | 維護JSON資料表（`weapons.json`/`enemies.json`/`bosses.json`/`elements.json`）、GDD、實施計劃文件 | `data/*.json`、`docs/**` |
| **審查者 (Reviewer)** | 對每個PR做spec compliance + code quality兩階段審查（見`subagent-driven-development`技能），批准後才能合併 | 唯讀，僅留審查意見 |

**這個模型直接解決了上面提到的場景檔案合併地獄問題**：任何時刻只有一個agent（整合者）在改`.tscn`，其他人提交的都是純腳本/資料，衝突機率降到最低。

---

## 2. 模組所有權劃分（對應實施計劃的8個階段）

依實施計劃（`docs/plans/2026-07-26-implementation-plan.md`）的階段拆分模組邊界，每個模組指派給一個獨立agent/session，人格化命名便於在PR/commit裡追蹤：

| 模組 | 對應階段 | 負責檔案 | 依賴 |
|---|---|---|---|
| **核心角色系統** | 一 | `scripts/character.gd`, `scripts/player.gd`, `scripts/hanzi_sprite.gd`, `scripts/hanzi_data.gd`, `scripts/camera_bounds.gd` | 無（最先開工，其他模組依賴它） |
| **武器與五行系統** | 二 | `scripts/element_system.gd`, `scripts/weapon_manager.gd`, `scripts/bullet.gd`, `scripts/weapon_glyph_display.gd`, `data/weapons.json`, `data/elements.json` | 依賴核心角色系統的`Character`基類 |
| **音核合體與部件掉落** | 二（Task 2.6；Phase 3.5 gate） | `scripts/fusion_resolver.gd`, `scripts/glyph_loadout.gd`, `scripts/component_pickup.gd`, `scripts/component_dropper.gd`, `data/components.json`, `data/fusion_recipes.json`；在`data/enemies.json`只新增`drop_component_id` | 依賴武器系統 + 階段三的敵人死亡signal；必須在階段四前整合 |
| **敵人與AI** | 三 | `scripts/enemy.gd`, `scripts/enemy_ai_*.gd`, `scripts/enemy_spawner.gd`, `data/enemies.json` | 依賴核心角色系統 + 武器系統（`take_damage`介面） |
| **關卡系統** | 四 | `scripts/level_manager.gd`, `scripts/checkpoint.gd`, `data/`關卡相關設定 | 依賴敵人系統（放置EnemySpawner） |
| **Boss系統** | 五 | `scripts/boss.gd`, `scripts/boss_attack_patterns.gd`, `data/bosses.json`；終Boss「仁」額外負責 `scripts/boss_ren.gd`（Phase 2.1「命」機制、賜俸招式判定） | 依賴敵人系統（Boss繼承Enemy）+ 對話/演出框架（開場白、賜俸台詞、Phase 2.1選擇UI） |
| **對話／演出框架** | 四（序章／終章）+ 五（Boss台詞） | `scripts/dialogue_box.gd`, `scripts/cutscene_player.gd`, `data/dialogue/*.json`（各關卡/Boss台詞資料表，繁體中文） | 依賴核心角色系統（暫停玩家輸入時的介面）；序章教程NPC、仁的開場白／賜俸／Phase 2.1三選一、終章「主」降臨訓誡，共用同一套對話演出元件 |
| **UI與存檔** | 六 | `scripts/pause_menu.gd`, `scripts/weapon_codex.gd`, `scripts/save_system.gd`（含`has_ever_hoarded`隱藏結局旗標） | 依賴武器系統（圖鑑讀取weapons.json）|
| **Steam整合與打包** | 七、八 | `scripts/steam.gd`, `export_presets.cfg`, `steam_appid.txt` | 依賴全部模組（最後整合） |

**並行策略：** 「核心角色系統」必須第一個完成（其他所有模組都繼承`Character`或依賴`HanziData`/`ElementSystem`兩個autoload）。完成後，「武器系統」「敵人與AI」「UI與存檔」三個模組**互相獨立、可以完全並行**（它們互不依賴彼此的具體實作，只依賴核心角色系統暴露的介面）。「關卡系統」「Boss系統」需等敵人系統的`Enemy`基類穩定後才能開工。

### 2.1 Task 2.6本PR的Integrator邊界

Task 2.6會同時接上Player、武器、敵人死亡signal與測試場景，因此本PR指定**root agent為唯一
Integrator**。只有root可修改以下整合檔：

- `game/scenes/player.tscn`
- `game/scenes/component_pickup.tscn`
- `game/scenes/test_room.tscn`
- `game/project.godot`

Logic Worker只能修改自己被分派的`.gd`與測試，不能碰上述整合檔；本PR的JSON與產生器只由
被指定的單一Data Worker修改，文件維護者只改`docs/`。本PR完成前不得並行開始Phase 4的
場景／`LevelManager`整合，因為Phase 4也會依賴`Player`、`EnemySpawner`並修改
`project.godot`。第3.4節「不修改`.tscn` / `project.godot`」的自查項目適用於Logic/Data
Worker；Integrator在明確列出並獨占上述檔案時，可於同一整合PR完成掛載與Input Map修改。

### 2.2 Task 4.0本PR的Integrator邊界

Task 4.0 產出的是一個**新的**場景檔 `game/scenes/ui/dialogue_box.tscn`（不是修改既有場景），
新檔案沒有第0節說的合併地獄風險。但本PR同時要把對話框掛進測試場景才有辦法實機驗證，
因此一樣指定**root agent為唯一Integrator**，獨占以下整合檔：

- `game/scenes/ui/dialogue_box.tscn`（新增）
- `game/scenes/test_room.tscn`（掛載 DialogueBox / CutscenePlayer、更新HUD提示）

本PR**沒有**修改 `project.godot`：測試場景的三個除錯捷徑（T/Y/U）刻意用原始 keycode 而非
Input Action，正式玩法的推進／選項也一律沿用既有的 `fire` / `move_left` / `move_right`，
避免為了臨時驗證去動最容易互相覆蓋的 `[input]` 小節。後續 Task 4.1a／4.4／5.4 若需要
在正式關卡掛對話框，`dialogue_box.tscn` 直接 instance 即可，不需要再改本PR的任何檔案。

---

## 3. Git分支與PR流程

延續`github-pr-workflow`技能的標準流程，針對本專案做以下約定：

### 3.1 分支命名

```
feat/character-core       — 核心角色系統
feat/weapon-elemental     — 武器與五行系統
feat/weapon-glyph-display — Task 2.5 場景內武器字形顯示
feat/task-2.6-glyph-fusion — Task 2.6「令」× 部件vertical slice
feat/dialogue-framework   — Task 4.0 對話／演出框架
feat/enemy-ai             — 敵人與AI
feat/level-system         — 關卡系統
feat/boss-system          — Boss系統
feat/ui-save              — UI與存檔
feat/steam-integration    — Steam整合與打包
fix/<簡述>                — bug修復
docs/<簡述>                — 文件更新
```

### 3.2 每個Logic Worker的標準流程

```bash
git checkout main && git pull origin main
git checkout -b feat/weapon-elemental

# (agent在自己的分支上只寫 .gd 腳本 + .json 資料表，完全不碰 .tscn/project.godot)

git add game/scripts/element_system.gd game/scripts/weapon_manager.gd game/scripts/bullet.gd game/data/weapons.json game/data/elements.json
git commit -m "feat: implement five-element weapon system with radical-based weapons"
git push -u origin feat/weapon-elemental

gh pr create --title "feat: 部首武器 x 五行相剋系統" --body "實作Task 2.0-2.4，純腳本+JSON，未觸碰場景檔案"
```

### 3.3 PR審查與合併

- **強制走兩階段審查**（`subagent-driven-development`技能的spec compliance → code quality），由Reviewer角色的獨立agent session執行，不能自己審自己的PR
- 合併方式統一用 **squash merge**（保持main分支歷史整潔，每個模組一個commit）
- 合併後由**整合者**在自己的工作分支上pull最新`.gd`檔案，手動在Godot編輯器裡把腳本掛載到場景節點上（這一步無法自動化，必須有display環境的人工/agent操作）

### 3.4 衝突預防檢查清單（PR提交前自查）

- [ ] 本次提交沒有修改任何`.tscn`檔案
- [ ] 本次提交沒有修改`project.godot`的`[autoload]`或`[input]`小節（若必須新增autoload，先在協作頻道/Issue裡知會整合者）
- [ ] 新增的`.gd`檔案的`class_name`沒有和已存在的類別重名（開工前用`search_files(pattern="class_name X", path="game/scripts")`檢查）
- [ ] JSON資料表若是多人共改同一檔案（如`weapons.json`），改動前先`git pull`確認不是舊版本

---

## 4. 任務分派機制（用 delegate_task / cronjob 實現）

### 4.1 單次批量分派（適合當下就要並行推進的模組）

用`delegate_task`的批次模式（`tasks`陣列），把「武器系統」「敵人與AI」「UI與存檔」三個獨立模組同時分派給三個子agent：

- 每個task的`context`裡必須包含：
  1. 本模組在實施計劃裡的完整Task原文（不要讓subagent自己去讀取整份計劃文件，直接餵原文）
  2. 明確聲明「只能修改`scripts/`下自己負責的檔案和對應JSON，不能碰`.tscn`/`project.godot`」
  3. `Character`基類的介面簽名（`take_damage`, `element`, `hp`等），讓它知道如何跟核心系統對接
  4. Git分支名稱與PR提交指令

### 4.2 使用GitHub Issues追蹤任務狀態（可選，適合較長期協作）

若協作規模擴大到需要可視化追蹤，用`github-issues`技能在repo裡建立對應的Issue，每個Issue對應一個模組，標籤用：
- `module:core-character` / `module:weapon` / `module:enemy-ai` / `module:level` / `module:boss` / `module:ui-save` / `module:steam`
- `status:in-progress` / `status:review` / `status:blocked`（依賴未完成）/ `status:done`

### 4.3 CI基本檢查（強烈建議，防止低級錯誤流入main）

在repo設定一個GitHub Actions workflow，PR提交時自動跑：
1. Godot headless語法檢查：`godot4 --headless --path game --check-only`（捕捉GDScript語法錯誤）
2. 若有GUT測試（`element_system`等純邏輯模組），跑`godot4 --headless --path game -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
3. JSON資料表格式檢查（`python3 -c "import json; json.load(open('game/data/weapons.json'))"`，逐個資料檔跑一遍）

這一步能在合併前攔截掉「JSON格式寫錯」「GDScript語法錯誤」這類最常見、最容易被人工審查漏掉的低級錯誤。

---

## 5. 環境分工（銜接既有結論）

- **無GPU/display的agent環境**（本機/雲端sandbox）：適合承擔所有Logic Worker、Data Worker、Reviewer角色——這些工作只需要讀寫文字檔案、跑headless語法檢查，不需要看畫面
- **本地有display的Godot環境**（人工/未來若有帶GUI的agent）：承擔整合者角色——把腳本掛到場景節點、連接signal、調整視覺參數（筆畫崩解速度、彈幕密度手感等），以及最終的playtest驗證

這個分工與README、GDD裡已經記錄的「agent寫程式碼+跑headless測試，本地Godot實機驗證」結論一致，多AI協作只是把「agent寫程式碼」這一步進一步拆分給多個並行agent，整合與實機驗證仍然收斂到同一個地方完成。

---

## 6. 常見協作事故與預防

| 事故 | 原因 | 預防 |
|---|---|---|
| 兩個agent的PR都改了`weapons.json`，合併時互相覆蓋對方新增的武器項 | JSON是陣列，兩人在陣列尾端各自新增元素，Git按行合併時容易把其中一方整個刪掉或重複 | 修改共用JSON前，先`git pull`；若確定要並行新增，用有意義的順序約定（例如水系武器由worker A加、金系由worker B加，各自在陣列中間插入固定區塊而非都往尾端加） |
| Boss agent以為`Enemy.take_damage()`還是舊版邏輯（不含死亡競態修復），沿用了危險寫法 | 子agent context沒有帶上最新的核心類別程式碼 | 每次delegate_task前，把`Character`/`Enemy`基類的**最新**原始碼直接貼進context，而不是描述性文字 |
| 整合者發現兩個模組都定義了同名的`class_name` | 沒有提前檢查全域命名空間 | 開工前用`search_files`檢查現有`class_name`清單，建一份命名登記表（見下方） |
| Steam整合的autoload和UI模組的autoload在`project.godot`裡互相覆蓋 | 多人都在改`[autoload]`小節 | 只有整合者能碰`project.godot`，Logic Worker只需要在PR描述裡註明「需要新增autoload: XXX」，由整合者統一加 |

### 6.1 全域 class_name 命名登記表（開工前更新，避免重名）

| class_name | 定義檔案 | 所屬模組 |
|---|---|---|
| `Character` | `scripts/character.gd` | 核心角色系統 |
| `HanziSprite` | `scripts/hanzi_sprite.gd` | 核心角色系統 |
| `WeaponGlyphDisplay` | `scripts/weapon_glyph_display.gd` | 武器與五行系統 |
| `FusionResolver` | `scripts/fusion_resolver.gd` | 音核合體與部件掉落 |
| `GlyphLoadout` | `scripts/glyph_loadout.gd` | 音核合體與部件掉落 |
| `ComponentPickup` | `scripts/component_pickup.gd` | 音核合體與部件掉落 |
| `ComponentDropper` | `scripts/component_dropper.gd` | 音核合體與部件掉落 |
| `Enemy` | `scripts/enemy.gd` | 敵人與AI |
| `Boss` | `scripts/boss.gd` | Boss系統 |
| `BossAttackPatterns` | `scripts/boss_attack_patterns.gd` | Boss系統 |
| `BossRen` | `scripts/boss_ren.gd` | Boss系統（終Boss「仁」，繼承`Boss`） |
| `DialogueBox` | `scripts/dialogue_box.gd` | 對話／演出框架 |
| `CutscenePlayer` | `scripts/cutscene_player.gd` | 對話／演出框架 |

（新增`.gd`檔案含`class_name`時，先搜尋此表確認不重名，再補登記）

---

## 7. 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-08-01 | 加入Task 4.0協作邊界（第2.2節）：對話框場景是新增檔案而非修改既有場景，但掛進`test_room.tscn`仍由root獨占；本PR不動`project.godot`，對話推進／選項一律沿用既有Input Action，測試場景的除錯捷徑改用原始keycode |
| 2026-07-30 | 新增「對話／演出框架」模組（序章教程NPC、終Boss「仁」開場白/賜俸/Phase 2.1三選一、終章「主」降臨訓誡共用同一套元件），登記`DialogueBox`/`CutscenePlayer`/`BossRen`三個`class_name`；Boss系統模組職責擴充納入終Boss「仁」專屬腳本；UI與存檔模組補充`has_ever_hoarded`隱藏結局旗標職責 |
| 2026-07-26 | 加入Task 2.6協作邊界：新增音核合體／部件掉落模組與四個`class_name`；本PR由root擔任唯一Integrator並獨占`player.tscn`、`component_pickup.tscn`、`test_room.tscn`與`project.godot` |
| 2026-07-26 | 加入Task 2.5協作邊界：`weapon_glyph_display.gd`歸武器模組、使用`feat/weapon-glyph-display`分支，並登記`WeaponGlyphDisplay`全域類別名稱；`player.tscn`仍僅能由整合者修改 |
| 2026-07-26 | 初版：定義整合者/邏輯實作者/資料維護者/審查者四種角色，模組所有權劃分，Git分支與PR流程，任務分派機制，衝突預防清單 |
