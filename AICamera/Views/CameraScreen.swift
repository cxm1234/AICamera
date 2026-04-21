import SwiftUI

struct CameraScreen: View {
    @Environment(CameraViewModel.self) private var vm
    @State private var previewSize: CGSize = .zero
    @State private var pinchStart: CGFloat = 1.0

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            // 预览（可点对焦 / 双指变焦）
            PreviewLayer()
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { previewSize = proxy.size }
                        .onChange(of: proxy.size) { _, new in previewSize = new }
                })
                .contentShape(Rectangle())
                .onTapGesture { location in
                    vm.focus(at: location, in: previewSize)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let factor = pinchStart * value.magnification
                            vm.setZoom(max(1.0, min(8.0, factor)))
                        }
                        .onEnded { _ in
                            pinchStart = vm.configuration.zoomFactor
                        }
                )
                .overlay(alignment: .topLeading) {
                    if vm.configuration.isGridVisible {
                        GridOverlay().allowsHitTesting(false)
                    }
                }
                .overlay {
                    if let focus = vm.focusIndicator {
                        FocusIndicator(state: focus)
                    }
                }
                .overlay {
                    if vm.countdownRemaining > 0 {
                        CountdownOverlay(value: vm.countdownRemaining)
                    }
                }

            VStack(spacing: 0) {
                TopBar()
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                Spacer(minLength: 0)
                BottomBar()
            }

            // Toast
            if let toast = vm.toast {
                ToastView(message: toast)
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Animation.fade, value: vm.toast)
        .animation(Theme.Animation.snappy, value: vm.mode)
        .animation(Theme.Animation.snappy, value: vm.configuration.isGridVisible)
        .sheet(isPresented: Binding(
            get: { vm.isShowingPreview },
            set: { if !$0 { vm.dismissPreview() } }
        )) {
            if let captured = vm.lastCaptured {
                PhotoPreviewSheet(photo: captured) { vm.dismissPreview() }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            // toast 自动消失
            // 用 onChange 监听更精确
        }
        .onChange(of: vm.toast) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if vm.toast?.id == newValue?.id { vm.toast = nil }
            }
        }
    }
}
