# App Store Connect 提出用メタデータ（OurHours）

> GitHub Pages（`main` ブランチ `/docs` フォルダ）を有効にすると、以下の URL がそのまま使えます。

## 1. 基本情報 & URL
- **App Name**: `OurHours`
- **Primary Language**: 日本語（Japanese）
- **Bundle ID**: `io.github.inazumimakoto.OurHours`
- **Version**: `1.0.0` (Build `1`)
- **Primary Category**: ライフスタイル（Lifestyle）
- **Secondary Category**: ユーティリティ（Utilities）
- **Age Rating**: `4+`（非該当をすべて「なし」）
- **Support URL**: `https://inazumimakoto.github.io/OurHours/support.html`
- **Marketing URL**: `https://inazumimakoto.github.io/OurHours/`
- **Privacy Policy URL**: `https://inazumimakoto.github.io/OurHours/privacy.html`

---

## 2. App Store テキスト（日本語）

### Subtitle（30文字以内 — 現在15文字）
`ふたりで過ごした時間を、そっと残す`

### Promotional Text（170文字以内 — 現在107文字）
`Bluetoothと暗号化ログで、ふたりが一緒にいた時間を自動記録。会っている間はホームのシャボン玉がぐんぐん成長し、カレンダーや1日のメモで思い出をやさしく振り返れます。`

### Keywords（100文字以内 — 現在86文字）
`カップル,ペア,記念日,タイマー,時間記録,カレンダー,思い出,日記,プライバシー,同棲,恋人,デート`

### Description（説明文）
```text
ポケットに入れたまま、ふたりが一緒にいた時間をふんわり記録。
OurHours（アワーアワーズ）は、パートナーと過ごした時間をシャボン玉のようにやさしく残せる、ふたり専用の時間ログアプリです。

■ 会っている時間が見えて、楽しくなる
・Bluetooth の近接通信（＋暗号化した位置滞在補完）で、一緒にいる時間を自動でカウント
・一緒にいる時間が長くなるほど、ホーム画面のシャボン玉キャラクターがぐんぐん大きく成長
・タップするとシャボン玉がぽわんと弾けて、記録中の時間や付き合った日数（「付き合って◯日目」）を確認できます

■ ふたりのカレンダー＆24時間タイムライン
・月別カレンダーと日別の時間合計、記念日・誕生日のマークをひと目で確認
・1日の「ひとことメモ」を記入して、パートナーと共有
・タイムラインのバーを長押しドラッグしたり、時刻ホイールを回したりして 1 分単位で編集・結合・手動追加も可能

■ ふたりだけの安心プライバシー設計
・地図や現在地の座標を画面に表示したり、リアルタイム位置共有したりしません
・QR コード（1ステップ）で 256-bit の鍵を交換し、すべての同期データを端末内でエンドツーエンド暗号化（Apple CryptoKit AES-GCM）
・保存先はあなたとパートナーの Apple iCloud Private Database 共有ゾーン（CKShare）のみ。開発者がサーバーで記録を閲覧することはできません
・広告なし・第三者トラッキングなし
```

---

## 3. App Store テキスト（English / Optional Localization）

### Subtitle (<= 30 chars)
`Track shared hours together`

### Promotional Text (<= 170 chars)
`Automatically log time spent together with Bluetooth and encrypted proximity backup. Watch your shared bubble mascot grow and look back on memories in your calendar.`

### Keywords (<= 100 chars)
`couple,partner,anniversary,timer,time tracker,calendar,memories,diary,privacy,relationship,date`

### Description
```text
Quietly capture the hours you spend together.
OurHours is a private time-tracking companion for couples that turns the moments you are together into gentle soap-bubble memories.

- Automatic Together Timer: Uses Bluetooth proximity (with encrypted background location backup—never shown as a map or coordinates) to count time spent nearby. As your session grows, your bubble mascot swells continuously.
- Shared Calendar & 24h Timeline: Browse daily totals, monthly hours, anniversary/birthday marks, and daily memos. Edit, merge, or add sessions down to the minute.
- End-to-End Encrypted iCloud Private Sync: Exchange a 256-bit key with a 1-step QR scan. Your records, memos, and anniversaries are encrypted on-device with Apple CryptoKit and synced only through your personal iCloud Private Database share. Zero ads, zero tracking, zero developer servers.
```

---

## 4. App Store Privacy（App プライバシーアンケート回答ガイド）

App Store Connect の **App のプライバシー** で「データを収集していますか？」に回答する際の指針です：

