import AppKit
import SwiftUI

@main
struct DictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var overlay: OverlayController?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Launch Services normally coalesces launches; also protect direct binary launches.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        overlay = OverlayController(model: model)
        model.showOverlay = { [weak self] in self?.overlay?.show() }
        model.hideOverlay = { [weak self] in self?.overlay?.hide() }
        model.overlayPositionChanged = { [weak self] in self?.overlay?.repositionIfVisible() }
        model.showSettings = { [weak self] in self?.openSettings() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Dictation — Control + Globe")
        item.button?.toolTip = model.text("menu.tooltip")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        model.interfaceLanguageChanged = { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.toolTip = self.model.text("menu.tooltip")
        }
        model.start()
        if !model.microphoneAllowed || !model.accessibilityAllowed || CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: model.busy ? model.headline : "Dictation · Control + 🌐", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        add(model.text("menu.settings"), action: #selector(openSettings), key: ",", to: menu)
        if model.busy { add(model.text("menu.cancel"), action: #selector(cancel), to: menu) }
        if !model.lastTranscript.isEmpty { add(model.text("menu.copyLast"), action: #selector(copyLast), to: menu) }
        menu.addItem(.separator())
        add(model.text("menu.quit"), action: #selector(quit), key: "q", to: menu)
    }

    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc func openSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 760), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Dictation"
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.045, green: 0.065, blue: 0.075, alpha: 1)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func cancel() { model.cancel() }
    @objc private func copyLast() { TextInsertion.copy(model.lastTranscript) }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}
