import SwiftUI

struct FilterStrip: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            // 强度滑杆（仅在选中非原图时展示）
            if vm.selectedFilter.kind != .original {
                HStack(spacing: Theme.Spacing.m) {
                    Text("强度")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Color.onSurfaceMuted)
                    BeautySlider(value: Binding(
                        get: { vm.filterIntensity },
                        set: { vm.updateFilterIntensity($0) }
                    ))
                    Text("\(Int(vm.filterIntensity * 100))")
                        .font(Theme.Font.label.monospacedDigit())
                        .foregroundStyle(Theme.Color.onSurface)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Color.surfaceStrong, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(vm.availableFilters) { preset in
                            FilterChip(preset: preset, isSelected: preset == vm.selectedFilter) {
                                vm.selectFilter(preset)
                                withAnimation(Theme.Animation.snappy) {
                                    proxy.scrollTo(preset.id, anchor: .center)
                                }
                            }
                            .id(preset.id)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
                .scrollClipDisabled()
            }
            .frame(height: 78)
        }
    }
}

private struct FilterChip: View {
    let preset: FilterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: gradientColors(for: preset.kind),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 50, height: 50)
                    if preset.kind == .original {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Theme.Color.primary : Color.clear, lineWidth: 2)
                )
                Text(preset.displayName)
                    .font(Theme.Font.label)
                    .foregroundStyle(isSelected ? Theme.Color.primary : Theme.Color.onSurface)
            }
        }
        .buttonStyle(.plain)
    }

    private func gradientColors(for kind: FilterKind) -> [Color] {
        switch kind {
        case .original: return [Color.gray.opacity(0.4), Color.gray.opacity(0.2)]
        case .vivid:    return [.orange, .pink]
        case .natural:  return [.green.opacity(0.7), .yellow.opacity(0.6)]
        case .mono:     return [Color(white: 0.7), Color(white: 0.25)]
        case .cinema:   return [.indigo, .black]
        case .portra:   return [Color(red: 0.95, green: 0.78, blue: 0.55), Color(red: 0.78, green: 0.45, blue: 0.35)]
        case .cool:     return [.cyan, .blue]
        case .warm:     return [.yellow, .orange]
        case .vintage:  return [Color(red: 0.62, green: 0.45, blue: 0.30), Color(red: 0.30, green: 0.20, blue: 0.15)]
        case .faded:    return [Color(white: 0.85), Color(white: 0.55)]
        case .pink:     return [.pink, .purple]
        case .tokyo:    return [Color(red: 0.16, green: 0.32, blue: 0.55), Color(red: 0.85, green: 0.30, blue: 0.55)]
        }
    }
}
