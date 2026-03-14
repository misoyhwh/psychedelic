import AVFoundation
import Observation
import QuartzCore

@Observable
@MainActor
class AudioReactiveEngine {
    var audioLevel: Float = 0
    var bassLevel: Float = 0
    var trebleLevel: Float = 0
    var isRunning: Bool = false
    var sensitivity: Float = 1.0  // set from outside
    var autoPulseEnabled: Bool = false
    var autoPulseBPM: Float = 120.0

    private var recorder: AVAudioRecorder?
    private var smoothedLevel: Float = 0
    private var displayLink: CADisplayLink?
    private var debugLogCounter: Int = 0
    private var autoPulseTime: Float = 0
    private var lastAutoPulseTimestamp: TimeInterval = 0

    func start() {
        guard !isRunning else { return }

        if autoPulseEnabled {
            // Auto Pulse mode: no microphone needed
            isRunning = true
            autoPulseTime = 0
            lastAutoPulseTimestamp = 0
            print("AudioReactive: Auto Pulse mode started at \(autoPulseBPM) BPM")
            startDisplayLink()
            return
        }

        Task {
            let granted = await requestMicrophonePermission()
            guard granted else {
                print("AudioReactive: Microphone permission denied")
                return
            }
            setupRecorder()
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        isRunning = false
        audioLevel = 0
        bassLevel = 0
        trebleLevel = 0
        smoothedLevel = 0
        autoPulseTime = 0
    }

    // MARK: - Private

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func setupRecorder() {
        let session = AVAudioSession.sharedInstance()

        let configs: [(AVAudioSession.Category, AVAudioSession.Mode, String)] = [
            (.playAndRecord, .default, "playAndRecord/default"),
            (.record, .default, "record/default"),
            (.record, .measurement, "record/measurement"),
        ]

        for (category, mode, label) in configs {
            do {
                try session.setCategory(category, mode: mode)
                try session.setActive(true)
                print("AudioReactive: Session configured with \(label)")
                break
            } catch {
                print("AudioReactive: \(label) failed: \(error.localizedDescription)")
            }
        }

        if let inputs = session.availableInputs {
            print("AudioReactive: Available inputs: \(inputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        }
        print("AudioReactive: Current route inputs: \(session.currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" })")

        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("audio_meter.caf")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let rec = try AVAudioRecorder(url: tempURL, settings: settings)
            rec.isMeteringEnabled = true

            if rec.record() {
                self.recorder = rec
                self.isRunning = true
                print("AudioReactive: Recorder started, metering enabled")
                startDisplayLink()
            } else {
                print("AudioReactive: record() returned false")
            }
        } catch {
            print("AudioReactive: Failed to create recorder: \(error)")
        }
    }

    private func startDisplayLink() {
        let target = DisplayLinkTarget { [weak self] in
            Task { @MainActor in
                self?.updateLevels()
            }
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: RunLoop.main, forMode: RunLoop.Mode.default)
        displayLink = link
    }

    private func updateLevels() {
        if autoPulseEnabled {
            updateAutoPulse()
            return
        }

        guard let recorder, recorder.isRecording else { return }

        recorder.updateMeters()

        let avgPower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)

        // Debug log every ~2 seconds
        debugLogCounter += 1
        if debugLogCounter % 60 == 0 {
            print("AudioReactive: avg=\(String(format: "%.1f", avgPower))dB peak=\(String(format: "%.1f", peakPower))dB")
        }

        // Sensitivity adjusts the floor: higher sensitivity = lower floor = picks up quieter sounds
        let floorDB: Float = -50.0 / sensitivity
        let linearAvg = dbToLinear(avgPower, floor: floorDB)
        let linearPeak = dbToLinear(peakPower, floor: floorDB)

        // Apply sensitivity as a gain multiplier
        let gained = min(linearAvg * sensitivity, 1.0)
        let gainedPeak = min(linearPeak * sensitivity, 1.0)

        smoothedLevel += (gained - smoothedLevel) * 0.25
        audioLevel = smoothedLevel

        let transient = max(gainedPeak - gained, 0)
        bassLevel += (smoothedLevel - bassLevel) * 0.15
        trebleLevel += (min(transient * 2.0 * sensitivity, 1.0) - trebleLevel) * 0.3
        trebleLevel = min(trebleLevel, 1.0)
    }

    private func updateAutoPulse() {
        autoPulseTime += 1.0 / 30.0  // ~30fps display link

        let bps = autoPulseBPM / 60.0  // beats per second
        let beatPhase = autoPulseTime * bps
        let beatFrac = beatPhase - floor(beatPhase)  // 0..1 within each beat

        // Sharp kick on the beat (fast attack, medium decay)
        let kick = pow(max(1.0 - beatFrac * 3.0, 0.0), 2.0)

        // Off-beat hi-hat pattern (between beats)
        let halfBeatFrac = (beatPhase * 2.0) - floor(beatPhase * 2.0)
        let hihat = pow(max(1.0 - halfBeatFrac * 5.0, 0.0), 3.0)

        // Sine wave swell for smooth variation
        let swell = (sin(autoPulseTime * bps * .pi * 2.0) * 0.5 + 0.5) * 0.6

        // Apply sensitivity
        audioLevel = min((kick * 0.7 + swell * 0.3) * sensitivity, 1.0)
        bassLevel = min(kick * sensitivity, 1.0)
        trebleLevel = min(hihat * 0.8 * sensitivity, 1.0)
    }

    private func dbToLinear(_ db: Float, floor: Float) -> Float {
        guard db > floor else { return 0 }
        return (db - floor) / (-floor)
    }
}

// MARK: - DisplayLink target

private class DisplayLinkTarget: NSObject {
    let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc func step(_ link: CADisplayLink) {
        callback()
    }
}
