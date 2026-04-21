import Foundation

/// 美颜参数（每项 0...1，UI 上展示为 0~100）。
struct BeautySettings: Sendable, Equatable {
    var smoothing: Double = 0
    var whitening: Double = 0
    var sharpness: Double = 0
    var slimFace: Double = 0
    var bigEye:   Double = 0

    static let zero = BeautySettings()

    static let natural = BeautySettings(
        smoothing: 0.45, whitening: 0.25, sharpness: 0.20,
        slimFace: 0.20, bigEye: 0.15
    )

    static let glam = BeautySettings(
        smoothing: 0.75, whitening: 0.55, sharpness: 0.30,
        slimFace: 0.45, bigEye: 0.35
    )

    /// 是否需要走美颜管线。低于阈值视为关闭，可短路加速。
    var enabled: Bool {
        smoothing + whitening + sharpness + slimFace + bigEye > 0.005
    }

    /// 是否需要人脸关键点（瘦脸/大眼依赖）
    var needsFaceLandmarks: Bool {
        slimFace > 0.005 || bigEye > 0.005
    }
}

enum BeautyDimension: String, CaseIterable, Identifiable, Sendable {
    case smoothing, whitening, sharpness, slimFace, bigEye
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .smoothing: return "磨皮"
        case .whitening: return "美白"
        case .sharpness: return "锐化"
        case .slimFace:  return "瘦脸"
        case .bigEye:    return "大眼"
        }
    }
    var icon: String {
        switch self {
        case .smoothing: return "wand.and.stars"
        case .whitening: return "sun.max.fill"
        case .sharpness: return "circle.hexagongrid.fill"
        case .slimFace:  return "face.dashed"
        case .bigEye:    return "eye.fill"
        }
    }
}
