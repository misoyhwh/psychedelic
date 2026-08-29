import CoreVideo
import CoreGraphics

/// 動画フレームの外周にある黒帯 (レターボックス/ピラーボックス) を走査して、
/// 実際にコンテンツが写っている矩形を求める。
///
/// 静止画スライドショーを動画に焼いたファイルでは、解像度の違う画像が
/// 共通のフレームサイズに収まるよう余白を黒で塗られている。そのまま板に貼ると
/// 黒枠付きで表示されてしまうので、フレームごとに中身の矩形を検出して UV をクロップする。
///
/// 状態を持たない純粋な static メソッドのみで構成しているため、どのスレッドから呼んでもよい
/// (フレーム抽出は再生スレッド側で走るので、MainActor 分離を避ける意味でも重要)。
enum VideoBorderScanner {

    /// 長辺をおおよそ何サンプルに分割して走査するか。
    /// 黒帯の境界は数ピクセル単位の精度で分かれば十分なので、全ピクセル走査は無駄が大きい。
    /// 4K フレームでも 1 行あたり 96 サンプル程度に落として、毎フレーム呼んでも負荷が乗らないようにする。
    private static let targetSampleCount = 96

    /// 「その走査線は黒帯」と判定する黒ピクセルの割合。
    /// 100% にすると JPEG/H.264 のブロックノイズや境界のリンギングで数サンプル明るくなるだけで
    /// 黒帯を検出できなくなるため、少し余裕を持たせる。
    private static let blackLineRatio = 0.95

    /// 検出結果として許容する最小の幅/高さ (正規化)。
    /// これを下回るのは黒基調のシーンを誤って帯と判定した場合がほとんどなので、
    /// クロップせず素直に全面表示に倒す。
    private static let minContentExtent = 0.2

