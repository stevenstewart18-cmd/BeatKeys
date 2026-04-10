import AppKit

class SettingsWindowController: NSWindowController {

    private let engine: BeatAudioEngine

    private var iconControl:        NSSegmentedControl!
    private var patternControl:     NSSegmentedControl!
    private var bandControl:        NSSegmentedControl!
    private var sensitivitySlider:  NSSlider!
    private var sensitivityLabel:   NSTextField!
    private var calibrateButton:    NSButton!
    private var intervalSlider:     NSSlider!
    private var intervalLabel:      NSTextField!
    private var screenFlashCheck:   NSButton!
    private var bpmLabel:           NSTextField!
    private var beatMeter:          NSProgressIndicator!
    private var meterLevel:         Double = 0
    private var pollTick:           Int    = 0
    private var pollTimer:          Timer?

    // UserDefaults keys
    private enum Key {
        static let sensitivity   = "sensitivity"
        static let minBeatGapMs  = "minBeatGapMs"
        static let frequencyBand = "frequencyBand"
        static let iconMode      = "iconMode"
        static let pulsePattern  = "pulsePattern"
        static let screenFlash   = "screenFlash"
    }

    init(engine: BeatAudioEngine) {
        self.engine = engine

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 372),
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
        pollTick = 0
        pollTimer?.invalidate()
        // 50 ms tick: meter decays every tick, BPM label updates every 10th tick (500 ms).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }

            // Meter: peak on new beat, decay otherwise.
            let strength = Double(self.engine.lastBeatStrength)
            if strength > self.meterLevel {
                self.meterLevel = strength
            } else {
                self.meterLevel = max(0, self.meterLevel - 0.08)
            }
            self.beatMeter.doubleValue = self.meterLevel

            // BPM label: update every 500 ms.
            self.pollTick += 1
            if self.pollTick % 10 == 0 {
                let bpm = self.engine.estimatedBPM
                self.bpmLabel.stringValue = bpm > 0 ? "\(Int(bpm.rounded())) BPM" : "—"
            }
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

