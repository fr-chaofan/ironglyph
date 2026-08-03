#!/usr/bin/env python3
"""從 Make Me a Hanzi 資料集擷取本專案用到的漢字，合併成 game/data/hanzi_decomposition.json。

Make Me a Hanzi 實際是兩個檔案，欄位不同，需分別讀取再合併：
  - dictionary.txt : character / decomposition / radical / pinyin
  - graphics.txt   : character / strokes(SVG path陣列) / medians(中軸點)

用法（在 repo 根目錄，需先 source .venv/bin/activate 或直接用 .venv/bin/python）：
    python3 tools/build_hanzi_data.py

同時執行實施計劃 Task 1.2b 的覆蓋率檢查：資料集查不到、或查到但缺筆畫資料的字
一律**跳過不寫入**（專案決策：缺字直接捨棄，不做近似字替換），並在輸出中列出。
"""

import json
import os
import sys
import urllib.request

# 從實施計劃 Task 2.1 / 3.1 / 5.1 與字形融合系統的字表彙總
#
# 「燄」原在此表，但Make Me a Hanzi查無此字（它是「焰」的異體字，資料集只收「焰」）。
# 依專案決策不做近似字替換而是移除，並補上同為火屬性、資料集有收錄的「焚」以維持
# 每屬性4隻敵人的對稱（⿱林火，其部首「林」同時也是木屬性敵字，部首武器機制可跨屬性互動）。
# 形聲合體字（令為聲符）：泠苓鈴柃。這些是 `令 + 部件` 的真字，
# 不是外掛偏旁——見 data/fusion_recipes.json。
#
# ⚠️ 繁體沒有「山＋令」的字：「嶺」是 ⿱山領（領才是 ⿰令頁），
# 「岭」只作為「嶺」的簡化形存在。因此山屬部件無法融合，維持外置手持。
NEEDED_CHARS = "我令零淼焱森河海湖雨焰炎灶焚鋼針劍錘樹藤林巖石山塵泠苓鈴柃"

# ─── 組字：資料集沒收錄的合體字，用部件的筆畫自己拼出來 ───
#
# 「坽炩砱刢」四個字生僻到 Make Me a Hanzi 沒有收錄，但它們的**部件都有筆畫資料**。
# 既然本專案的字形是用 medians 畫成 Line2D 筆畫（不是交給字型平塗），就可以自己把字拼出來
# ——形聲字本來就是拼出來的，這正是「字界」的立意。
#
# ⚠️ 附帶好處：**字型缺不缺變得無關緊要**。「炩」與「刢」不在霞鶩文楷裡，
#    但我們從不用字型畫它們，因此不必為了它們換字型。
#
# ⚠️ 代價：拼出來的字比資料集的真字略遜——真正的偏旁會變形（提土旁末筆上挑、
#    火字旁末筆收短），這裡只是把原字壓窄。遠看過得去，並排細看得出來。
#
# 每筆：(合體字, 左/上部件, 右/下部件, 版面)
COMPOSED_CHARS = [
    ("坽", "土", "令", "left_right"),
    ("炩", "火", "令", "left_right"),
    ("砱", "石", "令", "left_right"),
    ("刢", "令", "刂", "blade_right"),
]

# 版面框（1024 字身框，y 軸朝上）：(x0, y0, x1, y1)
#
# ⚠️ **這些數字是從資料集裡的真字量出來的，不是憑感覺調的。**
# 量測結果（單獨的「令」寬 899、高 855）：
#
#   泠 ⿰氵令  令 寬646(-28%) 高820(-4%)   氵 寬242
#   鈴 ⿰釒令  令 寬521(-42%) 高796(-7%)   釒 寬417
#   柃 ⿰木令  令 寬611(-32%) 高814(-5%)   木 寬355
#   領 ⿰令頁  令 寬428      高698        頁 寬493
#   劍 ⿰僉刂  刂 寬204      高763        僉 寬495
#
# 結論：**部件只變窄，幾乎不變矮。** 令當右半時高度只掉 4～7%，寬度卻掉 28～42%。
# 早期版本用等比縮放（取寬高比例的較小值），一壓就整體縮小——
# 「加了火字旁之後整個字變小」就是這樣來的。現在改用**非等比縮放**：
# x 與 y 各自獨立縮放到目標框，這也正是真字的做法。
COMPOSE_BOXES = {
    # 令在右：偏旁佔左側約三分之一，令從中線稍後一路撐到右緣，高度幾乎不減
    "left_right": ((55, 90, 395, 760), (435, -15, 985, 805)),
    # 令在左＋立刀旁：**左半的寬度取決於右半需要多少**。
    # 領/翎/瓴 的右半是頁(493)/羽(449)/瓦(472)，所以令只有 362～428；
    # 但「刂」在劍裡只佔 204 寬，左半的「僉」因此拿到 495。
    # 刢 的右半同樣是刂，令自然也該拿到接近 490 的寬度——只給 395 會顯得偏窄。
    # 刂 的位置直接照抄劍的量測值 x[614,818] y[45,808]。
    "blade_right": ((55, 70, 545, 800), (614, 45, 818, 808)),
}


