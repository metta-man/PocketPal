# 收據核對流程交付紀錄 — 2026-09-07

已完成本輪範圍：簡化核對頁、確認並下一張、統一確認與正式匯出狀態。

## 行為

- 核對頁保留商戶、日期、金額／幣種、支出用途；備註、稅項、項目及收支類型放入「更多資料」。缺少必要分類時，直接顯示分類欄位；業務／報銷展開稅務分類。
- 已附收據在欄位之前顯示；個人手動記錄不用先看沒有附件的提示。移除重複標題、模型分數與重複狀態標籤；確認按鈕固定在底部。
- Inbox 與稅務待處理清單使用獨立導航項目及清單快照；成功確認後替換同一詳情頁的記錄，最後一張返回清單。略過已確認、已刪除及未完成處理的項目；不跳到範圍外記錄。
- 資料完整與用戶已確認分開判斷。正式稅務 CSV 在 service 層再次篩選，只納入已確認且資料齊全的業務／報銷支出。一般完整帳本匯出繼續保留未確認資料與狀態。
- 草稿儲存不等於確認。重新抽取若改變欄位，撤回舊確認狀態；稅務頁批次標記改為逐張核對入口。
- 儲存失敗保留表單輸入，還原當前收據原有欄位與審核狀態，不跳頁、不回滾其他未儲存工作。

## 驗證

- 最終 iOS Simulator：17 個測試通過，0 失敗（14:01 HKT）。包括未確認／個人／收入排除、確認後保存草稿、失敗還原、缺欄位／未來日期、重複／已刪除／處理中清單項目、抽取後撤回確認，以及 UIHostingController 畫面渲染。
- macOS hosted infrastructure tests：4 個測試通過，0 失敗；最終共享 UI 調整後 macOS build 再次成功。
- `Tools/VerifyInfrastructure.sh` 通過；已更新正式匯出入口檢查，保留原有完整帳本序列化檢查。
- `git diff --check` 通過。
- 已目視檢查 390 × 844 pt 測試宿主渲染：一般字體淺色、accessibility3 深色。放大字體下欄位可捲動，底部確認按鈕可見。這是記憶體樣本渲染，不是真機操作或 XCTest UI 點擊流程證明。

## 邊界與待驗證

- 未做真機安裝、發布、commit 或 push。未更改持久化 schema，未清除收據或原始附件。
- 工作區原有大量修改；本輪在其上增量修改，未重建 Xcode project。測試與編譯直接使用現有已包含相關檔案的 project。
- 補附件入口、完整交付資料包、首頁與 Mac 導航重整不在本輪範圍。
- 仍需用同一批 20 張真實收據做前後耗時、修正次數及真機相機／鍵盤／逐張導航比較。本輪未宣稱已達到時間節省目標。

## 證據

- [一般字體畫面](/Volumes/External%20SSD%204TB/DeveloperData/PocketPal/review-flow-20260907/final-screenshots/review-phone-light.png)
- [放大字體深色畫面](/Volumes/External%20SSD%204TB/DeveloperData/PocketPal/review-flow-20260907/final-screenshots/review-accessibility-dark.png)
- 測試、編譯 log、xcresult、修改前備份及本輪主要 Swift 檔案差異：`/Volumes/External SSD 4TB/DeveloperData/PocketPal/review-flow-20260907/`
