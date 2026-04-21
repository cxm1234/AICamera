import SwiftUI

struct LevelView: View {
    let reading: LevelReading

    var body: some View {
        let isLevel = reading.isLevel
        let color: Color = isLevel ? .green : Theme.Color.onSurface

        ZStack {
            // 中心固定参考线
            Rectangle()
                .frame(width: 36, height: 1)
                .foregroundStyle(Theme.Color.onSurfaceMuted)

            // 旋转随陀螺仪变化的指示线
            Rectangle()
                .frame(width: 64, height: 1.5)
                .foregroundStyle(color)
                .rotationEffect(.degrees(reading.rollDegrees))
                .animation(.easeOut(duration: 0.08), value: reading.rollDegrees)

            // 中心点
            Circle()
                .frame(width: 4, height: 4)
                .foregroundStyle(color)
        }
        .frame(width: 80, height: 24)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.Color.surfaceStrong, in: Capsule())
        .overlay(Capsule().stroke(Theme.Color.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
