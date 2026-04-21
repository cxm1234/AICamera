import SwiftUI

struct BottomBar: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            // 上方面板：根据 mode 切换
            Group {
                switch vm.mode {
                case .filter:
                    FilterStrip()
                case .beauty:
                    BeautyPanel()
                case .photo:
                    Color.clear.frame(height: 1)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)

            ModeSelector()
                .padding(.horizontal, Theme.Spacing.l)

            HStack {
                GalleryThumbButton()
                Spacer()
                ShutterButton(isCapturing: vm.isCapturing) { vm.capture() }
                Spacer()
                SwitchCameraButton()
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
        }
        .padding(.top, Theme.Spacing.m)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct GalleryThumbButton: View {
    @Environment(CameraViewModel.self) private var vm
    var body: some View {
        Button {
            if vm.lastCaptured != nil { vm.isShowingPreview = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.Color.surfaceStrong)
                    .frame(width: 46, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.Color.onSurfaceMuted, lineWidth: 1)
                    )
                if let img = vm.lastCaptured?.thumbnail {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: SFIcons.gallery)
                        .foregroundStyle(Theme.Color.onSurface)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开最近一张照片")
    }
}

private struct SwitchCameraButton: View {
    @Environment(CameraViewModel.self) private var vm
    @State private var spin = 0.0
    var body: some View {
        Button {
            spin += 180
            vm.switchCamera()
        } label: {
            Image(systemName: SFIcons.switchCam)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Color.onSurface)
                .frame(width: 46, height: 46)
                .background(Theme.Color.surfaceStrong, in: Circle())
                .rotationEffect(.degrees(spin))
                .animation(.easeInOut(duration: 0.35), value: spin)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换前后摄")
    }
}
