import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import UIKit
import os

/// 相机会话编排器：actor 内部串行执行所有 session 配置 / 启停 / 切换。
/// 视频帧通过 AsyncStream 暴露给消费者；session delegate 在自己的队列里执行。
actor CameraService {

    // MARK: - Public state

    private(set) var configuration = CameraConfiguration()
    private(set) var isRunning = false

    /// 视频帧流。多次订阅会替换前一个。
    func frames() -> AsyncStream<VideoFrame> {
        let (stream, continuation) = AsyncStream.makeStream(of: VideoFrame.self,
                                                            bufferingPolicy: .bufferingNewest(2))
        frameSink.replace(continuation: continuation)
        return stream
    }

    // MARK: - Internals

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let videoQueue = DispatchQueue(label: "com.aicamera.video", qos: .userInitiated)
    /// 帧投递容器。nonisolated（线程安全）：sample-buffer 回调直接调它，避免回 actor 一跳。
    private let frameSink = FrameContinuationHolder()
    /// 当前镜头朝向的原子缓存，供 nonisolated ingest 读取。
    private let positionCache = PositionCache()
    private var sampleHandler: SampleHandler?
    private let log = Logger(subsystem: "com.aicamera", category: "camera")
    private let signpost = OSSignposter(subsystem: "com.aicamera", category: "camera")

    private var pendingCapture: PendingCapture?

    // MARK: - Bootstrap

    /// 在 App 启动早期可调用，预热 session 配置（不真正启动）。
    func bootstrap() async {
        guard videoInput == nil else { return }
        do {
            try configureSession(position: configuration.position)
        } catch {
            log.error("bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Lifecycle

    func start() async throws {
        if videoInput == nil {
            try configureSession(position: configuration.position)
        }
        guard !session.isRunning else { isRunning = true; return }
        let state = signpost.beginInterval("session.start")
        // AVCaptureSession.startRunning 内部会跳到自己的队列，actor 调用方不会阻塞主线程。
        session.startRunning()
        signpost.endInterval("session.start", state)
        isRunning = session.isRunning
    }

    func stop() async {
        guard session.isRunning else { isRunning = false; return }
        session.stopRunning()
        isRunning = false
    }

    // MARK: - Mutators

    func updateConfiguration(_ block: (inout CameraConfiguration) -> Void) {
        block(&configuration)
    }

    func switchCamera() async throws {
        let target: AVCaptureDevice.Position = (configuration.position == .back) ? .front : .back
        configuration.position = target
        try configureSession(position: target)
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        configuration.flashMode = mode
    }

    /// 视图坐标系（0~1）下的兴趣点
    func setFocus(at point: CGPoint) async {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        } catch {
            log.error("setFocus failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setZoom(_ factor: CGFloat) async {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let clamped = max(1.0, min(device.activeFormat.videoMaxZoomFactor, factor))
            device.videoZoomFactor = clamped
            configuration.zoomFactor = clamped
        } catch {
            log.error("setZoom failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pro controls

    func capabilities() -> DeviceCapabilities {
        guard let device = videoInput?.device else { return .empty }
        let format = device.activeFormat
        let minD = CMTimeGetSeconds(format.minExposureDuration)
        let maxD = min(CMTimeGetSeconds(format.maxExposureDuration), 0.5)
        let minBias = device.minExposureTargetBias
        let maxBias = device.maxExposureTargetBias

        return DeviceCapabilities(
            minISO: format.minISO,
            maxISO: format.maxISO,
            minShutter: minD,
            maxShutter: maxD,
            minBiasEV: max(minBias, -2),
            maxBiasEV: min(maxBias, 2),
            maxZoom:  format.videoMaxZoomFactor,
            lensStops: lensStops(for: device),
            supportsCustomExposure: device.isExposureModeSupported(.custom),
            supportsManualFocus: device.isFocusModeSupported(.locked) && device.isLockingFocusWithCustomLensPositionSupported,
            deviceLabel: deviceDisplayLabel(device)
        )
    }

    func setExposureMode(_ mode: ExposureMode) {
        guard let device = videoInput?.device else { return }
        let target: AVCaptureDevice.ExposureMode = (mode == .auto) ? .continuousAutoExposure : .custom
        guard device.isExposureModeSupported(target) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.exposureMode = target
        } catch {
            log.error("setExposureMode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 将 ISO 或快门设到自定义曝光（device 必须支持 .custom）。
    func setManualExposure(iso: Float?, shutterSeconds: Double?) {
        guard let device = videoInput?.device, device.isExposureModeSupported(.custom) else { return }
        let format = device.activeFormat
        let isoTarget: Float = iso.map { max(format.minISO, min(format.maxISO, $0)) }
            ?? AVCaptureDevice.currentISO
        let shutterTarget: CMTime
        if let sec = shutterSeconds {
            let minSec = CMTimeGetSeconds(format.minExposureDuration)
            let maxSec = min(CMTimeGetSeconds(format.maxExposureDuration), 0.5)
            let clamped = max(minSec, min(maxSec, sec))
            shutterTarget = CMTime(seconds: clamped, preferredTimescale: 1_000_000_000)
        } else {
            shutterTarget = AVCaptureDevice.currentExposureDuration
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.exposureMode != .custom { device.exposureMode = .custom }
            device.setExposureModeCustom(duration: shutterTarget, iso: isoTarget, completionHandler: nil)
        } catch {
            log.error("setManualExposure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setExposureBias(_ ev: Float) {
        guard let device = videoInput?.device else { return }
        let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, ev))
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setExposureTargetBias(clamped, completionHandler: nil)
        } catch {
            log.error("setExposureBias failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setFocusMode(_ mode: FocusMode) {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            switch mode {
            case .auto:
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            case .manual:
                if device.isFocusModeSupported(.locked) && device.isLockingFocusWithCustomLensPositionSupported {
                    device.focusMode = .locked
                }
            }
        } catch {
            log.error("setFocusMode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setLensPosition(_ pos: Float) {
        guard let device = videoInput?.device,
              device.isLockingFocusWithCustomLensPositionSupported else { return }
        let clamped = max(0, min(1, pos))
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
        } catch {
            log.error("setLensPosition failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 切到指定焦段；smooth=true 时使用 ramp，false 直接赋值。
    func setZoomStop(_ stop: LensZoomStop, smooth: Bool) {
        guard let device = videoInput?.device else { return }
        let clamped = max(1.0, min(device.activeFormat.videoMaxZoomFactor, stop.factor))
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isRampingVideoZoom {
                device.cancelVideoZoomRamp()
            }
            if smooth {
                device.ramp(toVideoZoomFactor: clamped, withRate: 6.0)
            } else {
                device.videoZoomFactor = clamped
            }
            configuration.zoomFactor = clamped
        } catch {
            log.error("setZoomStop failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 长按预览：锁定 AE/AF。返回是否成功。
    @discardableResult
    func lockAEAF() -> Bool {
        guard let device = videoInput?.device else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
            return true
        } catch {
            log.error("lockAEAF failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func unlockAEAF() {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        } catch {
            log.error("unlockAEAF failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Capture

    /// 拍照。返回原图像素缓冲（已应用方向），由调用方继续处理（滤镜/美颜）+ 落盘。
    func capturePhoto() async throws -> CapturedRaw {
        guard session.isRunning else { throw CameraError.captureFailed("会话未运行") }
        let settings = makePhotoSettings()
        let isFront = (configuration.position == .front)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CapturedRaw, Error>) in
            let delegate = PhotoCaptureDelegate(isFront: isFront) { [weak self] result in
                Task { await self?.clearPending() }
                cont.resume(with: result)
            }
            self.pendingCapture = PendingCapture(delegate: delegate)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func clearPending() {
        pendingCapture = nil
    }

    // MARK: - Session config

    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 旧 input
        if let old = videoInput { session.removeInput(old) }

        // 新 input
        guard let device = bestDevice(for: position) else {
            throw CameraError.deviceUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("无法添加视频输入")
        }
        session.addInput(input)
        videoInput = input

        // 视频输出（用于实时预览）
        if !session.outputs.contains(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let handler = SampleHandler(owner: self)
            sampleHandler = handler
            videoOutput.setSampleBufferDelegate(handler, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else {
                throw CameraError.configurationFailed("无法添加视频输出")
            }
            session.addOutput(videoOutput)
        }

        // 拍照输出
        if !session.outputs.contains(photoOutput) {
            photoOutput.maxPhotoQualityPrioritization = .balanced
            guard session.canAddOutput(photoOutput) else {
                throw CameraError.configurationFailed("无法添加拍照输出")
            }
            session.addOutput(photoOutput)
        }

        // 方向 / 镜像（iOS 17+ 用 videoRotationAngle，竖屏 = 90°）
        let portraitAngle: CGFloat = 90
        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(portraitAngle) {
                conn.videoRotationAngle = portraitAngle
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (position == .front)
            }
        }
        if let conn = photoOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(portraitAngle) {
                conn.videoRotationAngle = portraitAngle
            }
            if conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = (position == .front)
            }
        }

        configuration.zoomFactor = device.videoZoomFactor
        positionCache.set(isFront: position == .front)
    }

    private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera
        ]
        for type in preferredTypes {
            if let d = AVCaptureDevice.default(type, for: .video, position: position) { return d }
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// 根据当前 device 探测可用的多镜头变焦档位。
    /// - 物理设备只有单镜头：返回 [1×]
    /// - 虚拟设备（双 / 三摄）：用 `virtualDeviceSwitchOverVideoZoomFactors` + 是否带 ultrawide 决定档位
    private func lensStops(for device: AVCaptureDevice) -> [LensZoomStop] {
        let maxZoom = device.activeFormat.videoMaxZoomFactor
        var stops: [LensZoomStop] = []

        let constituents = device.constituentDevices
        let hasUltraWide = constituents.contains { $0.deviceType == .builtInUltraWideCamera }
            || device.deviceType == .builtInUltraWideCamera

        if hasUltraWide {
            stops.append(LensZoomStop(label: "0.5×", factor: 1.0)) // 虚拟相机的 1.0 = 广角，超广角通过 0.5 表示在 UI 上
        }

        // 1× 总是可用
        let oneXFactor: CGFloat = hasUltraWide ? 2.0 : 1.0
        stops.append(LensZoomStop(label: "1×", factor: oneXFactor))

        // 2×：广角自适应（虚拟相机的 2x 通常对应 4，单镜头则 2）
        if maxZoom >= oneXFactor * 2 {
            stops.append(LensZoomStop(label: "2×", factor: oneXFactor * 2))
        }

        // 3× / 5×：使用 virtual device 的切换点
        for cross in device.virtualDeviceSwitchOverVideoZoomFactors {
            let f = CGFloat(truncating: cross)
            // 跳过已包含的档位
            if stops.contains(where: { abs($0.factor - f) < 0.05 }) { continue }
            let displayed = f / oneXFactor
            let label: String
            if displayed >= 4.5 {
                label = "5×"
            } else if displayed >= 2.5 {
                label = "3×"
            } else {
                continue
            }
            stops.append(LensZoomStop(label: label, factor: f))
        }

        return stops
    }

    private func deviceDisplayLabel(_ device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInTripleCamera:    return "Triple"
        case .builtInDualCamera:      return "Dual"
        case .builtInDualWideCamera:  return "Dual Wide"
        case .builtInWideAngleCamera: return "Wide"
        case .builtInUltraWideCamera: return "Ultra Wide"
        case .builtInTelephotoCamera: return "Tele"
        default:                      return device.localizedName
        }
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        if let device = videoInput?.device, device.hasFlash {
            if photoOutput.supportedFlashModes.contains(configuration.flashMode) {
                settings.flashMode = configuration.flashMode
            }
        }
        settings.photoQualityPrioritization = .balanced
        return settings
    }

    // MARK: - Frame ingest (called by SampleHandler on videoQueue)

    /// sample buffer 回调专用：不跳回 actor，直接投递到 frameSink。
    /// 读取 isFront 通过原子缓存，避免主 actor 跳转。
    fileprivate nonisolated func ingest(_ sampleBuffer: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frame = VideoFrame(
            pixelBuffer: pb,
            presentationTime: pts,
            orientation: .up,
            isFrontCamera: positionCache.isFront
        )
        frameSink.yield(frame)
    }
}

// MARK: - Helpers

/// 帧续流的线程安全持有者：actor 与 capture queue 都能安全访问。
private final class FrameContinuationHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<VideoFrame>.Continuation?

    func replace(continuation new: AsyncStream<VideoFrame>.Continuation) {
        lock.lock()
        let old = continuation
        continuation = new
        lock.unlock()
        old?.finish()
    }

    func yield(_ frame: VideoFrame) {
        lock.lock()
        let c = continuation
        lock.unlock()
        c?.yield(frame)
    }
}

/// 当前镜头朝向的原子缓存。
private final class PositionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var _isFront = false
    var isFront: Bool {
        lock.lock(); defer { lock.unlock() }; return _isFront
    }
    func set(isFront value: Bool) {
        lock.lock(); _isFront = value; lock.unlock()
    }
}

/// SampleBuffer 代理：单独的 NSObject 子类，避免 actor 直接遵循协议引发的隔离问题。
private final class SampleHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    weak var owner: CameraService?
    init(owner: CameraService) { self.owner = owner }
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        owner?.ingest(sampleBuffer)
    }
}

/// 拍照原始结果（已带方向，未做美颜/滤镜）。
struct CapturedRaw: @unchecked Sendable {
    let image: CIImage
    let originalData: Data?
    let isFront: Bool
}

/// 拍照委托：把 didFinishProcessing 转成 async 回调。
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<CapturedRaw, Error>) -> Void
    private let isFront: Bool
    init(isFront: Bool, completion: @escaping @Sendable (Result<CapturedRaw, Error>) -> Void) {
        self.isFront = isFront
        self.completion = completion
    }
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            completion(.failure(CameraError.captureFailed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            completion(.failure(CameraError.captureFailed("无法读取照片数据")))
            return
        }
        let ci = CIImage(cgImage: cg)
        completion(.success(CapturedRaw(image: ci, originalData: data, isFront: isFront)))
    }
}

/// 把 delegate 持引用，防止在回调到达前被释放。
private struct PendingCapture {
    let delegate: NSObject
}