    /// フレーム全面を指す矩形。検出できない場合のフォールバック。
    private static let fullRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// フレームの黒フチを除いたコンテンツ矩形を正規化座標 (0...1) で返す。
    /// 座標系: 原点は「左下」、y は上向き (RealityKit の UV 規約に合わせる。
    /// ピクセルバッファの row 0 は画像の上端であることに注意して変換する)。
    /// - Parameters:
    ///   - buffer: 走査対象のフレーム。kCVPixelFormatType_32BGRA の非 planar バッファのみ対応。
    ///   - blackThreshold: 輝度 (0...1) がこの値以下なら「黒」とみなす
    /// - Returns: コンテンツ矩形。ほぼ全面が黒 (コンテンツが見つからない)、
    ///   フチが検出されない (フルフレームがコンテンツ)、または対応外のバッファなら全面矩形。
    nonisolated static func contentRect(in buffer: CVPixelBuffer, blackThreshold: Float) -> CGRect {
        // 対応外フォーマットは解析せず全面扱い。MV-HEVC などは planar や YUV で返ることがあり、
        // BGRA 前提でバイトを読むと壊れた値を見てしまうため、ここで確実に弾く。
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(buffer) else { return fullRect }

        // ロックとアンロックは defer で対にする。途中の early return が多いので、
        // 手で書くと必ずどこかで漏れる。
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return fullRect }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        // bytesPerRow は幅より大きい (アラインメントのパディング) ことがある。
        // 逆に小さいのはあり得ないので、その場合は読み出し自体が危険とみなす。
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return fullRect }
        let bufferSize = bytesPerRow * height

        // 閾値は 0...255 の整数に落としてから比較する。ピクセルごとに Float 除算するより速く、
        // NaN や範囲外の値が渡ってきても整数変換でクラッシュしないようここで正規化しておく。
        let normalized = blackThreshold.isFinite ? min(max(blackThreshold, 0), 1) : 0
        let blackLimit = UInt8(min(max(Int((normalized * 255).rounded()), 0), 255))

        // 走査の間引き幅。長辺が targetSampleCount 個くらいに割れるようにする。
        let step = max(1, max(width, height) / targetSampleCount)
        let columns = Array(stride(from: 0, to: width, by: step))
        let rows = Array(stride(from: 0, to: height, by: step))
        guard !columns.isEmpty, !rows.isEmpty else { return fullRect }

        /// 指定ピクセルが黒かどうか。輝度は max(R,G,B) で近似する。
        /// BT.709 の加重和は青の寄与が 7% しかないため、濃い青一色のコンテンツを
        /// 黒帯と誤判定してクロップしてしまう。ここで欲しいのは「全チャンネルが沈んでいるか」なので、
        /// どれか 1 チャンネルでも明るければコンテンツとみなす max の方が目的に合う。
        func isBlack(x: Int, y: Int) -> Bool {
            let offset = y * bytesPerRow + x * 4
            // 範囲外は「黒」に倒す。帯の内側判定が保守的になるだけで、コンテンツを削る方向には効かない。
            guard offset >= 0, offset + 3 < bufferSize else { return true }
            let ptr = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            // BGRA なので ptr[0]=B, ptr[1]=G, ptr[2]=R。アルファは黒判定に使わない。
            return ptr[0] <= blackLimit && ptr[1] <= blackLimit && ptr[2] <= blackLimit
        }

        func isRowBlack(_ y: Int) -> Bool {
            var blackCount = 0
            for x in columns where isBlack(x: x, y: y) { blackCount += 1 }
            return Double(blackCount) >= blackLineRatio * Double(columns.count)
        }

        func isColumnBlack(_ x: Int) -> Bool {
            var blackCount = 0
            for y in rows where isBlack(x: x, y: y) { blackCount += 1 }
            return Double(blackCount) >= blackLineRatio * Double(rows.count)
        }

        // 外側から内側へ進み、最初に「黒帯でなくなった」走査線がコンテンツの端。
        // 反対側の走査線と交差する = どの行/列も黒帯だった、なので全面黒フレーム。
        // その場合はクロップのしようがないので全面矩形を返す。
        guard let topIndex = rows.firstIndex(where: { !isRowBlack($0) }),
              let bottomIndex = rows.lastIndex(where: { !isRowBlack($0) }),
              let leftIndex = columns.firstIndex(where: { !isColumnBlack($0) }),
              let rightIndex = columns.lastIndex(where: { !isColumnBlack($0) })
        else { return fullRect }

        // 端の走査線がそのままコンテンツなら、その辺に黒帯は無い。
        let hasTopBorder = topIndex > 0
        let hasBottomBorder = bottomIndex < rows.count - 1
        let hasLeftBorder = leftIndex > 0
        let hasRightBorder = rightIndex < columns.count - 1

        // 四辺とも帯が無ければフルフレームがコンテンツ。
        // ここで抜けておかないと、下の安全マージンが理由もなく画を削ってしまう。
        guard hasTopBorder || hasBottomBorder || hasLeftBorder || hasRightBorder else { return fullRect }

        var top = rows[topIndex]
        var bottom = rows[bottomIndex]
        var left = columns[leftIndex]
        var right = columns[rightIndex]

        // 安全マージンは「帯を検出した辺」にだけ内側 1 サンプル分入れる。
        // 間引き走査なので実際の境界は最大 step ピクセル外側にあり得るし、
        // エンコード由来のにじみで境界数ピクセルはグレーになる。帯の無い辺に効かせると
        // ただのクロップ過剰になるため、辺ごとに分けて適用する。
        if hasTopBorder { top += step }
        if hasBottomBorder { bottom -= step }
        if hasLeftBorder { left += step }
        if hasRightBorder { right -= step }

        guard top <= bottom, left <= right else { return fullRect }

        // ピクセル座標 → 正規化座標。row 0 は画像の上端なので、y を上向きにするため反転する。
        // bottom/right は「その行/列自体がコンテンツ」なので +1 して終端に変換する。
        let x = Double(left) / Double(width)
        let maxX = Double(right + 1) / Double(width)
        let y = 1.0 - Double(bottom + 1) / Double(height)
        let maxY = 1.0 - Double(top) / Double(height)
        let rectWidth = maxX - x
        let rectHeight = maxY - y

        // 極端に小さい矩形は誤検出。暗いシーンを丸ごと帯と判定した場合などがこれに当たる。
        guard rectWidth >= minContentExtent, rectHeight >= minContentExtent else { return fullRect }

        return CGRect(x: x, y: y, width: rectWidth, height: rectHeight)
    }
}
