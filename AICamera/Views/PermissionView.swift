import SwiftUI

struct PermissionView: View {
    let state: PermissionState
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: SFIcons.cameraFill)
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Theme.Color.primary)
            Text(title)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.onSurface)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Color.onSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Spacer()
            Button(action: onAction) {
                Text(actionTitle)
                    .font(Theme.Font.chip)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.Color.onSurface, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var title: String {
        switch state {
        case .denied, .restricted: return "请允许 AI Camera 使用相机"
        case .unknown:             return "开启相机以开始创作"
        case .authorized:          return ""
        }
    }
    private var subtitle: String {
        switch state {
        case .denied:              return "前往「设置」→「隐私」→「相机」打开 AI Camera 的访问权限。"
        case .restricted:          return "当前设备策略限制了相机访问，请联系管理员。"
        case .unknown:             return "实时滤镜与美颜需要相机权限，您可以随时在系统设置中关闭。"
        case .authorized:          return ""
        }
    }
    private var actionTitle: String {
        switch state {
        case .denied, .restricted: return "前往设置"
        case .unknown:             return "授权相机"
        case .authorized:          return ""
        }
    }
}
