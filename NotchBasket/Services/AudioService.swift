import AVFoundation
import OSLog

enum SoundEffect: CaseIterable, Hashable {
    case bounce
    case rim
    case backboard
    case score
    case deploy
    case retract
}

/// A low, rubbery basketball impact with a short wooden-court resonance.
/// Keeping this separate from the other one-shot effects makes it impossible
/// for the bounce to inherit their bright, glass-like noise transient.
enum BasketballCourtBounceSynthesizer {
    static let duration: Double = 0.18

    static func samples(sampleRate: Double) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        var result = [Float](repeating: 0, count: frameCount)
        var bodyPhase = 0.0
        var lowPassStageOne = 0.0
        var lowPassStageTwo = 0.0

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let normalizedTime = time / duration
            let attack = min(time / 0.0018, 1)
            let release = min(max((duration - time) / 0.028, 0), 1)

            // A basketball's hollow body drops slightly in pitch as the shell
            // rebounds. Integrating phase avoids chirp discontinuities.
            let bodyPitch = 114 - (39 * min(normalizedTime, 1))
            bodyPhase += 2 * .pi * bodyPitch / sampleRate
            let body = sin(bodyPhase) * exp(-19 * time) * 0.78

            // Rubber shell and maple-floor resonances add definition without
            // the high partials that made the old sound resemble struck glass.
            let rubber =
                sin((2 * .pi * 205 * time) + 0.18) * exp(-38 * time) * 0.20
            let wood =
                sin(2 * .pi * 88 * time) * exp(-16 * time) * 0.18 +
                sin(2 * .pi * 176 * time) * exp(-31 * time) * 0.07

            let rawNoise = pseudoNoise(at: index)
            lowPassStageOne += (rawNoise - lowPassStageOne) * 0.075
            lowPassStageTwo += (lowPassStageOne - lowPassStageTwo) * 0.11
            let floorContact = lowPassStageTwo * exp(-55 * time) * 0.11

            let value = (body + rubber + wood + floorContact) * attack * release
            result[index] = Float(tanh(value * 1.08))
        }

        return result
    }

    private static func pseudoNoise(at index: Int) -> Double {
        let seed = Double(index)
        return sin((seed * 12.9898) + (sin(seed * 0.173) * 78.233))
    }
}

/// A tiny procedural sound bank. Generating buffers locally keeps the toy self-contained
/// and avoids borrowing macOS alert sounds that feel unrelated to basketball.
final class AudioService {
    private let logger = Logger(subsystem: "com.notchbasket.app", category: "AudioService")
    private let engine = AVAudioEngine()
    // AVFoundation guarantees this valid mono PCM format can be constructed.
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 1
    )!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var nextPlayerIndex = 0
    private var lastPlayedAt: [SoundEffect: TimeInterval] = [:]

    init() {
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        buffers = Dictionary(uniqueKeysWithValues: SoundEffect.allCases.compactMap { effect in
            guard let buffer = makeBuffer(for: effect) else { return nil }
            return (effect, buffer)
        })
        engine.prepare()
    }

    func play(
        _ effect: SoundEffect,
        intensity: CGFloat = 1,
        preferences: PreferencesService
    ) {
        guard preferences.soundEnabled, let buffer = buffers[effect], !players.isEmpty else {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let cooldown: TimeInterval
        switch effect {
        case .bounce: cooldown = 0.16
        case .rim: cooldown = 0.075
        default: cooldown = 0.11
        }
        if let last = lastPlayedAt[effect], now - last < cooldown {
            return
        }
        lastPlayedAt[effect] = now

        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            logger.error("Audio engine could not start: \(error.localizedDescription, privacy: .public)")
            return
        }

        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        player.stop()
        player.volume = Float(
            min(max(CGFloat(preferences.masterVolume) * max(intensity, 0.16), 0), 1)
        )
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    func stopAll() {
        players.forEach { $0.stop() }
        engine.pause()
    }

    private func makeBuffer(for effect: SoundEffect) -> AVAudioPCMBuffer? {
        let duration: Double
        switch effect {
        case .bounce: duration = BasketballCourtBounceSynthesizer.duration
        case .rim: duration = 0.20
        case .backboard: duration = 0.17
        case .score: duration = 0.52
        case .deploy: duration = 0.30
        case .retract: duration = 0.24
        }

        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData
        else {
            return nil
        }
        buffer.frameLength = frameCount
        let samples = channelData[0]

        if effect == .bounce {
            let bounceSamples = BasketballCourtBounceSynthesizer.samples(
                sampleRate: format.sampleRate
            )
            for index in 0..<min(Int(frameCount), bounceSamples.count) {
                samples[index] = bounceSamples[index]
            }
            return buffer
        }

        for index in 0..<Int(frameCount) {
            let time = Double(index) / format.sampleRate
            let normalizedTime = time / duration
            let noise = pseudoNoise(at: index)
            let value: Double

            switch effect {
            case .bounce:
                // Bounce buffers are generated by BasketballCourtBounceSynthesizer.
                value = 0

            case .rim:
                let envelope = exp(-18 * time)
                let metal =
                    sin(2 * .pi * 760 * time) * 0.46 +
                    sin(2 * .pi * 1_170 * time) * 0.31 +
                    sin(2 * .pi * 1_910 * time) * 0.14
                value = metal * envelope

            case .backboard:
                let thump = sin(2 * .pi * 165 * time) * exp(-25 * time) * 0.68
                let knock = noise * exp(-48 * time) * 0.28
                value = thump + knock

            case .score:
                let swishShape = sin(.pi * min(max(normalizedTime, 0), 1))
                let swish = noise * swishShape * exp(-2.1 * time) * 0.20
                let firstTone = sin(2 * .pi * 660 * time) * exp(-7 * time) * 0.24
                let delayedTime = max(time - 0.10, 0)
                let secondTone = time >= 0.10
                    ? sin(2 * .pi * 880 * delayedTime) * exp(-7 * delayedTime) * 0.24
                    : 0
                value = swish + firstTone + secondTone

            case .deploy:
                let frequency = 180 + (520 * normalizedTime)
                let shape = sin(.pi * min(max(normalizedTime, 0), 1))
                value = sin(2 * .pi * frequency * time) * shape * 0.23

            case .retract:
                let frequency = 620 - (430 * normalizedTime)
                let shape = sin(.pi * min(max(normalizedTime, 0), 1))
                value = sin(2 * .pi * frequency * time) * shape * 0.18
            }

            samples[index] = Float(tanh(value))
        }
        return buffer
    }

    private func pseudoNoise(at index: Int) -> Double {
        let seed = Double(index)
        return sin((seed * 12.9898) + (sin(seed * 0.173) * 78.233))
    }
}
