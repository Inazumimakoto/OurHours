# App Store Connect 提出用メタデータ（OurHours）

> GitHub Pages（`main` ブランチ `/docs` フォルダ）を有効にすると、以下の URL がそのまま使えます。

## 1. 基本情報 & URL
- **App Name**: `OurHours`
- **Primary Language**: 日本語（Japanese）
- **Bundle ID**: `io.github.inazumimakoto.OurHours`
- **Version**: `1.0.0` (Build `1`)
- **Primary Category**: ライフスタイル（Lifestyle）
- **Secondary Category**: ユーティリティ（Utilities）
- **Age Rating**: `4+`（提出時のアンケート回答に基づき確認）
- **Support URL**: `https://inazumimakoto.github.io/OurHours/support.html`
- **Marketing URL**: `https://inazumimakoto.github.io/OurHours/`
- **Privacy Policy URL**: `https://inazumimakoto.github.io/OurHours/privacy.html`

---

## 2. App Store テキスト（日本語）

### Subtitle（30文字以内）

`ふたりで過ごした時間を自動で記録`

### Promotional Text（170文字以内）

`会っている間は、ホーム画面にふたりのシャボン玉が並び、一緒に過ごした時間に合わせて大きくなります。カレンダーで日ごとの合計を確認し、その日のひとことメモを相手と共有できます。`

### Keywords（100バイト以内）

`カップル,ペア,記念日,タイマー,カレンダー,日記,同棲,恋人,デート`

### Description（説明文）

```text
デートの帰りに、今日は何時間一緒にいたかを確認できます。OurHoursは、ペア設定した2台のiPhoneが近くにいる時間をBluetoothで自動記録するアプリです。

■ 会っている時間をホームで確認
一緒にいる間はタイマーが進み、ふたりのシャボン玉が少しずつ大きくなります。記念日を登録すると、付き合って何日目かもわかります。

■ カレンダーで日ごとに振り返る
カレンダーには日ごとの合計時間と、記念日や誕生日のマークが並びます。日付をタップすると、会っていた時間帯を24時間のタイムラインで確認できます。開始・終了時刻は1分単位で編集でき、記録の追加や結合もできます。ひとことメモには、一緒に行った場所や観た映画などを書いて共有できます。

■ ふたりの記録を暗号化して同期
QRコードでペアを設定すると、時間の記録とメモを端末で暗号化し、iCloud経由で相手と同期します。位置情報による記録補完は任意です。地図や座標の表示、現在地のリアルタイム共有はありません。広告や第三者によるトラッキングもありません。
```

---

## 3. App Store テキスト（English / Optional Localization）

### Subtitle (30 characters max)

`Track your time together`

### Promotional Text (170 characters max)

`Watch your bubbles grow while you’re together. Open the calendar to see how long you met, adjust a session to the minute, or share a note about your day.`

### Keywords (100 bytes max)

`couple,partner,anniversary,timer,time tracker,calendar,memories,diary,privacy,relationship,date`

### Description

```text
OurHours uses Bluetooth to record how long you spend together when your paired iPhones are nearby. While you’re together, your bubbles grow alongside a live timer. Add your anniversary to see how many days you’ve been together.

Open the calendar for daily totals, birthdays, and anniversaries. Tap a date to see your sessions on a 24-hour timeline. Adjust start and end times to the minute, add a missed session, merge records, or share a daily note with your partner.

Pair by QR code to sync your records and notes with end-to-end encryption through iCloud. Optional location assistance helps fill gaps in Bluetooth recording. The app has no maps, coordinate display, live location sharing, ads, or third-party tracking.
```

---

## 4. App Store Privacy（App プライバシーアンケート回答ガイド）

現行版のプライバシーマニフェストでは、収集するデータは「なし」、トラッキングは「なし」です。位置補完を有効にすると、位置の滞在記録も端末で暗号化してペア間で同期します。共有ゾーンを利用できない場合は、暗号化した記録をCloudKitの公開データベース経由で同期します。[PrivacyInfo.xcprivacy](../Apps/OurHoursiOS/Sources/PrivacyInfo.xcprivacy)

提出時には、開発者や第三者パートナーがサービス提供に必要な時間を超えてアクセスできるデータがあるかを、同期用レコードのメタデータも含めて確認してください。その結果に基づき「データの収集」と「トラッキング」に回答します。[AppleのAppプライバシー回答ガイド](https://developer.apple.com/app-store/app-privacy-details/)

---

## 5. App Review Notes（審査メモ：日英併記）

App Store Connect の **App Review の情報 → メモ** にそのまま貼り付けてください：

```text
Thank you for reviewing OurHours!

1. Single-Device Review Walkthrough (No Second Phone Required):
- After launching the app, step through onboarding or tap "スキップ" (Skip), OR on the pairing step tap "今はひとりで始める" (Start alone for now).
- You can use the Home view, tap the bubble mascot, open Calendar, tap a past day, tap "+" to add a manual time record, drag/edit start & end times, write a daily memo, and open Settings to customize your bubble color, birthday, anniversary, and calendar mark styles.

2. Two-Device Pairing Walkthrough (Optional):
- On Device A (Settings -> "ペアを設定する" or Onboarding Pairing), choose the invite QR action to generate an invite QR containing the 256-bit E2EE key and, when available, the iCloud share URL.
- On Device B, choose the QR scanner and scan Device A's QR code. Both devices perform mutual Bluetooth authentication and sync end-to-end encrypted records through CloudKit. The owner shares a private zone using CKShare. CloudKit’s public database carries encrypted bootstrap data and can also carry encrypted records while the shared zone is unavailable.

3. Background Modes & Permissions Justification:
- bluetooth-central & bluetooth-peripheral: Required so paired devices can mutually authenticate and automatically record shared encounter duration while in pockets or background.
- location (Always / When In Use): Optional BLE fallback (can be disabled in Settings). Used solely to infer proximity stay intervals when iOS suspends background BLE connections. OurHours never displays a map, never shares live coordinates, and automatically purges raw location buckets after 14 days.
- remote-notification (Push Notifications): Used strictly for silent CloudKit CKDatabaseSubscription pushes to keep paired calendars and memos up to date; no user-facing marketing notifications are sent.
- Encryption Compliance: Uses only Apple CryptoKit (AES-GCM / HKDF) and system Keychain/CloudKit; exempt per ITSAppUsesNonExemptEncryption = NO in Info.plist.

---
【日本語補足】
・1台のみでもオンボーディング「今はひとりで始める」からホーム・カレンダー・手動記録作成/編集・ひとことメモ・設定変更のすべてのUIを確認できます。
・Bluetoothで近接時間を自動記録し、任意の位置情報で記録を補完します。サイレント通知でCloudKitの変更を受け取り、暗号化した記録をペア間で同期します。
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
