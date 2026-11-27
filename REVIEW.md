# Code review 判讀與修正 — 0.1.1

逐項核對使用者提供的 `code_review.txt`，並查閱 Apple 的 API 文件。下表保留原報告編號；嚴重程度與修法不直接照抄。

| 編號 | 判讀 | 本次處理 |
|---|---|---|
| 1 強制轉型 | 防禦性改善合理；「Apple 任意改變回傳型別」不宜當成已存在的 crash 證據。這是受 API 契約約束的系統輸出。 | 改成安全轉型。若無有效格式清單，以 `.image` 限制開啟面板，避免空陣列讓所有檔案都能選取。 |
| 2 LRU 替換 | 成立，但也可以視為原本未明確定義的替換策略；保留舊值較符合預期。 | 先驗證新 cost，再移除舊項目。過大與負值都不破壞舊值；一併避免 `totalCost + cost` 整數溢位。新增兩個回歸測試。 |
| 3 解碼去重 | 成立。Actor 在 await 時可重入，原本同 key 的 cache miss 會啟動重複解碼。原報告的「4 路同張」需修正：完整影像佇列最多 2 路，另 2 路是獨立縮圖佇列，且解析度不同不是相同 key。 | 新增 `SharedRequestPool`，完整影像與縮圖按各自 key 去重。每個等待者可獨立取消；最後一個取消才取消底層工作。工作 UUID 隔離舊結果與新同名請求；二次快取檢查補足跨 actor 排程時序。 |
| 4 Swift 6／NSItemProvider | 改善方向合理，但原本 `ViewerRootView` 已是 MainActor，Task 會繼承其隔離；只看那段程式不能斷定一定出現 Swift 6 錯誤。加上 `@Sendable` 也不會使 provider 自動安全。 | 新增 MainActor `FileDropLoader`。同步啟動 provider 讀取，Task 只攜帶 URL 值；保留拖放順序，取消過期批次，避免舊拖放覆蓋新拖放。全 App 的 Swift 6 建置仍需 macOS SDK 驗證。 |
| 5 無效 callback | 成立，新增視窗實際走 AppDelegate 的原生選單 action。 | 刪除 `onNewWindow` 宣告與設定，保留原有新增視窗功能。 |
| 6 舊拖放 API | 更新方向合理，棄用版本敘述錯誤。核對到的 Apple DocC metadata 是 macOS **27.0** 棄用，不是 13；官方建議 `loadObjectOfClass:completionHandler:`。 | 改用 `loadObject(ofClass: NSURL.self)`，沒有採用報告中未確認的 `loadItem(for:)` 寫法。 |
| 7 Singleton 建構子 | 屬於 API 設計選擇，internal init 本身不是 bug，獨立 instance 也可用於測試或依賴注入。當前 App 已一致使用 shared。 | 按本版「共用一個 pipeline」的設計將 init 改成 private；共用請求核心仍可獨立建立並測試。 |
| 8 複製回饋 | 成立，原本要換圖才會恢復。 | `.task(id:)` 在約兩秒後恢復，重複點擊會重新計時；換圖與關閉面板會取消舊計時，避免舊工作重置新狀態。 |
| 9 清除回饋 | 成立。 | 清除中暫時停用按鈕；完成回饋約兩秒後恢復。關閉設定時取消 UI 工作。一併加入快取世代檢查，避免清除前開始的載入稍後回填影像／中繼資料快取。 |
| 10 示範圖無回應 | 成立，資源缺失時不應靜默返回。 | 顯示可理解的錯誤，讓使用者仍能開啟自己的照片。開發時可檢查 Samples 的 Copy Bundle Resources 設定。 |

## 本次新增的併發回歸測試

- 三個同 key 等待者只啟動一個工作。
- 取消其中一個等待者，其他等待者仍能收到結果。
- 最後等待者取消後，舊非協作工作晚到不會移除新同 key 工作。
- 錯誤傳遞給所有等待者，之後可重新請求。
- 不同 key 不會被錯誤合併。

這些測試用受控 gate 等待實際工作與等待者註冊，不把任意固定 sleep 當成「工作已開始」的證據。

## 驗證範圍

19 個核心 XCTest 已於 Linux、Swift 6.0.3 編譯器執行，0 失敗。測試 runner 採套件預設的 Swift 5 語言模式；4 個核心原始檔另外以 `-swift-version 6 -strict-concurrency=complete` 通過型別檢查。

6 個 macOS 整合測試、FileDropLoader 的原生行為與整個 App 的建置仍待 macOS SDK。沒有宣稱全 App 已通過 Swift 6 或原生 GUI 實機驗收。

## API 依據

- [ImageIO 支援格式識別碼](https://developer.apple.com/documentation/imageio/cgimagesourcecopytypeidentifiers())。
- [NSItemProvider 與 UI callback 執行緒](https://developer.apple.com/documentation/foundation/nsitemprovider)。
- [loadItem 官方文件](https://developer.apple.com/documentation/foundation/nsitemprovider/loaditem(fortypeidentifier:options:completionhandler:))。
- [loadItem 官方 DocC metadata（含棄用版本與替代 API）](https://developer.apple.com/tutorials/data/documentation/foundation/nsitemprovider/loaditem(fortypeidentifier:options:completionhandler:).json)。
