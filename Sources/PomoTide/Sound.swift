import AVFoundation

/// Plays an analog-sounding clock tick.
///
/// Each tick is picked at random from recorded single ticks, alternating between
/// "tick" and "tock" recordings, with slight random pitch, loudness and timing.
/// The audio engine only runs while ticking.
@MainActor
final class TickPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var raw: [[Float]] = []
    private var variants: [[AVAudioPCMBuffer]] = [[], []]  // [tick, tock]
    private var variantsFor: TickSound?
    private var sound: TickSound = .off
    private var scheduler: Timer?
    private var nextSample: AVAudioFramePosition = 0
    private var beat = 0

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        raw = Self.loadTicks()
    }

    var volume: Double = 0.5 {
        didSet { node.volume = Float(volume) }
    }

    var isPlaying: Bool { scheduler != nil }

    func start(_ sound: TickSound) {
        guard sound != .off, !raw.isEmpty else { return stop() }
        if isPlaying, sound == self.sound { return }
        stop()
        self.sound = sound
        buildVariants(for: sound)
        node.volume = Float(volume)
        do {
            try engine.start()
        } catch {
            NSLog("PomoTide: audio engine failed to start: \(error)")
            return
        }
        node.play()
        nextSample = currentSample + AVAudioFramePosition(format.sampleRate * 0.15)
        beat = 0
        scheduleAhead()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAhead() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduler = timer
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
        node.stop()
        engine.stop()
    }

    private var currentSample: AVAudioFramePosition {
        guard let nodeTime = node.lastRenderTime, let t = node.playerTime(forNodeTime: nodeTime) else { return 0 }
        return t.sampleTime
    }

    /// Keeps about 1.5 seconds of ticks queued on the player node.
    private func scheduleAhead() {
        let sr = format.sampleRate
        let horizon = currentSample + AVAudioFramePosition(sr * 1.5)
        while nextSample < horizon {
            let set = variants[beat % 2]
            if let buffer = set.randomElement() {
                node.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: nextSample, atRate: sr))
            }
            beat += 1
            // A real escapement is never perfectly even: up to ±1 % of the interval.
            let jitter = Double.random(in: -0.01...0.01) * sound.interval
            nextSample += AVAudioFramePosition(sr * (sound.interval + jitter))
        }
    }

    private func buildVariants(for sound: TickSound) {
        guard variantsFor != sound else { return }
        let maxLength = Int(format.sampleRate * sound.interval * 0.9)
        variants = [[], []]
        for (i, samples) in raw.enumerated() {
            for _ in 0..<2 {
                let pitch = sound.pitch * Float.random(in: 0.97...1.03)
                let gain = sound.gain * Float.random(in: 0.85...1.0)
                let out = Self.resample(samples, by: pitch, gain: gain, maxLength: maxLength)
                if let buffer = makeBuffer(out) { variants[i % 2].append(buffer) }
            }
        }
        variantsFor = sound
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    /// Linear-interpolation resampling; changes pitch and length together, like a faster or slower recording.
    private static func resample(_ x: [Float], by rate: Float, gain: Float, maxLength: Int) -> [Float] {
        let count = min(Int(Float(x.count) / rate), maxLength)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Float(i) * rate
            let j = Int(pos)
            let frac = pos - Float(j)
            let a = x[j]
            let b = j + 1 < x.count ? x[j + 1] : 0
            out[i] = (a + (b - a) * frac) * gain
        }
        // Short fade-out so a shortened tick never ends with a click.
        let fade = min(count, 441)
        for k in 0..<fade {
            out[count - fade + k] *= Float(fade - k) / Float(fade)
        }
        return out
    }

    private static func loadTicks() -> [[Float]] {
        guard let dir = Bundle.main.resourceURL?.appending(path: "Sounds") else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("tick_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil,
                      let data = buffer.floatChannelData
                else { return nil }
                return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            }
    }
}

/// Plays the gong at phase changes.
@MainActor
final class GongPlayer {
    private var player: AVAudioPlayer?

    func play(volume: Double) {
        if player == nil, let url = Bundle.main.url(forResource: "gong", withExtension: "wav", subdirectory: "Sounds") {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player else { return }
        player.volume = Float(volume)
        player.currentTime = 0
        player.play()
    }
}
