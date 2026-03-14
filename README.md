# PsychedelicRoom

Apple Vision Pro (visionOS) 向けの Mixed Reality アプリです。ARKit のシーン再構築を利用して、現実の部屋の壁・床・天井をサイケデリックな模様でリアルタイムに彩ります。

## 機能

### サイケデリックエフェクト
- **7種類のシェーダーパターン**: Psychedelic / Fractal / 39(初音ミク) / Rainbow Wave / Aurora / Voronoi / Interference
- Metal Compute Shader による GPU リアルタイムテクスチャ生成
- 速度・強度をスライダーで調整可能

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

### オクルージョンパネル
- 任意の位置に配置できる遮蔽パネル
- ドラッグで移動、幅・高さ・回転角を調整可能

### ブラウザ & 動画プレーヤー
- WKWebView ベースのブラウザウィンドウ（YouTube 等の閲覧に対応）
- ローカル動画再生プレーヤー（Spatial Video 対応）

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
├── ImmersiveView.swift         # Immersive Space & オクルージョンパネル
├── SceneReconstructor.swift    # ARKit シーン再構築 & マテリアル管理
├── TextureGenerator.swift      # Metal GPU テクスチャ生成
├── AudioReactiveEngine.swift   # 音声入力 & Auto Pulse エンジン
├── ParticleSystem.swift        # パーティクルシステム
├── BrowserView.swift           # Web ブラウザ
├── VideoPlayerView.swift       # 動画プレーヤー
└── Shaders/
    └── PsychedelicShader.metal # Metal Compute Shader（7種のパターン）
```
