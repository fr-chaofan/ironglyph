# 地形貼圖素材說明

本目錄的5張地形貼圖（`water_ground.png` / `fire_ground.png` / `wood_ground.png` /
`earth_ground.png` / `altar_ground.png`）是**程式化生成的過渡佔位圖**，
不是神經網路AI繪圖模型的產物——當前環境沒有配置任何可用的圖像生成API
（無OpenAI/Stability/Midjourney等），因此改用`gen_tileset.py`（Pillow+NumPy）
以周期性Perlin/fBm噪聲＋Voronoi紋理程式化合成。

## 規格

- 512×512px，PNG
- 顏色嚴格取自 `game/data/palette.json` 的 `paper`/`paper_shade`/`elements`欄位
- **可無縫平鋪（tileable）**：邊界像素差已驗證與內部相鄰像素差同量級，
  可直接用於Godot TileMap橫向鋪滿整個關卡
- 色調驗證：5張圖的RGB均值皆落在暖色宣紙調（均值0.71-0.87區間），
  與純黑底或高飽和卡通色的距離足夠遠，符合`docs/GDD.md`第2.3節宣紙底規範

## 對應關卡

| 檔案 | 關卡 | 疊加色調 |
|---|---|---|
| `water_ground.png` | 水域關 | 淡靛藍水波紋 |
| `fire_ground.png` | 火山關 | 淡朱砂裂紋/岩紋 |
| `wood_ground.png` | 森林關 | 淡石綠木紋/苔蘚感 |
| `earth_ground.png` | 礦山關 | 淡藤黃岩層/石塊感 |
| `altar_ground.png` | 終章「崩筆祭壇」 | 淡焦墨中性色調，無五行歸屬 |

## ⚠️ 待辦：升級為正式美術資源

這批圖是**臨時佔位資源**，用於場景搭建階段（Task 4.1a/4.1/4.2/4.4）先把
TileMap跑起來、驗證關卡尺寸與碰撞邏輯，不代表最終上線品質。正式美術資源
應優先考慮：

1. 接入真正的圖像生成API（Stable Diffusion/Midjourney等）重新生成，或
2. 從 `Kenney.nl` / `OpenGameArt.org` 取用CC授權的水墨風tileset素材
   （`docs/GDD.md`第3.2節已列為候選來源），或
3. 委託人工美術繪製

`gen_tileset.py`保留在本目錄，若暫時沿用程式化方案，調整某關墨色濃淡/
紋理密度可直接修改對應`gen_xxx()`函式的強度參數重新生成，不需要改核心
噪聲/平鋪邏輯。

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-08-03 | 初版：程式化生成5張關卡地形貼圖佔位資源，配合`docs/LEVEL-DESIGN.md`關卡設計定案 |
