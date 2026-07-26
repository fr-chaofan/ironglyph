# 《合金文字機甲》IRONGLYPH — Windows GPU開發機設置指南

> 本文件供**整合者(Integrator)角色**使用的機器參考（見`docs/COLLABORATION.md`第1節角色分工）。這台機器負責：原生執行Godot編輯器、Steam本地測試、AI coding agent（透過WSL2）、最終build打包。

**架構：WSL2 + 原生Windows雙環境並行**——Godot編輯器、Steam客戶端、GPU相關工作留在原生Windows；AI coding agent（Claude Code/Codex CLI）與Python腳本類工作放在WSL2的Ubuntu裡。兩邊透過檔案系統互通共用同一份專案程式碼，不需要在Windows和Linux之間反覆同步或重開機切換。

---

## 步驟一：確認GPU與顯示卡驅動

1. 打開裝置管理員確認顯示卡型號（NVIDIA/AMD/Intel）
2. 安裝最新官方驅動（NVIDIA用GeForce Experience或官網直接下載；AMD用Adrenalin）
3. 裝好後打開PowerShell執行 `dxdiag`，Display分頁確認驅動版本、「Direct3D加速」已啟用

**這一步很重要：** Godot 4預設用Vulkan渲染，驅動沒裝對會退化成軟體渲染，編輯器和遊戲畫面都會很卡。

**驗證：** 之後打開Godot編輯器時，右下角應顯示「Vulkan」或「Forward+」，而非「Compatibility(GLES3軟渲染)」。

---

## 步驟二：安裝 WSL2 + Ubuntu

以系統管理員身分打開 PowerShell：

```powershell
wsl --install -d Ubuntu-24.04
```

裝完重新啟動一次電腦。之後可透過以下任一方式進入Linux環境：

- 開始選單搜尋「Ubuntu」直接點開
- Windows Terminal頂部標籤頁下拉選單選「Ubuntu」
- 任何cmd/PowerShell裡直接輸入 `wsl`

