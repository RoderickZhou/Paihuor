import SwiftUI

struct TaskListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    @State private var selectedBoard: TaskBoard = .arranged

    private let autoRefreshIntervalNanoseconds: UInt64 = 8_000_000_000
    private let archiveAfterCompletionSeconds: TimeInterval = 24 * 60 * 60

    var body: some View {
        Group {
            if let profile = profileStore.profile {
                let tasks = taskStore.relevantTasks(for: profile)
                let archiveTasks = tasks.filter { isAutoArchived($0) }
                let activeTasks = tasks.filter { !isAutoArchived($0) }
                let arrangedTasks = activeTasks.filter { $0.fromUserId == profile.userId.rawValue }
                let visibleTasks = visibleTasks(
                    arrangedTasks: arrangedTasks,
                    archiveTasks: archiveTasks
                )
                let sections = taskSections(for: visibleTasks)

                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            boardPicker(
                                arrangedCount: arrangedTasks.count,
                                archiveCount: archiveTasks.count
                            )

                            if let message = taskStore.syncErrorMessage {
                                networkIssueBanner(message: message, profile: profile)
                            }

                            if sections.isEmpty {
                                emptyState(for: selectedBoard)
                            } else {
                                ForEach(sections) { section in
                                    taskSection(section, profile: profile)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 96)
                    }
                    .refreshable {
                        await taskStore.refreshFromRemote(for: profile)
                    }

                    Button {
                        router.present(.newTask)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold())
                            .frame(width: 58, height: 58)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
                    .padding(20)
                    .accessibilityLabel("新建任务")
                }
                .background(Color.paiBackground.ignoresSafeArea())
                .onAppear {
                    if selectedBoard == .archive, archiveTasks.isEmpty {
                        selectedBoard = .arranged
                    }
                }
                .task(id: "\(profile.familyId)-\(profile.userId.rawValue)-\(scenePhase == .active)-\(router.selectedTab == .tasks)") {
                    guard scenePhase == .active, router.selectedTab == .tasks else { return }
                    await taskStore.refreshFromRemote(for: profile)
                    await runAutoRefresh(for: profile)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func boardPicker(
        arrangedCount: Int,
        archiveCount: Int
    ) -> some View {
        Picker("任务视角", selection: $selectedBoard) {
            Text("我安排的 \(arrangedCount)").tag(TaskBoard.arranged)

            Text("归档 \(archiveCount)").tag(TaskBoard.archive)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("任务视角")
    }

    private func runAutoRefresh(for profile: FamilyProfile) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: autoRefreshIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            await taskStore.refreshFromRemote(for: profile, showsActivity: false)
        }
    }

    private func visibleTasks(
        arrangedTasks: [PaihuorTask],
        archiveTasks: [PaihuorTask]
    ) -> [PaihuorTask] {
        switch selectedBoard {
        case .arranged:
            return arrangedTasks
        case .archive:
            return archiveTasks
        }
    }

    private func isAutoArchived(_ task: PaihuorTask, now: Date = Date()) -> Bool {
        guard task.status == .done else { return false }

        if task.archived {
            return true
        }

        if let archivedAt = task.archivedAt, archivedAt > 0 {
            return true
        }

        let completedAt = task.doneAt > 0
            ? Date(epochMilliseconds: task.doneAt)
            : task.updatedAt

        return now.timeIntervalSince(completedAt) >= archiveAfterCompletionSeconds
    }

    private func networkIssueBanner(message: String, profile: FamilyProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(Color.paiDanger)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("网络连接异常")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.paiTextPrimary)

                Text("任务会先保存在本机。\(message)")
                    .font(.caption)
                    .foregroundStyle(Color.paiTextSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                Task {
                    await taskStore.refreshFromRemote(for: profile)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("重试同步")
        }
        .padding(12)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func taskSection(_ section: TaskDateSection, profile: FamilyProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(section.bucket.title, systemImage: section.bucket.icon)
                    .font(.headline)
                    .foregroundStyle(section.bucket.tint)

                Text("\(section.tasks.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(section.bucket.tint)
                    .clipShape(Capsule())

                Spacer()
            }

            if !section.bucket.subtitle.isEmpty {
                Text(section.bucket.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.paiTextSecondary)
            }

            LazyVStack(spacing: 10) {
                ForEach(section.tasks) { task in
                    TaskCardView(task: task, profile: profile)
                }
            }
        }
    }

    private func taskSections(for tasks: [PaihuorTask]) -> [TaskDateSection] {
        let now = Date()
        let calendar = Calendar.current
        var buckets: [TaskDateBucket: [PaihuorTask]] = [:]

        for task in tasks {
            let bucket = TaskDateBucket.bucket(for: task, now: now, calendar: calendar)
            buckets[bucket, default: []].append(task)
        }

        return TaskDateBucket.allCases.compactMap { bucket in
            guard let tasks = buckets[bucket], !tasks.isEmpty else { return nil }
            return TaskDateSection(bucket: bucket, tasks: sortedTasks(tasks, in: bucket))
        }
    }

    private func sortedTasks(_ tasks: [PaihuorTask], in bucket: TaskDateBucket) -> [PaihuorTask] {
        switch bucket {
        case .completed:
            return tasks.sorted { lhs, rhs in
                let lhsTime = lhs.doneAt > 0 ? lhs.doneAt : lhs.updatedAt.epochMilliseconds
                let rhsTime = rhs.doneAt > 0 ? rhs.doneAt : rhs.updatedAt.epochMilliseconds
                return lhsTime > rhsTime
            }
        case .noDeadline:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        default:
            return tasks.sorted { lhs, rhs in
                if lhs.deadline == rhs.deadline {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.deadline < rhs.deadline
            }
        }
    }

    private func emptyState(for board: TaskBoard) -> some View {
        VStack(spacing: 14) {
            Image(systemName: board.emptyIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.paiPrimary)

            Text(board.emptyTitle)
                .font(.headline)
                .foregroundStyle(Color.paiTextPrimary)

            Text(board.emptySubtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paiTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum TaskBoard: String, CaseIterable, Identifiable {
    case arranged
    case archive

    var id: String { rawValue }

    var emptyIcon: String {
        switch self {
        case .arranged:
            return "paperplane"
        case .archive:
            return "archivebox"
        }
    }

    var emptyTitle: String {
        switch self {
        case .arranged:
            return "还没有安排出去的事"
        case .archive:
            return "归档里还没有记录"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .arranged:
            return "点右下角加号，交代一件事。"
        case .archive:
            return "完成超过一天的任务会自动收进这里，记录不会删除。"
        }
    }
}

private struct TaskDateSection: Identifiable {
    var bucket: TaskDateBucket
    var tasks: [PaihuorTask]

    var id: TaskDateBucket { bucket }
}

private enum TaskDateBucket: String, CaseIterable, Identifiable {
    case overdue
    case today
    case tomorrow
    case later
    case noDeadline
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue:
            return "逾期"
        case .today:
            return "今天"
        case .tomorrow:
            return "明天"
        case .later:
            return "以后"
        case .noDeadline:
            return "无截止时间"
        case .completed:
            return "已完成"
        }
    }

    var subtitle: String {
        switch self {
        case .overdue:
            return "需要优先处理"
        case .today:
            return "今天要做完"
        case .tomorrow:
            return "明天处理"
        case .later:
            return "后续安排"
        case .noDeadline:
            return "没有明确时间"
        case .completed:
            return "已经勾掉"
        }
    }

    var icon: String {
        switch self {
        case .overdue:
            return "exclamationmark.triangle.fill"
        case .today:
            return "sun.max.fill"
        case .tomorrow:
            return "calendar"
        case .later:
            return "tray.full"
        case .noDeadline:
            return "clock.badge.questionmark"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overdue:
            return .paiDanger
        case .today:
            return .paiPrimary
        case .tomorrow:
            return .paiWarning
        case .later:
            return .paiTextPrimary
        case .noDeadline:
            return .paiTextSecondary
        case .completed:
            return .paiTextSecondary
        }
    }

    static func bucket(for task: PaihuorTask, now: Date, calendar: Calendar) -> TaskDateBucket {
        if task.status == .done {
            return .completed
        }

        guard task.deadline > 0 else {
            return .noDeadline
        }

        let deadline = Date(epochMilliseconds: task.deadline)

        if deadline < now {
            return .overdue
        }

        if calendar.isDateInToday(deadline) {
            return .today
        }

        if calendar.isDateInTomorrow(deadline) {
            return .tomorrow
        }

        return .later
    }
}
