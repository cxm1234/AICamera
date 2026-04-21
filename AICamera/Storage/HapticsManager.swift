import UIKit

/// 触感反馈管家。预热生成器，避免首次使用时的延迟。
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    private let lightImpact  = UIImpactFeedbackGenerator(style: .light)
    private let softImpact   = UIImpactFeedbackGenerator(style: .soft)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpact  = UIImpactFeedbackGenerator(style: .rigid)
    private let selection    = UISelectionFeedbackGenerator()
    private let notify       = UINotificationFeedbackGenerator()

    private init() {
        prepare()
    }

    func prepare() {
        lightImpact.prepare()
        softImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        selection.prepare()
        notify.prepare()
    }

    func light()      { lightImpact.impactOccurred() }
    func soft()       { softImpact.impactOccurred() }
    func medium()     { mediumImpact.impactOccurred() }
    func rigid()      { rigidImpact.impactOccurred() }
    func tick()       { selection.selectionChanged() }
    func success()    { notify.notificationOccurred(.success) }
    func warning()    { notify.notificationOccurred(.warning) }
    func error()      { notify.notificationOccurred(.error) }
}