首次進入需設定使用者名稱與密碼。之後：

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl build-essential python3 python3-pip python3-venv unzip
```

**啟用systemd**（避免關閉WSL視窗後背景服務就跟著死掉）：
```bash
sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[boot]
systemd=true
EOF
```

設定完在Windows端執行 `wsl --shutdown`，再重新打開Ubuntu讓設定生效。

**WSL2與Windows的檔案互通：**
- Windows存取Linux檔案：位址列輸入 `\\wsl$\Ubuntu\home\你的使用者名稱\`
- Linux存取Windows的C槽：路徑是 `/mnt/c/`

---

## 步驟三：Git與GitHub認證（在WSL2裡）

```bash
git config --global user.name "你的名字"
git config --global user.email "你的GitHub郵箱"
git config --global credential.helper store
```

用GitHub Personal Access Token（`repo`權限）做一次操作觸發認證，並把專案clone到Windows檔案系統（方便原生Godot也能開啟同一份檔案）：

```bash
git clone https://github.com/fr-chaofan/ironglyph.git /mnt/c/dev/ironglyph
# Username: fr-chaofan
# Password: 貼上 Personal Access Token（不是GitHub登入密碼）
```

以後Windows端（Godot編輯器等）直接指向 `C:\dev\ironglyph` 開啟即可，兩邊是同一份檔案，不需要重複clone或同步。

---

## 步驟四：安裝 Godot 4（原生Windows）

> **版本定案：Godot 4.5.2-stable**（原初版寫4.3，已改；理由見下方「版本選擇說明」）

1. 前往 https://godotengine.org/download/archive/4.5.2-stable/ 下載 **Godot 4.5.2 穩定版 Windows 64位元**（標準版即可，GDScript不需要.NET版本）
2. 解壓縮到固定位置，例如 `C:\Tools\Godot\`，執行檔可改名為`godot4.exe`方便命令列呼叫
3. 把該目錄加入系統PATH（系統內容 → 環境變數 → Path 新增該目錄），之後可在cmd/PowerShell直接輸入`godot4`啟動
4. 打開Godot編輯器一次，開啟`C:\dev\ironglyph\game`專案，確認右下角渲染器顯示Vulkan/Forward+

**下載Export Templates**（打包Windows/Steam build必需，體積約1.3GB）：
- Godot編輯器選單 Editor → Manage Export Templates → Download and Install，會自動抓取對應目前版本的範本
- 或手動下載 `Godot_v4.5.2-stable_export_templates.tpz`（其實是zip），解壓後把`templates/`底下全部檔案放到 `%APPDATA%\Godot\export_templates\4.5.2.stable\`，效果相同且不受編輯器下載節點速度影響

### 版本選擇說明（為何不用4.3）

初版文件寫Godot 4.3，實際設置時發現兩個問題，故改為4.5.2：

1. **GodotSteam外掛已不支援4.3。** 現行GDExtension版本（4.16以後）最低要求Godot 4.4；還支援4.3的最後一版是GodotSteam 4.15（Steamworks 1.62，已停止更新）。
2. **本機顯卡為RTX 5080（Blackwell架構），晚於Godot 4.3發布。** Blackwell相關的驅動修正在4.4之後才進入引擎。

實施計劃寫的是「Godot 4.3+」，且`game/`專案尚未建立，此時改版本零成本。選4.5.2而非最新的4.7.1，是因為GodotSteam的release明確以4.5.2為建置目標之一（v4.20.1 = Godot 4.7.1 / 4.5.2），相容性最有保障。

**（可選）VSCode + godot-tools擴充套件：**
- 安裝VSCode（原生Windows）+ **WSL擴充套件**（連接WSL2裡的檔案）+ **godot-tools擴充套件**（GDScript語法高亮/跳轉定義）
- Godot編輯器 Editor Settings 裡把外部編輯器設為VSCode，可視化編輯體驗更好

---

## 步驟五：GodotSteam 插件

> **注意：GodotSteam已從GitHub搬遷到Codeberg。** GitHub上的`GodotSteam/GodotSteam`現在只是一個指向Codeberg的空殼repo，其releases提供的是「重新編譯過的Godot引擎執行檔」，**不是**本專案要的`addons/godotsteam`外掛資料夾。外掛版（GDExtension）只在Codeberg發布，tag以`-gde`結尾。

1. 前往 https://codeberg.org/godotsteam/godotsteam/releases 找 **`v4.20.1-gde`**（標題為 "Godot 4.4+ - Steamworks 1.64 - GodotSteam GDExtension 4.20.1"），下載 `godotsteam-4.20.1-gdextension-plugin-4.4.zip`
2. 解壓縮後把`addons/godotsteam`整個資料夾複製到 `C:\dev\ironglyph\game\addons\godotsteam`（zip內已是`addons/godotsteam/...`結構，直接對著`game/`解壓即可）
3. Godot編輯器開啟專案後，Project Settings → Plugins，勾選啟用GodotSteam

---

## 步驟六：Steam客戶端 + 測試用App ID

1. 安裝Steam客戶端並登入開發者帳號
2. 在 `game/` 目錄（與`project.godot`同層）新建`steam_appid.txt`，內容只寫一行：
   ```
   480
   ```
   （Valve官方公開測試ID，讓本地不透過Steam客戶端啟動也能初始化Steamworks API）
3. 打包出來的build同樣要把這個檔案放在`.exe`同層（見實施計劃Task 7.1/7.3）

---

## 步驟七：GUT 測試框架

> **不要用AssetLib安裝。** GUT的版本與Godot版本嚴格對應，而AssetLib目前上架的是9.6.1（對應Godot 4.6.x），裝到我們的4.5.2上會出問題。**Godot 4.5.x對應的是GUT 9.5.0**，只能從GitHub取得。

1. 下載 https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip
2. 解壓後把`addons/gut`整個資料夾複製到 `C:\dev\ironglyph\game\addons\gut`
3. Godot編輯器 Project Settings → Plugins，勾選啟用Gut

GUT與Godot的版本對應表見 https://github.com/bitwes/Gut 的readme。**日後若升級Godot版本，GUT必須同步換版。**

---

## 步驟八：Node.js + AI Coding Agent CLI（在WSL2裡）

```bash
# 用nvm安裝Node.js（避免apt裝的版本太舊）
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts

