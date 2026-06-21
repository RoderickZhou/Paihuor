import Foundation

enum AppSheet: Identifiable {
    case newTask
    case negotiation(PaihuorTask)

    var id: String {
        switch self {
        case .newTask:
            return "new-task"
        case .negotiation(let task):
            return "negotiation-\(task.objectId)"
        }
    }
}

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .tasks
    @Published var presentedSheet: AppSheet?

    func present(_ sheet: AppSheet) {
        presentedSheet = sheet
    }
}

enum DeepLinkDestination: Equatable {
    case record
}

final class DeepLinkCenter: ObservableObject {
    @Published private(set) var pendingDestination: DeepLinkDestination?

    func handle(_ url: URL) {
        guard url.scheme == "paihuor" else { return }

        if url.host == "record" || url.path == "/record" {
            pendingDestination = .record
        }
    }

    func consume() {
        pendingDestination = nil
    }
}
