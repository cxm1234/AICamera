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
