import Foundation
import ObjectiveC.runtime

class KeyboardController {

    static let shared = KeyboardController()

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private(set) var homeBrightness: Float = 1.0
    private var isLoaded = false
    private var pulseInFlight = false

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

    func pulse() {
        guard !pulseInFlight else { return }
        pulseInFlight = true

        let home = homeBrightness
        let dip  = max(0.05, home - 0.5)

        setBrightness(dip, fadeSpeed: 25)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            let mid = dip + (home - dip) * 0.55
            self?.setBrightness(mid, fadeSpeed: 90)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.setBrightness(home, fadeSpeed: 120)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.pulseInFlight = false
        }
    }

    func restore() {
        pulseInFlight = false
        setBrightness(homeBrightness, fadeSpeed: 150)
    }
}
