import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case tasks

    var id: String { rawValue }

    @ViewBuilder
    func makeContentView() -> some View {
        switch self {
        case .tasks:
            TaskListView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .tasks:
            Label("任务", systemImage: "checklist")
        }
    }
}
