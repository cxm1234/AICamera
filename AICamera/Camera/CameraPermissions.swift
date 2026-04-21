import AVFoundation
import Photos

enum CameraPermissions {

    static var camera: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .unknown
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        @unknown default:    return .denied
        }
    }

    static var photoLibraryAdd: PermissionState {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .notDetermined: return .unknown
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized,
             .limited:       return .authorized
        @unknown default:    return .denied
        }
    }

    @discardableResult
    static func requestCamera() async -> PermissionState {
        if camera != .unknown { return camera }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    @discardableResult
    static func requestPhotoLibraryAdd() async -> PermissionState {
        if photoLibraryAdd != .unknown { return photoLibraryAdd }
        let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
        }
        switch status {
        case .authorized, .limited: return .authorized
        case .denied:               return .denied
        case .restricted:           return .restricted
        case .notDetermined:        return .unknown
        @unknown default:           return .denied
        }
    }
}
