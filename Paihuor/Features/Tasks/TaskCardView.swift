import SwiftUI

struct TaskCardView: View {
    let task: PaihuorTask
    let profile: FamilyProfile
    let onOpen: () -> Void

    private var isDone: Bool {
        task.status == .done
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

    private var displayTitle: String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        let rawText = task.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawText.isEmpty ? "未命名任务" : rawText
    }

    private var detailText: String {
        task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deadlineText: String? {
        guard task.deadline > 0 else { return nil }
        return PaihuorDateFormatter.friendlyDeadline(task.deadline)
    }

    private var statusHint: String? {
        switch task.status {
        case .pending:
            return task.toUserId == profile.userId.rawValue ? "待我收到" : "等待对方收到"
        case .received:
            return task.toUserId == profile.userId.rawValue ? "我已收到" : "对方已收到"
        case .negotiating:
            return latestNegotiationIsMine ? "等对方回应" : "对方想商量"
        case .done:
            return "已完成"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                statusBox
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "已完成" : "未完成")

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isDone ? Color.paiTextSecondary : Color.paiTextPrimary)
                    .strikethrough(isDone, color: Color.paiTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let deadlineText {
                        Label(deadlineText, systemImage: "calendar")
                            .foregroundStyle(deadlineColor)
                    }

                    if let statusHint {
                        Label(statusHint, systemImage: statusIcon)
                            .foregroundStyle(statusColor)
                    }
                }
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)

                if let images = task.images, !images.isEmpty {
                    Label("\(images.count) 张图片", systemImage: "photo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.paiPrimary)
                }

                if needsNegotiationReply, let latestNegotiation {
                    Text(latestNegotiation.text)
                        .font(.caption)
                        .foregroundStyle(Color.paiWarning)
                        .lineLimit(2)
                } else if !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(Color.paiTextSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    private var statusBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isDone ? Color.paiPrimary : Color.paiTextSecondary.opacity(0.55), lineWidth: 2)
                .frame(width: 24, height: 24)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(Color.paiPrimary)
            } else if needsNegotiationReply {
                Circle()
                    .fill(Color.paiWarning)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 2)
    }

    private var deadlineColor: Color {
        guard task.status != .done,
              let countdown = PaihuorDateFormatter.countdownText(task.deadline) else {
            return .paiPrimary
        }

        return countdown == "已超时" ? .paiDanger : .paiPrimary
    }

    private var statusColor: Color {
        if needsNegotiationReply {
            return .paiWarning
        }

        return task.status == .done ? .paiTextSecondary : .paiTextSecondary
    }

    private var statusIcon: String {
        switch task.status {
        case .pending:
            return "paperplane"
        case .received:
            return "checkmark.circle"
        case .negotiating:
            return "text.bubble"
        case .done:
            return "checkmark.circle.fill"
        }
    }
}
