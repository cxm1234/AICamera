import CoreImage
import os

/// 帧处理上下文：每帧由 ViewModel 同步推过来的最新参数。
/// 值类型 + Sendable，保证读取无锁。
struct FrameContext: Sendable {
    var filter: FilterKind = .original
    var filterIntensity: Double = 1.0
    var beauty: BeautySettings = .zero

    var needsBeauty: Bool { beauty.enabled }
    var needsFilter: Bool { filter != .original && filterIntensity > 0.001 }
    var isPassthrough: Bool { !needsFilter && !needsBeauty }
}

/// 协议化便于测试 / 替换实现
protocol FrameSink: AnyObject, Sendable {
    func draw(_ image: CIImage, sourceExtent: CGRect)
}

/// 帧处理器：串行队列 + 零拷贝 + 短路。
/// 读取最新 FrameContext 由外部用 NSLock 守护。
final class FrameProcessor: @unchecked Sendable {

    private let filterEngine = FilterEngine()
    private let beautyEngine = BeautyEngine()
    private let faceDetector: FaceDetector
    private let histogramSampler: HistogramSampler?
    private weak var sink: FrameSink?

    private let lock = NSLock()
    private var context = FrameContext()

    private let signpost = OSSignposter(subsystem: "com.aicamera", category: "frame")

    init(faceDetector: FaceDetector,
         sink: FrameSink,
         histogramSampler: HistogramSampler? = nil) {
        self.faceDetector = faceDetector
        self.sink = sink
        self.histogramSampler = histogramSampler
    }

    func updateContext(_ ctx: FrameContext) {
        lock.lock()
        context = ctx
        lock.unlock()
    }

    func process(_ frame: VideoFrame) {
        let ctx = currentContext()

        // 直方图采样（采样器内部已限频；与渲染并列，无依赖）
        histogramSampler?.submit(frame.pixelBuffer)

        // 短路：原图直出
        if ctx.isPassthrough {
            let img = frame.makeCIImage()
            sink?.draw(img, sourceExtent: img.extent)
            return
        }

        let signpostID = signpost.makeSignpostID()
        let state = signpost.beginInterval("process", id: signpostID)
        defer { signpost.endInterval("process", state) }

        var image = frame.makeCIImage()

        // 仅当瘦脸/大眼启用时才送入 face detector，节省功耗
        if ctx.beauty.needsFaceLandmarks {
            faceDetector.submit(pixelBuffer: frame.pixelBuffer, orientation: frame.orientation)
        }

        if ctx.needsFilter {
            image = filterEngine.apply(image, kind: ctx.filter, intensity: ctx.filterIntensity)
        }

        if ctx.needsBeauty {
            image = beautyEngine.apply(image, settings: ctx.beauty, faces: faceDetector.latest)
        }

        sink?.draw(image, sourceExtent: image.extent)
    }

    // MARK: -

    private func currentContext() -> FrameContext {
        lock.lock(); defer { lock.unlock() }
        return context
    }
}
