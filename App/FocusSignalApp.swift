import SwiftUI
import FamilyControls

@main
struct FocusSignalApp: App {
    @StateObject private var model = SessionViewModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            FocusRootView(model: model)
                .tint(.indigo)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh(force: true) }
                }
                .onReceive(AuthorizationCenter.shared.$authorizationStatus) { _ in model.refresh(force: true) }
        }
    }
}
