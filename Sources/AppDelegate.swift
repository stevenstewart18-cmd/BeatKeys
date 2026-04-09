import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    let audioEngine = BeatAudioEngine()
    var isActive    = false
    var toggleItem: NSMenuItem!

    lazy var settingsController = SettingsWindowController(engine: audioEngine)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeStatusIcon(active: false)
        statusItem.button?.imageScaling = .scaleProportionallyDown
        buildMenu()

        audioEngine.onBeat = { [weak self] intensity in self?.onBeat(intensity) }

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

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit BeatKeys",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func toggleSync() {
        if isActive { stop() } else { start() }
    }

    @objc func openSettings() {
        settingsController.show()
    }

    func start() {
        audioEngine.start()
        isActive = true
        statusItem.button?.image = makeStatusIcon(active: true)
        toggleItem?.title = "⏹  Stop Beat Sync"
    }

    func stop() {
        audioEngine.stop()
        isActive = false
        statusItem.button?.image = makeStatusIcon(active: false)
        toggleItem?.title = "▶  Start Beat Sync"
        KeyboardController.shared.restore()
    }

    func onBeat(_ intensity: Float) {
        KeyboardController.shared.pulse(intensity: intensity)
        guard isActive else { return }
        statusItem.button?.image = makeStatusIcon(active: true, beat: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isActive else { return }
            self.statusItem.button?.image = self.makeStatusIcon(active: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
        KeyboardController.shared.restore()
    }

    // MARK: — Menu bar icon

    private func makeStatusIcon(active: Bool, beat: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 22, height: 22), flipped: true) { _ in
            // flipped: true → y=0 at top, y increases downward (matches design coords)
            let iconColor = NSColor.labelColor.withAlphaComponent(0.85)

            // ── Keycap — filled with accent on beat, stroke-only otherwise ──
            let keycap = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: 18.5, height: 18),
                                      xRadius: 4, yRadius: 4)
            if beat {
                NSColor.systemOrange.withAlphaComponent(0.85).setFill()
                keycap.fill()
            }
            keycap.lineWidth = 1.5
            iconColor.setStroke()
            keycap.stroke()

            // ── Double music note (♫) ──
            iconColor.setFill()

            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 4, width: 8, height: 1.5),
                         xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 6, width: 8, height: 1.5),
                         xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 4, width: 1.5, height: 8.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 13, y: 4, width: 1.5, height: 7.5),
                         xRadius: 0.75, yRadius: 0.75).fill()

            let lHead = NSBezierPath(ovalIn: NSRect(x: -2.7, y: -1.6, width: 5.4, height: 3.2))
            var lt = AffineTransform()
            lt.translate(x: 5.8, y: 14)
            lt.rotate(byDegrees: -15)
            lHead.transform(using: lt)
            lHead.fill()

            let rHead = NSBezierPath(ovalIn: NSRect(x: -2.7, y: -1.6, width: 5.4, height: 3.2))
            var rt = AffineTransform()
            rt.translate(x: 12.3, y: 12.5)
            rt.rotate(byDegrees: -15)
            rHead.transform(using: rt)
            rHead.fill()

            // ── Green dot — active state only ──
            if active {
                NSColor.systemGreen.setFill()
                NSBezierPath(ovalIn: NSRect(x: 16.8, y: 16.8, width: 5.2, height: 5.2)).fill()
            }

            return true
        }
        img.isTemplate = false
        return img
    }
}
