# PsychedelicRoom

Apple Vision Pro (visionOS) 向けの Mixed Reality アプリです。ARKit のシーン再構築を利用して、現実の部屋の壁・床・天井をサイケデリックな模様でリアルタイムに彩ります。

## 機能

### サイケデリックエフェクト
- **16種類のシェーダーパターン**: Psychedelic / Fractal / 39(初音ミク) / Rainbow Wave / Aurora / Voronoi / Interference / Hex Tunnel / Organic / Sparkles / Hearts / Caustic / Video Psychedelic / Video Interference / Video Rainbow / Video Aurora
- Metal Compute Shader による GPU リアルタイムテクスチャ生成
- 速度・強度・透明度をスライダーで調整可能

### カラーモード
- **Video Color Mode**: 動画パネルまたはスライドショーパネルの端の色を部屋のメッシュに反映
  - 天井 → パネル上端の色、壁 → パネル右端中央の色、床 → パネル下端の色
  - 色ソースを Video / Slideshow から選択可能
- **Video パターン** (Video Psychedelic / Video Interference / Video Rainbow / Video Aurora): グレースケールのシェーダーパターンにパネルの色をティンティングし、天井・壁・床で異なる色を反映

### シーン再構築
- ARKit `SceneReconstructionProvider` で部屋のメッシュをリアルタイム取得
- **メッシュ分類フィルター**: 壁・床・天井・テーブル・椅子・窓・ドア等をカテゴリ別に ON/OFF
- 取得したメッシュにサイケデリックテクスチャを投影
- 長時間稼働対策: メッシュ生成ループでは `ARGeometrySource` のスカラー値とバッファ参照を事前にローカルスナップショット + `withExtendedLifetime` でバッファ寿命を保証し、ARKit によるバッファ再利用との競合による use-after-free を防止

### 音声リアクティブ
- **マイク入力モード**: 環境音に反応してエフェクトが変化
- **Auto Pulse (BPM) モード**: マイク不要で BPM ベースの自動パルス生成
- 感度調整スライダー付き
- 音量・Bass・Treble のレベルメーター表示

### パーティクルシステム
- 床面から上昇する光球パーティクル（最大120個）
- 色相サイクル・点滅エフェクト
- 音声リアクティブ対応（音に合わせてスポーン量・速度・明るさが変化）

