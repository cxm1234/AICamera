import SwiftUI

@main
struct AICameraApp: App {
    @State private var viewModel = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(viewModel)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
                .onChange(of: scenePhase) { _, newPhase in
                    viewModel.onScenePhaseChange(newPhase)
                }
        }
    }
}
