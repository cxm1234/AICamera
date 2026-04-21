import Photos
import UIKit
import os

/// 照片落盘 + 写入相册。actor，串行，避免并发请求。
actor PhotoLibrarySaver {

    private let albumName = "AI Camera"
    private let log = Logger(subsystem: "com.aicamera", category: "library")
    private var cachedAlbum: PHAssetCollection?

    /// 保存图像数据；返回 PHAsset.localIdentifier。
    func save(imageData: Data) async throws -> String {
        let permission = await CameraPermissions.requestPhotoLibraryAdd()
        guard permission == .authorized else {
            throw CameraError.saveFailed("未授权访问相册")
        }
        let album = await ensureAlbum()
        let holder = Box<String>()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: imageData, options: nil)
                if let album, let placeholder = req.placeholderForCreatedAsset,
                   let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
                holder.set(req.placeholderForCreatedAsset?.localIdentifier)
            } completionHandler: { success, error in
                if success, let id = holder.get() {
                    cont.resume(returning: id)
                } else {
                    cont.resume(throwing: CameraError.saveFailed(error?.localizedDescription ?? "未知错误"))
                }
            }
        }
    }

    // MARK: - Album

    private func ensureAlbum() async -> PHAssetCollection? {
        if let cached = cachedAlbum { return cached }
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        let foundHolder = Box<PHAssetCollection>()
        let albumName = self.albumName
        fetch.enumerateObjects { c, _, stop in
            if c.localizedTitle == albumName {
                foundHolder.set(c)
                stop.pointee = true
            }
        }
        if let found = foundHolder.get() {
            cachedAlbum = found
            return found
        }
        let holder = Box<PHObjectPlaceholder>()
        return await withCheckedContinuation { (cont: CheckedContinuation<PHAssetCollection?, Never>) in
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                holder.set(req.placeholderForCreatedAssetCollection)
            } completionHandler: { success, _ in
                guard success, let placeholder = holder.get() else {
                    cont.resume(returning: nil); return
                }
                let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                let album = result.firstObject
                Task { await self.setCached(album) }
                cont.resume(returning: album)
            }
        }
    }

    /// 线程安全的可变盒子。仅用于在 PHPhotoLibrary 的 perform/completion 间桥接可变值。
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ v: T?) { lock.lock(); value = v; lock.unlock() }
        func get() -> T?  { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func setCached(_ album: PHAssetCollection?) {
        cachedAlbum = album
    }
}
