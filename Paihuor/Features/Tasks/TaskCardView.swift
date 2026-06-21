import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    let task: PaihuorTask
    let profile: FamilyProfile

    private var isIncoming: Bool {
        task.toUserId == profile.userId.rawValue
    }

    private var directionText: String {
        if isIncoming {
            return "来自 \(displayName(for: task.fromUserId))"
        }

        return "发给 \(displayName(for: task.toUserId))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(Color.paiTextPrimary)
                        .lineLimit(2)

                    Text(directionText)
                        .font(.caption)
                        .foregroundStyle(Color.paiTextSecondary)

                    Text("\(displayName(for: task.fromUserId)) -> \(displayName(for: task.toUserId))")
                        .font(.caption2)
                        .foregroundStyle(Color.paiTextSecondary)
                }

                Spacer(minLength: 8)

                Text(task.status.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(task.status.badgeColor)
                    .clipShape(Capsule())
            }

            if !task.detail.isEmpty {
                Text(task.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.paiTextPrimary)
                    .lineLimit(3)
            } else if !task.rawText.isEmpty {
                Text(task.rawText)
                    .font(.subheadline)
                    .foregroundStyle(Color.paiTextSecondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(PaihuorDateFormatter.friendlyDeadline(task.deadline), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(Color.paiTextSecondary)

                if let countdown = PaihuorDateFormatter.countdownText(task.deadline), task.status != .done {
                    Text(countdown)
                        .font(.caption.bold())
                        .foregroundStyle(countdown == "已超时" ? Color.paiDanger : Color.paiPrimary)
                }
            }

            if let latestNegotiation = task.negotiation.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近商量")
                        .font(.caption)
                        .foregroundStyle(Color.paiTextSecondary)
                    Text(latestNegotiation.text)
                        .font(.subheadline)
                        .foregroundStyle(Color.paiTextPrimary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.paiBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            actionRow
        }
        .padding(16)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private var actionRow: some View {
        if task.status == .done {
            Label("完成于 \(PaihuorDateFormatter.friendlyDeadline(task.doneAt))", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.paiTextSecondary)
        } else {
            HStack(spacing: 10) {
                if task.status == .pending {
                    if isIncoming {
                        Button {
                            taskStore.markReceived(task)
                        } label: {
                            Label("收到", systemImage: "bell.badge")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Label("等待对方收到", systemImage: "paperplane")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.paiTextSecondary)
                    }
                }

                Button {
                    router.present(.negotiation(task))
                } label: {
                    Label("商量", systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)

                Button {
                    taskStore.markDone(task)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private func displayName(for userId: String) -> String {
        UserRole(rawValue: userId)?.displayName ?? userId
    }
}
