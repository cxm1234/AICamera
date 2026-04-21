import CoreImage
import Metal
import MetalKit

/// MTKView 的渲染代理。每帧把外部最新的 CIImage 渲染到 drawable。
/// drawCIImage 由 FrameProcessor 在 video queue 调用。
final class PreviewRenderer: NSObject, MTKViewDelegate, FrameSink, @unchecked Sendable {

    private weak var view: MTKView?
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let lock = NSLock()
    private var pendingImage: CIImage?
    private var pendingExtent: CGRect = .zero

    @MainActor
    init?(view: MTKView) {
        guard let device = view.device ?? SharedRender.metalDevice,
              let queue  = device.makeCommandQueue() else { return nil }
        self.view = view
        self.commandQueue = queue
        self.context = SharedRender.ciContext
        super.init()
        view.device = device
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true                  // 我们手动 setNeedsDisplay
        view.enableSetNeedsDisplay = true
        view.delegate = self
        view.contentMode = .scaleAspectFill
        view.backgroundColor = .black
        view.layer.isOpaque = true
    }

    // MARK: - FrameSink

    func draw(_ image: CIImage, sourceExtent: CGRect) {
        lock.lock()
        pendingImage = image
        pendingExtent = sourceExtent
        lock.unlock()
        // 触发一次重绘；MTKView.draw 会在 main 安排
        Task { @MainActor [weak view] in
            view?.setNeedsDisplay()
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { /* no-op */ }

    func draw(in view: MTKView) {
        let snapshot: (CIImage, CGRect)? = {
            lock.lock(); defer { lock.unlock() }
            guard let img = pendingImage else { return nil }
            return (img, pendingExtent)
        }()
        guard let (image, sourceExtent) = snapshot,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = view.drawableSize
        let scaled = aspectFill(image: image, source: sourceExtent, into: drawableSize)

        let destination = CIRenderDestination(
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: buffer
        ) { drawable.texture }
        destination.colorSpace = SharedRender.colorSpaceSRGB

        do {
            _ = try context.startTask(toRender: scaled, to: destination)
        } catch {
            // 渲染失败仅本帧丢弃
        }

        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: - Aspect-fill 居中

    private func aspectFill(image: CIImage, source: CGRect, into size: CGSize) -> CIImage {
        guard size.width > 0, size.height > 0, source.width > 0, source.height > 0 else { return image }
        let sx = size.width  / source.width
        let sy = size.height / source.height
        let scale = max(sx, sy)
        let translated = image.transformed(by: CGAffineTransform(translationX: -source.origin.x, y: -source.origin.y))
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (size.width  - source.width  * scale) * 0.5
        let dy = (size.height - source.height * scale) * 0.5
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }
}
