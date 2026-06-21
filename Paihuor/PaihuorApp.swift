import SwiftUI

@main
struct PaihuorApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var taskStore = TaskStore()
    @StateObject private var deepLinkCenter = DeepLinkCenter()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(profileStore)
                .environmentObject(taskStore)
                .environmentObject(deepLinkCenter)
                .onOpenURL { url in
                    deepLinkCenter.handle(url)
                }
        }
    }
}
