import SwiftUI

struct AppView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var deepLinkCenter: DeepLinkCenter
    @StateObject private var router = AppRouter()

    var body: some View {
        ZStack {
            Color.paiBackground.ignoresSafeArea()
            rootContent
        }
        .tint(.paiPrimary)
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

    @ViewBuilder
    private var rootContent: some View {
        if profileStore.profile == nil {
            PairingSetupView()
        } else {
            NavigationStack {
                TaskListView()
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
}
