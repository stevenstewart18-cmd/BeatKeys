import CoreAudio
import Accelerate
import Foundation

// MARK: - FrequencyBand

enum FrequencyBand: Int, CaseIterable {
    case fullSpectrum = 0
    case bass         = 1   // 60–250 Hz  (kick drum, bass guitar)
    case rhythm       = 2   // 250–800 Hz (snare, mid percussion)
    case highs        = 3   // 2 kHz–8 kHz (hi-hat, cymbals)
    case multiBand    = 4   // weighted fusion of bass + rhythm + highs

    var label: String {
        switch self {
        case .fullSpectrum: return "All"
        case .bass:         return "Bass"
        case .rhythm:       return "Rhythm"
        case .highs:        return "Highs"
        case .multiBand:    return "Multi"
        }
    }

    /// Frequency range (Hz) used to select FFT bins.
    /// For .multiBand the range is unused; sub-band ranges are used directly.
    var range: (lo: Float, hi: Float) {
        switch self {
        case .fullSpectrum: return (20, 20_000)
        case .bass:         return (60, 250)
        case .rhythm:       return (250, 800)
        case .highs:        return (2_000, 8_000)
        case .multiBand:    return (60, 8_000)
        }
    }
}

// MARK: - BeatAudioEngine

class BeatAudioEngine {

    var onBeat: ((Float) -> Void)?   // intensity: 0–1 (how far above threshold the beat was)

    // ── Tunable parameters (safe to set from any thread before beat fires) ──
    var sensitivity: Float = 0.5

    // Multi-band fusion weights (bass + rhythm + highs); sum need not equal 1.
    private let bandWeights = (bass: Float(0.5), rhythm: Float(0.3), highs: Float(0.2))

    var frequencyBand: FrequencyBand = .fullSpectrum {
        didSet {
            // Reset FFT accumulator and prev-magnitude so the new band takes
            // effect immediately without comparing stale cross-band magnitudes.
            fftAccumCount = 0
            lastFlux      = 0
            let halfN     = fftSize / 2
            prevMagnitude = [Float](repeating: 0, count: halfN)
        }
    }

    /// Minimum time between beats in milliseconds (controls max BPM).
    /// Default 140 ms ≈ 428 BPM ceiling — well above any real music tempo.
    var minBeatIntervalMs: Double = 140 {
        didSet { minBeatInterval = minBeatIntervalMs / 1000.0 }
    }

    // ── CoreAudio state ──────────────────────────────────────────────────
    private var tapID:       AudioObjectID        = kAudioObjectUnknown
    private var aggregateID: AudioObjectID        = kAudioObjectUnknown
    private var ioProcID:    AudioDeviceIOProcID? = nil
    private var isRunning    = false
    private var currentOutputUID: String?
    private var deviceListenerInstalled = false

    private var callbackCount = 0
    private var nonZeroCount  = 0

    // ── Beat detection: ring buffer + adaptive threshold ─────────────────
    private let  bufSize = 200
    private var  ringBuf: [Float] = []
    private var  ringIdx = 0
    private var  lastBeatTime    = Date.distantPast
    private var  minBeatInterval: TimeInterval = 0.14
    private var  beatCount = 0

    // ── BPM estimation ───────────────────────────────────────────────────
    private var  beatIntervals:   [Double] = []  // last 16 inter-beat intervals (s)
    private(set) var estimatedBPM: Float   = 0
    private(set) var lastBeatStrength: Float = 0 // intensity of most recent beat (0–1)

    // ── FFT + spectral flux ──────────────────────────────────────────────
    private let  fftLog2n: vDSP_Length = 11   // 2048-point FFT
    private let  fftSize  = 2048
    private var  fftSetup: FFTSetup?
    private var  hannWindow:   [Float] = []
    private var  fftRealp:     [Float] = []
    private var  fftImagp:     [Float] = []
    private var  fftAccum:     [Float] = []   // mono-sample accumulator
    private var  fftAccumCount = 0
    private var  lastFlux:     Float   = 0    // cached result between FFT frames
    private var  prevMagnitude:[Float] = []   // per-bin magnitudes from previous frame
    private var  sampleRate:   Float   = 44100

