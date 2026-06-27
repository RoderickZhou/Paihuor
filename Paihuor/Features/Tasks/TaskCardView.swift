import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    @State private var showsDeleteConfirmation = false

    let task: PaihuorTask
    let profile: FamilyProfile

    private var isOwner: Bool {
        task.fromUserId == profile.userId.rawValue
    }

    private var isIncoming: Bool {
        task.toUserId == profile.userId.rawValue
    }

    private var canArchive: Bool {
        task.status == .done && !task.archived && (task.archivedAt ?? 0) == 0
    }

    private var canDelete: Bool {
        isOwner
    }

    private var latestNegotiation: NegotiationMessage? {
        task.negotiation.last
    }

    private var latestNegotiationIsMine: Bool {
        latestNegotiation?.fromUserId == profile.userId.rawValue
    }

    private var needsNegotiationReply: Bool {
        task.status == .negotiating && latestNegotiation != nil && !latestNegotiationIsMine
    }

    private var directionText: String {
        if isIncoming {
            return "\(displayName(for: task.fromUserId)) 派给我"
        }

        return "我派给 \(displayName(for: task.toUserId))"
    }

    private var statusText: String {
        switch task.status {
        case .pending:
            return isIncoming ? "待我收到" : "等对方收到"
        case .received:
            return isIncoming ? "我已收到" : "对方已收到"
        case .negotiating:
            return latestNegotiationIsMine ? "等对方回应" : "对方想商量"
        case .done:
            return "已完成"
        }
    }

    private var statusColor: Color {
        if needsNegotiationReply {
            return .paiWarning
        }

        switch task.status {
        case .pending:
            return .paiTextSecondary
        case .received:
            return .paiPrimary
        case .negotiating:
            return .paiWarning
        case .done:
            return .paiTextSecondary
        }
    }

    private var displayTitle: String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        return task.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bodyText: String {
        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return detail
        }

        return task.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deadlineTextColor: Color {
        guard task.status != .done,
              let countdown = PaihuorDateFormatter.countdownText(task.deadline) else {
            return .paiTextSecondary
        }

        return countdown == "已超时" ? .paiDanger : .paiPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(directionText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.paiTextSecondary)

                Spacer(minLength: 8)

                statusBadge
            }

            Text(displayTitle.isEmpty ? "未命名任务" : displayTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.paiTextPrimary)
                .lineLimit(3)

            if !bodyText.isEmpty && bodyText != displayTitle {
                Text(bodyText)
                    .font(.callout)
                    .foregroundStyle(Color.paiTextPrimary.opacity(0.82))
                    .lineLimit(3)
            }

            deadlineBlock

            if let latestNegotiation {
                negotiationPreview(latestNegotiation)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .confirmationDialog("删除这条任务？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                taskStore.deleteTask(task, profile: profile)
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("会从双方任务列表移除，记录仍保留在服务端。")
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor)
            .clipShape(Capsule())
    }

    private var deadlineBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(PaihuorDateFormatter.friendlyDeadline(task.deadline), systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(deadlineTextColor)

            if let countdown = PaihuorDateFormatter.countdownText(task.deadline), task.status != .done {
                Text(countdown)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(deadlineTextColor)
            }
        }
    }

    private func negotiationPreview(_ message: NegotiationMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: latestNegotiationIsMine ? "arrowshape.turn.up.right" : "text.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(needsNegotiationReply ? Color.paiWarning : Color.paiTextSecondary)

                Text(latestNegotiationIsMine ? "我提出的商量" : "对方提出的商量")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(needsNegotiationReply ? Color.paiWarning : Color.paiTextSecondary)
            }

            Text(message.text)
                .font(.callout)
                .foregroundStyle(Color.paiTextPrimary)
                .lineLimit(3)

            if message.proposedDeadline > 0 {
                Label("建议改到 \(PaihuorDateFormatter.friendlyDeadline(message.proposedDeadline))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color.paiTextSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(needsNegotiationReply ? Color.paiWarning.opacity(0.12) : Color.paiBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var actionRow: some View {
        if task.status == .done {
            completedActions
        } else if needsNegotiationReply {
            HStack(spacing: 8) {
                Button {
                    taskStore.acceptLatestNegotiation(task, profile: profile)
                } label: {
                    Label("同意", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    router.present(.negotiation(task))
                } label: {
                    Label("回复", systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.bordered)

                if canDelete {
                    deleteButton
                }
            }
            .font(.subheadline.weight(.semibold))
        } else if latestNegotiationIsMine && task.status == .negotiating {
            HStack(spacing: 8) {
                Label("等对方回应", systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.paiTextSecondary)

                Button {
                    router.present(.negotiation(task))
                } label: {
                    Label("补充", systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)

                if canDelete {
                    deleteButton
                }
            }
            .font(.subheadline.weight(.semibold))
        } else if isIncoming {
            incomingActions
        } else {
            outgoingActions
        }
    }

    private var completedActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("完成于 \(PaihuorDateFormatter.friendlyDeadline(task.doneAt))", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.paiTextSecondary)

            if canArchive || canDelete {
                HStack(spacing: 8) {
                    if canArchive {
                        Button {
                            taskStore.archiveTask(task, profile: profile)
                        } label: {
                            Label("归档", systemImage: "archivebox")
                        }
                        .buttonStyle(.bordered)
                    }

                    if canDelete {
                        deleteButton
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var incomingActions: some View {
        HStack(spacing: 8) {
            if task.status == .pending {
                Button {
                    taskStore.markReceived(task, profile: profile)
                } label: {
                    Label("收到", systemImage: "bell.badge")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                router.present(.negotiation(task))
            } label: {
                Label("商量", systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)

            if task.status == .received {
                Button {
                    taskStore.markDone(task, profile: profile)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private var outgoingActions: some View {
        HStack(spacing: 8) {
            Label(statusText, systemImage: task.status == .received ? "checkmark.circle" : "paperplane")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.paiTextSecondary)

            Button {
                router.present(.negotiation(task))
            } label: {
                Label("补充", systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)

            if canDelete {
                deleteButton
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showsDeleteConfirmation = true
        } label: {
            Label("删除", systemImage: "trash")
        }
        .buttonStyle(.bordered)
    }

    private func displayName(for userId: String) -> String {
        UserRole(rawValue: userId)?.displayName ?? userId
    }
}
