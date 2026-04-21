import SwiftUI

struct LensZoomBar: View {
    let stops: [LensZoomStop]
    let currentZoom: CGFloat
    let onSelect: (LensZoomStop) -> Void

    var body: some View {
        if stops.count >= 2 {
            HStack(spacing: 6) {
                ForEach(stops) { stop in
                    let active = isActive(stop)
                    Button {
                        onSelect(stop)
                    } label: {
                        Text(stop.label)
                            .font(.system(size: active ? 13 : 11, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? Theme.Color.primary : Theme.Color.onSurface)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(active ? Color.white : Color.black.opacity(0.55))
                            )
                            .overlay(
                                Circle().stroke(Theme.Color.separator, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: active)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.35))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("镜头变焦"))
        }
    }

    private func isActive(_ stop: LensZoomStop) -> Bool {
        // 当前 zoom 与 stop.factor 误差 < 0.1 视为激活
        abs(currentZoom - stop.factor) < 0.1
    }
}
