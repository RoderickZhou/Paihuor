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
        VStack(spacing: 0) {
            dragHandle
            editorHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    quickInputArea
                    parsedDraftArea
                    scheduleArea
                    holdToRecordButton
                    parseMessage
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 118)
            }

            sendBar
        }
        .background(Color.paiCardBackground.ignoresSafeArea())
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

    private var dragHandle: some View {
        Capsule()
            .fill(Color.paiTextSecondary.opacity(0.25))
            .frame(width: 42, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
    }

    private var editorHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.paiTextSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")

            Spacer()

            Text("新建任务")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.paiTextPrimary)

            Spacer()

            Button {
                clearDraft()
            } label: {
                Image(systemName: "trash")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.paiTextSecondary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(speechRecognizer.transcript.isEmpty && normalizedRawText.isEmpty && normalizedTitle.isEmpty && detail.isEmpty)
            .accessibilityLabel("清空")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var quickInputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("例如：3点回来带点菜", text: $rawText, axis: .vertical)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.paiTextPrimary)
                .lineLimit(2...4)

            TextField("描述", text: $detail, axis: .vertical)
                .font(.body)
                .foregroundStyle(Color.paiTextSecondary)
                .lineLimit(2...5)

            if !speechRecognizer.transcript.isEmpty {
                Text(speechRecognizer.transcript)
                    .font(.caption)
                    .foregroundStyle(Color.paiTextSecondary)
                    .lineLimit(2)
            }

            if let errorMessage = speechRecognizer.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.paiDanger)
            }
        }
    }

    @ViewBuilder
    private var parsedDraftArea: some View {
        if parseState == .parsed || !normalizedTitle.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("草稿标题", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.paiPrimary)

                TextField("标题", text: $title)
                    .font(.headline)
                    .foregroundStyle(Color.paiTextPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paiBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var scheduleArea: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $hasDeadline) {
                Label(hasDeadline ? "截止时间" : "不设截止时间", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.paiTextPrimary)
            }

            if hasDeadline {
                DatePicker("时间", selection: $deadline, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }

            Picker("发给", selection: $toUserId) {
                ForEach(UserRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var parseMessage: some View {
        switch parseState {
        case .idle:
            Text(AppConfig.hasMiniMaxAPIKey ? "按住录音，松开后会自动整理成任务。" : "MiniMax Key 未配置。")
                .font(.caption)
                .foregroundStyle(AppConfig.hasMiniMaxAPIKey ? Color.paiTextSecondary : Color.paiDanger)
        case .parsing:
            Label("正在整理任务内容", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.paiTextSecondary)
        case .parsed:
            Label("已生成草稿，可以直接发送", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(Color.paiPrimary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.paiDanger)
        }
    }

    private var sendBar: some View {
        HStack(spacing: 16) {
            Button {
                parseWithMiniMax()
            } label: {
                Image(systemName: parseState.isParsing ? "hourglass" : "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.paiTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!AppConfig.hasMiniMaxAPIKey || normalizedRawText.isEmpty || parseState.isParsing)
            .accessibilityLabel(parseState == .parsed ? "重新解析" : "解析")

            Spacer()

            Button {
                save()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(canSave ? Color.paiPrimary : Color.paiTextSecondary.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(.ultraThinMaterial)
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

    private func clearDraft() {
        cancelAutoParse()
        speechRecognizer.resetTranscript()
        rawText = ""
        title = ""
        detail = ""
        parseState = .idle
        lastAutoParsedText = ""
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
