import Vision
import CoreImage
import CoreVideo
import QuartzCore
import os

/// 人脸观测的轻量值类型，跨 actor 安全。
struct FaceObservation: Sendable, Equatable {
    /// 归一化坐标系（0~1，原点左下，按 CIImage 习惯）
    let boundingBox: CGRect
    /// 左眼中心（归一化）
    let leftEye:  CGPoint?
    /// 右眼中心（归一化）
    let rightEye: CGPoint?
    /// 嘴中心（归一化）
    let mouth:    CGPoint?
}

/// 异步人脸检测器：限频 + 平滑，避免抖动与卡顿。
final class FaceDetector: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.aicamera.face", qos: .utility)
    private let request = VNDetectFaceLandmarksRequest()
    private let interval: CFTimeInterval = 1.0 / 15.0   // 15 Hz
    private var lastProcessed: CFTimeInterval = 0
    private let lock = NSLock()
    private var cached: [FaceObservation] = []
    private var smoothed: [FaceObservation] = []
    private let smoothing: CGFloat = 0.65               // EMA 系数（旧值权重）
    private let log = Logger(subsystem: "com.aicamera", category: "face")

    /// 提交一帧（建议传入降采样后的 buffer，提升性能）。
    /// - Parameter orientation: 与 buffer 对应的 CGImagePropertyOrientation。
    func submit(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let now = CACurrentMediaTime()
        if now - lastProcessed < interval { return }
        lastProcessed = now

        // CVPixelBuffer 不是 Sendable，但这里只是把引用计数化的 buffer 移交给后台队列处理；
        // 实际的内容并不在主线程并发修改。用 nonisolated(unsafe) 局部副本绕过编译期检查。
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [weak self] in
            guard let self else { return }
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
            do {
                try handler.perform([self.request])
                let raw = (self.request.results ?? []).compactMap { Self.toObservation($0) }
                self.applySmoothing(raw)
            } catch {
                self.log.error("face detection failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 主线程或处理线程读取最新一组（已平滑）观测。
    var latest: [FaceObservation] {
        lock.lock(); defer { lock.unlock() }
        return smoothed
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        cached.removeAll()
        smoothed.removeAll()
    }

    // MARK: - 内部

    private static func toObservation(_ vn: VNFaceObservation) -> FaceObservation? {
        let landmarks = vn.landmarks
        return FaceObservation(
            boundingBox: vn.boundingBox,
            leftEye:  landmarks?.leftEye.flatMap  { center(of: $0,  in: vn.boundingBox) },
            rightEye: landmarks?.rightEye.flatMap { center(of: $0,  in: vn.boundingBox) },
            mouth:    landmarks?.outerLips.flatMap { center(of: $0, in: vn.boundingBox) }
        )
    }

    private static func center(of region: VNFaceLandmarkRegion2D, in box: CGRect) -> CGPoint? {
        guard region.pointCount > 0 else { return nil }
        let pts = region.normalizedPoints
        var sumX: CGFloat = 0, sumY: CGFloat = 0
        for p in pts { sumX += p.x; sumY += p.y }
        let cx = sumX / CGFloat(pts.count)
        let cy = sumY / CGFloat(pts.count)
        // 归一化到全图坐标
        return CGPoint(x: box.minX + cx * box.width, y: box.minY + cy * box.height)
    }

    private func applySmoothing(_ raw: [FaceObservation]) {
        lock.lock(); defer { lock.unlock() }
        if cached.count != raw.count {
            cached = raw
            smoothed = raw
            return
        }
        var newSmoothed: [FaceObservation] = []
        newSmoothed.reserveCapacity(raw.count)
        for (idx, r) in raw.enumerated() {
            let prev = smoothed[idx]
            newSmoothed.append(FaceObservation(
                boundingBox: lerpRect(prev.boundingBox, r.boundingBox, t: 1 - smoothing),
                leftEye:  lerpPoint(prev.leftEye,  r.leftEye,  t: 1 - smoothing),
                rightEye: lerpPoint(prev.rightEye, r.rightEye, t: 1 - smoothing),
                mouth:    lerpPoint(prev.mouth,    r.mouth,    t: 1 - smoothing)
            ))
        }
        cached = raw
        smoothed = newSmoothed
    }

    private func lerpRect(_ a: CGRect, _ b: CGRect, t: CGFloat) -> CGRect {
        CGRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * t,
            y: a.origin.y + (b.origin.y - a.origin.y) * t,
            width:  a.size.width  + (b.size.width  - a.size.width)  * t,
            height: a.size.height + (b.size.height - a.size.height) * t
        )
    }

    private func lerpPoint(_ a: CGPoint?, _ b: CGPoint?, t: CGFloat) -> CGPoint? {
        switch (a, b) {
        case let (a?, b?): return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        default:           return b ?? a
        }
    }
}
