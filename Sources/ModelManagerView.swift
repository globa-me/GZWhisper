import SwiftUI

struct ModelManagerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private var customModels: [LocalModelReference] {
        viewModel.installedModels.filter { reference in
            !viewModel.modelCatalog.contains {
                $0.matches(modelID: reference.modelID)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.modelCatalog) { option in
                        modelCard(option)
                    }

                    ForEach(customModels, id: \.modelPath) { reference in
                        customModelCard(reference)
                    }
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(minWidth: 650, idealWidth: 720, minHeight: 560, idealHeight: 680)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("models.title"))
                    .font(.title2.bold())
                Text(L10n.f("models.subtitle", viewModel.macProcessorTitle))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button(L10n.t("button.done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(L10n.t("models.requirementsNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: viewModel.connectExistingLocalModel) {
                Label(L10n.t("button.connectLocal"), systemImage: "externaldrive")
            }
            .disabled(isModelMutationBlocked)
        }
        .padding(14)
    }

    private func modelCard(_ option: WhisperModelOption) -> some View {
        let installed = viewModel.installedReference(for: option)
        let isActive = installed?.modelPath == viewModel.activeModelPath
        let installedRAMGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let meetsMinimumMemory = installedRAMGB >= option.minimumRAMGB
        let meetsRecommendedMemory = installedRAMGB >= option.recommendedRAMGB

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(option.displayName).font(.headline)
                        recommendationBadge(option.currentRecommendation)
                        if isActive {
                            Text(L10n.t("models.active"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.green.opacity(0.16), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    Text(modelDescription(option))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                actionButtons(option: option, installed: installed, isActive: isActive)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 7) {
                metric(L10n.t("models.accuracy"), value: option.qualityRank)
                metric(L10n.t("models.speed"), value: option.speedRank)
                Label(L10n.f("models.downloadSize", option.approximateDownloadGB), systemImage: "internaldrive")
                Label(L10n.f("models.minimumRAM", option.minimumRAMGB), systemImage: "memorychip")
                    .foregroundStyle(meetsMinimumMemory ? Color.secondary : Color.orange)
                Label(L10n.f("models.recommendedRAM", option.recommendedRAMGB), systemImage: "checkmark.circle")
                    .foregroundStyle(meetsRecommendedMemory ? Color.secondary : Color.orange)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !meetsMinimumMemory {
                Label(L10n.t("models.belowMinimumRAM"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if !meetsRecommendedMemory {
                Label(L10n.t("models.belowRecommendedRAM"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private func customModelCard(_ reference: LocalModelReference) -> some View {
        let isActive = reference.modelPath == viewModel.activeModelPath
        return HStack(spacing: 12) {
            Image(systemName: "externaldrive")
            VStack(alignment: .leading, spacing: 3) {
                Text(reference.modelID).font(.headline)
                Text(L10n.t("models.customModel")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button(L10n.t("button.select")) { viewModel.selectModel(reference) }
                    .disabled(isModelMutationBlocked)
            }
            Button { viewModel.revealModelInFinder(reference) } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel("\(L10n.t("help.openModelFolder")): \(reference.modelID)")
            Button(role: .destructive) { viewModel.deleteModel(reference) } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("\(L10n.t("help.deleteModel")): \(reference.modelID)")
            .disabled(isModelMutationBlocked)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func actionButtons(option: WhisperModelOption, installed: LocalModelReference?, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            if let installed {
                Button { viewModel.revealModelInFinder(installed) } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel("\(L10n.t("help.openModelFolder")): \(option.displayName)")
                if !isActive {
                    Button(L10n.t("button.select")) { viewModel.selectModel(installed) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isModelMutationBlocked)
                }
                Button(role: .destructive) { viewModel.deleteModel(installed) } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("\(L10n.t("help.deleteModel")): \(option.displayName)")
                .disabled(isModelMutationBlocked)
            } else {
                Button {
                    viewModel.downloadModelWithFolderPrompt(option)
                } label: {
                    Label(
                        viewModel.downloadingModelID == option.repositoryID ? L10n.t("button.downloading") : L10n.t("button.downloadModel"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isModelMutationBlocked || viewModel.runtimeIssueMessage != nil)
            }
            Link(destination: URL(string: "https://huggingface.co/\(option.repositoryID)")!) {
                Image(systemName: "safari")
            }
            .accessibilityLabel("Hugging Face: \(option.displayName)")
        }
    }

    private var isModelMutationBlocked: Bool {
        viewModel.isModelManagementBusy || viewModel.isTranscribing || viewModel.isRecording || viewModel.isStoppingRecording
    }

    private func recommendationBadge(_ value: WhisperModelOption.Recommendation) -> some View {
        let title: String
        let color: Color
        switch value {
        case .best: title = L10n.t("models.badgeBest"); color = .green
        case .recommended: title = L10n.t("models.badgeRecommended"); color = .blue
        case .supported: title = L10n.t("models.badgeSupported"); color = .secondary
        case .demanding: title = L10n.t("models.badgeDemanding"); color = .orange
        }
        return Text(title)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func metric(_ title: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Text(String(repeating: "●", count: value) + String(repeating: "○", count: 5 - value))
                .font(.system(size: 9, design: .monospaced))
        }
    }

    private func modelDescription(_ option: WhisperModelOption) -> String {
        switch option.displayName {
        case "Whisper Tiny": return L10n.t("models.descTiny")
        case "Whisper Base": return L10n.t("models.descBase")
        case "Whisper Small": return L10n.t("models.descSmall")
        case "Whisper Large v3 Turbo": return L10n.t("models.descTurbo")
        default: return L10n.t("models.descLarge")
        }
    }
}
