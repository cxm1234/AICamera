import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import UIKit
import os

/// 相机主屏的 ViewModel：编排 actor、暴露 UI 状态、收集错误。
@Observable
@MainActor
final class CameraViewModel {

    // MARK: - UI 状态（视图直接读取）

    var permission: PermissionState = .unknown
    var configuration = CameraConfiguration()
    var beauty = BeautySettings()
    var beautyDimension: BeautyDimension = .smoothing
    var selectedFilter: FilterPreset = .original
    var filterIntensity: Double = 1.0
    var mode: CameraMode = .photo
    var lastCaptured: CapturedPhoto?
    var isShowingPreview: Bool = false
    var isCapturing: Bool = false
    var toast: ToastMessage?
    var focusIndicator: FocusIndicatorState?
    var countdownRemaining: Int = 0
    var availableFilters: [FilterPreset] = FilterPreset.all

    // MARK: - 渲染桥（注入到 PreviewView）

    let previewBox = CameraPreviewView.Box()

    // MARK: - 私有依赖

    private let cameraService = CameraService()
    private let photoSaver = PhotoLibrarySaver()
    private let faceDetector = FaceDetector()
    private var processor: FrameProcessor?
    private var frameTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.aicamera", category: "vm")
    private let signpost = OSSignposter(subsystem: "com.aicamera", category: "vm")

    // MARK: - 启动

    init() {
        permission = CameraPermissions.camera
        Task { await cameraService.bootstrap() }
    }

    /// 由视图 onAppear 调用。串行做完：权限→预览渲染绑定→订阅帧→启动 session。
    func onAppear() async {
        if permission != .authorized {
            permission = await CameraPermissions.requestCamera()
        }
        guard permission == .authorized else { return }
        attachProcessorIfNeeded()
        await startStreaming()
        do {
            try await cameraService.start()
            HapticsManager.shared.prepare()
        } catch {
            present(error)
        }
    }

