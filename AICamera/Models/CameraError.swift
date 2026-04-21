import Foundation

enum CameraError: Error, LocalizedError, Sendable, Equatable {
    case denied
    case deviceUnavailable
    case configurationFailed(String)
    case captureFailed(String)
    case saveFailed(String)
    case interrupted

    var errorDescription: String? {
        switch self {
        case .denied:                       return "相机权限未开启"
        case .deviceUnavailable:            return "未找到可用相机"
        case .configurationFailed(let m):   return "相机初始化失败：\(m)"
        case .captureFailed(let m):         return "拍摄失败：\(m)"
        case .saveFailed(let m):            return "保存失败：\(m)"
        case .interrupted:                  return "相机被中断，请稍后再试"
        }
    }
}
