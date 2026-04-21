import SwiftUI

struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void

    @State private var pressed: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(isCapturing ? Theme.Color.primary : Color.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pressed ? 0.86 : 1.0)
                    .animation(Theme.Animation.press, value: pressed)
            }
        }
        .buttonStyle(PressDownStyle(pressed: $pressed))
        .accessibilityLabel("快门")
        .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
    }
}

private struct PressDownStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, new in
                pressed = new
            }
    }
}
