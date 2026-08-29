# PsychedelicRoom

Apple Vision Pro (visionOS) 向けの Mixed Reality アプリです。ARKit のシーン再構築を利用して、現実の部屋の壁・床・天井をサイケデリックな模様でリアルタイムに彩ります。[illust-server](https://github.com/misoyhwh/illust-server) と連携し、Spatial Photo / Spatial Video のタグベース閲覧ビューワーとしても機能します。

## 機能

### サイケデリックエフェクト
- **19 種類のシェーダーパターン**: Psychedelic / Fractal / 39(初音ミク) / Rainbow Wave / Aurora / Voronoi / Interference / Hex Tunnel / Organic / Sparkles / Hearts / Caustic / Video Psychedelic / Video Interference / Video Rainbow / Video Aurora / Media Kaleido / Media Tunnel / Media Ripple
- Metal Compute Shader による GPU リアルタイムテクスチャ生成
- 速度・強度・透明度をスライダーで調整可能

### メディア連動の部屋エフェクト
- **Video Color Mode**: パネルの端の色を部屋のメッシュに反映（天井 → 上端、壁 → 右端、床 → 下端）
- **Video 系ティントパターン** (Video Psychedelic / Interference / Rainbow / Aurora): グレースケールパターンにパネルの色をティンティング、天井・壁・床で異なる色
- **Media 系直接投影パターン** (動画・スライド画像の両対応):
  - **Media Kaleido**: 再生中の映像/画像を万華鏡変換して部屋全体に投影（強度でセグメント数、ズームが脈動）
  - **Media Tunnel**: 映像/画像を極座標マッピングし、壁がトンネル状に流れる
  - **Media Ripple**: メディアの平均色履歴（32 件）が中心から外周へ波紋のように伝播
  - 動画フレームは `CVMetalTextureCache` でゼロコピー供給、スライド画像は 1 枚につき 1 回だけテクスチャ化してキャッシュ
- **Color Source (Video / Slideshow)** セグメントでソースを切替（Color Mode・ティント・Media 系共通、常時表示）

### シーン再構築
- ARKit `SceneReconstructionProvider` で部屋のメッシュをリアルタイム取得
- **メッシュ分類フィルター**: 壁・床・天井・テーブル・椅子・窓・ドア等をカテゴリ別に ON/OFF
- 長時間稼働対策: メッシュ生成ループでは `ARGeometrySource` のスカラー値とバッファ参照を事前にローカルスナップショット + `withExtendedLifetime` でバッファ寿命を保証し、ARKit によるバッファ再利用との競合による use-after-free を防止

### 音声リアクティブ / パーティクル
- マイク入力 or Auto Pulse (BPM) でエフェクトが脈動、感度スライダー・レベルメーター付き
- 床から上昇する光球パーティクル（最大 120 個、音声リアクティブ対応）

### 動画パネル
- Immersive 空間内に枠なしの動画パネルを配置（`VideoMaterial`、Spatial Video 自動対応）
- **2 つのソース**:
  - **Local File**: 単一ファイル（ループ再生）または**フォルダ選択で連続再生**（mov/mp4/m4v、`名前順` / `追加日順` ソート切替可）
  - **Server Search**: illust-server からタグ検索でプレイリスト構築（最大 500 件）
- プレイリスト共通機能: 自動次送り、前後 / ±10 ジャンプ、繰り返し回数（N 回再生して次へ）、現在ファイル名表示
- **黒フチ自動カット**: フレーム外周から黒帯（レターボックス/ピラーボックス）を検出し、パネルを内容部分だけに切り詰め（0.5 秒間隔で追従、しきい値調整可、映像内部の黒には影響しない）
- **湾曲**: 水平・垂直の 2 軸で円筒/球面状に湾曲（±1.0、アーク長保存）
- **連続顔追跡**: 再生中の顔（または注目領域）を定期検出し、顔が頭の正面に来るようパネルがゆっくり追従（距離/高さ/水平オフセット、検出間隔 0.1〜3 秒）
- **背景透過（試作）**: クロマキー / Vision 前景抽出で動画の背景を抜く（StereoVideoFramePump による自前フレーム供給）
- HTTP 動画の自動再生信頼性: `AVPlayerItem.status` KVO + サイズ取得完了で entity を 1 回だけ生成（チラつき無し）、失敗時はプレイリスト次へスキップ

### スライドショーパネル
- **2 つのソース**: Local Folder（1000 枚以上対応）/ Server Search（最大 2000 件）
- **立体視 (Spatial Photo) 対応**: HEIC ステレオペアを自動検出し、`ShaderGraphMaterial` の `CameraIndexSwitch` で左右の目に別画像
- 表示テクスチャは最大 2048px に downsample（長時間再生でも GPU メモリ安定）
- 再生間隔調整、±1/±10/±100 ジャンプ、現在ファイル名（`作者名：ファイル名`）とタグの表示
- **湾曲**: 水平・垂直の 2 軸湾曲（動画パネルと同仕様）
- **顔中心配置**: スライドごとに顔を検出し、顔が頭の正面 + オフセット位置に来るようパネルを自動配置（ヨーは頭に向く）。検出方法は 3 択:
  - `顔検出` (Vision、実写向け) / `注目度` (サリエンシー、汎用) / `アニメ顔` (同梱 Core ML モデル、イラスト向け)
- **拡張背景 (アウトペイント)**: illust-server で事前生成した拡張画像 (`/outpaint/{hash}`) をパネル背後に 2 倍サイズ・中央ピクセル一致で表示（湾曲にも追従、未生成は通常表示）
- **背景透過**: クロマキー / Vision 前景抽出（被写体切り抜き、ステレオは左右別マスク）

### 手の甲追従
- 動画・スライドショー各パネルを**左手/右手の甲に追従**させられる（ARKit ハンドトラッキング）
- 高さ / 水平 / 奥行きの 3 軸オフセット（水平・奥行きは頭の向き基準）、60Hz の滑らかな補間追従
- 顔中心配置とは排他（手が優先）

### Illust Server 連携
- [illust-server](https://github.com/misoyhwh/illust-server)（Mac mini 上で稼働する Spatial Photo / Video タグベース管理サーバー）と Tailscale 経由で接続
- メイン UI にサーバ URL 入力 + 接続テストボタン（緑/赤の状態ドット）
- **検索**: タグ AND 検索（**タグなし = 全件検索**も可）+ rating フィルタ + 日付フィルター（今日/今週/今月/今年/すべて）+ 並び順（ファイル名 / 投稿日 / 追加日）
- **お気に入り (1〜10 のラベル)**: 表示中の画像/動画にアプリ上から設定（サーバの `general:favN` タグとして保存 = Web ビューワーとも共有）。検索フィルタは完全一致（「2 のみ」等）
- タグ / rating / 日付 / お気に入りは画像・動画で独立設定、`UserDefaults` に永続化
- **タグ選択ウィンドウ**（画像用・動画用の 2 窓）: カテゴリ別タブ（キャラ/シリーズ/一般/作者、各 90 件）+ インクリメンタル検索、選択はメイン画面へリアルタイム反映

### その他
- **メモリインジケータ**: プロセスメモリ (phys_footprint) とピーク値を常時表示（実機長時間検証用）
- **オクルージョンパネル**: 任意位置に置ける遮蔽パネル
- **ブラウザ**: WKWebView ベースのブラウザウィンドウ

## 動作環境

- Apple Vision Pro（visionOS 26 推奨 — 27 では StereoImageMaterial に既知の不具合あり）
- Xcode 16+
- (Illust Server 連携) Tailscale で同じネットワーク上の illust-server に到達できること

## ビルド

1. Xcode でプロジェクトを開く
2. Apple Vision Pro 実機またはシミュレータをターゲットに選択
3. ビルド & 実行

> **注意**: `SceneReconstructionProvider` とハンドトラッキングは実機でのみ動作します。シミュレータではサーバ検索・スライドショー・動画再生などの確認が可能です。

### Illust Server を使う場合の追加設定
1. illust-server を [手順](https://github.com/misoyhwh/illust-server) に従い Mac mini 等で起動（Tailscale 経由でアクセス可能な状態にする）
2. AVP（または開発機 Mac）でも Tailscale にサインインしておく
3. アプリ起動 → メイン UI の「Illust Server」セクションに URL を入力（既定: `http://misoyhwhmac-mini:8080/`）
4. 「接続テスト」ボタンで緑ドット (`接続OK`) を確認
5. **スライドショー**: パネル → Server Search セグメント → タグ入力 or タグ一覧ウィンドウから選択 → 「サーバ検索」
6. **動画**: 動画パネル → Server Search セグメント → 同様にタグ選択 → 「動画をサーバ検索」

> Info.plist で `NSAppTransportSecurity > NSAllowsArbitraryLoads = true` を設定しており、Tailscale 経由の HTTP 接続を許可しています（個人用途想定）。

### 長時間検証時の Tips
- 実機での Debug ビルドは重いため、長時間連続再生の検証は **Release ビルド**を推奨（Scheme → Run → Build Configuration を Release に変更）
- メモリインジケータがノコギリ波 (上下に揺れるが上限が一定) ならリークなし、単調右肩上がりならリーク

## プロジェクト構成

```
PsychedelicRoom/
├── PsychedelicRoomApp.swift        # エントリポイント（メイン / Browser / タグピッカー×2 / ImmersiveSpace）
├── AppModel.swift                  # 設定管理モデル（Illust Server 接続情報・検索条件を永続化）
├── ContentView.swift               # コントロールパネル UI
├── ImmersiveView.swift             # Immersive Space・パネル管理・湾曲メッシュ生成・追従/配置ロジック
├── SceneReconstructor.swift        # ARKit シーン再構築 & マテリアル管理
├── TextureGenerator.swift          # Metal GPU テクスチャ生成（動画フレーム/静止画のシェーダ供給含む）
├── AudioReactiveEngine.swift       # 音声入力 & Auto Pulse エンジン
├── ParticleSystem.swift            # パーティクルシステム
├── BrowserView.swift               # Web ブラウザ
├── VideoPlayerView.swift           # MediaPanelViewModel（動画・スライドショー・プレイリスト・サーバ検索）
├── SlideshowEngine.swift           # 画像読み込み・ステレオ検出・顔/注目度検出・前景マスク
├── IllustServerClient.swift        # illust-server REST API クライアント（お気に入り・アウトペイント含む）
├── TagPickerView.swift             # タグ選択ウィンドウ（画像用 / 動画用）
├── HandTrackingManager.swift       # ハンドトラッキング & 頭の姿勢（手の甲追従・顔中心配置用）
├── VideoBorderScanner.swift        # 動画フレームの黒フチ検出（黒フチ自動カット用）
├── StereoVideoFramePump.swift      # 動画フレームの自前テクスチャ供給（背景透過モード用）
├── StereoFrameExtractor.h/.m       # MV-HEVC フレーム抽出（Objective-C）
├── MemoryMonitor.swift             # 自プロセスのメモリ使用量取得ヘルパー
├── AnimeFaceDetector.mlpackage     # アニメ顔検出 Core ML モデル（deepghs/anime_face_detection v1.4_s）
├── Shaders/
│   └── PsychedelicShader.metal     # Metal Compute Shader（19 種のパターン）
└── Packages/
    └── RealityKitContent/          # ShaderGraph 立体視マテリアル（クロマキー/前景マスク対応）
```
