# 《合金文字機甲》 IRONGLYPH

繁體漢字橫版闖關遊戲，類似合金彈頭(Metal Slug)。核心機制：主角/敵人以渲染漢字呈現，武器來自漢字部首拆解，五行相生相剋驅動傷害平衡。

> ⚠️ **語言規範：本專案所有文字內容（UI、對話、關卡文字、字形渲染、圖鑑說明、Steam店鋪頁面）一律使用繁體中文，不使用簡體字。** 詳見 `docs/GDD.md` 第0節「語言規範」。

## 專案狀態

🚧 規劃階段 — 引擎已定案，詳細實施計劃已完成，尚未開始編碼。

## 引擎

**Godot 4 + GodotSteam**（詳見 `docs/GDD.md` 第3節 引擎決策）

## 文件

- [`docs/GDD.md`](docs/GDD.md) — 遊戲設計文件：語言規範、核心玩法、五行部首武器系統、引擎選型對比、成本估算、Steam上架計劃
- [`docs/plans/2026-07-26-implementation-plan.md`](docs/plans/2026-07-26-implementation-plan.md) — 詳細實施計劃，8個階段、33個任務，含完整程式碼示例
- [`docs/COLLABORATION.md`](docs/COLLABORATION.md) — 多AI協作規範：分支策略、任務分派、模組所有權、程式碼審查流程
- [`docs/SETUP-WINDOWS.md`](docs/SETUP-WINDOWS.md) — Windows GPU開發機設置指南（WSL2 + 原生Windows雙環境，供整合者角色使用）
- [`docs/STORY.md`](docs/STORY.md) — 劇情設計文件：世界觀、主角「令」的角色弧光、章節流程表
- [`docs/BOSS-仁.md`](docs/BOSS-仁.md) — 終極Boss「仁」完整設計：起源設定、三階段戰鬥機制、簽名招式、結局演出

## 核心玩法

| 部首 | 五行 | 武器型別 | 剋制 |
|---|---|---|---|
| 氵/水 | 水 | 水波/範圍減速 | 剋火 |
| 火/灬 | 火 | 火球/噴射AOE | 剋金 |
| 釒/金 | 金 | 利刃/高攻速暗器 | 剋木 |
| 木 | 木 | 藤蔓/控制刺擊 | 剋土 |
| 土 | 土 | 撞擊/防禦反彈 | 剋水 |

Boss為複合字（淼/焱/森），拆解出多個部首子武器，多階段戰鬥。

## 目標

- 開發出完整可玩版本（4關+3 Boss，10種部首武器，20種敵字）
- 提交Steam審核

## 協作模式

本專案採用多AI agent協作開發，詳見 [`docs/COLLABORATION.md`](docs/COLLABORATION.md)。核心原則：模組化任務拆分、分支隔離、強制程式碼審查後合併。

## 已知風險 / 待驗證事項

見 `docs/GDD.md` 第7節和實施計劃末尾「關鍵風險點」，包括：
- 生僻字Boss是否在Make Me a Hanzi資料集覆蓋範圍內（且需確認該資料集能否提供繁體字形，而非簡體）
- 開發環境無GPU/display，程式碼驗證與視覺/手感驗證需要分工（agent寫程式碼+跑headless測試，本地Godot實機驗證）
- Steam正式App ID需審核透過後才能拿到