    // ── Calibration ─────────────────────────────────────────────────────
    private(set) var isCalibrating = false
    private var calibrationFluxes: [Float] = []

    // ── Auto-recovery ────────────────────────────────────────────────────
    private var healthTimer:      DispatchSourceTimer?
    private var lastNonZeroCount  = 0
    private var staleSilenceRuns  = 0

    private let sysObj      = AudioObjectID(bitPattern: kAudioObjectSystemObject)
    private var isRestarting = false

    // MARK: - Init / Deinit

    init() {
        let halfN   = fftSize / 2
        fftSetup    = vDSP_create_fftsetup(fftLog2n, FFTRadix(FFT_RADIX2))
        hannWindow  = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        fftRealp    = [Float](repeating: 0, count: halfN)
        fftImagp    = [Float](repeating: 0, count: halfN)
        fftAccum    = [Float](repeating: 0, count: fftSize)
        prevMagnitude = [Float](repeating: 0, count: halfN)
    }

    deinit {
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        installDeviceChangeListener()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupTap()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        healthTimer?.cancel(); healthTimer = nil
        removeDeviceChangeListener()
        teardownTap()
        NSLog("BeatKeys: stopped")
    }

    // MARK: - Calibration

    func startCalibration() {
        calibrationFluxes.removeAll()
        isCalibrating = true
    }

    /// Analyzes collected flux samples and returns the auto-tuned sensitivity.
    /// Returns nil if fewer than 50 samples were collected (no audio playing).
    func finishCalibration() -> Float? {
        isCalibrating = false
        guard calibrationFluxes.count >= 50 else { return nil }
        let sorted = calibrationFluxes.sorted()
        let p85idx = Int(Float(sorted.count) * 0.85)
        let medidx = sorted.count / 2
        let p85    = sorted[min(p85idx, sorted.count - 1)]
        let median = sorted[medidx]
        guard median > 1e-9 else { return nil }
        // Invert the beat threshold formula: threshold = mean * (1.15 + (1-s)*0.4)
        // We want the multiplier so that p85 fires as a beat against the median background.
        let ratio = p85 / median
        let s = 1.0 - max(0, (ratio - 1.15) / 0.4)
        return min(1.0, max(0.1, Float(s)))
    }

    // MARK: - Output Device Change Listener

    private func installDeviceChangeListener() {
        guard !deviceListenerInstalled else { return }
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(
            sysObj, &prop, DispatchQueue.global(qos: .userInitiated)
        ) { [weak self] _, _ in self?.handleOutputDeviceChanged() }
        if status == noErr {
            deviceListenerInstalled = true
            NSLog("BeatKeys: 🎧 Output device change listener installed")
        }
    }

    private func removeDeviceChangeListener() {
        guard deviceListenerInstalled else { return }
        deviceListenerInstalled = false
    }

    private func handleOutputDeviceChanged() {
        guard isRunning, !isRestarting else { return }
        let newUID = getDefaultOutputDeviceUID()
        guard newUID != currentOutputUID else { return }
        NSLog("BeatKeys: 🎧 Output device changed: %@ → %@",
              currentOutputUID ?? "nil", newUID ?? "nil")
        isRestarting = true
        teardownTap()
        Thread.sleep(forTimeInterval: 0.5)
        setupTap()
        isRestarting = false
    }

    // MARK: - Tap Lifecycle

