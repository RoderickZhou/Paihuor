import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case tasks
    case settings

    var id: String { rawValue }

    @ViewBuilder
    func makeContentView() -> some View {
        switch self {
        case .tasks:
            TaskListView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .tasks:
            Label("任务", systemImage: "checklist")
        case .settings:
            Label("设置", systemImage: "person.2")
        }
    }
}
