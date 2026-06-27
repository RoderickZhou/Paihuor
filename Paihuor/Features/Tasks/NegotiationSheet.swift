import SwiftUI

struct NegotiationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore

    let task: PaihuorTask

    @State private var text = ""
    @State private var hasProposedDeadline = false
    @State private var proposedDeadline = Date().addingTimeInterval(1800)

    private var latestNegotiation: NegotiationMessage? {
        task.negotiation.last
    }

    private var latestNegotiationIsMine: Bool {
        latestNegotiation?.fromUserId == profileStore.profile?.userId.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    Text(task.title)
                        .font(.headline)
                    Text(PaihuorDateFormatter.friendlyDeadline(task.deadline))
                        .foregroundStyle(Color.paiTextSecondary)
                }

                if let latestNegotiation {
                    Section(latestNegotiationIsMine ? "我上一条商量" : "对方的商量") {
                        Text(latestNegotiation.text)
                            .font(.body)

                        if latestNegotiation.proposedDeadline > 0 {
                            Label("建议改到 \(PaihuorDateFormatter.friendlyDeadline(latestNegotiation.proposedDeadline))", systemImage: "calendar")
                                .foregroundStyle(Color.paiTextSecondary)
                        }
                    }
                }

                Section(replySectionTitle) {
                    TextField(replyPlaceholder, text: $text, axis: .vertical)
                        .lineLimit(3...6)

                    Toggle("提出新时间", isOn: $hasProposedDeadline)

                    if hasProposedDeadline {
                        DatePicker("建议时间", selection: $proposedDeadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle(sheetTitle)
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

    private var replyPlaceholder: String {
        guard latestNegotiation != nil else {
            return "比如：能不能改到明早九点？"
        }

        if latestNegotiationIsMine {
            return "比如：我补充一下，最好今晚前。"
        }

        return "比如：可以，或者我需要改到明早九点。"
    }

    private var replySectionTitle: String {
        guard latestNegotiation != nil else {
            return "想法"
        }

        return latestNegotiationIsMine ? "补充说明" : "我的回复"
    }

    private var sheetTitle: String {
        guard latestNegotiation != nil else {
            return "商量一下"
        }

        return latestNegotiationIsMine ? "补充商量" : "回复商量"
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