    func onDisappear() async {
        frameTask?.cancel()
        frameTask = nil
        await cameraService.stop()
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if permission == .authorized { Task { await onAppear() } }
        case .background, .inactive:
            Task { await onDisappear() }
        @unknown default: break
        }
    }

    // MARK: - 用户意图

    func toggleFlash() {
        configuration.flashMode = configuration.flashMode.next
        let mode = configuration.flashMode
        Task { await cameraService.setFlashMode(mode) }
        HapticsManager.shared.tick()
    }

    func cycleTimer() {
        let all = ShutterTimer.allCases
        let idx = (all.firstIndex(of: configuration.timer) ?? 0)
        configuration.timer = all[(idx + 1) % all.count]
        HapticsManager.shared.tick()
    }

    func toggleGrid() {
        configuration.isGridVisible.toggle()
        HapticsManager.shared.tick()
    }

    func toggleAspect() {
        let all = AspectRatio.allCases
        let idx = (all.firstIndex(of: configuration.aspectRatio) ?? 0)
        configuration.aspectRatio = all[(idx + 1) % all.count]
        HapticsManager.shared.tick()
    }

    func selectMode(_ m: CameraMode) {
        guard mode != m else { return }
        mode = m
        HapticsManager.shared.soft()
    }

    func selectFilter(_ preset: FilterPreset) {
        guard preset != selectedFilter else { return }
        selectedFilter = preset
        if preset.kind == .original { filterIntensity = 1.0 }
        syncProcessorContext()
        HapticsManager.shared.tick()
    }

    func updateFilterIntensity(_ value: Double) {
        filterIntensity = value
        syncProcessorContext()
    }

    func updateBeauty(dimension: BeautyDimension, value: Double) {
        switch dimension {
        case .smoothing: beauty.smoothing = value
        case .whitening: beauty.whitening = value
        case .sharpness: beauty.sharpness = value
        case .slimFace:  beauty.slimFace  = value
        case .bigEye:    beauty.bigEye    = value
        }
        syncProcessorContext()
    }

    func selectBeautyDimension(_ d: BeautyDimension) {
        beautyDimension = d
        HapticsManager.shared.tick()
    }

    func applyBeautyPreset(_ preset: BeautySettings) {
        beauty = preset
        syncProcessorContext()
        HapticsManager.shared.soft()
    }

    func switchCamera() {
        Task {
            do {
                try await cameraService.switchCamera()
                let cfg = await cameraService.configuration
                configuration.position = cfg.position
                HapticsManager.shared.soft()
            } catch {
                present(error)
            }
        }
    }

    func focus(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        focusIndicator = FocusIndicatorState(location: point, id: UUID())
        Task { await cameraService.setFocus(at: normalized) }
        HapticsManager.shared.light()
    }

    func setZoom(_ factor: CGFloat) {
        Task { await cameraService.setZoom(factor) }
    }

    func capture() {
        guard !isCapturing else { return }
        let timer = configuration.timer
        if timer != .off {
            startCountdown(seconds: timer.rawValue) { [weak self] in
                self?.performCapture()
            }
        } else {
            performCapture()
        }
    }

    func dismissPreview() {
        isShowingPreview = false
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 内部：订阅帧

    private func attachProcessorIfNeeded() {
        guard processor == nil, let renderer = previewBox.renderer else { return }
        processor = FrameProcessor(faceDetector: faceDetector, sink: renderer)
        syncProcessorContext()
    }

    private func startStreaming() async {
        attachProcessorIfNeeded()
        guard let processor else { return }
        frameTask?.cancel()
        let stream = await cameraService.frames()
        frameTask = Task.detached(priority: .userInitiated) { [processor] in
            for await frame in stream {
                if Task.isCancelled { break }
                processor.process(frame)
            }
        }
    }

    private func syncProcessorContext() {
        let ctx = FrameContext(
            filter: selectedFilter.kind,
            filterIntensity: filterIntensity,
            beauty: beauty
        )
        processor?.updateContext(ctx)
    }

    // MARK: - 拍摄实现

    private func performCapture() {
        let snapshotFilter = selectedFilter.kind
        let snapshotIntensity = filterIntensity
        let snapshotBeauty = beauty
        let isFront = (configuration.position == .front)
        let saver = photoSaver
        let detector = faceDetector

        isCapturing = true
        HapticsManager.shared.medium()
        let signpostID = signpost.makeSignpostID()
        let signpostState = signpost.beginInterval("capture", id: signpostID)

        Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isCapturing = false
                    self?.signpost.endInterval("capture", signpostState)
                }
            }
            do {
                let raw = try await self?.cameraService.capturePhoto()
                guard let raw else { return }
                let processed = Self.process(raw: raw,
                                             filter: snapshotFilter,
                                             intensity: snapshotIntensity,
                                             beauty: snapshotBeauty,
                                             isFront: isFront,
                                             faces: detector.latest)
                guard let cg = SharedRender.ciContext.createCGImage(processed, from: processed.extent) else {
                    throw CameraError.captureFailed("无法生成最终图像")
                }
                let ui = UIImage(cgImage: cg)
                guard let data = ui.heicData() ?? ui.jpegData(compressionQuality: 0.94) else {
                    throw CameraError.captureFailed("无法编码图像")
                }
                let assetID = try await saver.save(imageData: data)
                let captured = CapturedPhoto(thumbnail: ui, assetIdentifier: assetID)
                await MainActor.run {
                    self?.lastCaptured = captured
                    self?.isShowingPreview = true
                    HapticsManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    self?.present(error)
                    HapticsManager.shared.error()
                }
            }
        }
    }

    nonisolated private static func process(raw: CapturedRaw,
                                            filter: FilterKind,
                                            intensity: Double,
                                            beauty: BeautySettings,
                                            isFront: Bool,
                                            faces: [FaceObservation]) -> CIImage {
        var image = raw.image
        if isFront {
            // 前置自拍按"所见即所得"翻转，否则保存出来的方向与预览相反
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                         .transformed(by: CGAffineTransform(translationX: image.extent.width, y: 0))
        }
        let filtered = FilterEngine().apply(image, kind: filter, intensity: intensity)
        let beautified = BeautyEngine().apply(filtered, settings: beauty, faces: faces)
        return beautified
    }

    // MARK: - 倒计时

    private func startCountdown(seconds: Int, completion: @escaping @MainActor () -> Void) {
        countdownTask?.cancel()
        countdownRemaining = seconds
        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for tick in stride(from: seconds, through: 1, by: -1) {
                self.countdownRemaining = tick
                HapticsManager.shared.light()
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.countdownRemaining = 0
            completion()
        }
    }

    // MARK: - 错误

    private func present(_ error: Error) {
        log.error("\(error.localizedDescription, privacy: .public)")
        toast = ToastMessage(text: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }
}

// MARK: - 辅助小型值类型

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct FocusIndicatorState: Equatable {
    let location: CGPoint
    let id: UUID
}
