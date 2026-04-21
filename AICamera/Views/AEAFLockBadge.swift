import SwiftUI

struct AEAFLockBadge: View {
    var body: some View {
        Text("AE/AF LOCK")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color.yellow)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.yellow.opacity(0.7), lineWidth: 1))
            .transition(.opacity.combined(with: .scale))
            .accessibilityLabel(Text("AE 与 AF 已锁定"))
    }
}