    private func teardownTap() {
        if let p = ioProcID {
            AudioDeviceStop(aggregateID, p)
            AudioDeviceDestroyIOProcID(aggregateID, p)
            ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func setupTap() {
        guard let outUID = getDefaultOutputDeviceUID() else {
            NSLog("BeatKeys: ❌ No output device"); return
        }
        currentOutputUID = outUID
        let procs = getAudioProcessObjects()
        guard !procs.isEmpty else {
            NSLog("BeatKeys: ❌ No audio processes"); return
        }

        let desc = CATapDescription(processes: procs, deviceUID: outUID, stream: 0)
        desc.uuid = UUID(); desc.name = "BeatKeys"
        desc.isPrivate = true; desc.isExclusive = false; desc.muteBehavior = .unmuted

        var newTap: AudioObjectID = kAudioObjectUnknown
        guard AudioHardwareCreateProcessTap(desc, &newTap) == noErr else {
            NSLog("BeatKeys: ❌ CreateProcessTap failed"); return
        }
        tapID = newTap
        guard let tapUID = readTapUID(tapID) else {
            NSLog("BeatKeys: ❌ readTapUID failed"); teardownTap(); return
        }

        let aggProps: [String: Any] = [
            kAudioAggregateDeviceNameKey      as String: "BeatKeys",
            kAudioAggregateDeviceUIDKey       as String: "com.beatkeys.agg-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey   as String: [[
                kAudioSubTapUIDKey               as String: tapUID,
                kAudioSubTapDriftCompensationKey as String: true,
            ]],
        ]
        var newAgg: AudioObjectID = kAudioObjectUnknown
        guard AudioHardwareCreateAggregateDevice(aggProps as CFDictionary, &newAgg) == noErr else {
            NSLog("BeatKeys: ❌ CreateAgg failed"); teardownTap(); return
        }
        aggregateID = newAgg

        // Critical: sleep before attaching IOProc or it silently fails.
        Thread.sleep(forTimeInterval: 1.0)

        // Read sample rate now that the aggregate device exists.
        sampleRate = readSampleRate(aggregateID)
        NSLog("BeatKeys: sample rate %.0f Hz", sampleRate)

        var newProc: AudioDeviceIOProcID? = nil
        let ps = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, nil) {
            [weak self] _, input, _, _, _ in
            self?.processBuffer(input.pointee)
        }
        guard ps == noErr, let p = newProc else {
            NSLog("BeatKeys: ❌ IOProc failed: %d", ps); teardownTap(); return
        }
        ioProcID = p

        // Reset all detection state BEFORE starting the IOProc,
        // since the IO callback fires immediately on a different thread.
        callbackCount = 0; nonZeroCount = 0; beatCount = 0
        lastNonZeroCount = 0; staleSilenceRuns = 0
        ringBuf      = [Float](repeating: 0, count: bufSize)
        ringIdx      = 0
        fftAccumCount = 0; lastFlux = 0
        prevMagnitude = [Float](repeating: 0, count: fftSize / 2)
        beatIntervals = []; estimatedBPM = 0; lastBeatStrength = 0

        guard AudioDeviceStart(aggregateID, p) == noErr else {
            NSLog("BeatKeys: ❌ DeviceStart failed"); teardownTap(); return
        }

        isRunning = true
        NSLog("BeatKeys: ✅ Tap running on %@ (%d procs)", outUID, procs.count)
        startHealthMonitor()
    }

    // MARK: - Health Monitor

    private func startHealthMonitor() {
        healthTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in self?.healthCheck() }
        t.resume()
        healthTimer = t
    }

    private func healthCheck() {
        guard isRunning else { return }
        let nz = nonZeroCount; let tot = callbackCount

        let msg = nz > 0
            ? "AUDIO OK: \(nz)/\(tot) non-silent, \(beatCount) beats | band: \(frequencyBand.label) | device: \(currentOutputUID ?? "?")\n"
            : "SILENT: \(tot) callbacks all zero | device: \(currentOutputUID ?? "?")\n"
        try? msg.write(toFile: "/tmp/beatkeys_tap.log", atomically: true, encoding: .utf8)

        if nz > lastNonZeroCount { staleSilenceRuns = 0 }
        else if tot > lastNonZeroCount + 200 { staleSilenceRuns += 1 }
        lastNonZeroCount = nz

        if staleSilenceRuns >= 3 {
            NSLog("BeatKeys: 🔄 Recreating tap (silence)")
            teardownTap(); Thread.sleep(forTimeInterval: 0.5); setupTap()
        }
    }

