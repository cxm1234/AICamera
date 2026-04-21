import CoreImage
import CoreMedia
import CoreVideo
import ImageIO

/// 跨 actor 传递的相机帧轻量包装。
/// CVPixelBuffer 本身是引用计数对象，在闭包中即用即弃，不做长期持有。
struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let orientation: CGImagePropertyOrientation
    let isFrontCamera: Bool

    /// 直接构造 CIImage（零拷贝）
    func makeCIImage() -> CIImage {
        CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    }
}
