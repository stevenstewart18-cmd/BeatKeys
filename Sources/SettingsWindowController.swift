import AppKit

class SettingsWindowController: NSWindowController {

    private let engine: BeatAudioEngine

    private var bandControl:       NSSegmentedControl!
    private var sensitivitySlider: NSSlider!
    private var sensitivityLabel:  NSTextField!
    private var intervalSlider:    NSSlider!
    private var intervalLabel:     NSTextField!
    private var bpmLabel:          NSTextField!
    private var pollTimer:         Timer?

    // UserDefaults keys
    private enum Key {
        static let sensitivity   = "sensitivity"
        static let minBeatGapMs  = "minBeatGapMs"
        static let frequencyBand = "frequencyBand"
    }

    init(engine: BeatAudioEngine) {
        self.engine = engine

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 250),
            styleMask:   [.titled, .closable, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false)
        panel.title = "BeatKeys Settings"
        panel.isFloatingPanel          = true
        panel.becomesKeyOnlyIfNeeded   = true
        panel.center()

        super.init(window: panel)
        panel.delegate = self
        buildUI()
        loadAndApply()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let bpm = self.engine.estimatedBPM
            self.bpmLabel.stringValue = bpm > 0 ? "\(Int(bpm.rounded())) BPM" : "—"
        }
    }

    // MARK: - UI Construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // Column geometry
        let lx: CGFloat = 16    // label x
        let lw: CGFloat = 96    // label width (right-aligned)
        let cx: CGFloat = 118   // control x
        let cw: CGFloat = 174   // slider width
        let vx: CGFloat = 296   // value-label x
        let vw: CGFloat = 44    // value-label width

        // ── Row 1: Frequency Band ─────────────────────────────────────────
        addLabel("Beat Source:", x: lx, y: 203, w: lw, in: cv)
        bandControl = NSSegmentedControl(
            labels:       FrequencyBand.allCases.map(\.label),
            trackingMode: .selectOne,
            target:       self,
            action:       #selector(bandChanged))
        bandControl.frame = NSRect(x: cx, y: 200, width: cw + vw + 4, height: 26)
        cv.addSubview(bandControl)

        // ── Row 2: Sensitivity ────────────────────────────────────────────
        addLabel("Sensitivity:", x: lx, y: 157, w: lw, in: cv)
        sensitivitySlider = addSlider(min: 0.1, max: 1.0, val: 0.5,
                                      x: cx, y: 155, w: cw, in: cv,
                                      action: #selector(sensitivityChanged))
        sensitivityLabel = addValueLabel(x: vx, y: 155, w: vw, in: cv)

        // ── Row 3: Min Beat Gap ───────────────────────────────────────────
        addLabel("Min Beat Gap:", x: lx, y: 107, w: lw, in: cv)
        intervalSlider = addSlider(min: 50, max: 500, val: 140,
                                   x: cx, y: 105, w: cw, in: cv,
                                   action: #selector(intervalChanged))
        intervalLabel = addValueLabel(x: vx, y: 105, w: vw, in: cv)

        // ── Row 4: BPM readout (read-only) ────────────────────────────────
        addLabel("Estimated BPM:", x: lx, y: 57, w: lw, in: cv)
        bpmLabel = addValueLabel(x: cx, y: 57, w: 100, in: cv)
        bpmLabel.stringValue = "—"

        // ── Reset button ──────────────────────────────────────────────────
        let reset = NSButton(title: "Reset Defaults",
                             target: self, action: #selector(resetDefaults))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: cx, y: 16, width: 130, height: 28)
        cv.addSubview(reset)

        updateValueLabels()
    }

    // MARK: - Layout Helpers

    @discardableResult
    private func addLabel(_ text: String, x: CGFloat, y: CGFloat,
                          w: CGFloat, in view: NSView) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame     = NSRect(x: x, y: y, width: w, height: 20)
        lbl.alignment = .right
        lbl.font      = .systemFont(ofSize: 13)
        view.addSubview(lbl)
        return lbl
    }

    @discardableResult
    private func addSlider(min: Double, max: Double, val: Double,
                           x: CGFloat, y: CGFloat, w: CGFloat,
                           in view: NSView, action: Selector) -> NSSlider {
        let s = NSSlider(value: val, minValue: min, maxValue: max,
                         target: self, action: action)
        s.frame       = NSRect(x: x, y: y, width: w, height: 20)
        s.isContinuous = true
        view.addSubview(s)
        return s
    }

    @discardableResult
    private func addValueLabel(x: CGFloat, y: CGFloat,
                               w: CGFloat, in view: NSView) -> NSTextField {
        let lbl = NSTextField(labelWithString: "")
        lbl.frame     = NSRect(x: x, y: y, width: w, height: 20)
        lbl.alignment = .left
        lbl.font      = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        view.addSubview(lbl)
        return lbl
    }

    // MARK: - Actions

    @objc private func bandChanged() {
        let band = FrequencyBand(rawValue: bandControl.selectedSegment) ?? .fullSpectrum
        engine.frequencyBand = band
        UserDefaults.standard.set(band.rawValue, forKey: Key.frequencyBand)
    }

    @objc private func sensitivityChanged() {
        let val = Float(sensitivitySlider.doubleValue)
        engine.sensitivity = val
        UserDefaults.standard.set(val, forKey: Key.sensitivity)
        updateValueLabels()
    }

    @objc private func intervalChanged() {
        let ms = intervalSlider.doubleValue
        engine.minBeatIntervalMs = ms
        UserDefaults.standard.set(ms, forKey: Key.minBeatGapMs)
        updateValueLabels()
    }

    @objc private func resetDefaults() {
        sensitivitySlider.doubleValue  = 0.5
        intervalSlider.doubleValue     = 140
        bandControl.selectedSegment    = FrequencyBand.fullSpectrum.rawValue
        sensitivityChanged()
        intervalChanged()
        bandChanged()
    }

    // MARK: - State

    private func updateValueLabels() {
        sensitivityLabel.stringValue = String(format: "%.2f", sensitivitySlider.doubleValue)
        intervalLabel.stringValue    = "\(Int(intervalSlider.doubleValue)) ms"
    }

    /// Reads persisted settings, applies them to the engine, and syncs the UI.
    private func loadAndApply() {
        let ud = UserDefaults.standard

        let sens: Float = ud.object(forKey: Key.sensitivity) != nil
            ? Float(ud.double(forKey: Key.sensitivity)) : 0.5
        sensitivitySlider.doubleValue = Double(sens)
        engine.sensitivity            = sens

        let ms: Double = ud.object(forKey: Key.minBeatGapMs) != nil
            ? ud.double(forKey: Key.minBeatGapMs) : 140.0
        intervalSlider.doubleValue = ms
        engine.minBeatIntervalMs   = ms

        let bandRaw: Int = ud.object(forKey: Key.frequencyBand) != nil
            ? ud.integer(forKey: Key.frequencyBand) : FrequencyBand.fullSpectrum.rawValue
        let band = FrequencyBand(rawValue: bandRaw) ?? .fullSpectrum
        bandControl.selectedSegment = band.rawValue
        engine.frequencyBand        = band

        updateValueLabels()
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
