import SwiftUI

struct ModeSelector: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraMode.allCases) { m in
                Button { vm.selectMode(m) } label: {
                    Text(m.displayName)
                        .font(Theme.Font.captionTab)
                        .foregroundStyle(vm.mode == m ? Color.black : Theme.Color.onSurface)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if vm.mode == m {
                                Capsule(style: .continuous)
                                    .fill(Theme.Color.onSurface)
                                    .matchedGeometryEffect(id: "mode-bg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.Color.surfaceStrong, in: Capsule(style: .continuous))
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
    }

    @Namespace private var ns
}
