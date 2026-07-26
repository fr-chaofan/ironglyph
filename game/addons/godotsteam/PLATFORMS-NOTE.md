# 平臺二進位檔案已裁剪（本專案自行加入的說明，非上游檔案）

來源：GodotSteam GDExtension 4.20.1（Steamworks 1.64）
https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.20.1-gde

上游zip含全平臺二進位，共約94MB。依GDD第1節「目標平臺：Steam（PC，Windows優先，視時間可加Mac/Linux）」，
入庫時**移除了以下非目標平臺目錄**，減至約30MB：

| 已移除 | 原因 |
|---|---|
| `androidarm64/` (35MB) | 非目標平臺 |
| `win32/` (9.7MB) | 不支援32位元 |
| `linux32/` (11MB) | 不支援32位元 |
| `linuxarm64/` (9.3MB) | 非目標平臺 |

**保留：** `win64/`（主要目標）、`linux64/`（Logic Worker機器與CI）、`osx/`（GDD列為可能追加）、`editor/`

`godotsteam.gdextension`**未修改**，仍保有全平臺的路徑條目。這對已保留的平臺無影響
（Godot只載入當前平臺對應的條目）；但若日後要匯出到上表中已移除的平臺，
必須先重新下載上游zip補回對應目錄，否則匯出會找不到二進位檔。

補回方式：
```bash
curl -sL -o /tmp/godotsteam.zip \
  https://codeberg.org/godotsteam/godotsteam/releases/download/v4.20.1-gde/godotsteam-4.20.1-gdextension-plugin-4.4.zip
unzip -q -o /tmp/godotsteam.zip -d /tmp/gs
cp -r /tmp/gs/addons/godotsteam/<平臺目錄> game/addons/godotsteam/
```
