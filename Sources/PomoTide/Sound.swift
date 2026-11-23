import AVFoundation

/// Plays an analog-sounding clock tick.
///
/// Each tick is picked at random from 24 recorded single ticks, alternating
/// between "tick" and "tock" recordings, with slight random loudness and timing.
/// The samples are played unmodified at their own sample rate.
/// The audio engine only runs while ticking.
@MainActor
final class TickPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var ticks: [[AVAudioPCMBuffer]] = [[], []]  // [tick, tock]
    private var loaded: TickSound?
    private var sound: TickSound = .off
    private var scheduler: Timer?
    private var nextSample: AVAudioFramePosition = 0
    private var sampleRate: Double = 44_100
    private var beat = 0

    init() {
        engine.attach(node)
    }

    var volume: Double = 0.5 {
        didSet { applyVolume() }
    }

    /// 0...1 multiplier while fading in; 1 otherwise.
    private var fadeLevel: Float = 1
    private var fadeTimer: Timer?

    var isPlaying: Bool { scheduler != nil }

    /// Starts ticking. With `fadeIn` > 0 the ticks swell from silence over that many seconds.
    func start(_ sound: TickSound, fadeIn: TimeInterval = 0) {
        guard sound != .off else { return stop() }
        if isPlaying, sound == self.sound { return }
        stop()
        load(sound)
        guard let format = ticks[0].first?.format else { return }
        self.sound = sound
        sampleRate = format.sampleRate
        engine.connect(node, to: engine.mainMixerNode, format: format)
        fadeLevel = fadeIn > 0 ? 0 : 1
        applyVolume()
        do {
            try engine.start()
        } catch {
            NSLog("PomoTide: audio engine failed to start: \(error)")
            return
        }
        node.play()
        nextSample = currentSample + AVAudioFramePosition(sampleRate * 0.15)
        beat = 0
        scheduleAhead()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAhead() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduler = timer
        if fadeIn > 0 { startFade(over: fadeIn) }
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeLevel = 1
        scheduler?.invalidate()
        scheduler = nil
        node.stop()
        engine.stop()
    }

    private func startFade(over seconds: TimeInterval) {
        let start = Date()
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = min(1, Float(Date().timeIntervalSince(start) / seconds))
                self.fadeLevel = p * p  // slow start, so the first ticks stay under the ringing gong
                self.applyVolume()
                if p >= 1 {
                    self.fadeTimer?.invalidate()
                    self.fadeTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func applyVolume() {
        node.volume = Float(volume) * sound.gain * fadeLevel
    }

    private var currentSample: AVAudioFramePosition {
        guard let nodeTime = node.lastRenderTime, let t = node.playerTime(forNodeTime: nodeTime) else { return 0 }
        return t.sampleTime
    }

    /// Keeps about 1.5 seconds of ticks queued on the player node.
    private func scheduleAhead() {
        let horizon = currentSample + AVAudioFramePosition(sampleRate * 1.5)
        while nextSample < horizon {
            if let buffer = ticks[beat % 2].randomElement() {
                node.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: nextSample, atRate: sampleRate))
            }
            beat += 1
            // A real escapement is never perfectly even: up to ±1 % of the second.
            nextSample += AVAudioFramePosition(sampleRate * Double.random(in: 0.99...1.01))
        }
    }

    /// Loads each tick twice, once at full level and once slightly quieter, for variety.
    private func load(_ sound: TickSound) {
        guard loaded != sound else { return }
        ticks = [[], []]
        for (i, buffer) in Self.loadBuffers(prefix: sound.filePrefix).enumerated() {
            ticks[i % 2].append(buffer)
            if let quieter = Self.scaled(buffer, by: Float.random(in: 0.8...0.9)) {
                ticks[i % 2].append(quieter)
            }
        }
        loaded = sound
    }

    private static func scaled(_ buffer: AVAudioPCMBuffer, by gain: Float) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        for ch in 0..<Int(buffer.format.channelCount) {
            for i in 0..<Int(buffer.frameLength) { dst[ch][i] = src[ch][i] * gain }
        }
        return copy
    }

    private static func loadBuffers(prefix: String) -> [AVAudioPCMBuffer] {
        guard let dir = Bundle.main.resourceURL?.appending(path: "Sounds") else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix + "_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil
                else { return nil }
                return buffer
            }
    }
}

/// Plays the gong or singing bowl at the start and end of a break.
@MainActor
final class TransitionPlayer {
    private var players: [TransitionSound: AVAudioPlayer] = [:]

    func play(_ sound: TransitionSound, volume: Double) {
        guard let file = sound.file else { return }
        if players[sound] == nil, let url = Bundle.main.url(forResource: file.name, withExtension: file.ext, subdirectory: "Sounds") {
            players[sound] = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player = players[sound] else { return }
        player.volume = Float(volume) * sound.gain
        player.currentTime = 0
        player.play()
    }
}
