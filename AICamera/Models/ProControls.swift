import CoreGraphics
import Foundation

enum ExposureMode: String, Sendable, Equatable {
    case auto, manual
    var displayName: String { self == .auto ? "AUTO" : "MANUAL" }
}

enum FocusMode: String, Sendable, Equatable {
    case auto, manual
    var displayName: String { self == .auto ? "AF" : "MF" }
}

/// 用户当前的专业控件状态。值类型，安全跨 actor 边界。
struct ProSettings: Sendable, Equatable {
    var exposureMode: ExposureMode = .auto
    var focusMode:    FocusMode    = .auto
    var iso:               Float = 100
    var shutterSeconds:    Double = 1.0 / 60.0
    var exposureBiasEV:    Float = 0
    var lensPosition:      Float = 0.5
    var lockedAEAF:        Bool = false
}

/// 当前镜头能力的快照。actor 计算后返回给 ViewModel。
struct DeviceCapabilities: Sendable, Equatable {
    var minISO: Float = 22
    var maxISO: Float = 3200
    var minShutter: Double = 1.0 / 8000     // 短到 1/8000 s
    var maxShutter: Double = 1.0 / 2.0      // 最长 0.5 s（避免预览卡顿）
    var minBiasEV: Float = -2
    var maxBiasEV: Float = 2
    var maxZoom: CGFloat = 1
    var lensStops: [LensZoomStop] = []
    var supportsCustomExposure = false
    var supportsManualFocus    = false
    /// 只读：当前镜头型号显示名（如 "Wide"/"UltraWide"/"Tele"）
    var deviceLabel: String = ""

    static let empty = DeviceCapabilities()
}

struct LensZoomStop: Hashable, Sendable, Identifiable {
    let label: String
    let factor: CGFloat
    var id: String { label }
}

/// 一些常用快门档位（仅用于拨盘吸附与显示）。
enum ShutterPresets {
    static let table: [Double] = [
        1.0/8000, 1.0/4000, 1.0/2000, 1.0/1000,
        1.0/500,  1.0/250,  1.0/125,  1.0/60,
        1.0/30,   1.0/15,   1.0/8,    1.0/4,
        1.0/2
    ]

    static func displayName(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        let denom = (1.0 / seconds).rounded()
        return "1/\(Int(denom))"
    }

    /// 从连续值找最近的档位 index。
    static func nearestIndex(to seconds: Double) -> Int {
        var best = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, v) in table.enumerated() {
            let d = abs(log(v) - log(seconds))
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }
}
