import CoreImage
import Metal

/// 全应用共享的 CIContext / MTLDevice。
/// 创建昂贵且不需要并发多份；放在一处复用。
enum SharedRender {
    static let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()

    static let commandQueue: MTLCommandQueue? = metalDevice?.makeCommandQueue()

    static let ciContext: CIContext = {
        let opts: [CIContextOption: Any] = [
            .cacheIntermediates: false,            // 实时管线不需要缓存中间结果，避免内存膨胀
            .priorityRequestLow: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ]
        if let device = metalDevice {
            return CIContext(mtlDevice: device, options: opts)
        }
        return CIContext(options: opts)
    }()

    static let colorSpaceSRGB: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
}
