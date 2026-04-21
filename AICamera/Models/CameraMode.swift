import Foundation

enum CameraMode: String, CaseIterable, Identifiable, Sendable {
    case beauty
    case photo
    case filter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beauty: return "美颜"
        case .photo:  return "拍照"
        case .filter: return "滤镜"
        }
    }
}

enum PermissionState: Sendable, Equatable {
    case unknown
    case denied
    case restricted
    case authorized
}
