import AppKit

private class FlashView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let borderW: CGFloat = 20
        NSColor.systemOrange.withAlphaComponent(0.85).setFill()
        // Top
        NSRect(x: 0, y: bounds.height - borderW, width: bounds.width, height: borderW).fill()
        // Bottom
        NSRect(x: 0, y: 0, width: bounds.width, height: borderW).fill()
        // Left
        NSRect(x: 0, y: borderW, width: borderW, height: bounds.height - borderW * 2).fill()
        // Right
        NSRect(x: bounds.width - borderW, y: borderW, width: borderW, height: bounds.height - borderW * 2).fill()
    }
}

class ScreenFlashController {

    private let flashWindow: NSWindow

    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                flashWindow.orderFrontRegardless()
            } else {
                flashWindow.orderOut(nil)
                flashWindow.alphaValue = 0
            }
        }
    }

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        flashWindow = NSWindow(
            contentRect:  screen.frame,
            styleMask:    .borderless,
            backing:      .buffered,
            defer:        false)
        flashWindow.level           = .screenSaver
        flashWindow.backgroundColor = .clear
        flashWindow.isOpaque        = false
        flashWindow.hasShadow       = false
        flashWindow.ignoresMouseEvents = true
        flashWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        flashWindow.alphaValue      = 0
        flashWindow.contentView     = FlashView()
    }

    func flash(intensity: Float) {
        guard isEnabled else { return }
        let alpha = CGFloat(min(1.0, intensity) * 0.8)
        flashWindow.alphaValue = alpha
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            flashWindow.animator().alphaValue = 0
        }
    }
}
