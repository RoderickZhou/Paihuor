import SwiftUI

struct AppView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var deepLinkCenter: DeepLinkCenter
    @StateObject private var router = AppRouter()

    var body: some View {
        Group {
            if profileStore.profile == nil {
                PairingSetupView()
            } else {
                TabView(selection: $router.selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        NavigationStack {
                            tab.makeContentView()
                        }
                        .tabItem { tab.label }
                        .tag(tab)
                    }
                }
                .environmentObject(router)
                .sheet(item: $router.presentedSheet) { sheet in
                    switch sheet {
                    case .newTask:
                        TaskEditorView()
                    case .negotiation(let task):
                        NegotiationSheet(task: task)
                    }
                }
            }
        }
        .tint(.paiPrimary)
        .background(Color.paiBackground)
        .onReceive(deepLinkCenter.$pendingDestination.compactMap { $0 }) { destination in
            guard profileStore.profile != nil else { return }

            switch destination {
            case .record:
                router.selectedTab = .tasks
                router.present(.newTask)
            }

            deepLinkCenter.consume()
        }
    }
}