- Apple の定義では、**アプリがユーザーの iCloud（Private / Shared CloudKit DB）のみを使用し、開発者のサーバーや第三者 SDK に一切送信しない場合、「はい、このアプリからデータを収集しています」＝「いいえ（このアプリからデータを収集しません / Data Not Collected）」** として扱われます（ただし Review Notes で iCloud Private DB のみを扱うことを明記するとスムーズです）。
- もし審査担当者との認識齟齬を避けて明示したい場合でも、「Location（位置情報）」のみを選択し、以下のように設定します：
  - Usage: **App の機能（App Functionality）** のみ
  - Linked to the user's identity: **いいえ（No）**
  - Used for tracking: **いいえ（No）**
- 広告・解析 SDK が無いため、`NSPrivacyTracking` は `false` です（[PrivacyInfo.xcprivacy](file:///Users/inazumimakoto/OurHours/Apps/OurHoursiOS/Sources/PrivacyInfo.xcprivacy) に記載済み）。

---

## 5. App Review Notes（審査メモ：日英併記）

App Store Connect の **App Review の情報 → メモ** にそのまま貼り付けてください：

```text
Thank you for reviewing OurHours!

1. Single-Device Review Walkthrough (No Second Phone Required):
- After launching the app, step through onboarding or tap "スキップ" (Skip), OR on the pairing step tap "今はひとりで始める" (Start alone for now).
- You can use the Home view, tap the bubble mascot, open Calendar, tap any day, tap "+" to add a manual time record, drag/edit start & end times, write a daily memo, and open Settings to customize your bubble color, birthday, anniversary, and calendar mark styles.

2. Two-Device Pairing Walkthrough (Optional):
- On Device A (Settings -> "ペアを設定する" or Onboarding Pairing), tap "招待QRコードを作成" to generate an invite QR containing the 256-bit E2EE key and iCloud CKShare URL.
- On Device B, tap "QRコードを読み取る" and scan Device A's QR code. Both devices perform mutual Bluetooth authentication and synchronize E2EE data over iCloud Private DB zone sharing (CKShare).

3. Background Modes & Permissions Justification:
- bluetooth-central & bluetooth-peripheral: Required so paired devices can mutually authenticate and automatically record shared encounter duration while in pockets or background.
- location (Always / When In Use): Optional BLE fallback (can be disabled in Settings). Used solely to infer proximity stay intervals when iOS suspends background BLE connections. OurHours never displays a map, never shares live coordinates, and automatically purges raw location buckets after 14 days.
- remote-notification (Push Notifications): Used strictly for silent CloudKit CKDatabaseSubscription pushes to keep paired calendars and memos up to date; no user-facing marketing notifications are sent.
- Encryption Compliance: Uses only Apple CryptoKit (AES-GCM / HKDF) and system Keychain/CloudKit; exempt per ITSAppUsesNonExemptEncryption = NO in Info.plist.

---
【日本語補足】
・1台のみでもオンボーディング「今はひとりで始める」からホーム・カレンダー・手動記録作成/編集・ひとことメモ・設定変更のすべてのUIを確認できます。
・Bluetooth / 位置情報（常に許可）/ silent remote-notification は、ペア間での「一緒にいる時間」の自動記録および iCloud Private DB（CKShare）同期のみに使用し、地図表示や第三者送信・トラッキングは一切行いません。
```

---

## 6. 提出前チェックリスト
1. **GitHub リポジトリで GitHub Pages を有効化**:
   - GitHub `Inazumimakoto/OurHours` → Settings → Pages → Source: `Deploy from a branch` → Branch: `main` / Folder: `/docs` → Save
   - 公開後、`https://inazumimakoto.github.io/OurHours/privacy.html` と `support.html` が開けることを確認
2. **CloudKit Dashboard で本番スキーマ（Production）をデプロイ**:
   - CloudKit Console (`iCloud.io.github.inazumimakoto.OurHours`) → **Deploy Schema Changes...** で Development → Production へ以下 4 レコードタイプをデプロイ:
     - `PairSpaceBootstrap`
     - `PairSharedJournal`
     - `PairDayPresence`
     - `PairEncryptedAsset`
3. **Xcode Archive & App Store Connect アップロード**:
   - Scheme: `OurHoursiOS` / Destination: `Any iOS Device (arm64)` → Product → Archive → Distribute App → TestFlight / App Store Connect
   - App Store Connect にアイコン反映・説明文貼り付け・スクリーンショット（6.9インチ `1320×2868`）アップロード・Review Notes 記入後に提出！
