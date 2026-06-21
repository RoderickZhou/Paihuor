import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore

    @State private var rawText = ""
    @State private var title = ""
    @State private var detail = ""
    @State private var hasDeadline = true
    @State private var deadline = Date().addingTimeInterval(3600)
    @State private var toUserId: UserRole = .husband

    private var canSave: Bool {
        !normalizedTitle.isEmpty || !normalizedRawText.isEmpty
    }

    private var normalizedRawText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原话") {
                    TextField("例如：今晚八点前把垃圾带下去", text: $rawText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("审核") {
                    TextField("标题", text: $title)
                    TextField("补充细节", text: $detail, axis: .vertical)
                        .lineLimit(2...5)

                    Toggle("设置截止时间", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker("截止", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("收件人") {
                    Picker("发给", selection: $toUserId) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.paiBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let profile = profileStore.profile {
                    toUserId = profile.counterpartUserId
                }
            }
        }
    }

    private func save() {
        guard let profile = profileStore.profile else { return }

        let finalTitle = normalizedTitle.isEmpty
            ? String(normalizedRawText.prefix(15))
            : normalizedTitle
        let finalRawText = normalizedRawText.isEmpty ? finalTitle : normalizedRawText

        taskStore.createTask(
            rawText: finalRawText,
            title: finalTitle,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: hasDeadline ? deadline.epochMilliseconds : 0,
            toUserId: toUserId,
            profile: profile
        )

        dismiss()
    }
}
