import CoreMotion
import Foundation
import os

struct LevelReading: Sendable, Equatable {
    var rollDegrees:  Double
    var pitchDegrees: Double
    var isLevel: Bool { abs(rollDegrees) < 1.0 }
    static let zero = LevelReading(rollDegrees: 0, pitchDegrees: 0)
}

@MainActor
final class LevelSensor {
    private let motion = CMMotionManager()
    private(set) var current: LevelReading = .zero
    private let log = Logger(subsystem: "com.aicamera", category: "level")

    /// 启动 10 Hz 设备运动采样。
    func start(onUpdate: @escaping @MainActor (LevelReading) -> Void) {
        guard motion.isDeviceMotionAvailable else {
            log.notice("deviceMotion unavailable")
            return
        }
        if motion.isDeviceMotionActive { return }
        motion.deviceMotionUpdateInterval = 1.0 / 10.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let g = dm.gravity
            let roll  = atan2(g.x, g.y) * 180.0 / .pi
            // 当设备竖向使用时，roll ≈ 0 表示水平
            let normalizedRoll = (roll + 180).truncatingRemainder(dividingBy: 360) - 180
            let pitch = atan2(-g.z, hypot(g.x, g.y)) * 180.0 / .pi
            let reading = LevelReading(rollDegrees: -normalizedRoll, pitchDegrees: pitch)
            self.current = reading
            onUpdate(reading)
        }
    }

    func stop() {
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }
}
