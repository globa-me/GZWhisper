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
                .frame(minWidth: 640, idealWidth: 1100, minHeight: 500, idealHeight: 760)
        }
    }
}

private struct HistoryHoverView<Content: View>: View {
    @State private var isHovered = false
    private let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(isHovered)
            .onHover { isHovered = $0 }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHistoryVisible = true
    @State private var isDropTargeted = false
    @State private var historySearchText = ""
    @State private var isHistorySearchExpanded = false
    @State private var historySearchResults: [TranscriptHistoryItem] = []
    @State private var historySearchTask: Task<Void, Never>?
    @State private var selectedQueueItemIDs: Set<UUID> = []
    @State private var isBulkExportSelectionActive = false
    @State private var selectedExportItemIDs: Set<UUID> = []
    @State private var editingHistoryItemID: UUID?
    @State private var historyRenameDraft = ""
    @State private var recordingHUDWindowController: RecordingHUDWindowController?
    @FocusState private var focusedHistoryRenameFieldID: UUID?
    @FocusState private var isHistorySearchFocused: Bool

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

    private var filteredHistoryItems: [TranscriptHistoryItem] {
        guard isHistorySearchActive else {
            return viewModel.historyItems
        }

        let currentIDs = Set(viewModel.historyItems.map(\.id))
        return historySearchResults.filter { currentIDs.contains($0.id) }
    }

    private var isHistorySearchActive: Bool {
        !historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var historyCountLabel: String {
        if isHistorySearchActive {
            return "\(filteredHistoryItems.count)/\(viewModel.historyCount)"
        }
        return "\(viewModel.historyCount)"
    }

    private var visibleExportItemIDs: Set<UUID> {
        Set(filteredHistoryItems.compactMap { item in
            item.state == .completed && item.transcriptPath != nil ? item.id : nil
        })
    }

    private var primaryQueueButtonTitle: String {
        if viewModel.isTranscribing {
            return L10n.t("button.cancelQueue")
        }
        if viewModel.isQueuePaused {
            return L10n.t("button.resumeQueue")
        }
        return L10n.t("button.transcribeAll")
    }

    private var primaryQueueButtonIcon: String {
        if viewModel.isTranscribing {
            return "xmark.circle.fill"
        }
        if viewModel.isQueuePaused {
            return "play.circle.fill"
        }
        return "waveform.badge.magnifyingglass"
    }

    private var canUsePrimaryQueueButton: Bool {
        if viewModel.isTranscribing {
            return viewModel.canCancelQueue
        }
        if viewModel.isQueuePaused {
            return viewModel.canResumeQueue
        }
        return viewModel.canStartQueue
    }

    private var selectedQueueRunTargetIDs: Set<UUID> {
        let checkedIDs = selectedQueueItemIDs.filter { id in
            guard let item = viewModel.historyItems.first(where: { $0.id == id }) else {
                return false
            }
            return viewModel.canRunHistoryItem(item)
        }

        if !checkedIDs.isEmpty {
            return Set(checkedIDs)
        }

        if let selectedItem = viewModel.selectedHistoryItem, viewModel.canRunHistoryItem(selectedItem) {
            return [selectedItem.id]
        }

        return []
    }

    private var canTranscribeSelectedQueueTargets: Bool {
        !viewModel.isDownloadingModel
            && !viewModel.isTranscribing
            && !viewModel.isRecording
            && !viewModel.isStoppingRecording
            && viewModel.hasConnectedModel
            && viewModel.runtimeIssueMessage == nil
            && !selectedQueueRunTargetIDs.isEmpty
    }

    private func primaryQueueAction() {
        if viewModel.isTranscribing {
            viewModel.cancelTranscriptionQueue()
        } else if viewModel.isQueuePaused {
            viewModel.resumeQueue()
        } else {
            viewModel.transcribeAllQueuedFiles()
        }
    }

    private func transcribeSelectedQueueTargets() {
        let ids = selectedQueueRunTargetIDs
        guard !ids.isEmpty else {
            viewModel.transcribeSelectedHistoryItem()
            return
        }

        viewModel.transcribeHistoryItemsNow(ids)
        selectedQueueItemIDs.subtract(ids)
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
            .padding(12)
        }
        .onAppear {
            viewModel.initialize()
            historySearchResults = viewModel.historyItems
            if recordingHUDWindowController == nil {
                recordingHUDWindowController = RecordingHUDWindowController(viewModel: viewModel)
            }
            updateRecordingHUDWindowVisibility()
        }
        .onDisappear {
            historySearchTask?.cancel()
            recordingHUDWindowController?.hide()
        }
        .onChange(of: historySearchText) { _ in
            scheduleHistorySearch()
        }
        .onChange(of: viewModel.isRecording) { _ in
            updateRecordingHUDWindowVisibility()
        }
        .onChange(of: viewModel.isRecordingHUDVisible) { _ in
            updateRecordingHUDWindowVisibility()
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("GZWhisper")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)

                versionBadge

                Spacer(minLength: 12)

                modelControls
            }

