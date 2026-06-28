import SwiftUI

struct TaskListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    @State private var selectedBoard: TaskBoard = .arranged
    @State private var pendingDeleteTask: PaihuorTask?
    @State private var showsDeleteConfirmation = false

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

                VStack(spacing: 0) {
                    topBar(profile: profile)

                    ZStack(alignment: .bottom) {
                        content(sections: sections, profile: profile)

                        bottomDock(profile: profile)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        addButton
                            .padding(.trailing, 32)
                            .padding(.bottom, 94)
                    }
                }
                .background(Color.paiBackground.ignoresSafeArea())
                .confirmationDialog("删除这条任务？", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                    Button("删除", role: .destructive) {
                        guard let task = pendingDeleteTask else { return }
                        taskStore.deleteTask(task, profile: profile)
                        pendingDeleteTask = nil
                    }

                    Button("取消", role: .cancel) {
                        pendingDeleteTask = nil
                    }
                } message: {
                    Text("会从双方任务列表移除，记录仍保留在服务端。")
                }
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

    private func topBar(profile: FamilyProfile) -> some View {
        HStack(spacing: 14) {
            Menu {
                Button {
                    selectedBoard = .arranged
                } label: {
                    Label("收集箱", systemImage: "checkmark.square")
                }

                Button {
                    selectedBoard = .archive
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
            } label: {
                CircleIcon(systemName: "line.3.horizontal")
            }
            .buttonStyle(.plain)

            Text(selectedBoard.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.paiTextPrimary)

            Spacer()

            Menu {
                Button {
                    Task {
                        await taskStore.refreshFromRemote(for: profile)
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    router.present(.newTask)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            } label: {
                CircleIcon(systemName: "square.grid.2x2")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func content(sections: [TaskDateSection], profile: FamilyProfile) -> some View {
        if sections.isEmpty {
            VStack {
                if let message = taskStore.syncErrorMessage {
                    networkIssueBanner(message: message, profile: profile)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                }

                Spacer()

                emptyState(for: selectedBoard)
                    .padding(.horizontal, 28)
                    .offset(y: -54)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let message = taskStore.syncErrorMessage {
                    networkIssueBanner(message: message, profile: profile)
                        .listRowInsets(.init(top: 2, leading: 20, bottom: 10, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.tasks) { task in
                            TaskCardView(task: task, profile: profile) {
                                router.present(.taskDetail(task))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if task.fromUserId == profile.userId.rawValue {
                                    Button(role: .destructive) {
                                        pendingDeleteTask = task
                                        showsDeleteConfirmation = true
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }

                                if task.status == .done && !task.archived {
                                    Button {
                                        taskStore.archiveTask(task, profile: profile)
                                    } label: {
                                        Label("归档", systemImage: "archivebox")
                                    }
                                    .tint(.blue)
                                }

                                Button {
                                    router.present(.taskDetail(task))
                                } label: {
                                    Label("日期", systemImage: "calendar")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if task.toUserId == profile.userId.rawValue && task.status == .pending {
                                    Button {
                                        taskStore.markReceived(task, profile: profile)
                                    } label: {
                                        Label("收到", systemImage: "bell.badge")
                                    }
                                    .tint(.blue)
                                } else if task.toUserId == profile.userId.rawValue && task.status == .received {
                                    Button {
                                        taskStore.markDone(task, profile: profile)
                                    } label: {
                                        Label("完成", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                            .listRowInsets(.init(top: 5, leading: 20, bottom: 7, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }

                Color.clear
                    .frame(height: 126)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .refreshable {
                await taskStore.refreshFromRemote(for: profile)
            }
        }
    }

    private func sectionHeader(_ section: TaskDateSection) -> some View {
        HStack(spacing: 8) {
            Text(section.bucket.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.paiTextSecondary)

            Text("\(section.tasks.count)")
                .font(.caption.bold())
                .foregroundStyle(Color.paiTextSecondary.opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var addButton: some View {
        Button {
            router.present(.newTask)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 66, height: 66)
                .background(Color.paiPrimary)
                .clipShape(Circle())
                .shadow(color: Color.paiPrimary.opacity(0.35), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("新建任务")
    }

    private func bottomDock(profile: FamilyProfile) -> some View {
        HStack(spacing: 42) {
            dockButton(.arranged, systemName: "checkmark.square.fill")
            dockButton(.archive, systemName: "archivebox.fill")

            Button {
                Task {
                    await taskStore.refreshFromRemote(for: profile)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.paiTextPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }

    private func dockButton(_ board: TaskBoard, systemName: String) -> some View {
        Button {
            selectedBoard = board
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(selectedBoard == board ? Color.paiPrimary : Color.paiTextPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(board.title)
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
        VStack(spacing: 18) {
            Image(systemName: board.emptyIcon)
                .font(.system(size: 68, weight: .regular))
                .foregroundStyle(Color.paiPrimary.opacity(0.9))
                .frame(width: 120, height: 120)
                .background(Color.paiPrimaryLight.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 7) {
                Text(board.emptyTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.paiTextPrimary)

                Text(board.emptySubtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.paiTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CircleIcon: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.paiTextPrimary)
            .frame(width: 58, height: 58)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

private enum TaskBoard: String, CaseIterable, Identifiable {
    case arranged
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arranged:
            return "收集箱"
        case .archive:
            return "归档"
        }
    }

    var emptyIcon: String {
        switch self {
        case .arranged:
            return "checklist.unchecked"
        case .archive:
            return "archivebox"
        }
    }

    var emptyTitle: String {
        switch self {
        case .arranged:
            return "没有任务"
        case .archive:
            return "归档里还没有记录"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .arranged:
            return "点击 + 按钮即可添加"
        case .archive:
            return "完成后的任务会收进这里，记录不会删除"
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
