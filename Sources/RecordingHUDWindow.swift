import AppKit
import SwiftUI

final class RecordingHUDWindowController {
    private let panel: NSPanel

    init(viewModel: AppViewModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 134),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hosting = NSHostingView(rootView: RecordingHUDView(viewModel: viewModel))
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 134)
        panel.contentView = hosting

        self.panel = panel
    }

    func show() {
        positionInTopRightCorner()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionInTopRightCorner() {
        guard let screen = targetScreen() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visibleFrame.maxX - panelSize.width - 16
        let y = visibleFrame.maxY - panelSize.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let active = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return active
        }
        if let main = NSScreen.main {
            return main
        }
        return NSScreen.screens.first
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(L10n.t("label.recording"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: viewModel.hideRecordingHUD) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }

            Text(viewModel.recordingElapsedText)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(action: viewModel.toggleRecordingPause) {
                    Label(
                        viewModel.isRecordingPaused ? L10n.t("button.resumeRecording") : L10n.t("button.pauseRecording"),
                        systemImage: viewModel.isRecordingPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isRecordingPaused ? !viewModel.canResumeRecording : !viewModel.canPauseRecording)

                Button(action: viewModel.stopRecording) {
                    Label(L10n.t("button.stopRecording"), systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(!viewModel.canStopRecording)
            }
        }
        .padding(12)
        .frame(width: 280, height: 134, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.20))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
    }
}
