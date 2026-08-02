# 台詞資料表（Task 4.0）

每個檔案是一段對話，檔名即 `dialogue_id`，由 `DialogueBox.play(dialogue_id)` 讀取。

```json
{
  "id": "boss_ren_intro",
  "lines": [
    {"speaker": "仁", "text": "「跪下，見證朕的完整。」"},
    {"speaker": "", "text": "（旁白／演出提示把 speaker 留空）"}
  ]
}
```

規則（`tests/test_dialogue_data.gd` 會在CI逐條檢查）：

- `id` 必須與檔名一致，否則 `play(id)` 找不到檔案。
- `lines` 至少一句；每句都要有 `speaker`（旁白用空字串）與非空的 `text`。
- **一律繁體中文**（GDD 第0節）。簡體字有字形、不會報錯，只會安靜地混進遊戲。
- 用字必須在 `assets/fonts/NotoSansTC-Bold.otf`（繁中子集版）裡有字形，
  缺字形不報錯，只會畫出一個空的豆腐方框。

選項型對話（賜俸三選一、Phase 2.1「命」接住/放手）的**選項**不寫在這裡——
選項會影響戰鬥數值，由呼叫端（`BossRen`）以程式傳入 `play_choice()`，
台詞檔只負責選項出現前的那幾句話。

一行一句、每句獨立成行，是為了讓多人同時編輯不同段落時 Git 能逐行正確合併。
