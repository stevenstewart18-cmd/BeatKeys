import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    let audioEngine = BeatAudioEngine()
    var isActive    = false
    var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎵"
        buildMenu()

        audioEngine.onBeat = { [weak self] in self?.onBeat() }

        // Set keyboard to max brightness and use that as home level
        KeyboardController.shared.setMaxAndSnapshot()
        start()
    }

    func buildMenu() {
        let menu = NSMenu()

        toggleItem = NSMenuItem(title: "⏹  Stop Beat Sync",
                                action: #selector(toggleSync), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let sensLabel = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        sensLabel.isEnabled = false
        menu.addItem(sensLabel)

        for (label, value): (String, Float) in [("  Low", 0.2), ("  Medium", 0.5), ("  High", 0.8)] {
            let item = NSMenuItem(title: label,
                                  action: #selector(setSensitivity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: value)
            item.state = label.contains("Medium") ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit BeatKeys",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleSync() {
        if isActive { stop() } else { start() }
    }

    func start() {
        audioEngine.start()
        isActive = true
        statusItem.button?.title = "🔊"
        toggleItem?.title = "⏹  Stop Beat Sync"
    }

    func stop() {
        audioEngine.stop()
        isActive = false
        statusItem.button?.title = "🎵"
        toggleItem?.title = "▶  Start Beat Sync"
        KeyboardController.shared.restore()
    }

    func onBeat() { KeyboardController.shared.pulse() }

    @objc func setSensitivity(_ sender: NSMenuItem) {
        for item in statusItem.menu?.items ?? [] where item.action == #selector(setSensitivity(_:)) {
            item.state = .off
        }
        sender.state = .on
        if let val = (sender.representedObject as? NSNumber)?.floatValue {
            audioEngine.sensitivity = val
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
        KeyboardController.shared.restore()
    }
}
