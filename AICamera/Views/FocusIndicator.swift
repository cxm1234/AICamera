import SwiftUI

struct FocusIndicator: View {
    let state: FocusIndicatorState
    @State private var phase: CGFloat = 1.4

    var body: some View {
        Rectangle()
            .stroke(Theme.Color.primary, lineWidth: 1.4)
            .frame(width: 72, height: 72)
            .scaleEffect(phase)
            .opacity(Double(2 - phase))
            .position(state.location)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) {
                    phase = 1.0
                }
            }
            .id(state.id)
    }
}
