import AVFoundation

/// 相机会话级别的配置项。值类型，可安全跨 actor 传递。
struct CameraConfiguration: Sendable, Equatable {
    var position: AVCaptureDevice.Position = .back
    var flashMode: AVCaptureDevice.FlashMode = .off
    var timer: ShutterTimer = .off
    var aspectRatio: AspectRatio = .ratio4x3
    var isGridVisible: Bool = false
    var isLevelVisible: Bool = false
    var zoomFactor: CGFloat = 1.0
}

enum ShutterTimer: Int, CaseIterable, Identifiable, Sendable {
    case off = 0, t3 = 3, t5 = 5, t10 = 10
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .t3:  return "3s"
        case .t5:  return "5s"
        case .t10: return "10s"
        }
    }
}

enum AspectRatio: String, CaseIterable, Identifiable, Sendable {
    case ratio1x1 = "1:1"
    case ratio4x3 = "4:3"
    case ratio16x9 = "16:9"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// 宽 / 高
    var value: CGFloat {
        switch self {
        case .ratio1x1:  return 1.0
        case .ratio4x3:  return 4.0 / 3.0
        case .ratio16x9: return 16.0 / 9.0
        }
    }
}

extension AVCaptureDevice.FlashMode {
    var displayIcon: String {
        switch self {
        case .off:  return SFIcons.flashOff
        case .on:   return SFIcons.flashOn
        case .auto: return SFIcons.flashAuto
        @unknown default: return SFIcons.flashOff
        }
    }

    var next: AVCaptureDevice.FlashMode {
        switch self {
        case .off:  return .auto
        case .auto: return .on
        case .on:   return .off
        @unknown default: return .off
        }
    }
}
