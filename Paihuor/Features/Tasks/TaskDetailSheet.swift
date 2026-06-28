import SwiftUI

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    @State private var showsDeleteConfirmation = false

    let task: PaihuorTask

    private var profile: FamilyProfile? {
        profileStore.profile
    }

    private var isOwner: Bool {
        task.fromUserId == profile?.userId.rawValue
    }

    private var isIncoming: Bool {
        task.toUserId == profile?.userId.rawValue
    }

    private var canArchive: Bool {
        task.status == .done && !task.archived && (task.archivedAt ?? 0) == 0
    }

    private var latestNegotiation: NegotiationMessage? {
        task.negotiation.last
    }

    private var latestNegotiationIsMine: Bool {
        latestNegotiation?.fromUserId == profile?.userId.rawValue
    }

    private var needsNegotiationReply: Bool {
        task.status == .negotiating && latestNegotiation != nil && !latestNegotiationIsMine
    }

    private var titleText: String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        let rawText = task.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawText.isEmpty ? "未命名任务" : rawText
    }

    private var detailText: String {
        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            return detail
        }

        return task.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    metaRow
                    titleBlock

                    if let latestNegotiation {
                        negotiationBlock(latestNegotiation)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }

            bottomActions
        }
        .background(Color.paiCardBackground.ignoresSafeArea())
        .confirmationDialog("删除这条任务？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard let profile else { return }
                taskStore.deleteTask(task, profile: profile)
                dismiss()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("会从双方任务列表移除，记录仍保留在服务端。")
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭详情")

            Spacer()

            Text("收集箱")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.paiTextPrimary)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.paiTextSecondary)

            Spacer()

            Menu {
                if isIncoming && task.status == .pending {
                    Button {
                        markReceived()
                    } label: {
                        Label("收到", systemImage: "bell.badge")
                    }
                }

                if isIncoming && task.status == .received {
                    Button {
                        markDone()
                    } label: {
                        Label("完成", systemImage: "checkmark.circle")
                    }
                }

                if needsNegotiationReply {
                    Button {
                        acceptNegotiation()
                    } label: {
                        Label("同意商量", systemImage: "checkmark.circle")
                    }
                }

                if canArchive {
                    Button {
                        archive()
                    } label: {
                        Label("归档", systemImage: "archivebox")
                    }
                }

                if isOwner {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            statusBox

            if task.deadline > 0 {
                Label(PaihuorDateFormatter.friendlyDeadline(task.deadline), systemImage: "alarm")
                    .font(.headline)
                    .foregroundStyle(Color.paiPrimary)
            } else {
                Label("未设截止时间", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(Color.paiTextSecondary)
            }

            Spacer()

            Image(systemName: "flag")
                .font(.title2)
                .foregroundStyle(Color.paiTextSecondary)
        }
    }

    private var statusBox: some View {
        Button {
            if isIncoming && task.status == .pending {
                markReceived()
            } else if isIncoming && task.status == .received {
                markDone()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(task.status == .done ? Color.paiPrimary : Color.paiTextSecondary.opacity(0.6), lineWidth: 2)
                    .frame(width: 28, height: 28)

                if task.status == .done {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.paiPrimary)
                } else if needsNegotiationReply {
                    Circle()
                        .fill(Color.paiWarning)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.status == .done ? "已完成" : "任务状态")
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titleText)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.paiTextPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailText.isEmpty || detailText == titleText ? "描述" : detailText)
                .font(.title3)
                .foregroundStyle(detailText.isEmpty || detailText == titleText ? Color.paiTextSecondary.opacity(0.5) : Color.paiTextSecondary)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func negotiationBlock(_ message: NegotiationMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(latestNegotiationIsMine ? "我提出的商量" : "对方提出的商量", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(needsNegotiationReply ? Color.paiWarning : Color.paiTextSecondary)

            Text(message.text)
                .font(.body)
                .foregroundStyle(Color.paiTextPrimary)

            if message.proposedDeadline > 0 {
                Text("建议改到 \(PaihuorDateFormatter.friendlyDeadline(message.proposedDeadline))")
                    .font(.caption)
                    .foregroundStyle(Color.paiPrimary)
            }

            if needsNegotiationReply {
                HStack(spacing: 10) {
                    Button {
                        acceptNegotiation()
                    } label: {
                        Label("同意", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        presentNegotiation()
                    } label: {
                        Label("回复", systemImage: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(needsNegotiationReply ? Color.paiWarning.opacity(0.12) : Color.paiBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bottomActions: some View {
        HStack(spacing: 18) {
            if isIncoming && task.status == .pending {
                Button {
                    markReceived()
                } label: {
                    Label("收到", systemImage: "bell.badge")
                }
                .buttonStyle(.borderedProminent)
            } else if isIncoming && task.status == .received {
                Button {
                    markDone()
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                presentNegotiation()
            } label: {
                Label(task.status == .negotiating ? "回复" : "商量", systemImage: "text.bubble")
            }
            .buttonStyle(.bordered)
            .disabled(task.status == .done)

            if canArchive {
                Button {
                    archive()
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
            }

            if isOwner {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .background(.ultraThinMaterial)
    }

    private func presentNegotiation() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            router.present(.negotiation(task))
        }
    }

    private func markReceived() {
        guard let profile else { return }
        taskStore.markReceived(task, profile: profile)
        dismiss()
    }

    private func markDone() {
        guard let profile else { return }
        taskStore.markDone(task, profile: profile)
        dismiss()
    }

    private func acceptNegotiation() {
        guard let profile else { return }
        taskStore.acceptLatestNegotiation(task, profile: profile)
        dismiss()
    }

    private func archive() {
        guard let profile else { return }
        taskStore.archiveTask(task, profile: profile)
        dismiss()
    }
}
