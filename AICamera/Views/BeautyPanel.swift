import SwiftUI

struct BeautyPanel: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Text(vm.beautyDimension.displayName)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Color.onSurfaceMuted)
                    .frame(width: 36, alignment: .leading)
                BeautySlider(value: Binding(
                    get: { currentValue() },
                    set: { vm.updateBeauty(dimension: vm.beautyDimension, value: $0) }
                ))
                Text("\(Int(currentValue() * 100))")
                    .font(Theme.Font.label.monospacedDigit())
                    .foregroundStyle(Theme.Color.onSurface)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.Color.surfaceStrong, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))

            HStack(spacing: Theme.Spacing.m) {
                ForEach(BeautyDimension.allCases) { d in
                    Button { vm.selectBeautyDimension(d) } label: {
                        VStack(spacing: 4) {
                            Image(systemName: d.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(d.displayName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(vm.beautyDimension == d ? Theme.Color.primary : Theme.Color.onSurface)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            vm.beautyDimension == d
                            ? Theme.Color.primaryMuted
                            : Theme.Color.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Theme.Spacing.s) {
                presetButton("自然", BeautySettings.natural)
                presetButton("精致", BeautySettings.glam)
                presetButton("关闭", BeautySettings.zero)
            }
        }
    }

    private func presetButton(_ title: String, _ settings: BeautySettings) -> some View {
        Button { vm.applyBeautyPreset(settings) } label: {
            Text(title)
                .font(Theme.Font.label)
                .foregroundStyle(matches(settings) ? Color.black : Theme.Color.onSurface)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(matches(settings) ? Theme.Color.onSurface : Theme.Color.surface,
                            in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func matches(_ settings: BeautySettings) -> Bool {
        vm.beauty == settings
    }

    private func currentValue() -> Double {
        switch vm.beautyDimension {
        case .smoothing: return vm.beauty.smoothing
        case .whitening: return vm.beauty.whitening
        case .sharpness: return vm.beauty.sharpness
        case .slimFace:  return vm.beauty.slimFace
        case .bigEye:    return vm.beauty.bigEye
        }
    }
}
