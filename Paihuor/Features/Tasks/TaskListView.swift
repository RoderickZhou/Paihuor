import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if let profile = profileStore.profile {
                let tasks = taskStore.relevantTasks(for: profile)

                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            roleBanner(profile: profile)
                            summaryRow(tasks: tasks)

                            if tasks.isEmpty {
                                emptyState
                            } else {
                                ForEach(tasks) { task in
                                    TaskCardView(task: task, profile: profile)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 96)
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
            }
        }
        .navigationTitle("派活儿")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.present(.newTask)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("新建任务")
            }
        }
    }

    private func roleBanner(profile: FamilyProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("当前身份", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.paiTextPrimary)

                Spacer()

                Text(profile.userId.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.paiPrimary)
            }

            Picker("当前身份", selection: Binding(
                get: { profile.userId },
                set: { newRole in
                    profileStore.save(
                        familyId: profile.familyId,
                        userId: newRole,
                        userName: newRole.displayName
                    )
                }
            )) {
                ForEach(UserRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("默认发给")
                    .foregroundStyle(Color.paiTextSecondary)
                Spacer()
                Text(profile.counterpartUserId.displayName)
                    .foregroundStyle(Color.paiTextPrimary)
            }
            .font(.caption)
        }
        .padding(14)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryRow(tasks: [PaihuorTask]) -> some View {
        HStack(spacing: 10) {
            summaryPill(title: "全部", value: tasks.count, color: .paiPrimary)
            summaryPill(title: "待处理", value: tasks.filter { $0.status != .done }.count, color: .paiWarning)
            summaryPill(title: "完成", value: tasks.filter { $0.status == .done }.count, color: .paiTextSecondary)
        }
    }

    private func summaryPill(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.paiTextSecondary)
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist.unchecked")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.paiPrimary)

            Text("还没有任务")
                .font(.headline)
                .foregroundStyle(Color.paiTextPrimary)

            Text("点右下角加号，先用文字创建一条本地任务。录音和模型解析会在 M2 接上。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paiTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.paiCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
