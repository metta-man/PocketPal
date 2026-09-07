# Gemini 收據抽取設定

程式已接入 Gemini 3.5 Flash-Lite（`gemini-3.5-flash-lite`）。實際帳戶尚未完成金鑰及連線驗證。

## 在新版 App 啟用

1. 開啟「設定 → 收據抽取 → Gemini 收據抽取」。
2. 點「取得 Gemini API key」，或前往 https://aistudio.google.com/apikey 。將你的 Gemini API key 填入安全輸入框，再按「儲存 API Key」。金鑰保存在 Keychain，不需要貼到對話或程式碼。
3. 按「測試 Gemini 連線」。這只讀取模型資訊，不上傳收據，也不呼叫生成。
4. 開啟「用 Gemini 自動抽取收據」。畫面會說明新收據圖片／PDF及辨識文字將傳送到 Google。
5. 匯入新收據。既有未確認記錄可在詳情頁使用「用 Gemini 重新抽取」；已確認記錄需先明確存為草稿。

## 行為與邊界

- 每張新圖片或 PDF 在啟用後使用 Gemini；不再以本機 OCR 信心高低決定是否呼叫。沒有金鑰、未同意上傳或未啟用時，維持本機處理。
- 原始圖片／PDF直接送入 Gemini；OCR僅作不可信輔助，沒有把本機候選金額當作正確答案。支援 JPG、PNG、WebP、HEIC、HEIF、PDF，直接傳送上限 14 MB，超限顯示錯誤並保留檔案。
- 結構化 JSON 欄位可為 null；無法確定日期／金額／幣種時不要求模型猜測，也不使用模型自報信心分數當作正確率。多張獨立收據放同一檔案時不合併總額。
- Gemini結果更新尚未確認的機器欄位，能修正本機已填錯的值。備註、支出用途、稅務分類及原始附件保留。已確認或抽取期間被修改的欄位不會被覆蓋。
- 自動抽取期間保持處理中；詳情页在新結果到達後更新未被修改的表單。抽取本身不會將記錄標記已確認。
- OCR失敗仍可直接從原圖嘗試 Gemini；PDF不要求先有OCR文字。Gemini離線／配額／解析失敗保留本機結果並顯示錯誤。
- Gemini使用獨立金鑰及上傳同意設定；不沿用舊OpenAI同意。舊OpenAI金鑰及历史來源值保留，預設執行路徑已切換Gemini。

## 驗證

iOS mock HTTP／pipeline tests 包括原圖與schema、nullable欄位、繁體中文、截斷／錯誤JSON／HTTP429拒絕、缺key不發送、模型連線不傳文件、OCR高信心亦調用Gemini、OCR失敗／PDF接手、修正錯誤OCR、並行修改與已確認保護、離線保留本機結果，以及手動上傳同意門檻。

模擬接口測試不能證明真實API帳戶可用、費用、收據準確率或真機行為。仍需在新版App輸入key完成連線，再用真實收據比較欄位正確率。未進行真機安裝、發布、commit、push或批次上傳既有資料。

編譯／測試log與修改前備份位於：`/Volumes/External SSD 4TB/DeveloperData/PocketPal/gemini-20260907/`。

## 官方API依據（2026-09-07核對）

- https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite
- https://ai.google.dev/api/generate-content （inlineData、generationConfig.responseJsonSchema）
- https://ai.google.dev/gemini-api/docs/structured-output