        // ── Row 0: Icon Style ─────────────────────────────────────────────
        addLabel("Icon Style:", x: lx, y: 325, w: lw, in: cv)
        iconControl = NSSegmentedControl(
            labels:       ["Full", "Minimal"],
            trackingMode: .selectOne,
            target:       self,
            action:       #selector(iconChanged))
        iconControl.frame = NSRect(x: cx, y: 322, width: 120, height: 26)
        cv.addSubview(iconControl)

        // ── Row 1: Pulse Pattern ──────────────────────────────────────────
        addLabel("Pulse Pattern:", x: lx, y: 279, w: lw, in: cv)
        patternControl = NSSegmentedControl(
            labels:       PulsePattern.allCases.map(\.label),
            trackingMode: .selectOne,
            target:       self,
            action:       #selector(patternChanged))
        patternControl.frame = NSRect(x: cx, y: 276, width: cw + vw + 4, height: 26)
        cv.addSubview(patternControl)

        // ── Row 2: Frequency Band ─────────────────────────────────────────
        addLabel("Beat Source:", x: lx, y: 233, w: lw, in: cv)
        bandControl = NSSegmentedControl(
            labels:       FrequencyBand.allCases.map(\.label),
            trackingMode: .selectOne,
            target:       self,
            action:       #selector(bandChanged))
        bandControl.frame = NSRect(x: cx, y: 230, width: cw + vw + 4, height: 26)
        cv.addSubview(bandControl)

        // ── Row 3: Sensitivity ────────────────────────────────────────────
        addLabel("Sensitivity:", x: lx, y: 187, w: lw, in: cv)
        sensitivitySlider = addSlider(min: 0.1, max: 1.0, val: 0.5,
                                      x: cx, y: 185, w: cw - 90, in: cv,
                                      action: #selector(sensitivityChanged))
        sensitivityLabel = addValueLabel(x: vx - 86, y: 185, w: vw, in: cv)
        calibrateButton = NSButton(title: "Calibrate", target: self,
                                   action: #selector(calibrateTapped))
        calibrateButton.bezelStyle = .rounded
        calibrateButton.controlSize = .small
        calibrateButton.frame = NSRect(x: vx - 86 + vw + 4, y: 183, width: 82, height: 22)
        cv.addSubview(calibrateButton)

        // ── Row 3: Min Beat Gap ───────────────────────────────────────────
        addLabel("Min Beat Gap:", x: lx, y: 137, w: lw, in: cv)
        intervalSlider = addSlider(min: 50, max: 500, val: 140,
                                   x: cx, y: 135, w: cw, in: cv,
                                   action: #selector(intervalChanged))
        intervalLabel = addValueLabel(x: vx, y: 135, w: vw, in: cv)

        // ── Row 4: Screen Flash ───────────────────────────────────────────
        addLabel("Screen Flash:", x: lx, y: 107, w: lw, in: cv)
        screenFlashCheck = NSButton(checkboxWithTitle: "Flash screen edges on beat",
                                    target: self, action: #selector(screenFlashChanged))
        screenFlashCheck.frame = NSRect(x: cx, y: 105, width: cw + vw + 4, height: 20)
        cv.addSubview(screenFlashCheck)

        // ── Row 5: BPM readout ────────────────────────────────────────────
        addLabel("Estimated BPM:", x: lx, y: 87, w: lw, in: cv)
        bpmLabel = addValueLabel(x: cx, y: 87, w: 100, in: cv)
        bpmLabel.stringValue = "—"

        // ── Row 5: Beat meter ─────────────────────────────────────────────
        addLabel("Beat Strength:", x: lx, y: 55, w: lw, in: cv)
        beatMeter = NSProgressIndicator()
        beatMeter.style        = .bar
        beatMeter.isIndeterminate = false
        beatMeter.minValue     = 0
        beatMeter.maxValue     = 1
        beatMeter.doubleValue  = 0
        beatMeter.controlSize  = .small
        beatMeter.frame        = NSRect(x: cx, y: 58, width: cw + vw + 4, height: 12)
        cv.addSubview(beatMeter)

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

    @objc private func iconChanged() {
        let mode = IconMode(rawValue: iconControl.selectedSegment) ?? .full
        UserDefaults.standard.set(mode.rawValue, forKey: Key.iconMode)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.iconMode = mode
            delegate.refreshStatusIcon()
        }
    }

    @objc private func screenFlashChanged() {
        let on = screenFlashCheck.state == .on
        UserDefaults.standard.set(on, forKey: Key.screenFlash)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.screenFlash.isEnabled = on
        }
    }

    @objc private func calibrateTapped() {
        calibrateButton.isEnabled = false
        calibrateButton.title = "Listening…"
        engine.startCalibration()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self else { return }
            if let s = self.engine.finishCalibration() {
                self.engine.sensitivity = s
                self.sensitivitySlider.doubleValue = Double(s)
                UserDefaults.standard.set(s, forKey: Key.sensitivity)
                self.updateValueLabels()
            } else {
                let alert = NSAlert()
                alert.messageText = "No audio detected"
                alert.informativeText = "Play music during calibration and try again."
                alert.alertStyle = .warning
                alert.runModal()
            }
            self.calibrateButton.title = "Calibrate"
            self.calibrateButton.isEnabled = true
        }
    }

    @objc private func patternChanged() {
        let p = PulsePattern(rawValue: patternControl.selectedSegment) ?? .pulse
        KeyboardController.shared.pattern = p
        UserDefaults.standard.set(p.rawValue, forKey: Key.pulsePattern)
    }

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
        iconControl.selectedSegment    = IconMode.full.rawValue
        patternControl.selectedSegment = PulsePattern.pulse.rawValue
        screenFlashCheck.state         = .off
        sensitivityChanged()
        intervalChanged()
        bandChanged()
        iconChanged()
        patternChanged()
        screenFlashChanged()
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

        let iconRaw: Int = ud.object(forKey: Key.iconMode) != nil
            ? ud.integer(forKey: Key.iconMode) : IconMode.full.rawValue
        let mode = IconMode(rawValue: iconRaw) ?? .full
        iconControl.selectedSegment = mode.rawValue
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.iconMode = mode
        }

        let patternRaw: Int = ud.object(forKey: Key.pulsePattern) != nil
            ? ud.integer(forKey: Key.pulsePattern) : PulsePattern.pulse.rawValue
        let p = PulsePattern(rawValue: patternRaw) ?? .pulse
        patternControl.selectedSegment    = p.rawValue
        KeyboardController.shared.pattern = p

        let flashOn = ud.bool(forKey: Key.screenFlash)
        screenFlashCheck.state = flashOn ? .on : .off
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.screenFlash.isEnabled = flashOn
        }

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
