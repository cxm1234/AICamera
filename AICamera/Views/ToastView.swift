import SwiftUI

struct ToastView: View {
    let message: ToastMessage
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: SFIcons.warning)
                .foregroundStyle(Theme.Color.primary)
            Text(message.text)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Color.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.Color.surfaceStrong, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }
}
