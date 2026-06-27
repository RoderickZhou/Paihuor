import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore

    @State private var familyId = ""
    @State private var userId: UserRole = .wife
    @State private var userName = ""
    @State private var showingClearConfirmation = false
    @State private var isSyncingFromProfile = false

    var body: some View {
        Form {
            Section("家庭") {
                TextField("家庭配对码", text: $familyId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: familyId) { _ in
                        saveIfReady()
                    }

                Picker("我的身份", selection: $userId) {
                    ForEach(UserRole.allCases) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .onChange(of: userId) { newValue in
                    if userName.isEmpty || UserRole.allCases.map(\.displayName).contains(userName) {
                        userName = newValue.displayName
                    }
                    saveIfReady()
                }

                TextField("显示名", text: $userName)
                    .onChange(of: userName) { _ in
                        saveIfReady()
                    }
            }

            Section("默认派活对象") {
                HStack {
                    Text("对方")
                    Spacer()
                    Text(userId.counterpart.displayName)
                        .foregroundStyle(Color.paiTextSecondary)
                }
            }

            Section("本地数据") {
                Button {
                    saveIfReady()
                } label: {
                    Label("保存当前设置", systemImage: "checkmark.circle")
                }
                .disabled(familyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("清空本机任务", systemImage: "trash")
                }
            }

            Section("后续接入") {
                LabeledContent("LeanCloud", value: "等待 AppId / AppKey / ServerURL")
                LabeledContent("Paihuor Relay", value: AppConfig.hasPaihuorRelayConfig ? "已配置" : "未配置")
                LabeledContent("默认家庭码", value: AppConfig.defaultFamilyId)
                LabeledContent("MiniMax", value: AppConfig.hasMiniMaxAPIKey ? "已配置" : "未配置")
                LabeledContent("模型", value: AppConfig.minimaxModel)
            }
        }
        .navigationTitle("设置")
        .scrollContentBackground(.hidden)
        .background(Color.paiBackground)
        .onAppear(perform: syncFromProfile)
        .confirmationDialog("清空本机任务？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                taskStore.clearAll(profile: profileStore.profile)
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func syncFromProfile() {
        guard let profile = profileStore.profile else { return }
        isSyncingFromProfile = true
        familyId = profile.familyId
        userId = profile.userId
        userName = profile.effectiveDisplayName
        isSyncingFromProfile = false
    }

    private func saveIfReady() {
        guard !isSyncingFromProfile else { return }

        let trimmedFamilyId = familyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFamilyId.isEmpty else { return }

        profileStore.save(familyId: trimmedFamilyId, userId: userId, userName: userName)
    }
}
