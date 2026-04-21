import CoreImage
import CoreImage.CIFilterBuiltins

/// 纯函数式滤镜引擎：根据 (kind, intensity) 把 CIImage 变形。
/// 内部全部使用 Core Image 内建滤镜，0 第三方资源。
struct FilterEngine: Sendable {

    /// 应用滤镜。intensity 范围 0~1。kind == .original 或 intensity == 0 则原样返回。
    func apply(_ image: CIImage, kind: FilterKind, intensity: Double) -> CIImage {
        guard kind != .original, intensity > 0.001 else { return image }
        let i = max(0, min(1, intensity))
        switch kind {
        case .original:
            return image
        case .vivid:
            return tone(image, saturation: 1.0 + 0.45 * i, contrast: 1.0 + 0.18 * i, brightness: 0.04 * i)
        case .natural:
            return tone(image, saturation: 1.0 + 0.10 * i, contrast: 1.0 + 0.06 * i, brightness: 0.02 * i)
        case .mono:
            let m = monochrome(image, color: CIColor(red: 0.78, green: 0.78, blue: 0.78), strength: 1.0)
            return mix(image, with: m, t: i)
        case .cinema:
            let t = tone(image, saturation: 0.85 - 0.10 * i, contrast: 1.0 + 0.22 * i, brightness: -0.03 * i)
            return temperature(t, k: -800 * i)
        case .portra:
            let t = tone(image, saturation: 1.0 + 0.05 * i, contrast: 1.0 + 0.10 * i, brightness: 0.02 * i)
            return temperature(t, k: 350 * i)
        case .cool:
            return temperature(image, k: -1100 * i)
        case .warm:
            return temperature(image, k: 1100 * i)
        case .vintage:
            let t    = tone(image, saturation: 0.75 - 0.10 * i, contrast: 0.95, brightness: 0.0)
            let warm = temperature(t, k: 600 * i)
            return vignette(warm, intensity: 0.6 * i, radius: 1.6)
        case .faded:
            let t = tone(image, saturation: 0.78 - 0.12 * i, contrast: 0.92, brightness: 0.05 * i)
            return mix(image, with: t, t: i)
        case .pink:
            let t = tone(image, saturation: 1.05, contrast: 1.05, brightness: 0.03 * i)
            return colorBias(t, r: 0.06 * i, g: 0.0, b: 0.04 * i)
        case .tokyo:
            let t    = tone(image, saturation: 1.10, contrast: 1.12, brightness: 0.0)
            let cool = temperature(t, k: -700 * i)
            return colorBias(cool, r: -0.02 * i, g: 0.02 * i, b: 0.05 * i)
        }
    }

    // MARK: - 基础变换（每次实例化 CIFilter，开销微小且无并发隐患）

    private func tone(_ image: CIImage, saturation: Double, contrast: Double, brightness: Double) -> CIImage {
        let f = CIFilter.colorControls()
        f.inputImage = image
        f.saturation = Float(saturation)
        f.contrast   = Float(contrast)
        f.brightness = Float(brightness)
        return f.outputImage ?? image
    }

    private func temperature(_ image: CIImage, k: Double) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: 6500 + CGFloat(k), y: 0)
        f.targetNeutral = CIVector(x: 6500, y: 0)
        return f.outputImage ?? image
    }

    private func vignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        let f = CIFilter.vignette()
        f.inputImage = image
        f.intensity = Float(intensity)
        f.radius    = Float(radius)
        return f.outputImage ?? image
    }

    private func monochrome(_ image: CIImage, color: CIColor, strength: Double) -> CIImage {
        let f = CIFilter.colorMonochrome()
        f.inputImage = image
        f.color = color
        f.intensity = Float(strength)
        return f.outputImage ?? image
    }

    private func colorBias(_ image: CIImage, r: Double, g: Double, b: Double) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.biasVector = CIVector(x: CGFloat(r), y: CGFloat(g), z: CGFloat(b), w: 0)
        return f.outputImage ?? image
    }

    /// 不透明度混合：用 CIColorMatrix 改 alpha，再 sourceOver。
    private func mix(_ base: CIImage, with overlay: CIImage, t: Double) -> CIImage {
        guard t > 0.001 else { return base }
        let alpha = max(0, min(1, t))
        let masked = overlay.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
        ])
        return masked.composited(over: base)
    }
}
