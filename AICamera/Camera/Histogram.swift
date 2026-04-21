import Accelerate
import CoreVideo
import Foundation
import os

/// 直方图采样结果。bin 数固定 64，索引 0=最暗，63=最亮。
struct HistogramBins: Sendable, Equatable {
    var luma: [UInt32]      // 64 bins
    var maxBin: UInt32      // 用于归一化
    static let empty = HistogramBins(luma: Array(repeating: 0, count: 64), maxBin: 1)
}

/// 直方图采样器：限频 + 降采样 + vImage。
/// 由 FrameProcessor 在 video queue 调用 `submit(_:)`。
final class HistogramSampler: @unchecked Sendable {

    private let lock = NSLock()
    private var cached: HistogramBins?

    /// 每 N 帧采样一次。
    private let everyN: Int = 6
    private var counter: Int = 0

    /// 降采样目标边长。
    private let targetSize: Int = 128

    /// 静态分配的下采样缓冲与 4×256 的直方图缓冲。
    private var scaleBufferData: Data?
    private var scaleBufferRowBytes: Int = 0
    private let log = Logger(subsystem: "com.aicamera", category: "histogram")

    var latest: HistogramBins? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func reset() {
        lock.lock()
        cached = nil
        counter = 0
        lock.unlock()
    }

    func submit(_ pixelBuffer: CVPixelBuffer) {
        counter += 1
        if counter % everyN != 0 { return }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var src = vImage_Buffer(data: base,
                                height: vImagePixelCount(height),
                                width: vImagePixelCount(width),
                                rowBytes: stride)

        // 准备目标 buffer
        let dstW = targetSize
        let dstH = targetSize
        let dstRowBytes = dstW * 4
        if scaleBufferData == nil {
            scaleBufferData = Data(count: dstRowBytes * dstH)
            scaleBufferRowBytes = dstRowBytes
        }
        guard scaleBufferData != nil else { return }

        scaleBufferData!.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let dstBase = raw.baseAddress else { return }
            var dst = vImage_Buffer(data: dstBase,
                                    height: vImagePixelCount(dstH),
                                    width:  vImagePixelCount(dstW),
                                    rowBytes: scaleBufferRowBytes)
            // 1) 缩放
            let scaleErr = vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags))
            if scaleErr != kvImageNoError {
                log.error("vImageScale failed: \(scaleErr)")
                return
            }
            // 2) 4×256 直方图
            var rBins = [UInt](repeating: 0, count: 256)
            var gBins = [UInt](repeating: 0, count: 256)
            var bBins = [UInt](repeating: 0, count: 256)
            var aBins = [UInt](repeating: 0, count: 256)
            rBins.withUnsafeMutableBufferPointer { r in
                gBins.withUnsafeMutableBufferPointer { g in
                    bBins.withUnsafeMutableBufferPointer { b in
                        aBins.withUnsafeMutableBufferPointer { a in
                            // BGRA 排列：通道顺序 [B, G, R, A]
                            var hist: [UnsafeMutablePointer<vImagePixelCount>?] = [
                                b.baseAddress, g.baseAddress, r.baseAddress, a.baseAddress
                            ]
                            hist.withUnsafeMutableBufferPointer { hp in
                                _ = vImageHistogramCalculation_ARGB8888(&dst, hp.baseAddress!, vImage_Flags(kvImageNoFlags))
                            }
                        }
                    }
                }
            }

            // 3) 合并为 64-bin Luma：Y = 0.299R + 0.587G + 0.114B
            var luma64 = [UInt32](repeating: 0, count: 64)
            for i in 0..<256 {
                let y = Double(rBins[i]) * 0.299
                       + Double(gBins[i]) * 0.587
                       + Double(bBins[i]) * 0.114
                let bin = i / 4   // 256 → 64
                luma64[bin] &+= UInt32(min(y, Double(UInt32.max)))
            }
            let maxBin = max(luma64.max() ?? 1, 1)
            let result = HistogramBins(luma: luma64, maxBin: maxBin)
            lock.lock(); cached = result; lock.unlock()
        }
    }
}
