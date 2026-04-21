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

        // 1) 磨皮（最贵，先降采样、再上采样；可选 face-mask）
        if settings.smoothing > 0.005 {
            result = smoothSkin(result,
                                intensity: settings.smoothing,
                                faces: faces,
                                scale: downsampleScale)
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

    // MARK: - 磨皮（高斯模糊 + 椭圆柔边 mask + 五官"洞"）
    //
    // 之所以放弃频率分离：CI 内建的 SubtractBlendMode 是 max(0, B-S)，
    // AdditionCompositing 是 min(1, S+B)，两次饱和截断会把皮肤亮区压成
    // 灰平面甚至纯黑。这里改用稳定且效果显著的方案：
    //   1. 在 0.5x 空间对全图做高斯模糊（半径随 intensity 增大）；
    //   2. 上采样回原尺寸；
    //   3. 构造一张柔边人脸 mask：椭圆区域 = peak（=0.85·pow(i,0.65)），
    //      眼睛 / 嘴的位置乘上一个内黑外白的洞 mask，从而保留五官细节；
    //   4. blendWithMask(smoothed, original, mask)。
    //
    // peak ≤ 0.85：即便 intensity=1，仍保留 15% 原始纹理，避免"塑料感"。
    private func smoothSkin(_ image: CIImage,
                            intensity: Double,
                            faces: [FaceObservation],
                            scale: CGFloat) -> CIImage {
        let i = max(0, min(1, intensity))
        let extent = image.extent

        // 1) 降采样
        let s = max(0.3, min(1.0, scale))
        let down: CIImage
        if abs(s - 1.0) > 0.01 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image
            f.scale = Float(s)
            f.aspectRatio = 1.0
            down = (f.outputImage ?? image)
        } else {
            down = image
        }
        let downExtent = down.extent

        // 2) 强高斯模糊（0.5x 空间下半径 2..10 ≈ 原图 4..20）
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = down.clampedToExtent()
        blur.radius = Float(2.0 + 8.0 * i)
        let blurred = (blur.outputImage ?? down).cropped(to: downExtent)

        // 3) 上采样回原尺寸
        let smoothed: CIImage
        if abs(s - 1.0) > 0.01 {
            let u = CIFilter.lanczosScaleTransform()
            u.inputImage = blurred
            u.scale = Float(1.0 / s)
            u.aspectRatio = 1.0
            smoothed = (u.outputImage ?? blurred).cropped(to: extent)
        } else {
            smoothed = blurred
        }

        // 4) 构造 mask（眼睛/嘴有"洞"）
        let mask = makeFaceMask(in: extent, faces: faces, intensity: i)

        // 5) 混合
        let blend = CIFilter.blendWithMask()
        blend.inputImage = smoothed
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// 构造灰度 mask（白 = 用 smoothed，黑 = 用原图）。
    /// - 峰值上限 0.85 · pow(i, 0.65)，避免完全压平；
    /// - 无脸时 fallback 为均匀 0.55·peak（不至于把整图磨糊）；
    /// - 有脸时：椭圆 radial gradient，再 multiply 一个"内黑外白"的洞 mask
    ///   保留眼睛和嘴的锐度。
    private func makeFaceMask(in extent: CGRect,
                              faces: [FaceObservation],
                              intensity: Double) -> CIImage {
        let peak = CGFloat(0.85 * pow(intensity, 0.65))

        if faces.isEmpty {
            let global = peak * 0.55
            return CIImage(color: CIColor(red: global, green: global, blue: global, alpha: 1))
                .cropped(to: extent)
        }

        let span = max(extent.width, extent.height)
        var combined = CIImage(color: .black).cropped(to: extent)

        for face in faces {
            let faceLayer = makeSingleFaceMask(face: face, in: extent, span: span, peak: peak)
            // 多张脸用 lighten，取较亮像素，避免 multiply 互相压暗
            let merge = CIFilter.lightenBlendMode()
            merge.inputImage = faceLayer
            merge.backgroundImage = combined
            combined = (merge.outputImage ?? combined).cropped(to: extent)
        }

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = combined
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return (clamp.outputImage ?? combined).cropped(to: extent)
    }

    /// 单张脸：椭圆磨皮区域 multiply 多个"内黑外白"的洞（眼睛、嘴）。
    private func makeSingleFaceMask(face: FaceObservation,
                                    in extent: CGRect,
                                    span: CGFloat,
                                    peak: CGFloat) -> CIImage {
        let center = CGPoint(
            x: extent.origin.x + face.boundingBox.midX * extent.width,
            y: extent.origin.y + face.boundingBox.midY * extent.height
        )
        let faceSpan = max(face.boundingBox.width, face.boundingBox.height) * span
        let r0 = faceSpan * 0.40
        let r1 = faceSpan * 0.72

        let g = CIFilter.radialGradient()
        g.center  = center
        g.radius0 = Float(r0)
        g.radius1 = Float(r1)
        g.color0  = CIColor(red: peak, green: peak, blue: peak, alpha: 1)
        g.color1  = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        var layer = (g.outputImage ?? CIImage(color: .black)).cropped(to: extent)

        // 五官洞：用 multiplyCompositing，洞中心黑（=0，乘后变 0），外围白（=1，乘后保留）
        for hole in featureHoles(for: face, in: extent, span: span) {
            let h = CIFilter.radialGradient()
            h.center  = hole.center
            h.radius0 = Float(hole.radius0)
            h.radius1 = Float(hole.radius1)
            h.color0  = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            h.color1  = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            let holeMask = (h.outputImage ?? layer).cropped(to: extent)

            let mul = CIFilter.multiplyCompositing()
            mul.inputImage = holeMask
            mul.backgroundImage = layer
            layer = (mul.outputImage ?? layer).cropped(to: extent)
        }
        return layer
    }

    private struct FeatureHole {
        let center: CGPoint
        let radius0: CGFloat
        let radius1: CGFloat
    }

    private func featureHoles(for face: FaceObservation,
                              in extent: CGRect,
                              span: CGFloat) -> [FeatureHole] {
        var holes: [FeatureHole] = []
        let faceSpan = max(face.boundingBox.width, face.boundingBox.height) * span
        let eyeR0 = faceSpan * 0.05
        let eyeR1 = eyeR0 * 2.4
        for eye in [face.leftEye, face.rightEye].compactMap({ $0 }) {
            let c = CGPoint(
                x: extent.origin.x + eye.x * extent.width,
                y: extent.origin.y + eye.y * extent.height
            )
            holes.append(FeatureHole(center: c, radius0: eyeR0, radius1: eyeR1))
        }
        if let mouth = face.mouth {
            let c = CGPoint(
                x: extent.origin.x + mouth.x * extent.width,
                y: extent.origin.y + mouth.y * extent.height
            )
            let mr0 = faceSpan * 0.08
            let mr1 = mr0 * 2.0
            holes.append(FeatureHole(center: c, radius0: mr0, radius1: mr1))
        }
        return holes
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
        f.radius    = Float(1.4)
        f.intensity = Float(0.85 * intensity)
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
