import SwiftUI

struct PreviewLayer: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        CameraPreviewView(box: vm.previewBox)
            .ignoresSafeArea()
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.6)
        }
    }
}

struct CountdownOverlay: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.system(size: 120, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: .black.opacity(0.45), radius: 12)
            .transition(.scale.combined(with: .opacity))
            .id(value)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: value)
    }
}