### 動画パネル
- Immersive 空間内に枠なしの動画パネルを配置
- `VideoMaterial` による直接レンダリング（Spatial Video 自動対応）
- **2 つのソースに対応**:
  - **Local File**: ローカル動画ファイルを単独再生（自動ループ）
  - **Server Search**: [illust-server](https://github.com/misoyhwh/illust-server) からタグ検索で動画プレイリストを構築（最大 500 件 / 検索）、終了時に自動で次の動画へ進む
- ドラッグで位置移動、両手ピンチでサイズ変更、水平・垂直回転をスライダーで調整
- メインUI上で再生・一時停止・停止・シークバー操作、プレイリスト時は前後 / ±10 ジャンプ
- HTTP 動画の自動再生信頼性向上: `AVPlayerItem.status` を KVO で監視し `.readyToPlay` + サイズ取得完了の両方が揃ったタイミングで entity を 1 回だけ生成（チラつき無し）、`.failed` 時はプレイリスト次へ自動スキップ

### スライドショーパネル
- **2 つのソースに対応**:
  - **Local Folder**: ローカルフォルダ内の画像を表示（1000 枚以上対応）
  - **Server Search**: [illust-server](https://github.com/misoyhwh/illust-server) からタグ検索で画像を取得（最大 2000 件 / 検索）
- **立体視 (Spatial Photo) 対応**: HEIC ステレオペアを自動検出し、`ShaderGraphMaterial` の `CameraIndexSwitch` で左右の目に異なる画像を表示
- 表示用テクスチャは最大 2048px に downsample（GPU メモリを抑え長時間再生でも安定）
- 再生間隔の調整、前後ナビゲーション（±1/±10/±100 ジャンプ）
- ドラッグで位置移動、両手ピンチでサイズ変更、水平・垂直回転をスライダーで調整

### Illust Server 連携
- [illust-server](https://github.com/misoyhwh/illust-server)（Mac mini 上で稼働する Spatial Photo / Video タグベース管理サーバー）と Tailscale 経由で接続
- メイン UI にサーバ URL 入力 + 接続テストボタン（緑/赤の状態ドット）
- **スライドショー (画像)** と **動画パネル (Spatial Video)** の両方で Server Search モードに対応
- タグ AND 検索 + rating フィルタ、検索結果は自動ページングで集約（画像: 最大 2000 件 / 動画: 最大 500 件）
- タグ・rating はスライドショーと動画で共有 (タグピッカーで一度選べば両方の検索に流用可能)
- 検索条件 (タグ・rating) と接続先 URL は `UserDefaults` に永続化

### タグ選択ウィンドウ
- 別ウィンドウでタグを視覚的に選択（メインウィンドウで毎回タイプ入力する必要なし）
- **カテゴリ別タブ表示**（キャラ / シリーズ / 一般 / 作者）— 各 namespace ごとに人気タグ 90 件
- インクリメンタル検索（250ms デバウンス、`/api/tags/suggest` の FTS5 ベース補完）
- 選択中タグはチップ表示（クリックで解除、「すべて解除」ボタン）
- 編集結果はメインウィンドウの検索欄にリアルタイム反映 → メインで「サーバ検索」ボタンを押して適用

### メモリインジケータ
- ContentView 上部にプロセスメモリ (phys_footprint, MB) とピーク値を常時表示（2 秒更新）
- Xcode に繋がない実機長時間検証で、リーク有無を目視で確認可能
- ピーク値はリセットボタンで再計測可能

### オクルージョンパネル
- 任意の位置に配置できる遮蔽パネル
- ドラッグで移動、幅・高さ・回転角を調整可能

### ブラウザ
- WKWebView ベースのブラウザウィンドウ（YouTube 等の閲覧に対応）

## 動作環境

- Apple Vision Pro
- visionOS 2.0+
- Xcode 16+
- (Illust Server 連携) Tailscale で同じネットワーク上の illust-server に到達できること

## ビルド

1. Xcode でプロジェクトを開く
2. Apple Vision Pro 実機またはシミュレータをターゲットに選択
3. ビルド & 実行

> **注意**: `SceneReconstructionProvider` は実機でのみ動作します。シミュレータではシーン再構築機能は利用できません。

### Illust Server を使う場合の追加設定
1. illust-server を [手順](https://github.com/misoyhwh/illust-server) に従い Mac mini 等で起動（Tailscale 経由でアクセス可能な状態にする）
2. AVP（または開発機 Mac）でも Tailscale にサインインしておく
3. アプリ起動 → メイン UI の「Illust Server」セクションに URL を入力（既定: `http://misoyhwhmac-mini:8080/`）
4. 「接続テスト」ボタンで緑ドット (`接続OK`) を確認
5. **スライドショー**: パネル → Server Search セグメント → タグ入力 or タグ一覧ウィンドウから選択 → 「サーバ検索」
6. **動画**: 動画パネル → Server Search セグメント → 同様にタグ選択 → 「動画をサーバ検索」 (タグはスライドショーと共有)

> Info.plist で `NSAppTransportSecurity > NSAllowsArbitraryLoads = true` を設定しており、Tailscale 経由の HTTP 接続を許可しています（個人用途想定）。

### 長時間検証時の Tips
- 実機での Debug ビルドは重いため、長時間連続再生の検証は **Release ビルド**を推奨（Scheme → Run → Build Configuration を Release に変更）
- メモリインジケータがノコギリ波 (上下に揺れるが上限が一定) ならリークなし、単調右肩上がりならリーク

## プロジェクト構成

```
PsychedelicRoom/
├── PsychedelicRoomApp.swift    # エントリポイント（メイン / Browser / TagPicker / ImmersiveSpace のシーン定義）
├── AppModel.swift              # 設定管理モデル（Illust Server 接続情報も永続化）
├── ContentView.swift           # コントロールパネル UI（メモリ表示・Illust Server 設定セクション含む）
├── ImmersiveView.swift         # Immersive Space & パネル管理
├── SceneReconstructor.swift    # ARKit シーン再構築 & マテリアル管理
├── TextureGenerator.swift      # Metal GPU テクスチャ生成
├── AudioReactiveEngine.swift   # 音声入力 & Auto Pulse エンジン
├── ParticleSystem.swift        # パーティクルシステム
├── BrowserView.swift           # Web ブラウザ
├── VideoPlayerView.swift       # MediaPanelViewModel（動画・スライドショー管理、サーバ検索ロジック）
├── SlideshowEngine.swift       # ステレオ画像検出・テクスチャ読み込み（ローカル/HTTP 両対応 + downsample）
├── IllustServerClient.swift    # illust-server REST API クライアント
├── TagPickerView.swift         # タグ選択用の別ウィンドウ
├── MemoryMonitor.swift         # 自プロセスのメモリ使用量取得ヘルパー
├── Shaders/
│   └── PsychedelicShader.metal # Metal Compute Shader（16種のパターン）
└── Packages/
    └── RealityKitContent/      # ShaderGraph 立体視マテリアル
```
