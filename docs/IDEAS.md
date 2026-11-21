# OurHours アイデア・UI刷新メモ・実機検証ノート

> 本ドキュメントは [SPEC.md](SPEC.md) を補完し、今後の実装予定・未実装アイデア・確定したUI刷新方針・実機検証で得られた技術的知見をまとめるバックログ資料です。

---

## 1. 将来機能アイデア（未実装・バックログ）

- **付き合った日の登録＆記念日演出**
  - 交際開始日を登録し、ホーム等で「付き合って◯日目」を表示できるようにする。
  - 1年記念日などの節目の日には、ホーム画面が祝福寄りの特別な演出になる。
- **「お礼を伝えてみませんか？」＆アプリ内手紙機能**
  - さりげなく感謝を伝えるきっかけを提案（例：「お礼を伝えてみませんか？」）し、そのままアプリ内で相手へ手紙を送れる機能。
- **ホームの泡キャラ成長＋表情・色アンロック**
  - 最初は小さめ → 会う時間・回数に応じて少しずつ大きくなり、現在の 2〜3 倍程度のサイズで成長上限に達する。
  - 上限到達後は、新しい表情のアンロックや、ほのかな泡の色チェンジなどのご褒美へ発展させる。
- **「終了不明」記録を次の記録と繋げる（マージ）機能**
  - 2026-11-21 02:57 の夜間実機テストで、実際に iOS 側で `unknownEnd`（`terminatedWhileActive`）が発生することを確認済み。
  - CloudKit 導入後はもう片方の端末の正常終了ログによる自動補完も行うが、両端末欠損や一時切断後の再開ケースに備え、手動編集で直後の会合記録と結合（マージ）できる導線を検討する。

---

## 2. 確定したUI刷新方針メモ（2026-11-21 実装反映済み）

- **全体フォント**: `Zen Maru Gothic`（Regular / Medium / Bold）を同梱し、ナビゲーションバー・全画面・全シートで柔らかい丸ゴシックへ統一。
- **背景の泡演出**: 下から粒が規則的に昇り続ける演出をやめ、大きめでふわふわ緩やかに漂う泡表現（`FoamAmbientBackgroundView`）へ刷新。
- **カレンダーのページ送りアニメーション**: **3か月連続横スワイプカルーセル（前月・当月・次月を隣接配置し、ゆっくりドラッグしても前後の月が日付に泡が張り付いたまま滑らかに追従＋切り替え確定後に次の月の会った日の泡が時間差でポコポコ膨らむ演出）**。横スワイプ中は日付タップを誤爆しないようガード済み。
- **タブバー**: 画面下に張り付く初期デザイン（`FoamTabBarBase`）を復元しつつ、左上の泡（`FoamCornerCluster`）と同じツヤのある大小ミックス泡＆離れて漂う小泡粒を追加。上アイコン・下ラベルのまま、選択中は案D（`OrganicFoamPressedHollow`）として押された箇所の泡が薄くなり背景の桃色/水色がほんのり透けつつ深く凹み、内容幅へ自動追従してラベル長を問わずはみ出さない設計。
- **右上の設定ボタン・ピロー類**: 左上の泡（`FoamCornerCluster`）および下端タブバーと同じ泡粒子 DNA・離れて漂う小泡粒で `FoamSettingsLather` / `FoamPillLather` / `FoamCardLather` を生成し、画面全体の泡質感を統一。
- **Liquid Glass・シャボン玉感・ホイップクリーム感の不採用**: 半透明ガラスピル、虹色シャボン玉、滑らかなホイップクリーム表面ではなく、`FoamCornerCluster` 準拠のツヤのある大小ミックス石鹸泡と小粒サテライト泡で UI を統一。
- **カレンダーの日付泡**: 規則的な花形スタンプを廃止し、3種の不規則なもこもこ泡（`FoamDayPuffA/B/C`＋ランダム回転・反転）へ刷新。お泊まり等で日をまたいだ記録は `FoamDayBridge` で日付同士の泡を連結。
- **タップ時の泡演出**:
  - タブバータップ：等間隔・規則的な扇状をなくし、大きさ・飛び方・時間差・揺れに自然なランダム性を入れた `.tabSplash`。
  - 画面の他エリアタップ：タブバーとは別の出し方として、`UIWindow` 監視（`FoamTapObserverView`）＋最前面描画（`FoamTapBurstsOverlayView`）により、指先の位置からその場でぷくぷく湧いて揺れて消える `.screenPuff`。

---

## 3. 2026-11-21 夜間BLE実機テストの知見（2026-11-21 修正反映済み）

`OurHoursBLEEngine.swift` / `BLEConstants.swift` における実機（iPhone 12 ↔ MacPeer）一晩検証ログの解析で判明した課題と実施した修正。

1. **既知パートナー認証失敗のクールダウンが 300 秒（5 分）になっていた問題**
   - `failCentralAuth` 側でも、既知パートナー（`lastAuthenticatedPeripheralID`）の一時的失敗（`AuthError.expired` / `CBATTError.invalidHandle` / トランスポート失敗など）は `knownPeerAuthFailureCooldownSeconds = 15` 秒へ短縮（暗号不一致・別人衝突は 300 秒維持）。
2. **アプリをフォアグラウンドで開いてもクールダウン解除・再接続トリガーが走らなかった問題**
   - `OurHoursBLEEngine.handleForegroundActivation()` を追加し、iOS (`scenePhase == .active`) および MacPeer (`didBecomeActiveNotification`) の復帰時に、壁時計（`Date`）で期限切れになったハンドシェイクを解放し、既知パートナーのクールダウンを解除して `refreshRadios()` を実行。
3. **iOS バックグラウンド起動の約 10 秒枠と `authTimeoutSeconds = 10` 秒の衝突＋GATT ハンドルキャッシュ不整合**
   - **修正内容**: `authTimeoutSeconds` を **6 秒**へ短縮＋壁時計 `authStartedAt` 保持＋`CBATTError.invalidHandle` 受信時は即切断せず `0.6` 秒待ってから `discoverServices(nil)` でフル再探索を 1 回リトライするよう改善。
4. **正確な位置情報 × BLE ハイブリッドによる取りこぼし根絶（実装済み）**
   - `LocationPresenceMonitor`（`CLVisit`・100 m 出口ジオフェンス・大幅位置変化・`NSLocationDefaultAccuracyReduced` 廃止）＋ `LocationPayloadCipher`（HKDF + AES-GCM E2EE）＋ `CloudKitLocationSync`（`PairDayPresence` Public DB 同期）＋ `LocationProximityMatcher` を実装。
   - 地図や現在地 UI は一切表示せず、端末内のみで `BLE ∪ 正確な位置情報` の時間帯を統合して取りこぼしを補完（生座標バケットは 14 日で自動削除し、確定セッションのみ保持）。
