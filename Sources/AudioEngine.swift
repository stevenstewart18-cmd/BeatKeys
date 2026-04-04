import CoreAudio
import Accelerate
import Foundation

class BeatAudioEngine {

    var onBeat: (() -> Void)?
    var sensitivity: Float = 0.5

    private var tapID:       AudioObjectID        = kAudioObjectUnknown
    private var aggregateID: AudioObjectID        = kAudioObjectUnknown
    private var ioProcID:    AudioDeviceIOProcID? = nil
    private var isRunning    = false
    private var currentOutputUID: String?
    private var deviceListenerInstalled = false

    private var callbackCount = 0
    private var nonZeroCount  = 0

    // ── Beat detection: large ring buffer + simple threshold ─────────────
    private let bufSize = 500
    private var ringBuf: [Float] = []
    private var ringIdx = 0
    private var lastBeatTime = Date.distantPast
    private let minBeatInterval: TimeInterval = 0.14

    private var beatCount = 0

    // Auto-recovery
    private var healthTimer: DispatchSourceTimer?
    private var lastNonZeroCount = 0
    private var staleSilenceRuns = 0

    private let sysObj = AudioObjectID(bitPattern: kAudioObjectSystemObject)

    // Prevent overlapping restarts
    private var isRestarting = false

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
        NSLog("BeatLight: stopped")
    }

    // MARK: - Output Device Change Listener

    private func installDeviceChangeListener() {
        guard !deviceListenerInstalled else { return }
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(
            sysObj, &prop, DispatchQueue.global(qos: .userInitiated)
        ) { [weak self] _, _ in
            self?.handleOutputDeviceChanged()
        }
        if status == noErr {
            deviceListenerInstalled = true
            NSLog("BeatLight: 🎧 Output device change listener installed")
        }
    }

    private func removeDeviceChangeListener() {
        guard deviceListenerInstalled else { return }
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // We can't easily remove block-based listeners without storing the block,
        // but setting the flag prevents the handler from acting after stop()
        deviceListenerInstalled = false
    }

    private func handleOutputDeviceChanged() {
        guard isRunning, !isRestarting else { return }
        let newUID = getDefaultOutputDeviceUID()
        guard newUID != currentOutputUID else { return }
        NSLog("BeatLight: 🎧 Output device changed: %@ → %@",
              currentOutputUID ?? "nil", newUID ?? "nil")
        isRestarting = true
        teardownTap()
        // Brief delay to let the system settle after device switch
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
            NSLog("BeatLight: ❌ No output device"); return
        }
        currentOutputUID = outUID
        let procs = getAudioProcessObjects()
        guard !procs.isEmpty else {
            NSLog("BeatLight: ❌ No audio processes"); return
        }

        let desc = CATapDescription(processes: procs, deviceUID: outUID, stream: 0)
        desc.uuid = UUID(); desc.name = "BeatLight"
        desc.isPrivate = true; desc.isExclusive = false; desc.muteBehavior = .unmuted

        var newTap: AudioObjectID = kAudioObjectUnknown
        guard AudioHardwareCreateProcessTap(desc, &newTap) == noErr else {
            NSLog("BeatLight: ❌ CreateProcessTap failed"); return
        }
        tapID = newTap
        guard let tapUID = readTapUID(tapID) else {
            NSLog("BeatLight: ❌ readTapUID failed"); teardownTap(); return
        }

        let aggProps: [String: Any] = [
            kAudioAggregateDeviceNameKey      as String: "BeatLight",
            kAudioAggregateDeviceUIDKey       as String: "com.beatlight.agg-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapListKey   as String: [[
                kAudioSubTapUIDKey               as String: tapUID,
                kAudioSubTapDriftCompensationKey as String: true,
            ]],
        ]
        var newAgg: AudioObjectID = kAudioObjectUnknown
        guard AudioHardwareCreateAggregateDevice(aggProps as CFDictionary, &newAgg) == noErr else {
            NSLog("BeatLight: ❌ CreateAgg failed"); teardownTap(); return
        }
        aggregateID = newAgg
        Thread.sleep(forTimeInterval: 1.0)

        var newProc: AudioDeviceIOProcID? = nil
        let ps = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, nil) {
            [weak self] _, input, _, _, _ in
            self?.processBuffer(input.pointee)
        }
        guard ps == noErr, let p = newProc else {
            NSLog("BeatLight: ❌ IOProc failed: %d", ps); teardownTap(); return
        }
        ioProcID = p
        guard AudioDeviceStart(aggregateID, p) == noErr else {
            NSLog("BeatLight: ❌ DeviceStart failed"); teardownTap(); return
        }

        // Reset state
        callbackCount = 0; nonZeroCount = 0; beatCount = 0
        lastNonZeroCount = 0; staleSilenceRuns = 0
        ringBuf = [Float](repeating: 0, count: bufSize)
        ringIdx = 0

        isRunning = true
        NSLog("BeatLight: ✅ Tap running on %@ (%d procs)", outUID, procs.count)
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
            ? "AUDIO OK: \(nz)/\(tot) non-silent, \(beatCount) beats | device: \(currentOutputUID ?? "?")\n"
            : "SILENT: \(tot) callbacks all zero | device: \(currentOutputUID ?? "?")\n"
        try? msg.write(toFile: "/tmp/beatlight_tap.log", atomically: true, encoding: .utf8)

        if nz > lastNonZeroCount { staleSilenceRuns = 0 }
        else if tot > lastNonZeroCount + 200 { staleSilenceRuns += 1 }
        lastNonZeroCount = nz

        if staleSilenceRuns >= 3 {
            NSLog("BeatLight: 🔄 Recreating tap (silence)")
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
        var rms: Float = 0
        vDSP_rmsqv(samples, vDSP_Stride(ch), &rms, vDSP_Length(frames))

        callbackCount += 1
        if rms > 0.0001 { nonZeroCount += 1 }

        // Store in ring buffer
        ringBuf[ringIdx % bufSize] = rms
        ringIdx += 1

        // Need at least 1s of data before detecting
        guard ringIdx > 100 else { return }

        // Compute mean of the full ring buffer
        var mean: Float = 0
        vDSP_meanv(ringBuf, 1, &mean, vDSP_Length(bufSize))

        // Sensitivity → multiplier:
        //   High(0.8) → 1.3×   Medium(0.5) → 1.5×   Low(0.2) → 1.7×
        let multiplier: Float = 1.3 + (1.0 - sensitivity) * 0.5
        let threshold = mean * multiplier

        let now = Date()
        guard rms > threshold,
              rms > 0.002,
              now.timeIntervalSince(lastBeatTime) > minBeatInterval
        else { return }

        lastBeatTime = now
        beatCount += 1
        let cb = onBeat
        DispatchQueue.main.async { cb?() }
    }

    // MARK: - CoreAudio Helpers

    private func getDefaultOutputDeviceUID() -> String? {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sysObj, &prop, 0, nil, &size, &devID) == noErr else { return nil }
        var uidProp = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
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
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
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
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let ok = withUnsafeMutablePointer(to: &cfRef) {
            AudioObjectGetPropertyData(id, &prop, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard ok == noErr, let ref = cfRef else { return nil }
        return ref.takeRetainedValue() as String
    }
}
