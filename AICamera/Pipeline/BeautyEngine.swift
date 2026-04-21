import CoreImage
import CoreImage.CIFilterBuiltins

/// 本地美颜引擎：磨皮 / 美白 / 锐化 / 大眼 / 瘦脸。
/// 全部基于 Core Image 内建滤镜，无外部模型，无第三方依赖。
struct BeautyEngine: Sendable {

    /// 输入：原始 CIImage（与 ExtentRect 对齐的相机帧）
    /// faces：当前帧最近一次平滑后的人脸观测（归一化到 image.extent）
    /// downsampleScale：磨皮时的降采样比例（< 1 提升性能）
    func apply(_ image: CIImage,
               settings: BeautySettings,
               faces: [FaceObservation],
               downsampleScale: CGFloat = 0.6) -> CIImage {
        guard settings.enabled else { return image }
        var result = image

        // 1) 磨皮（最贵，先降采样、再上采样）
        if settings.smoothing > 0.005 {
            result = smoothSkin(result, intensity: settings.smoothing, scale: downsampleScale)
        }
        // 2) 美白（曲线 + 略微提饱和）
        if settings.whitening > 0.005 {
            result = whiten(result, intensity: settings.whitening)
        }
        // 3) 锐化（避免噪点：unsharpMask 半径取小值）
        if settings.sharpness > 0.005 {
            result = sharpen(result, intensity: settings.sharpness)
        }
        // 4) 瘦脸 + 大眼（依赖人脸关键点）
        if !faces.isEmpty {
            if settings.slimFace > 0.005 {
                result = slimFace(result, faces: faces, intensity: settings.slimFace)
            }
            if settings.bigEye > 0.005 {
                result = enlargeEyes(result, faces: faces, intensity: settings.bigEye)
            }
        }
        return result.cropped(to: image.extent)
    }

    // MARK: - 磨皮（双边滤波 + 原图融合）

    private func smoothSkin(_ image: CIImage, intensity: Double, scale: CGFloat) -> CIImage {
        let s = max(0.3, min(1.0, scale))
        let downscaled: CIImage
        if abs(s - 1.0) > 0.01 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image
            f.scale = Float(s)
            f.aspectRatio = 1.0
            downscaled = f.outputImage ?? image
        } else {
            downscaled = image
        }

        // 双边滤波：CINoiseReduction 在保边平滑上效果好且性能稳定
        let nr = CIFilter.noiseReduction()
        nr.inputImage = downscaled
        nr.noiseLevel = Float(0.02 + 0.10 * intensity)
        nr.sharpness  = Float(0.40)
        let blurred = nr.outputImage ?? downscaled

        let upscaled: CIImage
        if abs(s - 1.0) > 0.01 {
            let up = CIFilter.lanczosScaleTransform()
            up.inputImage = blurred
            up.scale = Float(1.0 / s)
            up.aspectRatio = 1.0
            upscaled = (up.outputImage ?? blurred).cropped(to: image.extent)
        } else {
            upscaled = blurred
        }

        return alphaBlend(upscaled, over: image, alpha: intensity)
    }

    // MARK: - 美白（提亮 + 略微降饱和保留肤色，再轻微暖色补偿）

    private func whiten(_ image: CIImage, intensity: Double) -> CIImage {
        let i = max(0, min(1, intensity))
        let cc = CIFilter.colorControls()
        cc.inputImage = image
        cc.brightness = Float(0.06 * i)
        cc.contrast   = 1.0 + Float(0.04 * i)
        cc.saturation = 1.0 - Float(0.05 * i)
        let bright = cc.outputImage ?? image

        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = bright
        temp.neutral = CIVector(x: 6500 - CGFloat(220 * i), y: 0)
        temp.targetNeutral = CIVector(x: 6500, y: 0)
        return temp.outputImage ?? bright
    }

    // MARK: - 锐化

    private func sharpen(_ image: CIImage, intensity: Double) -> CIImage {
        let f = CIFilter.unsharpMask()
        f.inputImage = image
        f.radius    = Float(1.2)
        f.intensity = Float(0.4 * intensity)
        return f.outputImage ?? image
    }

    // MARK: - 瘦脸（按脸部包围盒中心做 CIPinchDistortion）

    private func slimFace(_ image: CIImage, faces: [FaceObservation], intensity: Double) -> CIImage {
        var result = image
        let extent = image.extent
        for face in faces {
            let center = CGPoint(
                x: extent.origin.x + face.boundingBox.midX * extent.width,
                y: extent.origin.y + face.boundingBox.midY * extent.height
            )
            let radius = max(extent.width, extent.height) * face.boundingBox.width * 0.55
            let f = CIFilter.pinchDistortion()
            f.inputImage = result
            f.center = center
            f.radius = Float(radius)
            f.scale  = Float(0.18 * intensity)        // 正值向中心收缩
            result = f.outputImage ?? result
        }
        return result
    }

    // MARK: - 大眼（CIBumpDistortion，正向放大）

    private func enlargeEyes(_ image: CIImage, faces: [FaceObservation], intensity: Double) -> CIImage {
        var result = image
        let extent = image.extent
        for face in faces {
            let eyeRadius = max(extent.width, extent.height) * face.boundingBox.width * 0.18
            for eye in [face.leftEye, face.rightEye].compactMap({ $0 }) {
                let center = CGPoint(
                    x: extent.origin.x + eye.x * extent.width,
                    y: extent.origin.y + eye.y * extent.height
                )
                let f = CIFilter.bumpDistortion()
                f.inputImage = result
                f.center = center
                f.radius = Float(eyeRadius)
                f.scale  = Float(0.30 * intensity)
                result = f.outputImage ?? result
            }
        }
        return result
    }

    // MARK: - 工具

    private func alphaBlend(_ top: CIImage, over base: CIImage, alpha: Double) -> CIImage {
        let a = max(0, min(1, alpha))
        let masked = top.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a))
        ])
        return masked.composited(over: base)
    }
}
