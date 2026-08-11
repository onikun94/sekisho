# Sekisho PoC 実装メモ

この初期実装は `PLAN.md` の Phase 0 に限定する。目的は、招待コード・匿名マッチング・課金ではなく、Screen Time 系 API と earn-access ループが実機で成立するかを検証すること。

## 入っているもの

- SwiftUI 4タブ構成: 関所 / 五人組 / 番付 / 自分
- `FamilyControls` の `.individual` 認可リクエスト
- `FamilyActivityPicker` による対象アプリ選択
- `ManagedSettingsStore` によるシールド適用 / 解除
- `DeviceActivityMonitor` による日次スクリーンタイム閾値監視
- アプリ内集中セッション完了による通行手形発行
- Shield Configuration extension のカスタム文言
- Shield Action extension からローカル通知を出す実機検証用ワークアラウンド

## ビルド

プロジェクトは XcodeGen で生成する。

```sh
xcodegen generate
xcodebuild -scheme Sekisho -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Sekisho -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

実機に入れる場合は `project.yml` の bundle ID / App Group と Apple Developer の登録値を揃え、Xcode 側で Team を設定する。`com.apple.developer.family-controls` は entitlement 申請が通っていない状態では実機配布時に署名で止まる可能性がある。

## 実機検証で見ること

1. Screen Time 権限が `.individual` で通るか。
2. 対象アプリ選択後に `ManagedSettingsStore` のシールドが実際にかかるか。
3. 「スクリーンタイム監視を始める」で `DeviceActivityCenter.startMonitoring` が通るか。
4. 対象アプリの利用が日次上限を超えた時に `DeviceActivityMonitorExtension.eventDidReachThreshold` が呼ばれ、シールドがかかるか。
5. シールドの「務めを果たす」ボタンでローカル通知が出て、通知タップからアプリへ戻れるか。
6. 集中セッション完了後に `clearAllSettings()` で解除されるか。
7. アプリをバックグラウンドにした場合、集中セッションが中断扱いになるか。

## 現在の制限条件

対象アプリ / カテゴリ / Web ドメインを選び、ホームの「今日の制限を始める」を押すと、毎日 0:00〜23:59 の繰り返しスケジュールで監視する。閾値は「ルール」の「1日の上限」で設定する。iOS 17.4 以降では `includesPastActivity: false` を使い、開始・更新した時点より前の利用は新しい閾値判定に含めない。

iOS 26.3 以前では `DeviceActivityEvent` が設定した閾値より早く発火する既知の不具合がある。そのため、監視開始から上限時間ぶんの実時間が経過していない callback は早期発火として破棄し、シールドを適用しない。破棄した日はホームに診断メッセージを表示する。これは誤制限を防ぐための安全側の処理であり、その callback が再送されない場合は当日の制限が遅れる可能性がある。

閾値に達すると `SekishoDeviceActivityMonitorExtension` が `ManagedSettingsStore` にシールドを適用する。解除はアプリ内集中セッション完了、または PoC 用の手動解除ボタンで行う。

## 後続で未実装

- 招待コード五人組
- Supabase 同期
- push 通知
- 免除申請のサーバー投票
- StoreKit 課金
- 通報 / ブロック
