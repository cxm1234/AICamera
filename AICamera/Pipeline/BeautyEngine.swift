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

    // MARK: - 磨皮（频率分离 + 高频衰减 + 人脸柔边 mask）
    //
    // 算法：
    //   low  = GaussianBlur(image, large)         // 低频：肤色与瑕疵
    //   high = image - low + 0.5                  // 高频：皮肤纹理与边缘
    //   high'= (high - 0.5) * (1 - k * i) + 0.5   // 衰减高频强度（k=0.85）
    //   smooth = low + (high' - 0.5)              // 重构：保留结构、去掉颗粒
    //   mask = 椭圆柔边（按 face boundingBox），无脸时退化为整图
    //   final = blend(smooth, image, mask * pow(i, 0.65))
    //
    // 这是 Snapseed / Facetune 同源的"频率分离"磨皮。intensity=1 时高频近乎抹平
    // 形成瓷感；intensity=0.5 时衰减 ~42%，肤色细腻但五官锐度保留。
    private func smoothSkin(_ image: CIImage,
                            intensity: Double,
                            faces: [FaceObservation],
                            scale: CGFloat) -> CIImage {
        let i = max(0, min(1, intensity))
        let extent = image.extent

        // 1) 降采样（默认 0.5x）
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

        // 2) 低频（强高斯模糊）
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = down.clampedToExtent()
        blur.radius = Float(3.0 + 9.0 * i)              // 3..12 in 0.5x 空间
        let lowFreq = (blur.outputImage ?? down).cropped(to: downExtent)

        // 3) 高频 = down - lowFreq + 0.5
        let sub = CIFilter.subtractBlendMode()
        sub.inputImage = down
        sub.backgroundImage = lowFreq
        let detailRaw = (sub.outputImage ?? down).cropped(to: downExtent)
        let detailShifted = detailRaw.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0)
        ])

        // 4) 高频衰减
        let strength = CGFloat(1.0 - 0.85 * i)
        let bias = 0.5 * (1 - strength)
        let detailAtt = detailShifted.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector":    CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputGVector":    CIVector(x: 0, y: strength, z: 0, w: 0),
            "inputBVector":    CIVector(x: 0, y: 0, z: strength, w: 0),
            "inputAVector":    CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ])

        // 5) 重组 lowFreq + (detailAtt - 0.5)
        let add = CIFilter.additionCompositing()
        add.inputImage = detailAtt
        add.backgroundImage = lowFreq
        let combined = (add.outputImage ?? down).cropped(to: downExtent)
        let smoothedDown = combined.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0)
        ])

        // 6) 上采样回原尺寸
        let smoothed: CIImage
        if abs(s - 1.0) > 0.01 {
            let u = CIFilter.lanczosScaleTransform()
            u.inputImage = smoothedDown
            u.scale = Float(1.0 / s)
            u.aspectRatio = 1.0
            smoothed = (u.outputImage ?? smoothedDown).cropped(to: extent)
        } else {
            smoothed = smoothedDown
        }

        // 7) 用 face mask 限制只磨脸；强度走感知曲线 pow(i, 0.65)
        let mask = makeFaceMask(in: extent, faces: faces, intensity: i)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = smoothed
        blend.backgroundImage = image
        blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// 构造柔边人脸 mask（白=磨皮，黑=保留原图）。
    /// - 无脸：整图均匀强度 = pow(i, 0.65)
    /// - 有脸：每张脸一个 radial gradient，叠加并 clamp 到 [0,1]
    private func makeFaceMask(in extent: CGRect,
                              faces: [FaceObservation],
                              intensity: Double) -> CIImage {
        let strength = CGFloat(pow(intensity, 0.65))

        if faces.isEmpty {
            return CIImage(color: CIColor(red: strength, green: strength, blue: strength, alpha: 1))
                .cropped(to: extent)
        }

        var combined = CIImage(color: .black).cropped(to: extent)
        let span = max(extent.width, extent.height)
        for face in faces {
            let center = CGPoint(
                x: extent.origin.x + face.boundingBox.midX * extent.width,
                y: extent.origin.y + face.boundingBox.midY * extent.height
            )
            // 用脸部包围盒短边作为基准，r0 = 实心区域，r1 = 完全衰减半径
            let faceSpan = max(face.boundingBox.width, face.boundingBox.height) * span
            let r0 = faceSpan * 0.45
            let r1 = faceSpan * 0.78

            let g = CIFilter.radialGradient()
            g.center  = center
            g.radius0 = Float(r0)
            g.radius1 = Float(r1)
            g.color0  = CIColor(red: strength, green: strength, blue: strength, alpha: 1)
            g.color1  = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            let layer = (g.outputImage ?? combined).cropped(to: extent)

            let merge = CIFilter.additionCompositing()
            merge.inputImage = layer
            merge.backgroundImage = combined
            combined = (merge.outputImage ?? combined).cropped(to: extent)
        }

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = combined
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return (clamp.outputImage ?? combined).cropped(to: extent)
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
