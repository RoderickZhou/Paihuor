import SwiftUI

struct PairingSetupView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var familyId = AppConfig.defaultFamilyId
    @State private var userId: UserRole = .wife
    @State private var userName = "老婆"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("派活儿")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.paiTextPrimary)

                        Text("先填同一个家庭配对码，再选择这台手机是谁。iOS 默认作为老婆端发送任务。")
                            .font(.body)
                            .foregroundStyle(Color.paiTextSecondary)
                    }

                    VStack(spacing: 16) {
                        TextField("家庭配对码，例如 9527", text: $familyId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        Picker("身份", selection: $userId) {
                            ForEach(UserRole.allCases) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: userId) { newValue in
                            userName = newValue.displayName
                        }

                        TextField("显示名", text: $userName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(18)
                    .background(Color.paiCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        profileStore.save(familyId: familyId, userId: userId, userName: userName)
                    } label: {
                        Label("开始使用", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(familyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .background(Color.paiBackground.ignoresSafeArea())
            .navigationTitle("家庭配对")
        }
    }
}
