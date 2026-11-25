import AppKit
import SwiftUI

private let aqua = Color(red: 0.40, green: 0.94, blue: 0.78)

enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottom, center, top
    var id: String { rawValue }

}

struct OverlayView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(aqua.opacity(0.12)).frame(width: 40, height: 40)
                if model.phase == .transcribing {
                    ProgressView().controlSize(.small).tint(aqua)
                } else {
                    Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(model.phase == .error ? .orange : aqua)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.headline).font(.system(size: 13, weight: .semibold))
                    if model.phase == .recording {
                        Circle().fill(aqua).frame(width: 5, height: 5)
                        Text(String(format: "%02d:%02d", Int(model.duration) / 60, Int(model.duration) % 60))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                Text(model.phase == .recording ? model.text("status.release") : model.detail)
                    .font(.system(size: 9, weight: .medium)).tracking(model.phase == .recording ? 1.1 : 0)
                    .foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.phase == .recording || model.phase == .transcribing {
                Waveform(samples: model.waveformLevels, processing: model.phase == .transcribing, accessibilityDescription: model.text(model.phase == .transcribing ? "spectrum.processing" : "spectrum.recording")).frame(width: 171)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 17)
        .frame(width: 490, height: 88)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28).fill(Color(red: 0.025, green: 0.045, blue: 0.055).opacity(0.86))
                RoundedRectangle(cornerRadius: 28).strokeBorder(LinearGradient(colors: [.white.opacity(0.21), aqua.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .padding(28)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var icon: String {
        switch model.phase {
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .success: return "checkmark"
        case .copied: return "doc.on.clipboard"
        case .error: return "exclamationmark"
        case .idle: return "waveform"
        }
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let panel: OverlayPanel
    private let model: AppModel
    init(model: AppModel) {
        self.model = model
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 546, height: 144), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        // Build SwiftUI's initial layout at launch, not on the first hotkey.
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func show() {
        // Choose the pointer's screen at the start, then keep the same screen
        // through recording, recognition and the completion message.
        let point = NSEvent.mouseLocation
        let screen = (panel.isVisible ? panel.screen : nil)
            ?? NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        position(on: screen)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func repositionIfVisible() {
        guard panel.isVisible else { return }
        position(on: panel.screen ?? NSScreen.main)
    }

    private func position(on screen: NSScreen?) {
        if let frame = screen?.visibleFrame {
            let y: CGFloat
            switch model.overlayPosition {
            case .bottom: y = frame.minY + 20
            case .center: y = frame.midY - panel.frame.height / 2
            case .top: y = frame.maxY - panel.frame.height - 20
            }
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: y))
        }
    }

    func hide() { panel.orderOut(nil) }
}
