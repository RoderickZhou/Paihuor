import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var taskStore: TaskStore

    @StateObject private var speechRecognizer = SpeechRecognizerService()
    @State private var rawText = ""
    @State private var title = ""
    @State private var detail = ""
    @State private var hasDeadline = true
    @State private var deadline = Date().addingTimeInterval(3600)
    @State private var toUserId: UserRole = .husband
    @State private var parseState: MiniMaxParseState = .idle
    @State private var isPressingRecord = false
    @State private var pendingAutoParseAfterRecording = false
    @State private var lastAutoParsedText = ""
    @State private var autoParseTask: Task<Void, Never>?

    private var canSave: Bool {
        !normalizedTitle.isEmpty || !normalizedRawText.isEmpty
    }

    private var normalizedRawText: String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("语音") {
                    holdToRecordButton

                    if !speechRecognizer.transcript.isEmpty {
                        Text(speechRecognizer.transcript)
                            .foregroundStyle(Color.paiTextSecondary)
                    }

                    if let errorMessage = speechRecognizer.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    Button {
                        cancelAutoParse()
                        speechRecognizer.resetTranscript()
                        rawText = ""
                        parseState = .idle
                        lastAutoParsedText = ""
                    } label: {
                        Label("清空语音文字", systemImage: "trash")
                    }
                    .disabled(speechRecognizer.transcript.isEmpty && normalizedRawText.isEmpty)
                }

                Section("原话") {
                    TextField("例如：今晚八点前把垃圾带下去", text: $rawText, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("MiniMax 解析") {
                    Button {
                        parseWithMiniMax()
                    } label: {
                        HStack {
                            if parseState.isParsing {
                                ProgressView()
                            }
                            Label(parseState == .parsed ? "重新解析" : "解析成任务草稿", systemImage: "sparkles")
                        }
                    }
                    .disabled(!AppConfig.hasMiniMaxAPIKey || normalizedRawText.isEmpty || parseState.isParsing)

                    switch parseState {
                    case .idle:
                        if AppConfig.hasMiniMaxAPIKey {
                            Text("按住录音结束后会自动生成草稿。")
                                .foregroundStyle(Color.paiTextSecondary)
                        } else {
                            Text("MiniMax Key 未配置。")
                                .foregroundStyle(.red)
                        }
                    case .parsing:
                        Text("正在解析任务标题、细节和截止时间。")
                            .foregroundStyle(Color.paiTextSecondary)
                    case .parsed:
                        Text("已生成草稿，请检查下面内容后发送。")
                            .foregroundStyle(Color.paiPrimary)
                    case .failed(let message):
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }

                Section("审核") {
                    TextField("标题", text: $title)
                    TextField("补充细节", text: $detail, axis: .vertical)
                        .lineLimit(2...5)

                    Toggle("设置截止时间", isOn: $hasDeadline)

                    if hasDeadline {
                        DatePicker("截止", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("收件人") {
                    Picker("发给", selection: $toUserId) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }
            }
            .navigationTitle("新建任务")
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
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let profile = profileStore.profile {
                    toUserId = profile.counterpartUserId
                }
            }
            .onChange(of: speechRecognizer.transcript) { newValue in
                guard !newValue.isEmpty else { return }
                rawText = newValue
                if parseState == .parsed || parseState.isFailed {
                    parseState = .idle
                }
            }
            .onChange(of: speechRecognizer.isRecording) { isRecording in
                if !isRecording && pendingAutoParseAfterRecording {
                    scheduleAutoParseAfterRecording()
                }
            }
            .onDisappear {
                cancelAutoParse()
                speechRecognizer.stopRecording(cancelRecognition: true)
            }
        }
    }

    private var holdToRecordButton: some View {
        HStack(spacing: 10) {
            Image(systemName: speechRecognizer.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(recordButtonTitle)
                    .font(.headline)
                Text(recordButtonSubtitle)
                    .font(.caption)
                    .foregroundStyle(speechRecognizer.isRecording ? Color.white.opacity(0.85) : Color.paiTextSecondary)
            }

            Spacer()

            if parseState.isParsing {
                ProgressView()
            }
        }
        .foregroundStyle(speechRecognizer.isRecording ? .white : Color.paiPrimary)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(speechRecognizer.isRecording ? Color.paiPrimary : Color.paiPrimary.opacity(0.12))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(recordGesture)
        .opacity(parseState.isParsing ? 0.55 : 1)
        .accessibilityLabel("按住说话")
        .accessibilityHint("松开后停止录音并自动解析")
    }

    private var recordButtonTitle: String {
        if speechRecognizer.isRecording {
            return "松开结束"
        }

        if parseState.isParsing {
            return "正在解析"
        }

        return "按住说话"
    }

    private var recordButtonSubtitle: String {
        if speechRecognizer.isRecording {
            return "正在录入语音"
        }

        if parseState.isParsing {
            return "请稍等"
        }

        return "松开后自动解析"
    }

    private var recordGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressingRecord, !parseState.isParsing else { return }
                isPressingRecord = true
                beginHoldRecording()
            }
            .onEnded { _ in
                guard isPressingRecord else { return }
                isPressingRecord = false
                endHoldRecording()
            }
    }

    private func beginHoldRecording() {
        cancelAutoParse()
        pendingAutoParseAfterRecording = true
        parseState = .idle

        Task { @MainActor in
            await speechRecognizer.startRecording()

            if !isPressingRecord, speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
                scheduleAutoParseAfterRecording()
            } else if !speechRecognizer.isRecording {
                pendingAutoParseAfterRecording = false
                isPressingRecord = false
            }
        }
    }

    private func endHoldRecording() {
        speechRecognizer.stopRecording()
        scheduleAutoParseAfterRecording()
    }

    private func scheduleAutoParseAfterRecording() {
        cancelAutoParse()

        autoParseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            pendingAutoParseAfterRecording = false
            let input = normalizedRawText

            guard !input.isEmpty else { return }
            guard AppConfig.hasMiniMaxAPIKey else {
                parseState = .failed("MiniMax Key 未配置。")
                return
            }
            guard input != lastAutoParsedText else { return }

            lastAutoParsedText = input
            parseWithMiniMax()
        }
    }

    private func cancelAutoParse() {
        autoParseTask?.cancel()
        autoParseTask = nil
    }

    private func parseWithMiniMax() {
        let input = normalizedRawText
        guard !input.isEmpty, !parseState.isParsing else { return }

        parseState = .parsing

        Task {
            do {
                let draft = try await MiniMaxTaskParser().parse(rawText: input)
                await MainActor.run {
                    title = draft.title
                    detail = draft.detail
                    if draft.hasDeadline {
                        hasDeadline = true
                        deadline = Date(epochMilliseconds: draft.deadline)
                    } else {
                        hasDeadline = false
                    }
                    parseState = .parsed
                }
            } catch {
                await MainActor.run {
                    parseState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func save() {
        guard let profile = profileStore.profile else { return }

        let finalTitle = normalizedTitle.isEmpty
            ? String(normalizedRawText.prefix(15))
            : normalizedTitle
        let finalRawText = normalizedRawText.isEmpty ? finalTitle : normalizedRawText

        taskStore.createTask(
            rawText: finalRawText,
            title: finalTitle,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: hasDeadline ? deadline.epochMilliseconds : 0,
            toUserId: toUserId,
            profile: profile
        )

        dismiss()
    }
}

private enum MiniMaxParseState: Equatable {
    case idle
    case parsing
    case parsed
    case failed(String)

    var isParsing: Bool {
        if case .parsing = self {
            return true
        }

        return false
    }

    var isFailed: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}
