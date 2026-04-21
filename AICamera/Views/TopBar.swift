import SwiftUI

struct TopBar: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            iconButton(icon: vm.configuration.flashMode.displayIcon,
                       isOn: vm.configuration.flashMode != .off,
                       action: vm.toggleFlash)
            iconButton(icon: SFIcons.timer,
                       isOn: vm.configuration.timer != .off,
                       label: vm.configuration.timer == .off ? nil : vm.configuration.timer.displayName,
                       action: vm.cycleTimer)
            iconButton(icon: SFIcons.aspect,
                       isOn: vm.configuration.aspectRatio != .ratio4x3,
                       label: vm.configuration.aspectRatio.displayName,
                       action: vm.toggleAspect)
            iconButton(icon: vm.configuration.isGridVisible ? SFIcons.grid : SFIcons.gridOff,
                       isOn: vm.configuration.isGridVisible,
                       action: vm.toggleGrid)
            Spacer()
        }
    }

    @ViewBuilder
    private func iconButton(icon: String,
                            isOn: Bool,
                            label: String? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                if let label {
                    Text(label).font(Theme.Font.label)
                }
            }
            .foregroundStyle(isOn ? Theme.Color.primary : Theme.Color.onSurface)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.Color.surface, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
