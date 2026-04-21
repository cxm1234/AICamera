import UIKit

/// 拍摄完成后的轻量结果，仅持有缩略图与文件 URL（如已落盘）。
struct CapturedPhoto: Identifiable, Sendable {
    let id: UUID
    let thumbnail: UIImage
    let assetIdentifier: String?
    let createdAt: Date

    init(thumbnail: UIImage, assetIdentifier: String? = nil) {
        self.id = UUID()
        self.thumbnail = thumbnail
        self.assetIdentifier = assetIdentifier
        self.createdAt = Date()
    }
}

