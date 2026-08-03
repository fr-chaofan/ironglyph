# 背景素材授權

本目錄的圖像全部來自**明確標示 CC0 / Public Domain 的博物館開放資料**，
可免費商用、無需署名。授權狀態是透過館方 API 的 `isPublicDomain` 欄位
程式化驗證的，不是靠肉眼判斷「看起來很老應該沒問題」。

⚠️ **不可以**從搜尋引擎、Pinterest 之類的地方隨手抓圖。遊戲要上 Steam 販售，
素材授權出錯是會被下架的。標了 CC BY-NC（非商業）的同樣不能用。

| 檔案 | 作品 | 作者 | 年代 | 對應關卡 | 來源 | 授權 |
|---|---|---|---|---|---|---|
| `liuyu-landscape-1680.jpg` | Landscape（山水手卷） | 劉玉 Liu Yu | 1680 | 水域關 / 通用示例 | [The Met, 物件 49134](https://www.metmuseum.org/art/collection/search/49134) | CC0 Public Domain |
| `zhaoyuan-landscape-1400.jpg` | Landscape（山水手卷） | 趙原 Zhao Yuan | 14世紀晚期 | 火山關 | [The Met, 物件 45650](https://www.metmuseum.org/art/collection/search/45650) | CC0 Public Domain |
| `liuyanchong-bamboo-grove-1844.jpg` | Seven Sages of the Bamboo Grove（竹林七賢） | 劉彥沖 Liu Yanchong | 1844 | 森林關 | [The Met, 物件 737747](https://www.metmuseum.org/art/collection/search/737747) | CC0 Public Domain |
| `zhangruitu-red-cliff-1628.jpg` | Illustration of Su Shi's "Second Rhapsody on Red Cliff"（後赤壁賦圖） | 張瑞圖 Zhang Ruitu | 1628 | 礦山關 | [The Met, 物件 48969](https://www.metmuseum.org/art/collection/search/48969) | CC0 Public Domain |
| `unidentified-landscape-17c.jpg` | Landscape（山水手卷，無款） | 無款 Unidentified artist | 17世紀 | 終章「崩筆祭壇」 | [The Met, 物件 51701](https://www.metmuseum.org/art/collection/search/51701) | CC0 Public Domain |

館藏說明：
- `liuyu-landscape-1680.jpg`：Bequest of John M. Crawford Jr., 1988。紙本水墨手卷，26.4 × 508.6 cm。
- `zhaoyuan-landscape-1400.jpg`：Edward Elliott Family Collection, Purchase, The Dillon Fund Gift, 1981。紙本水墨手卷，畫芯 24.9 × 77.5 cm。
- `liuyanchong-bamboo-grove-1844.jpg`：Gift of Jane DeBevoise and the Calello Family, 2024。紙本水墨手卷，畫芯 31.8 × 457 cm。
- `zhangruitu-red-cliff-1628.jpg`：Bequest of John M. Crawford Jr., 1988。緞本水墨手卷，畫芯 27.9 × 320 cm。
- `unidentified-landscape-17c.jpg`：From the Collection of A. W. Bahr, Purchase, Fletcher Fund, 1947。絹本水墨手卷，36.5 × 177.2 cm。

## 為什麼選手卷

側向卷軸遊戲需要**橫向**構圖。立軸與扇面的比例都不合用；手卷本來就是
「一段一段往右展開」的觀看方式，與橫向捲動的視差背景是同一個道理。

純水墨（ink on paper/silk，無設色）優先於設色作品——設色的青綠山水會與五行彩墨搶顏色。

## 選材對應關卡設計文件

四張新增素材是按 `docs/LEVEL-DESIGN.md` 的關卡主題挑選：
- **火山關**選山峰題材（趙原《山水》），呼應山勢崢嶸的視覺定位
- **森林關**選竹林題材（劉彥沖《竹林七賢》），呼應「木」屬性關卡
- **礦山關**選崖壁題材（張瑞圖《後赤壁賦圖》，畫的正是江畔崖壁），呼應「金/土過渡關」的岩石地貌
- **終章祭壇**選無款山水（避免特定畫家風格的視覺聯想蓋過終Boss「仁」戰鬥場景本身），呼應設計文件「無五行歸屬的中性色調」要求

## 驗證方式

所有5個物件ID均已透過 The Met Collection API（`https://collectionapi.metmuseum.org/public/collection/v1/objects/{id}`）
程式化核對 `isPublicDomain: true`、`medium`欄位含"ink"且不含"color"/"gold"（純水墨、非設色）、
`medium`欄位含"Handscroll"（手卷形制），三項全部通過才收錄進本目錄。