// MARK: - Beat Detection (IO thread)

    private func processBuffer(_ list: AudioBufferList) {
        let buf = list.mBuffers
        guard let data = buf.mData, buf.mDataByteSize > 0 else { return }

        let ch     = max(1, Int(buf.mNumberChannels))
        let floats = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let frames = floats / ch
        guard frames > 0 else { return }

        let samples = data.bindMemory(to: Float.self, capacity: floats)

        // Full-spectrum RMS — always computed for activity detection.
        var fullRMS: Float = 0
        vDSP_rmsqv(samples, vDSP_Stride(ch), &fullRMS, vDSP_Length(frames))
        callbackCount += 1
        if fullRMS > 0.0001 { nonZeroCount += 1 }

        // Gate: don't run beat detection on inaudible audio.
        guard fullRMS > 0.0001 else { return }

        // Spectral flux accumulates samples into a 2048-point FFT window.
        // Returns the half-wave-rectified flux for the selected band.
        // Fires on transients (note onsets, drum hits) rather than sustained energy.
        let flux = accumAndComputeFlux(samples: samples, stride: ch, frames: frames)

        if isCalibrating, calibrationFluxes.count < 500 {
            calibrationFluxes.append(flux)
        }

        ringBuf[ringIdx % bufSize] = flux
        ringIdx += 1

        guard ringIdx > 30 else { return }

        var mean: Float = 0
        vDSP_meanv(ringBuf, 1, &mean, vDSP_Length(bufSize))

        let multiplier: Float = 1.15 + (1.0 - sensitivity) * 0.4
        let threshold = mean * multiplier

        let now = Date()
        guard flux > threshold,
              now.timeIntervalSince(lastBeatTime) > minBeatInterval
        else { return }

        // Intensity: how far above the threshold this beat landed, clamped 0–1.
        let intensity = min(1.0, (flux - threshold) / max(threshold, 1e-9))

        let interval = now.timeIntervalSince(lastBeatTime)
        lastBeatTime     = now
        lastBeatStrength = intensity
        beatCount       += 1

        // Update BPM estimate from inter-beat interval (plausible range: 24–300 BPM).
        if interval > 0.2 && interval < 2.5 {
            if beatIntervals.count >= 16 { beatIntervals.removeFirst() }
            beatIntervals.append(interval)
            if beatIntervals.count >= 4 {
                let sorted = beatIntervals.sorted()
                let median = sorted[sorted.count / 2]
                estimatedBPM = Float(60.0 / median)
            }
        }

        let cb = onBeat
        DispatchQueue.main.async { cb?(intensity) }
    }

    // MARK: - Spectral Flux (IO thread)

    /// Accumulates mono samples into a 2048-point window, then computes
    /// spectral flux for the selected band. Returns the cached result while filling.
    private func accumAndComputeFlux(samples: UnsafePointer<Float>,
                                     stride:  Int,
                                     frames:  Int) -> Float {
        let space = fftSize - fftAccumCount
        let copy  = min(frames, space)
        for i in 0..<copy {
            fftAccum[fftAccumCount + i] = samples[i * stride]
        }
        fftAccumCount += copy
        guard fftAccumCount >= fftSize else { return lastFlux }

        lastFlux      = computeFFTFlux()
        fftAccumCount = 0
        return lastFlux
    }

    /// Computes half-wave-rectified spectral flux over the selected frequency band.
    /// Flux = Σ max(0, |X_n[k]| - |X_{n-1}[k]|) for k in band bins.
    /// Spikes on transients (drum hits, note onsets); stays low during sustained sound.
    private func computeFFTFlux() -> Float {
        guard let setup = fftSetup else { return 0 }

        let halfN = fftSize / 2

        // Hann-window the accumulated frame.
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(fftAccum, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // Re-interpret pairs of real floats as complex, pack into split form.
        windowed.withUnsafeBytes { rawPtr in
            let cPtr = rawPtr.bindMemory(to: DSPComplex.self).baseAddress!
            var split = DSPSplitComplex(realp: &fftRealp, imagp: &fftImagp)
            vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(halfN))
        }

        // In-place forward FFT.
        var split = DSPSplitComplex(realp: &fftRealp, imagp: &fftImagp)
        vDSP_fft_zrip(setup, &split, 1, fftLog2n, FFTDirection(FFT_FORWARD))

        // Power spectrum (squared magnitudes).
        var power = [Float](repeating: 0, count: halfN)
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(halfN))

        let binHz = sampleRate / Float(fftSize)

        if frequencyBand == .multiBand {
            // Weighted fusion: run spectral flux on three sub-bands independently.
            let bf = singleBandFlux(power: power, binHz: binHz, halfN: halfN,
                                    range: FrequencyBand.bass.range)
            let rf = singleBandFlux(power: power, binHz: binHz, halfN: halfN,
                                    range: FrequencyBand.rhythm.range)
            let hf = singleBandFlux(power: power, binHz: binHz, halfN: halfN,
                                    range: FrequencyBand.highs.range)
            return bandWeights.bass * bf + bandWeights.rhythm * rf + bandWeights.highs * hf
        }

        // Map the selected band's Hz range to FFT bin indices.
        // fullSpectrum skips DC (bin 0) and uses all remaining bins.
        let range = frequencyBand.range
        return singleBandFlux(power: power, binHz: binHz, halfN: halfN, range: range)
    }

    /// Computes half-wave-rectified flux for a single Hz range and updates prevMagnitude.
    private func singleBandFlux(power: [Float], binHz: Float, halfN: Int,
                                range: (lo: Float, hi: Float)) -> Float {
        let loBin = max(1,       Int((range.lo / binHz).rounded()))
        let hiBin = min(halfN-1, Int((range.hi / binHz).rounded()))
        guard loBin <= hiBin else { return 0 }
        var flux: Float = 0
        for i in loBin...hiBin {
            let mag  = sqrt(power[i])
            let diff = mag - prevMagnitude[i]
            if diff > 0 { flux += diff }
            prevMagnitude[i] = mag
        }
        return flux / Float(hiBin - loBin + 1) / Float(fftSize)
    }

    // MARK: - CoreAudio Helpers

    private func readSampleRate(_ deviceID: AudioObjectID) -> Float {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var rate: Float64 = 44100
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(deviceID, &prop, 0, nil, &size, &rate)
        return Float(rate)
    }

    private func getDefaultOutputDeviceUID() -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var devID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sysObj, &prop, 0, nil, &size, &devID) == noErr else { return nil }
        var uidProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var cfRef: Unmanaged<CFString>? = nil
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let ok = withUnsafeMutablePointer(to: &cfRef) {
            AudioObjectGetPropertyData(devID, &uidProp, 0, nil, &uidSize, UnsafeMutableRawPointer($0))
        }
        guard ok == noErr, let ref = cfRef else { return nil }
        return ref.takeRetainedValue() as String
    }

    private func getAudioProcessObjects() -> [AudioObjectID] {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sysObj, &prop, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sysObj, &prop, 0, nil, &dataSize, &objects) == noErr else { return [] }
        return objects
    }

    private func readTapUID(_ id: AudioObjectID) -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var cfRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let ok = withUnsafeMutablePointer(to: &cfRef) {
            AudioObjectGetPropertyData(id, &prop, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard ok == noErr, let ref = cfRef else { return nil }
        return ref.takeRetainedValue() as String
    }
}
