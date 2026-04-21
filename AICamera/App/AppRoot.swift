import SwiftUI

/// 根视图：根据权限状态切换"主屏 / 引导卡"。
struct AppRoot: View {
    @Environment(CameraViewModel.self) private var vm

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            switch vm.permission {
            case .authorized:
                CameraScreen()
            case .denied, .restricted:
                PermissionView(state: vm.permission) {
                    vm.openSystemSettings()
                }
            case .unknown:
                PermissionView(state: .unknown) {
                    Task { await vm.onAppear() }
                }
            }
        }
        .task { await vm.onAppear() }
    }
}
