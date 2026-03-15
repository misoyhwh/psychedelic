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
- ドラッグで位置移動、両手ピンチでサイズ変更、水平・垂直回転をスライダーで調整
- メインUI上で再生・一時停止・停止・シークバー操作

### スライドショーパネル
- フォルダ内の画像をスライドショー表示（1000枚以上対応）
- **立体視 (Spatial Photo) 対応**: HEIC ステレオペアを自動検出し、`ShaderGraphMaterial` の `CameraIndexSwitch` で左右の目に異なる画像を表示
- 再生間隔の調整、前後ナビゲーション（±1/±10/±100 ジャンプ）
- ドラッグで位置移動、両手ピンチでサイズ変更、水平・垂直回転をスライダーで調整

### オクルージョンパネル
- 任意の位置に配置できる遮蔽パネル
- ドラッグで移動、幅・高さ・回転角を調整可能

### ブラウザ
- WKWebView ベースのブラウザウィンドウ（YouTube 等の閲覧に対応）

## 動作環境

- Apple Vision Pro
- visionOS 2.0+
- Xcode 16+

## ビルド

1. Xcode でプロジェクトを開く
2. Apple Vision Pro 実機またはシミュレータをターゲットに選択
3. ビルド & 実行

> **注意**: `SceneReconstructionProvider` は実機でのみ動作します。シミュレータではシーン再構築機能は利用できません。

## プロジェクト構成

```
PsychedelicRoom/
├── PsychedelicRoomApp.swift    # エントリポイント
├── AppModel.swift              # 設定管理モデル
├── ContentView.swift           # コントロールパネル UI
├── ImmersiveView.swift         # Immersive Space & パネル管理
├── SceneReconstructor.swift    # ARKit シーン再構築 & マテリアル管理
├── TextureGenerator.swift      # Metal GPU テクスチャ生成
├── AudioReactiveEngine.swift   # 音声入力 & Auto Pulse エンジン
├── ParticleSystem.swift        # パーティクルシステム
├── BrowserView.swift           # Web ブラウザ
├── VideoPlayerView.swift       # MediaPanelViewModel（動画・スライドショー管理）
├── SlideshowEngine.swift       # ステレオ画像検出・テクスチャ読み込み
├── Shaders/
│   └── PsychedelicShader.metal # Metal Compute Shader（16種のパターン）
└── Packages/
    └── RealityKitContent/      # ShaderGraph 立体視マテリアル
```
