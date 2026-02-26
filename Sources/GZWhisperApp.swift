import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct GZWhisperApp: App {
    init() {
        if
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            let icon = NSImage(contentsOf: iconURL)
        {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 760)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHistoryVisible = true
    @State private var isDropTargeted = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color(red: 0.08, green: 0.10, blue: 0.15),
                    Color(red: 0.13, green: 0.16, blue: 0.23),
                ]
                : [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.89, green: 0.92, blue: 0.97),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackgroundColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.72)
    }

    private var cardBorderColor: Color {
        isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var pillBackgroundColor: Color {
        isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.80)
    }

    private var pillBorderColor: Color {
        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var editorBackgroundColor: Color {
        isDark ? Color.black.opacity(0.26) : Color.white.opacity(0.92)
    }

    private var editorBorderColor: Color {
        isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.08)
    }

    private var accentColor: Color {
        isDark
            ? Color(red: 0.74, green: 0.82, blue: 0.98)
            : Color(red: 0.08, green: 0.16, blue: 0.32)
    }

    private var footerBackground: Color {
        isDark ? Color.black.opacity(0.24) : Color.white.opacity(0.55)
    }

    private var runtimeIssueBackground: Color {
        isDark ? Color(red: 0.50, green: 0.24, blue: 0.12).opacity(0.35) : Color(red: 1.0, green: 0.95, blue: 0.86)
    }

    private var runtimeIssueBorder: Color {
        isDark ? Color.orange.opacity(0.45) : Color.orange.opacity(0.35)
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topCard
                workspaceBody
                footerBar
            }
            .padding(20)
        }
        .onAppear {
            viewModel.initialize()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            viewModel.handleDroppedProviders(providers)
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    private var topCard: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text("GZWhisper")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)

                    Text(viewModel.appVersionLabel)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(pillBackgroundColor, in: Capsule())
                        .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
                }

                Text(L10n.t("app.subtitle"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorderColor, lineWidth: 1))

            modelMiniCard
                .frame(width: 380)
        }
    }

    private var modelMiniCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let runtimeIssueMessage = viewModel.runtimeIssueMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(runtimeIssueMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(10)
                .background(runtimeIssueBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(runtimeIssueBorder, lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button(action: viewModel.revealModelInFinder) {
                    statusPill(title: L10n.t("label.model"), value: viewModel.modelStatus)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.hasConnectedModel)
                .help(L10n.t("help.openModelFolder"))

                Spacer(minLength: 8)

                if viewModel.hasConnectedModel {
                    Button(action: viewModel.deleteModel) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canDeleteModel)
                    .help(L10n.t("help.deleteModel"))
                } else {
                    Button(action: viewModel.downloadModelWithFolderPrompt) {
                        Label(viewModel.isDownloadingModel ? L10n.t("button.downloading") : L10n.t("button.downloadModel"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing || viewModel.runtimeIssueMessage != nil)

                    Button(action: viewModel.connectExistingLocalModel) {
                        Label(L10n.t("button.connectLocal"), systemImage: "externaldrive")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing || viewModel.runtimeIssueMessage != nil)
                }
            }

            HStack(spacing: 5) {
                Text(L10n.t("label.modelSource"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if viewModel.modelSourceText == L10n.t("status.sourceLocalFolder") {
                    Text(viewModel.modelSourceText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Link("Hugging Face", destination: viewModel.modelHubURL)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }

            if !viewModel.modelLocationText.isEmpty {
                Text(viewModel.modelLocationText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if viewModel.shouldShowDownloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.downloadSourceText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if viewModel.hasKnownDownloadTotal {
                        ProgressView(value: viewModel.downloadProgressFraction)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }

                    Text(viewModel.downloadProgressText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    private var workspaceBody: some View {
        HStack(spacing: 12) {
            if isHistoryVisible {
                historyPanel
                    .frame(width: 320)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                inputCard
                editorCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isHistoryVisible)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: { isHistoryVisible.toggle() }) {
                    Label(
                        isHistoryVisible ? L10n.t("button.hideHistory") : L10n.t("button.showHistory"),
                        systemImage: "sidebar.left"
                    )
                }
                .buttonStyle(.bordered)

                Button(action: viewModel.chooseFiles) {
                    Label(L10n.t("button.addMedia"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isDownloadingModel || viewModel.isRecording)

                Text(viewModel.queueSummaryText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: viewModel.transcribeAllQueuedFiles) {
                    Label(
                        viewModel.isTranscribing ? L10n.t("button.transcribingAll") : L10n.t("button.transcribeAll"),
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.05, green: 0.45, blue: 0.35))
                .disabled(!viewModel.canStartQueue)
            }

            HStack(spacing: 10) {
                Picker(L10n.t("label.language"), selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.languageOptions, id: \.code) { option in
                        Text(option.title).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                statusPill(title: L10n.t("label.detectedLanguage"), value: viewModel.detectedLanguage)

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Text(L10n.t("label.recordMode"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Picker("", selection: $viewModel.selectedRecordingMode) {
                    ForEach(viewModel.recordingModeOptions) { mode in
                        Text(viewModel.recordingModeTitle(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(viewModel.isRecording)

                Button(action: viewModel.isRecording ? viewModel.stopRecording : viewModel.startRecording) {
                    Label(
                        viewModel.isRecording ? L10n.t("button.stopRecording") : L10n.t("button.startRecording"),
                        systemImage: viewModel.isRecording ? "stop.fill" : "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRecording ? .red : Color(red: 0.75, green: 0.10, blue: 0.14))
                .disabled(viewModel.isRecording ? !viewModel.canStopRecording : !viewModel.canStartRecording)

                if viewModel.isRecording {
                    Button(action: viewModel.toggleRecordingPause) {
                        Label(
                            viewModel.isRecordingPaused ? L10n.t("button.resumeRecording") : L10n.t("button.pauseRecording"),
                            systemImage: viewModel.isRecordingPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRecordingPaused ? !viewModel.canResumeRecording : !viewModel.canPauseRecording)
                }

                statusPill(title: L10n.t("label.recording"), value: viewModel.recordingElapsedText)

                Spacer(minLength: 8)
            }

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6]))
                .foregroundStyle(isDropTargeted ? accentColor : cardBorderColor)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(editorBackgroundColor.opacity(0.4))
                )
                .overlay(alignment: .leading) {
                    Text(L10n.t("text.dropFiles"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                .frame(height: 40)
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("title.history"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))

                Spacer()

                Text("\(viewModel.historyCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pillBackgroundColor, in: Capsule())
                    .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
            }

            if viewModel.historyItems.isEmpty {
                Text(L10n.t("text.historyEmpty"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.historyItems) { item in
                            historyItemRow(item)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    private func historyItemRow(_ item: TranscriptHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                stateIndicator(for: item)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.sourceFileName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        if let badge = viewModel.historyBadgeText(for: item) {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.40, green: 0.30, blue: 0.02))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(red: 1.0, green: 0.89, blue: 0.45).opacity(isDark ? 0.85 : 1.0))
                                )
                                .help(viewModel.historyBadgeHelp(for: item) ?? "")
                        }
                    }

                    Text(viewModel.historyMetaText(for: item))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(viewModel.historyStateLabel(for: item.state))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(stateColor(for: item.state))
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if viewModel.canQueueHistoryItem(item) {
                        Button(action: { viewModel.queueHistoryItemForTranscription(item.id) }) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("help.transcribeFromHistory"))
                    }

                    if item.state == .completed {
                        Button(action: { viewModel.revealTranscriptInFinder(item.id) }) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("help.openTranscript"))
                    }

                    if item.audioPath != nil {
                        Button(action: { viewModel.revealAudioInFinder(item.id) }) {
                            Image(systemName: "waveform")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("help.openAudio"))
                    }

                    Button(action: { viewModel.deleteHistoryItem(item.id) }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!viewModel.canDeleteHistoryItem(item))
                }
            }

            if item.state == .processing {
                if let fraction = item.progressFraction {
                    Text(String(format: "%.0f%%", fraction * 100))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if !viewModel.etaText(for: item).isEmpty {
                    Text(viewModel.etaText(for: item))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if item.state == .failed, let errorMessage = item.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    viewModel.selectedHistoryItemID == item.id
                        ? accentColor.opacity(isDark ? 0.24 : 0.12)
                        : editorBackgroundColor.opacity(0.6)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(viewModel.selectedHistoryItemID == item.id ? accentColor.opacity(0.45) : editorBorderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openHistoryItem(item.id)
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("title.result"))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()

                Button(L10n.t("button.copyAll"), action: viewModel.copyAllText)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcriptText.isEmpty)

                Button(L10n.t("button.saveTXT"), action: viewModel.saveAsText)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcriptText.isEmpty)

                Button(L10n.t("button.saveJSON"), action: viewModel.saveAsJSON)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.transcriptText.isEmpty)
            }

            editorTextView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var editorTextView: some View {
        if #available(macOS 13.0, *) {
            TextEditor(text: $viewModel.transcriptText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(editorBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(editorBorderColor, lineWidth: 1)
                )
        } else {
            TextEditor(text: $viewModel.transcriptText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(editorBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(editorBorderColor, lineWidth: 1)
                )
        }
    }

    private var footerBar: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Link("GitHub", destination: URL(string: "https://github.com/globa-me/GZWhisper")!)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)

                Text("|")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Link(L10n.t("footer.author"), destination: URL(string: "https://zakharov.asia/")!)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(footerBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [8]))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accentColor.opacity(isDark ? 0.12 : 0.10))
            )
            .padding(18)
            .overlay {
                Text(L10n.t("text.dropFiles"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
            }
            .allowsHitTesting(false)
    }

    private func statusPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(pillBackgroundColor, in: Capsule())
        .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
    }

    private func stateIndicator(for item: TranscriptHistoryItem) -> some View {
        Group {
            switch item.state {
            case .queued:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .processing:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 14, height: 14)
    }

    private func stateColor(for state: TranscriptJobState) -> Color {
        switch state {
        case .queued:
            return .secondary
        case .processing:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
