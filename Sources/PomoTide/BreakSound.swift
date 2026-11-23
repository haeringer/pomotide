import AVFoundation

enum BreakSound: String, CaseIterable, Identifiable {
    case off, waves, whiteNoise, pinkNoise, brownNoise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Silence"
        case .waves: "Ocean Waves"
        case .whiteNoise: "White Noise"
        case .pinkNoise: "Pink Noise"
        case .brownNoise: "Brown Noise"
        }
    }
}

/// Background sound for breaks: a looped surf recording or generated noise.
/// Fades in and out; the audio engine only exists while the sound plays.
@MainActor
final class BreakSoundPlayer {
    private var engine: AVAudioEngine?
    private var current: BreakSound = .off
    private var fade: Timer?

    var volume: Double = 0.5 {
        didSet { if fade == nil { engine?.mainMixerNode.outputVolume = Float(volume) } }
    }

    func start(_ sound: BreakSound) {
        guard sound != .off else { return stop() }
        if engine != nil, sound == current {
            // Already playing, or fading out after a stop: fade (back) in.
            ramp(to: Float(volume), over: 1) {}
            return
        }
        stopNow()
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        switch sound {
        case .waves:
            guard let buffer = Self.loadWaves() else { return }
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            node.scheduleBuffer(buffer, at: nil, options: .loops)
            engine.mainMixerNode.outputVolume = 0
            guard (try? engine.start()) != nil else { return }
            node.play()
        default:
            let node = Self.makeNoiseNode(sound, format: format)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0
            guard (try? engine.start()) != nil else { return }
        }
        self.engine = engine
        current = sound
        ramp(to: Float(volume), over: 3) {}
    }

    /// Fades out, then releases the engine.
    func stop() {
        guard engine != nil, !isFadingOut else { return }
        isFadingOut = true
        ramp(to: 0, over: 1.5) { [weak self] in self?.stopNow() }
    }

    private var isFadingOut = false

    private func stopNow() {
        fade?.invalidate()
        fade = nil
        isFadingOut = false
        engine?.stop()
        engine = nil
        current = .off
    }

    private var rampFrom: Float = 0
    private var rampTo: Float = 0
    private var rampStep = 0
    private var rampSteps = 1
    private var rampDone: (@MainActor () -> Void)?

    private func ramp(to target: Float, over seconds: Double, then done: @escaping @MainActor () -> Void) {
        fade?.invalidate()
        if target > 0 { isFadingOut = false }
        guard let mixer = engine?.mainMixerNode else { return done() }
        rampFrom = mixer.outputVolume
        rampTo = target
        rampStep = 0
        rampSteps = max(1, Int(seconds * 30))
        rampDone = done
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rampTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fade = timer
    }

    private func rampTick() {
        rampStep += 1
        let p = Float(rampStep) / Float(rampSteps)
        engine?.mainMixerNode.outputVolume = rampFrom + (rampTo - rampFrom) * p * p * (3 - 2 * p)  // smoothstep
        guard rampStep >= rampSteps else { return }
        fade?.invalidate()
        fade = nil
        let done = rampDone
        rampDone = nil
        done?()
    }

    /// Must be nonisolated: a closure created inside a @MainActor method inherits that
    /// isolation, and Swift traps when the audio thread then calls it.
    private nonisolated static func makeNoiseNode(_ sound: BreakSound, format: AVAudioFormat) -> AVAudioSourceNode {
        let generator = NoiseGenerator(sound)
        return AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            generator.render(frameCount, into: bufferList)
        }
    }

    private static func loadWaves() -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: "waves", withExtension: "m4a", subdirectory: "Sounds"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else { return nil }
        return buffer
    }
}

/// Generates white, pink or brown noise on the audio render thread.
/// State is only touched from that thread.
private final class NoiseGenerator: @unchecked Sendable {
    private let kind: BreakSound
    private var rng = SystemRandomNumberGenerator()
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0

    init(_ kind: BreakSound) { self.kind = kind }

    func render(_ frameCount: AVAudioFrameCount, into bufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        for i in 0..<Int(frameCount) {
            out[i] = next()
        }
        return noErr
    }

    private func next() -> Float {
        let white = Float.random(in: -1...1, using: &rng)
        switch kind {
        case .pinkNoise:
            // Paul Kellet's refined pink noise filter.
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink * 0.028  // about 0.05 RMS
        case .brownNoise:
            // Leaky integrator keeps the random walk centered.
            brown = (brown + 0.02 * white) / 1.02
            return brown * 1.4  // about 0.08 RMS; low frequencies sound quieter
        default:
            return white * 0.07  // about 0.04 RMS; white noise sounds harsh at equal level
        }
    }
}
