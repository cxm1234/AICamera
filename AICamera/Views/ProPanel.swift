import SwiftUI

/// 专业模式底部面板：分组切换 (曝光/对焦)，按当前组显示对应控件。
struct ProPanel: View {

    @Environment(CameraViewModel.self) private var vm

    enum Tab: String, CaseIterable, Identifiable {
        case exposure, focus
        var id: String { rawValue }
        var title: String { self == .exposure ? "曝光" : "对焦" }
    }

    @State private var tab: Tab = .exposure

    var body: some View {
        let pro  = vm.pro
        let caps = vm.caps

        VStack(spacing: 10) {
            ProInfoStrip(pro: pro, caps: caps)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Group {
                switch tab {
                case .exposure: exposureGroup(pro: pro, caps: caps)
                case .focus:    focusGroup(pro: pro, caps: caps)
                }
            }
            .frame(minHeight: 100)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Color.separator, lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Exposure

    @ViewBuilder
    private func exposureGroup(pro: ProSettings, caps: DeviceCapabilities) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                segChip(title: "AUTO",   active: pro.exposureMode == .auto) {
                    vm.setExposureMode(.auto)
                }
                segChip(title: "MANUAL", active: pro.exposureMode == .manual,
                        disabled: !caps.supportsCustomExposure) {
                    vm.setExposureMode(.manual)
                }
                Spacer()
            }

            if pro.exposureMode == .auto {
                evRow(pro: pro, caps: caps)
            } else {
                isoRow(pro: pro, caps: caps)
                shutterRow(pro: pro, caps: caps)
            }
        }
    }

    @ViewBuilder
    private func evRow(pro: ProSettings, caps: DeviceCapabilities) -> some View {
        labeledSlider(
            label: "EV",
            value: Binding(
                get: { Double(pro.exposureBiasEV) },
                set: { vm.setEV(Float($0)) }
            ),
            range: Double(caps.minBiasEV)...Double(caps.maxBiasEV),
            step: 0.1,
            valueText: String(format: "%+.1f", pro.exposureBiasEV)
        )
    }

    @ViewBuilder
    private func isoRow(pro: ProSettings, caps: DeviceCapabilities) -> some View {
        labeledSlider(
            label: "ISO",
            value: Binding(
                get: { Double(pro.iso) },
                set: { vm.setISO(Float($0)) }
            ),
            range: Double(caps.minISO)...Double(caps.maxISO),
            step: 1,
            valueText: "\(Int(pro.iso))"
        )
    }

    @ViewBuilder
    private func shutterRow(pro: ProSettings, caps: DeviceCapabilities) -> some View {
        // 对快门用对数滑块，更接近真实感
        let logRange = log(caps.minShutter)...log(caps.maxShutter)
        labeledSlider(
            label: "S",
            value: Binding(
                get: { log(pro.shutterSeconds) },
                set: { vm.setShutter(seconds: exp($0)) }
            ),
            range: logRange,
            step: (logRange.upperBound - logRange.lowerBound) / 200,
            valueText: ShutterPresets.displayName(pro.shutterSeconds)
        )
    }

    // MARK: - Focus

    @ViewBuilder
    private func focusGroup(pro: ProSettings, caps: DeviceCapabilities) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                segChip(title: "AF", active: pro.focusMode == .auto) {
                    vm.setFocusMode(.auto)
                }
                segChip(title: "MF", active: pro.focusMode == .manual,
                        disabled: !caps.supportsManualFocus) {
                    vm.setFocusMode(.manual)
                }
                Spacer()
            }

            if pro.focusMode == .manual {
                labeledSlider(
                    label: "DIST",
                    value: Binding(
                        get: { Double(pro.lensPosition) },
                        set: { vm.setLensPosition(Float($0)) }
                    ),
                    range: 0...1,
                    step: 0.005,
                    valueText: String(format: "%.0f%%", pro.lensPosition * 100)
                )
            } else {
                Text("自动对焦中 · 点击预览选择对焦点 · 长按锁定 AE/AF")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Color.onSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func segChip(title: String, active: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(active ? Color.black : (disabled ? Theme.Color.onSurfaceMuted : Theme.Color.onSurface))
                .frame(width: 64, height: 28)
                .background(
                    Capsule().fill(active ? Theme.Color.primary : Color.black.opacity(0.35))
                )
                .overlay(Capsule().stroke(Theme.Color.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .sensoryFeedback(.selection, trigger: active)
    }

    @ViewBuilder
    private func labeledSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double.Stride,
        valueText: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.onSurfaceMuted)
                .frame(width: 40, alignment: .leading)

            Slider(value: value, in: range, step: step)
                .tint(Theme.Color.primary)

            Text(valueText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.onSurface)
                .frame(width: 60, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

/// 顶部信息条：当前镜头 / ISO / 快门 / EV，全只读。
struct ProInfoStrip: View {
    let pro: ProSettings
    let caps: DeviceCapabilities

    var body: some View {
        HStack(spacing: 14) {
            tag("LENS",  caps.deviceLabel.isEmpty ? "—" : caps.deviceLabel)
            tag("ISO",   "\(Int(pro.iso))")
            tag("S",     ShutterPresets.displayName(pro.shutterSeconds))
            tag("EV",    String(format: "%+.1f", pro.exposureBiasEV))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func tag(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Text(k)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Color.onSurfaceMuted)
            Text(v)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.onSurface)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 48)
    }
}