# 安裝 Claude Code
npm install -g @anthropic-ai/claude-code
claude --version
claude auth login          # 瀏覽器OAuth登入，或 claude auth login --console 走API key計費

# 可選：同時安裝 Codex CLI
npm install -g @openai/codex
```

（Claude Code另有不依賴Node的原生安裝方式 `curl -fsSL https://claude.ai/install.sh | bash`，會裝到`~/.local/bin/claude`。本機用的就是原生版；但Node LTS仍建議裝著，Codex CLI與其他npm工具會用到。）

驗證：
```bash
cd /mnt/c/dev/ironglyph
claude doctor
```

---

## 步驟九：Python環境（供資料腳本使用）

```bash
cd /mnt/c/dev/ironglyph
python3 -m venv .venv
source .venv/bin/activate
pip install opencc-python-reimplemented
```

`opencc-python-reimplemented`用於繁簡轉換校對（全專案文字須為繁體，見GDD.md第0節語言規範）；之後階段一Task 1.2抓取Make Me a Hanzi資料集的腳本也在這個venv裡執行。

---

## 驗證清單

- [ ] `dxdiag` 確認GPU驅動正常，Direct3D加速已啟用
- [ ] Godot編輯器開啟專案，右下角渲染器顯示Vulkan/Forward+（非軟渲染）
- [ ] `godot4 --version` 回報 `4.5.2.stable`
- [ ] Export Templates已安裝（Editor → Manage Export Templates 顯示「已安裝」）
- [ ] GodotSteam外掛（GDExtension 4.20.1，來自Codeberg）已啟用，`steam_appid.txt`已放置於`game/`目錄
- [ ] GUT外掛（9.5.0，非AssetLib版本）已安裝啟用
- [ ] WSL2裡 `claude --version`、`git --version`、`python3 --version` 皆正常
- [ ] `git clone`到`C:\dev\ironglyph`成功，WSL2裡`/mnt/c/dev/ironglyph`能看到同樣檔案
- [ ] 用Godot開啟`game/`專案（階段一完成後）能實際執行看到畫面，F5能跑起來

---

## 這台機器在協作流程中的角色

依`docs/COLLABORATION.md`的分工，此機器完成設置後負責：

- 各Logic Worker（雲端/其他agent）提交PR合併後，**在此機器pull最新程式碼，把腳本掛載到場景節點上**（這一步無法自動化，需要有display環境操作）
- 手感/視覺參數調優（筆畫崩解速度、彈幕密度、鏡頭跟隨手感等）
- 完整通關的playtest驗證（見實施計劃Task 8.1）
- 最終Windows build打包 + Steam本地測試（Task 7.3、8.2）

---

## 為什麼選擇 WSL2 而非雙系統（Dual Boot）

決策記錄：曾評估雙系統（原生Linux）方案，優點是GPU效能更純粹、AI coding agent體驗最順暢；但雙系統需要重開機切換系統，無法同時使用，會打斷「改程式碼→立即在Godot看效果→調參數」這種高頻往返的工作流程，且最終Steam build仍以Windows為主要目標平台（見GDD.md第1節），需要一台隨時可用的原生Windows環境做最終驗證。WSL2能零重開機成本地同時使用兩邊，因此採用WSL2 + 原生Windows雙環境並行方案。

---

## 變更記錄

| 日期 | 變更 |
|---|---|
| 2026-07-26 | 初版：WSL2 + 原生Windows雙環境設置指南，涵蓋GPU驅動、Godot、GodotSteam、Steam測試、GUT、AI coding agent CLI、Python環境 |
| 2026-07-26 | 實機設置後修訂：①引擎版本 4.3 → **4.5.2**（GodotSteam現行外掛需4.4+，且本機RTX 5080晚於4.3發布）；②GodotSteam下載來源改為 **Codeberg** 的`-gde` release（GitHub repo已搬遷，其releases是引擎執行檔而非外掛）；③GUT改為手動安裝 **9.5.0**（AssetLib上架的9.6.1對應Godot 4.6.x，版本不符） |
