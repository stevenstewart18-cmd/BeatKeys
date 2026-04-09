import Foundation
import ObjectiveC.runtime

class KeyboardController {

    static let shared = KeyboardController()

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private(set) var homeBrightness: Float = 1.0
    private var isLoaded = false
    private var pulseInFlight = false

    private var breathTimer:       DispatchSourceTimer?
    private var breathPhase:       Float = 0
    private var breathRestartItem: DispatchWorkItem?

    private typealias GetBrightnessFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias SetFadeFn       = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    private init() { setup() }

    private func setup() {
        let fwPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework"
        guard let bundle = Bundle(path: fwPath), bundle.load() else { return }
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }

        let c = cls.init()
        client = c

        let copyIDsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if let unmanaged = c.perform(copyIDsSel),
           let ids = unmanaged.takeRetainedValue() as? [NSNumber],
           let first = ids.first {
            keyboardID = first.uint64Value
        }
        isLoaded = true
    }

    private func imp<T>(of sel: Selector) -> T? {
        guard let c = client,
              let cls = object_getClass(c),
              let method = class_getInstanceMethod(cls, sel) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }

    func getRawBrightness() -> Float {
        guard let c = client else { return 1.0 }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let fn: GetBrightnessFn = imp(of: sel) else { return 1.0 }
        return fn(c, sel, keyboardID)
    }

    func setBrightness(_ value: Float, fadeSpeed: Int32 = 0) {
        guard let c = client, isLoaded else { return }
        if fadeSpeed > 0 {
            let sel = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
            if let fn: SetFadeFn = imp(of: sel) {
                _ = fn(c, sel, value, fadeSpeed, true, keyboardID)
                return
            }
        }
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        if let fn: SetBrightnessFn = imp(of: sel) {
            _ = fn(c, sel, value, keyboardID)
        }
    }

    /// Set keyboard to max and use that as the home level for pulses.
    func setMaxAndSnapshot() {
        setBrightness(1.0)
        homeBrightness = 1.0
    }

    func pulse(intensity: Float = 1.0) {
        // Every beat: cancel pending breath restart and stop active breathing.
        breathRestartItem?.cancel()
        breathRestartItem = nil
        breathTimer?.cancel()
        breathTimer = nil

        guard !pulseInFlight else { return }
        pulseInFlight = true

        let home  = homeBrightness
        // Scale dip depth by intensity: floor at 0.3 so weak beats are still visible.
        let depth = 0.75 * max(0.3, min(1.0, intensity))
        let dip   = max(0.0, home - depth)

        setBrightness(dip, fadeSpeed: 5)    // near-instant snap (0 uses a broken selector path)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            self?.setBrightness(home, fadeSpeed: 80)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.pulseInFlight = false
            // Schedule breathing to start after 2s of silence.
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.breathPhase = Float.pi   // start from home brightness, breathe down
                self.startBreathing()
            }
            self.breathRestartItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
        }
    }

    func restore() {
        breathRestartItem?.cancel()
        breathRestartItem = nil
        breathTimer?.cancel()
        breathTimer = nil
        pulseInFlight = false
        setBrightness(homeBrightness, fadeSpeed: 150)
    }

    // MARK: - Breathing

    private func startBreathing() {
        guard breathTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        t.setEventHandler { [weak self] in self?.breathTick() }
        t.resume()
        breathTimer = t
    }

    private func breathTick() {
        // ~0.35 Hz → ~2.9s per full cycle
        breathPhase += Float.pi * 2.0 * 0.35 / 30.0
        if breathPhase > Float.pi * 2.0 { breathPhase -= Float.pi * 2.0 }
        // Oscillates between 0.25 (dim) and 1.0 (bright)
        let brightness = 0.625 + 0.375 * sin(breathPhase - Float.pi / 2.0)
        setBrightness(brightness, fadeSpeed: 20)
    }
}