            if let runtimeIssueMessage = viewModel.runtimeIssueMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(runtimeIssueMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(runtimeIssueBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(runtimeIssueBorder, lineWidth: 1))
            }

            if viewModel.shouldShowDownloadProgress {
                downloadProgress
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    private var versionBadge: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(viewModel.appVersionLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(pillBackgroundColor, in: Capsule())
                .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
        }
        .help("Build \(viewModel.appBuildLabel)")
    }

    @ViewBuilder
    private var modelControls: some View {
        if viewModel.hasConnectedModel {
            Menu {
                Button(action: viewModel.revealModelInFinder) {
                    Label(L10n.t("help.openModelFolder"), systemImage: "folder")
                }

                Button(action: viewModel.connectExistingLocalModel) {
                    Label(L10n.t("button.connectLocal"), systemImage: "externaldrive")
                }
                .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing || viewModel.runtimeIssueMessage != nil)

                Link("Hugging Face", destination: viewModel.modelHubURL)

                Divider()

                Button(action: viewModel.deleteModel) {
                    Label(L10n.t("help.deleteModel"), systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteModel)
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)

                    Text(viewModel.modelStatus)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
                .font(.system(size: 12, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pillBackgroundColor, in: Capsule())
                .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 150, idealWidth: 280, maxWidth: 360, alignment: .trailing)
            .help(viewModel.modelLocationText)
        } else {
            Button(action: viewModel.downloadModelWithFolderPrompt) {
                Label(viewModel.isDownloadingModel ? L10n.t("button.downloading") : L10n.t("button.downloadModel"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing || viewModel.runtimeIssueMessage != nil)

            Button(action: viewModel.connectExistingLocalModel) {
                Image(systemName: "externaldrive")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing || viewModel.runtimeIssueMessage != nil)
            .help(L10n.t("button.connectLocal"))
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(viewModel.downloadSourceText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(viewModel.downloadProgressText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasKnownDownloadTotal {
                ProgressView(value: viewModel.downloadProgressFraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    private var workspaceBody: some View {
        HStack(spacing: 12) {
            if isHistoryVisible {
                historyPanel
                    .frame(minWidth: 200, idealWidth: 290, maxWidth: 340)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                inputCard
                editorCard
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHistoryVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            adaptiveQueueControls
            languageControls
            adaptiveRecordingControls
        }
        .padding(12)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var adaptiveQueueControls: some View {
        if #available(macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                queueControlsWide
                queueControlsCompact
            }
        } else {
            queueControlsCompact
        }
    }

    private var queueControlsWide: some View {
        HStack(spacing: 8) {
            historyToggleButton
            addMediaButton
            queueSummary
            Spacer(minLength: 8)
            primaryQueueButton
            queueActionsMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var queueControlsCompact: some View {
        HStack(spacing: 8) {
            historyToggleButton
            addMediaButtonCompact
            queueSummary
                .layoutPriority(1)
            Spacer(minLength: 4)
            primaryQueueButtonCompact
            queueActionsMenu
        }
    }

    private var historyToggleButton: some View {
        Button(action: { isHistoryVisible.toggle() }) {
            Image(systemName: "sidebar.left")
        }
        .buttonStyle(.bordered)
        .help(isHistoryVisible ? L10n.t("button.hideHistory") : L10n.t("button.showHistory"))
    }

    private var addMediaButton: some View {
        Button(action: viewModel.chooseFiles) {
            Label(L10n.t("button.addMedia"), systemImage: "plus")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isDownloadingModel || viewModel.isRecording)
    }

    private var addMediaButtonCompact: some View {
        Button(action: viewModel.chooseFiles) {
            Image(systemName: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isDownloadingModel || viewModel.isRecording)
        .help(L10n.t("button.addMedia"))
        .accessibilityLabel(L10n.t("button.addMedia"))
    }

    private var queueSummary: some View {
        Text(viewModel.queueSummaryText)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var primaryQueueButton: some View {
        Button(action: primaryQueueAction) {
            Label(primaryQueueButtonTitle, systemImage: primaryQueueButtonIcon)
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isTranscribing ? .red : Color(red: 0.05, green: 0.45, blue: 0.35))
        .disabled(!canUsePrimaryQueueButton)
    }

    private var primaryQueueButtonCompact: some View {
        Button(action: primaryQueueAction) {
            Image(systemName: primaryQueueButtonIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isTranscribing ? .red : Color(red: 0.05, green: 0.45, blue: 0.35))
        .disabled(!canUsePrimaryQueueButton)
        .help(primaryQueueButtonTitle)
        .accessibilityLabel(primaryQueueButtonTitle)
    }

    private var queueActionsMenu: some View {
        Menu {
            Button(action: transcribeSelectedQueueTargets) {
                Label(L10n.t("button.transcribeSelected"), systemImage: "play")
            }
            .disabled(!canTranscribeSelectedQueueTargets)

            Button(action: viewModel.togglePauseQueueAfterCurrent) {
                Label(
                    viewModel.shouldPauseQueueAfterCurrent
                        ? L10n.t("button.cancelPauseAfterCurrent")
                        : L10n.t("button.pauseAfterCurrent"),
                    systemImage: viewModel.shouldPauseQueueAfterCurrent ? "forward.fill" : "pause.circle"
                )
            }
            .disabled(!viewModel.isTranscribing)

            Button(action: viewModel.skipCurrentQueueItem) {
                Label(L10n.t("button.skipCurrent"), systemImage: "forward.end.fill")
            }
            .disabled(!viewModel.canSkipCurrentQueueItem)

            Divider()

            Button(action: viewModel.clearQueuedItems) {
                Label(L10n.t("button.clearQueue"), systemImage: "text.badge.xmark")
            }
            .disabled(!viewModel.canClearQueue)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help(L10n.t("button.queueActions"))
    }

    private var languageControls: some View {
        HStack(spacing: 8) {
            Picker(L10n.t("label.language"), selection: $viewModel.selectedLanguage) {
                ForEach(viewModel.languageOptions, id: \.code) { option in
                    Text(option.title).tag(option.code)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 100, idealWidth: 130, maxWidth: 150)

            statusPill(title: L10n.t("label.detectedLanguage"), value: viewModel.detectedLanguage)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var adaptiveRecordingControls: some View {
        if #available(macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                recordingControlsWide
                recordingControlsCompact
            }
        } else {
            recordingControlsCompact
        }
    }

    private var recordingControlsWide: some View {
        HStack(spacing: 8) {
            recordingModeLabel
            recordingModePicker
            recordingPrimaryButton
            recordingSessionButtons
            recordingStatus
            recordingOptionsMenu
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var recordingControlsCompact: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                recordingModeLabel
                recordingModePicker
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                recordingPrimaryButtonCompact
                recordingSessionButtonsCompact
                recordingStatus
                recordingOptionsMenu
                Spacer(minLength: 0)
            }
        }
    }

    private var recordingModeLabel: some View {
        Text(L10n.t("label.recordMode"))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var recordingModePicker: some View {
        Picker("", selection: $viewModel.selectedRecordingMode) {
            ForEach(viewModel.recordingModeOptions) { mode in
                Text(viewModel.recordingModeTitle(mode)).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 135, idealWidth: 190, maxWidth: 230)
        .disabled(viewModel.isRecording)
    }

    private var recordingPrimaryButton: some View {
        Button(action: viewModel.isRecording ? viewModel.stopRecording : viewModel.startRecording) {
            Label(
                viewModel.isRecording ? L10n.t("button.stopRecording") : L10n.t("button.startRecording"),
                systemImage: viewModel.isRecording ? "stop.fill" : "record.circle"
            )
            .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : Color(red: 0.75, green: 0.10, blue: 0.14))
        .disabled(viewModel.isRecording ? !viewModel.canStopRecording : !viewModel.canStartRecording)
    }

    private var recordingPrimaryButtonCompact: some View {
        Button(action: viewModel.isRecording ? viewModel.stopRecording : viewModel.startRecording) {
            Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle")
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : Color(red: 0.75, green: 0.10, blue: 0.14))
        .disabled(viewModel.isRecording ? !viewModel.canStopRecording : !viewModel.canStartRecording)
        .help(viewModel.isRecording ? L10n.t("button.stopRecording") : L10n.t("button.startRecording"))
        .accessibilityLabel(viewModel.isRecording ? L10n.t("button.stopRecording") : L10n.t("button.startRecording"))
    }

    @ViewBuilder
    private var recordingSessionButtons: some View {
        if viewModel.isRecording {
            Button(action: viewModel.toggleRecordingPause) {
                Label(
                    viewModel.isRecordingPaused ? L10n.t("button.resumeRecording") : L10n.t("button.pauseRecording"),
                    systemImage: viewModel.isRecordingPaused ? "play.fill" : "pause.fill"
                )
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRecordingPaused ? !viewModel.canResumeRecording : !viewModel.canPauseRecording)

            if !viewModel.isRecordingHUDVisible {
                Button(action: viewModel.showRecordingHUD) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                }
                .buttonStyle(.bordered)
                .help(L10n.t("help.showRecordingHUD"))
            }
        }
    }

    @ViewBuilder
    private var recordingSessionButtonsCompact: some View {
        if viewModel.isRecording {
            Button(action: viewModel.toggleRecordingPause) {
                Image(systemName: viewModel.isRecordingPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRecordingPaused ? !viewModel.canResumeRecording : !viewModel.canPauseRecording)
            .help(viewModel.isRecordingPaused ? L10n.t("button.resumeRecording") : L10n.t("button.pauseRecording"))
            .accessibilityLabel(viewModel.isRecordingPaused ? L10n.t("button.resumeRecording") : L10n.t("button.pauseRecording"))

            if !viewModel.isRecordingHUDVisible {
                Button(action: viewModel.showRecordingHUD) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                }
                .buttonStyle(.bordered)
                .help(L10n.t("help.showRecordingHUD"))
                .accessibilityLabel(L10n.t("help.showRecordingHUD"))
            }
        }
    }

    private var recordingStatus: some View {
        statusPill(title: L10n.t("label.recording"), value: viewModel.recordingElapsedText)
    }

    private var recordingOptionsMenu: some View {
        Menu {
            Toggle(L10n.t("setting.hudAutoShow"), isOn: $viewModel.shouldShowHUDOnRecordingStart)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help(L10n.t("help.recordingOptions"))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            adaptiveHistoryHeader

            if isHistorySearchExpanded && !viewModel.historyItems.isEmpty {
                historySearchField
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.historyItems.isEmpty {
                Text(L10n.t("text.historyEmpty"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer()
            } else if filteredHistoryItems.isEmpty {
                Text(L10n.t("text.historySearchEmpty"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredHistoryItems) { item in
                            historyItemRow(item)
                        }
                    }
                }
                .layoutPriority(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isHistorySearchExpanded)
        .clipped()
        .padding(12)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var adaptiveHistoryHeader: some View {
        HStack(spacing: 8) {
            historyTitleAndCount
            Spacer(minLength: 4)

            if !viewModel.historyItems.isEmpty {
                if isBulkExportSelectionActive {
                    Button(action: toggleAllVisibleExportItems) {
                        Image(systemName: visibleExportItemIDs.isEmpty || !visibleExportItemIDs.isSubset(of: selectedExportItemIDs) ? "checkmark.square" : "checkmark.square.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(visibleExportItemIDs.isEmpty)
                    .help(L10n.t("help.selectAllVisibleTranscripts"))

                    Menu {
                        Button(L10n.t("button.exportSelectedTXT")) {
                            exportSelectedHistoryItems(as: .txt)
                        }
                        Button(L10n.t("button.exportSelectedJSON")) {
                            exportSelectedHistoryItems(as: .json)
                        }
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(selectedExportItemIDs.isEmpty)
                    .help(L10n.f("help.exportSelectedTranscripts", selectedExportItemIDs.count))

                    Button(action: cancelBulkExportSelection) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.t("button.cancel"))
                } else {
                    Button(action: beginBulkExportSelection) {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.historyItems.contains(where: { $0.state == .completed && $0.transcriptPath != nil }))
                    .help(L10n.t("help.bulkExportTranscripts"))

                    Button(action: toggleHistorySearch) {
                        Image(systemName: isHistorySearchExpanded ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.t("placeholder.historySearch"))
                    .accessibilityLabel(L10n.t("placeholder.historySearch"))
                }
            }
        }
    }

    private var historyTitleAndCount: some View {
        HStack(spacing: 8) {
            Text(L10n.t("title.history"))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text(historyCountLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(pillBackgroundColor, in: Capsule())
                .overlay(Capsule().stroke(pillBorderColor, lineWidth: 1))
        }
    }

    private var historySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(L10n.t("placeholder.historySearch"), text: $historySearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .focused($isHistorySearchFocused)
                .onExitCommand(perform: closeHistorySearch)

            if isHistorySearchActive {
                Button(action: { historySearchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(editorBackgroundColor.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(editorBorderColor, lineWidth: 1))
    }

    private func toggleHistorySearch() {
        if isHistorySearchExpanded {
            closeHistorySearch()
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isHistorySearchExpanded = true
        }
        DispatchQueue.main.async {
            isHistorySearchFocused = true
        }
    }

    private func closeHistorySearch() {
        historySearchText = ""
        isHistorySearchFocused = false
        withAnimation(.easeOut(duration: 0.2)) {
            isHistorySearchExpanded = false
        }
    }

    private func beginBulkExportSelection() {
        isBulkExportSelectionActive = true
        selectedExportItemIDs.removeAll()
    }

    private func cancelBulkExportSelection() {
        isBulkExportSelectionActive = false
        selectedExportItemIDs.removeAll()
    }

    private func toggleAllVisibleExportItems() {
        if !visibleExportItemIDs.isEmpty && visibleExportItemIDs.isSubset(of: selectedExportItemIDs) {
            selectedExportItemIDs.subtract(visibleExportItemIDs)
        } else {
            selectedExportItemIDs.formUnion(visibleExportItemIDs)
        }
    }

    private func toggleExportSelection(for id: UUID) {
        if selectedExportItemIDs.contains(id) {
            selectedExportItemIDs.remove(id)
        } else {
            selectedExportItemIDs.insert(id)
        }
    }

    private func exportSelectedHistoryItems(as format: HistoryExportFormat) {
        if viewModel.exportHistoryItems(selectedExportItemIDs, format: format) {
            cancelBulkExportSelection()
        }
    }

    private func scheduleHistorySearch() {
        historySearchTask?.cancel()

        guard isHistorySearchActive else {
            historySearchResults = viewModel.historyItems
            return
        }

        let query = historySearchText
        historySearchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }

            guard
                !Task.isCancelled,
                query == historySearchText,
                let results = await viewModel.filteredHistoryItems(matching: query),
                !Task.isCancelled,
                query == historySearchText
            else {
                return
            }

            historySearchResults = results
        }
    }

    private func historyItemRow(_ item: TranscriptHistoryItem) -> some View {
        let canRunItem = viewModel.canRunHistoryItem(item)
        let badgeText = viewModel.historyBadgeText(for: item)
        let badgeHelp = viewModel.historyBadgeHelp(for: item) ?? ""
        let metaText = viewModel.historyMetaText(for: item)

        return HistoryHoverView { isHovered in
            let canExportItem = item.state == .completed && item.transcriptPath != nil
            let showsActions = !isBulkExportSelectionActive && (editingHistoryItemID == item.id || isHovered)

            VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if isBulkExportSelectionActive, canExportItem {
                    Image(systemName: selectedExportItemIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selectedExportItemIDs.contains(item.id) ? accentColor : .secondary)
                    .help(L10n.t("help.selectTranscriptForExport"))
                    .padding(.top, 0)
                } else if canRunItem && !isBulkExportSelectionActive {
                    Button(action: { toggleQueueSelection(for: item.id) }) {
                        Image(systemName: selectedQueueItemIDs.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedQueueItemIDs.contains(item.id) ? accentColor : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isTranscribing)
                    .help(L10n.t("help.transcribeSelected"))
                    .padding(.top, 0)
                }

                stateIndicator(for: item)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if editingHistoryItemID == item.id {
                            TextField("", text: $historyRenameDraft, prompt: Text(item.sourceFileName))
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(pillBackgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(pillBorderColor, lineWidth: 1))
                                .focused($focusedHistoryRenameFieldID, equals: item.id)
                                .onSubmit {
                                    commitHistoryRename(for: item.id)
                                }
                        } else {
                            Text(viewModel.historyDisplayName(for: item))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .help(viewModel.historyOriginalNameText(for: item) ?? item.sourceFileName)
                        }

                        if let badge = badgeText {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.40, green: 0.30, blue: 0.02))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(red: 1.0, green: 0.89, blue: 0.45).opacity(isDark ? 0.85 : 1.0))
                                )
                                .help(badgeHelp)
                        }
                    }

                    Text(metaText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(metaText)

                    HStack(spacing: 6) {
                        Text(viewModel.historyStateLabel(for: item.state))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(stateColor(for: item.state))
                            .lineLimit(1)

                        if let queuePosition = viewModel.queuePositionText(for: item) {
                            Text(queuePosition)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    if editingHistoryItemID == item.id {
                        Button(action: { commitHistoryRename(for: item.id) }) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.borderless)

                        Button(action: cancelHistoryRename) {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        if item.state == .queued {
                            Button(action: { viewModel.moveQueuedHistoryItemUp(item.id) }) {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!viewModel.canMoveQueuedHistoryItemUp(item))
                            .help(L10n.t("help.moveQueueUp"))

                            Button(action: { viewModel.moveQueuedHistoryItemDown(item.id) }) {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!viewModel.canMoveQueuedHistoryItemDown(item))
                            .help(L10n.t("help.moveQueueDown"))

                            Button(action: { viewModel.transcribeHistoryItemNow(item.id) }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isTranscribing || !viewModel.hasConnectedModel)
                            .help(L10n.t("help.transcribeSelected"))

                            Button(action: { viewModel.removeHistoryItemFromQueue(item.id) }) {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isTranscribing)
                            .help(L10n.t("help.removeFromQueue"))
                        } else if viewModel.canQueueHistoryItem(item) {
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

                        Button(action: { beginHistoryRename(item) }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("help.renameHistoryItem"))

                        Button(action: { viewModel.deleteHistoryItem(item.id) }) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!viewModel.canDeleteHistoryItem(item))
                    }
                }
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
                .accessibilityHidden(!showsActions)
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
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        (isBulkExportSelectionActive && selectedExportItemIDs.contains(item.id))
                            || viewModel.selectedHistoryItemID == item.id
                            ? accentColor.opacity(isDark ? 0.24 : 0.12)
                            : editorBackgroundColor.opacity(0.6)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        (isBulkExportSelectionActive && selectedExportItemIDs.contains(item.id))
                            || viewModel.selectedHistoryItemID == item.id
                            ? accentColor.opacity(0.45)
                            : editorBorderColor,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard editingHistoryItemID != item.id else {
                    return
                }
                if isBulkExportSelectionActive {
                    if canExportItem {
                        toggleExportSelection(for: item.id)
                    }
                } else {
                    viewModel.openHistoryItem(item.id)
                }
            }
        }
    }

    private func beginHistoryRename(_ item: TranscriptHistoryItem) {
        editingHistoryItemID = item.id
        historyRenameDraft = viewModel.historyDisplayName(for: item)
        focusedHistoryRenameFieldID = item.id
    }

    private func toggleQueueSelection(for id: UUID) {
        if selectedQueueItemIDs.contains(id) {
            selectedQueueItemIDs.remove(id)
        } else {
            selectedQueueItemIDs.insert(id)
        }
    }

    private func commitHistoryRename(for id: UUID) {
        viewModel.renameHistoryItem(id, to: historyRenameDraft)
        cancelHistoryRename()
    }

    private func cancelHistoryRename() {
        editingHistoryItemID = nil
        historyRenameDraft = ""
        focusedHistoryRenameFieldID = nil
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptiveEditorHeader

            editorTextView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var adaptiveEditorHeader: some View {
        if #available(macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                editorHeaderWide
                editorHeaderCompact
            }
        } else {
            editorHeaderCompact
        }
    }

    private var editorHeaderWide: some View {
        HStack(spacing: 8) {
            editorTitle
            Spacer(minLength: 8)
            copyAllButtonWithTitle
            exportMenuWithTitle
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var editorHeaderCompact: some View {
        HStack(spacing: 8) {
            editorTitle
            Spacer(minLength: 0)

            Button(action: viewModel.copyAllText) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.transcriptText.isEmpty)
            .help(L10n.t("button.copyAll"))

            Menu {
                exportMenuItems
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .disabled(viewModel.transcriptText.isEmpty)
            .help(L10n.t("button.export"))
        }
    }

    private var editorTitle: some View {
        Text(L10n.t("title.result"))
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .lineLimit(1)
    }

    private var copyAllButtonWithTitle: some View {
        Button(L10n.t("button.copyAll"), action: viewModel.copyAllText)
            .buttonStyle(.bordered)
            .disabled(viewModel.transcriptText.isEmpty)
    }

    private var exportMenuWithTitle: some View {
        Menu {
            exportMenuItems
        } label: {
            Label(L10n.t("button.export"), systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.transcriptText.isEmpty)
    }

    @ViewBuilder
    private var exportMenuItems: some View {
        Button(L10n.t("button.saveTXT"), action: viewModel.saveAsText)
        Button(L10n.t("button.saveJSON"), action: viewModel.saveAsJSON)
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
        HStack(spacing: 10) {
            footerStatusContent
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .layoutPriority(1)

            Spacer()

            if let deletedName = viewModel.pendingHistoryDeletionName {
                HStack(spacing: 6) {
                    Text(L10n.f("status.historyDeleted", deletedName))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(L10n.t("button.undo"), action: viewModel.undoHistoryDeletion)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!viewModel.canUndoHistoryDeletion)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            debugMenu
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.pendingHistoryDeletionName)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(footerBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }

    @ViewBuilder
    private var footerStatusContent: some View {
        if !viewModel.isTranscribing && !viewModel.isRecording {
            Text(viewModel.statusMessage)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            HStack(spacing: 8) {
                if viewModel.isTranscribing {
                    Text(transcriptionFooterText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if viewModel.isTranscribing && viewModel.isRecording {
                    Divider()
                        .frame(height: 14)
                }

                if viewModel.isRecording {
                    Text(recordingFooterText)
                        .lineLimit(1)
                }
            }
        }
    }

    private var transcriptionFooterText: String {
        let fileName = viewModel.currentTranscribingFileName.isEmpty
            ? L10n.t("button.transcribing")
            : viewModel.currentTranscribingFileName
        if let progress = viewModel.activeProgressFraction {
            return "\(L10n.t("label.transcription")): \(fileName) · \(String(format: "%.0f%%", progress * 100))"
        }
        return "\(L10n.t("label.transcription")): \(fileName)"
    }

    private var recordingFooterText: String {
        let pauseSuffix = viewModel.isRecordingPaused ? " · \(L10n.t("button.pauseRecording"))" : ""
        return "\(L10n.t("label.recording")): \(viewModel.recordingElapsedText)\(pauseSuffix)"
    }

    private var debugMenu: some View {
        Menu {
            Button(L10n.t("button.copyDebugInfo"), action: viewModel.copyDebugInfo)
            Button(L10n.t("button.openRuntimeFolder"), action: viewModel.revealRuntimeFolderInFinder)

            Divider()

            Link("GitHub", destination: URL(string: "https://github.com/globa-me/GZWhisper")!)
            Link(L10n.t("footer.author"), destination: URL(string: "https://zakharov.asia/")!)
        } label: {
            Image(systemName: "ladybug")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
        }
        .menuStyle(.borderlessButton)
        .help(L10n.t("button.debug"))
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
            case .ready:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
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
        case .ready:
            return .secondary
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

    private func updateRecordingHUDWindowVisibility() {
        guard let recordingHUDWindowController else {
            return
        }

        if viewModel.isRecording && viewModel.isRecordingHUDVisible {
            recordingHUDWindowController.show()
        } else {
            recordingHUDWindowController.hide()
        }
    }
}
