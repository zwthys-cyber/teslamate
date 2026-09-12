import SwiftUI

@main
@MainActor
struct TeslaMateMobileApp: App {
    #if DEBUG
    @State private var session = InterfacePreview.enabled ? InterfacePreview.makeSession() : AppSession()
    #else
    @State private var session = AppSession()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                #if DEBUG
                .preferredColorScheme(InterfacePreview.enabled && InterfacePreview.dark ? .dark : nil)
                .transformEnvironment(\.dynamicTypeSize) { size in
                    if InterfacePreview.enabled && InterfacePreview.large { size = .accessibility3 }
                }
                #endif
        }
    }
}
