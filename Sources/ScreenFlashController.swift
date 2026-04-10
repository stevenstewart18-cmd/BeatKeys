import AppKit

private class FlashView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let edgeW: CGFloat = 60   // gradient fade width

        let white    = NSColor.white.cgColor
        let clear    = NSColor.clear.cgColor
        let colors   = [white, clear] as CFArray
        let locs: [CGFloat] = [0, 1]
        let space = CGColorSpaceCreateDeviceRGB()
        guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: locs) else { return }

        // Top edge: fade downward
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: h),
            end:   CGPoint(x: 0, y: h - edgeW),
            options: [])
        // Bottom edge: fade upward
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: 0),
            end:   CGPoint(x: 0, y: edgeW),
            options: [])
        // Left edge: fade rightward
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: 0),
            end:   CGPoint(x: edgeW, y: 0),
            options: [])
        // Right edge: fade leftward
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: w, y: 0),
            end:   CGPoint(x: w - edgeW, y: 0),
            options: [])
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