def _bounds(medians):
    xs = [p[0] for s in medians for p in s]
    ys = [p[1] for s in medians for p in s]
    return min(xs), min(ys), max(xs), max(ys)


def _place(medians, box):
    """把一個部件的筆畫**非等比**縮放後填滿指定的框。

    ⚠️ 不可以等比縮放。真字裡的部件是「只變窄、幾乎不變矮」——
    等比縮放會讓部件在兩個方向一起縮小，字看起來就變小又不自然。
    """
    x0, y0, x1, y1 = box
    bx0, by0, bx1, by1 = _bounds(medians)
    bw = max(1.0, bx1 - bx0)
    bh = max(1.0, by1 - by0)
    sx = (x1 - x0) / bw
    sy = (y1 - y0) / bh
    return [
        [[(p[0] - bx0) * sx + x0, (p[1] - by0) * sy + y0] for p in stroke]
        for stroke in medians
    ]


DICT_URL = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt"
GRAPHICS_URL = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/graphics.txt"

CACHE_DIR = os.environ.get("MMH_CACHE", "/tmp/mmh")
OUT_PATH = "game/data/hanzi_decomposition.json"


def fetch(url: str, path: str) -> str:
    """下載並快取；已存在就直接用，避免重複抓30MB。"""
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print(f"下載 {url} -> {path}")
        urllib.request.urlretrieve(url, path)
    return path


def load_by_char(path: str, needed: set, fields: dict) -> dict:
    """逐行讀JSONL，只挑needed裡的字，抽出fields指定的欄位。"""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            ch = entry.get("character")
            if ch in needed:
                out[ch] = {k: entry.get(src, default)
                           for k, (src, default) in fields.items()}
    return out


def main() -> int:
    needed = set(NEEDED_CHARS)
    print(f"目標字數：{len(needed)}")

    dict_path = fetch(DICT_URL, os.path.join(CACHE_DIR, "dictionary.txt"))
    gfx_path = fetch(GRAPHICS_URL, os.path.join(CACHE_DIR, "graphics.txt"))

    dict_data = load_by_char(dict_path, needed, {
        "decomposition": ("decomposition", ""),
        "radical": ("radical", ""),
    })
    gfx_data = load_by_char(gfx_path, needed, {
        "strokes": ("strokes", []),
        "medians": ("medians", []),
    })

    merged = {}
    missing_entirely = []   # 兩個檔案都查不到
    missing_strokes = []    # 有字典條目但沒有筆畫資料（無法做崩解特效）

    for ch in sorted(needed):
        in_dict = ch in dict_data
        strokes = gfx_data.get(ch, {}).get("strokes", [])

        if not in_dict and not strokes:
            missing_entirely.append(ch)
            continue
        if not strokes:
            # 筆畫是Task 3.4崩解特效的必要資料，沒有就等於不能用
            missing_strokes.append(ch)
            continue

        merged[ch] = {
            "decomposition": dict_data.get(ch, {}).get("decomposition", ""),
            "radical": dict_data.get(ch, {}).get("radical", ""),
            "strokes": strokes,
            "medians": gfx_data.get(ch, {}).get("medians", []),
        }

    # ---- 組字：資料集沒有的合體字，用部件拼出來 ----
    parts_needed = {p for _, a, b, _ in COMPOSED_CHARS for p in (a, b)}
    parts_gfx = load_by_char(gfx_path, parts_needed, {"medians": ("medians", [])})
    composed_ok, composed_fail = [], []
    for ch, left, right, layout in COMPOSED_CHARS:
        lm = parts_gfx.get(left, {}).get("medians", [])
        rm = parts_gfx.get(right, {}).get("medians", [])
        if not lm or not rm:
            composed_fail.append(ch)
            continue
        lbox, rbox = COMPOSE_BOXES[layout]
        merged[ch] = {
            "decomposition": "⿰%s%s" % (left, right),
            "radical": left,
            "strokes": [],
            "medians": _place(lm, lbox) + _place(rm, rbox),
            # 標記給字型覆蓋測試用：這些字從不經過字型渲染
            "composed": True,
        }
        composed_ok.append(ch)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)

    # ---- Task 1.2b 覆蓋率報告 ----
    print(f"\n寫入 {OUT_PATH}：{len(merged)} 字（其中 {len(composed_ok)} 個是拼出來的：{''.join(composed_ok)}）")
    if composed_fail:
        print(f"  ⚠️ 缺部件筆畫、拼不出來：{''.join(composed_fail)}")
    if missing_entirely:
        print(f"  ⚠️ 資料集查無此字（已跳過）：{''.join(missing_entirely)}")
    if missing_strokes:
        print(f"  ⚠️ 有字典條目但無筆畫資料（已跳過）：{''.join(missing_strokes)}")
    if not missing_entirely and not missing_strokes:
        print("  ✅ 全部覆蓋")

    skipped = missing_entirely + missing_strokes
    if skipped:
        print(f"\n跳過的字需要從實施計劃的敵字/Boss字表中移除，否則階段三/五會拿到空陣列：{''.join(skipped)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
