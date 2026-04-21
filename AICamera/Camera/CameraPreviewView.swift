import MetalKit
import SwiftUI

/// SwiftUI ↔ MTKView 的桥。
/// 仅负责创建 MTKView 并把 PreviewRenderer 引用透出给上层（用于绑定到 FrameProcessor）。
struct CameraPreviewView: UIViewRepresentable {

    /// 由 ViewModel 持有；renderer 在 makeUIView 中被赋值。
    final class Box: ObservableObject {
        var renderer: PreviewRenderer?
    }

    let box: Box

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: SharedRender.metalDevice)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.backgroundColor = .black
        view.isOpaque = true
        view.isUserInteractionEnabled = false
        let renderer = PreviewRenderer(view: view)
        box.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) { /* no-op */ }

    static func dismantleUIView(_ uiView: MTKView, coordinator: ()) {
        uiView.delegate = nil
    }
}
