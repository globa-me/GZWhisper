import AppKit
import SwiftUI

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
                .frame(minWidth: 960, minHeight: 720)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.89, green: 0.92, blue: 0.97),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                headerCard
                controlsCard
                editorCard
                footerBar
            }
            .padding(22)
        }
        .onAppear {
            viewModel.initialize()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GZWhisper")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.32))

            Text(L10n.t("app.subtitle"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if viewModel.hasConnectedModel {
                    Button(action: viewModel.revealModelInFinder) {
                        statusPill(title: L10n.t("label.model"), value: viewModel.modelStatus)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("help.openModelFolder"))

                    Button(action: viewModel.deleteModel) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.canDeleteModel)
                    .help(L10n.t("help.deleteModel"))

                    Spacer(minLength: 10)
                } else {
                    statusPill(title: L10n.t("label.model"), value: viewModel.modelStatus)
                    Spacer(minLength: 10)

                    Button(action: viewModel.downloadModelWithFolderPrompt) {
                        Label(viewModel.isDownloadingModel ? L10n.t("button.downloading") : L10n.t("button.downloadModel"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing)

                    Button(action: viewModel.connectExistingLocalModel) {
                        Label(L10n.t("button.connectLocal"), systemImage: "externaldrive")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing)
                }
            }

            if viewModel.hasConnectedModel {
                if !viewModel.modelSourceText.isEmpty {
                    Text(viewModel.modelSourceText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !viewModel.modelLocationText.isEmpty {
                    Text(viewModel.modelLocationText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(L10n.f("text.downloadSources", viewModel.downloadSourcesHint))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if viewModel.shouldShowDownloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.downloadSourceText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.32))
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
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                Button(action: viewModel.chooseFile) {
                    Label(L10n.t("button.addMedia"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isDownloadingModel || viewModel.isTranscribing)

                Text(viewModel.selectedFileURL?.path ?? L10n.t("text.fileNotSelected"))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Picker(L10n.t("label.language"), selection: $viewModel.selectedLanguage) {
                    ForEach(viewModel.languageOptions, id: \.code) { option in
                        Text(option.title).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                statusPill(title: L10n.t("label.detectedLanguage"), value: viewModel.detectedLanguage)

                Spacer(minLength: 8)

                Button(action: viewModel.transcribeSelectedFile) {
                    Label(viewModel.isTranscribing ? L10n.t("button.transcribing") : L10n.t("button.transcribe"), systemImage: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.05, green: 0.45, blue: 0.35))
                .controlSize(.large)
                .disabled(!viewModel.canTranscribe)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .fill(Color.white.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        } else {
            TextEditor(text: $viewModel.transcriptText)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
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

            Text(L10n.t("footer.author"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.32))
        }
        .padding(.horizontal, 4)
    }

    private func statusPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.32))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.8), in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
}
