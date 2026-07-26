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

# 從實施計劃 Task 2.1 / 3.1 / 5.1 的字表彙總
#
# 「燄」原在此表，但Make Me a Hanzi查無此字（它是「焰」的異體字，資料集只收「焰」）。
# 依專案決策不做近似字替換而是移除，並補上同為火屬性、資料集有收錄的「焚」以維持
# 每屬性4隻敵人的對稱（⿱林火，其部首「林」同時也是木屬性敵字，部首武器機制可跨屬性互動）。
NEEDED_CHARS = "我淼焱森河海湖雨焰炎灶焚鋼針劍錘樹藤林巖石山塵"

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

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)

    # ---- Task 1.2b 覆蓋率報告 ----
    print(f"\n寫入 {OUT_PATH}：{len(merged)}/{len(needed)} 字")
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
