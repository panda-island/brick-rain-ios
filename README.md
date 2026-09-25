# Brick Rain

一款向早期「數字磚塊＋連續彈射」手機遊戲致意的原創 iOS 小品。拖曳瞄準、放開發射；在磚塊碰到底線前清除它們，並收集 `+1` 增加下一回合的球數。

## 玩法

- 拖曳畫面上半部調整角度，放開後連續發射所有球。
- 方塊上的數字代表還需碰撞幾次。
- 每回合結束後方塊下降一格並新增一排。
- 收集青色 `+1`，下一回合會多一顆球。
- 任一方塊抵達底線時遊戲結束。

## 本機開發

需要 macOS、Xcode 16+ 與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
brew install xcodegen
xcodegen generate
open BrickRain.xcodeproj
```

最低支援 iOS 17。專案使用 SwiftUI 管理介面與狀態，SpriteKit 負責即時物理與繪製。

目前版本：`1.4.0 (5)`。專案使用獨立 bundle identifier，以避免側載工具沿用舊 App 容器；每次功能更新都會同步提高 App 的版本或 build number。

## 下載 IPA

GitHub Actions 在每次推送與手動執行時會編譯、驗證新功能字串並產生帶版本號的 IPA artifact。這個檔案已包含真機 arm64 程式，但尚未由個人 Apple 憑證簽署；可用 AltStore、SideStore、Sideloadly 或其他簽名工具以自己的 Apple ID 簽署後安裝。

標準 iOS 安裝必須使用與裝置相符的 Apple 憑證與描述檔。基於安全考量，憑證不應提交到版本庫；若要讓 Actions 直接輸出已簽名 IPA，可在 repository secrets 加入憑證與 provisioning profile，再擴充 workflow 的 signing 步驟。

## 原創聲明

本專案只重現經典彈球打磚塊的玩法概念，沒有使用 BBTAN 的名稱、程式碼、美術、音效或商標素材。
