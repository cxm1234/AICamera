import SwiftUI

/// 自定义滑杆：更窄、视觉更精致、带触感反馈。
struct BeautySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false
    @State private var lastTickStep: Int = -1

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let pos = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * w
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Color.separator)
                    .frame(height: 4)
                Capsule()
                    .fill(Theme.Color.primary)
                    .frame(width: max(0, pos), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: max(0, min(w - 22, pos - 11)))
                    .scaleEffect(dragging ? 1.12 : 1.0)
                    .animation(Theme.Animation.press, value: dragging)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let raw = max(0, min(w, gesture.location.x))
                        let normalized = Double(raw / max(1, w))
                        let newValue = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
                        if abs(newValue - value) > 0.0005 { value = newValue }
                        let step = Int((normalized * 10).rounded())
                        if step != lastTickStep {
                            lastTickStep = step
                            HapticsManager.shared.tick()
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        lastTickStep = -1
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 28)
    }
}
