import SwiftUI

struct NegotiationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore

    let task: PaihuorTask

    @State private var text = ""
    @State private var hasProposedDeadline = false
    @State private var proposedDeadline = Date().addingTimeInterval(1800)

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    Text(task.title)
                        .font(.headline)
                    Text(PaihuorDateFormatter.friendlyDeadline(task.deadline))
                        .foregroundStyle(Color.paiTextSecondary)
                }

                Section("想法") {
                    TextField("比如：能不能改到明早九点？", text: $text, axis: .vertical)
                        .lineLimit(3...6)

                    Toggle("提出新时间", isOn: $hasProposedDeadline)

                    if hasProposedDeadline {
                        DatePicker("建议时间", selection: $proposedDeadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("商量一下")
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
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let profile = profileStore.profile else { return }

        taskStore.addNegotiation(
            to: task,
            from: profile,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            proposedDeadline: hasProposedDeadline ? proposedDeadline.epochMilliseconds : 0
        )

        dismiss()
    }
}
