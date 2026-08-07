import AVFoundation
import OSLog

enum SoundEffect: CaseIterable, Hashable {
    case bounce
    case rim
    case backboard
    case scoreTwo
    case scoreThree
    case newBest
    case buzzer
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


/// The shared rim-and-backboard impact, chosen by ear from auditioned WAV
/// candidates ("panya B"): a deep padded thud built from three plate modes that
/// each decay at their own rate, the ball's own sagging-pitch body, and a dark
/// double-lowpassed strike. Ported sample-for-sample from the approved waveform —
/// resist "fixing" the math here, because what was approved is the sound.
enum HoopImpactSynthesizer {
    static let duration: Double = 0.30

    static func samples(sampleRate: Double) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        var result = [Float](repeating: 0, count: frameCount)
        var lowPassStageOne = 0.0
        var lowPassStageTwo = 0.0

        // (frequency, amplitude, decay per second). Ratios are inharmonic and the
        // decays independent — the higher modes die first, which is what keeps
        // this reading as a struck object rather than a gated chord.
        let modes: [(Double, Double, Double)] = [
            (149, 0.60, 22),
            (243, 0.28, 28),
            (352, 0.14, 36)
        ]

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            var value = modes.reduce(0.0) { total, mode in
                total + (mode.1 * sin(2 * .pi * mode.0 * time) * exp(-mode.2 * time))
            }

            // The ball's hollow body, pitch sagging as the shell rebounds.
            let sag = 105 - (30 * min(time / 0.05, 1))
            value += 0.40 * sin(2 * .pi * sag * time) * exp(-30 * time)

            // Dark strike: noise through two gentle one-pole lowpasses, gone fast.
            let rawNoise = pseudoNoise(at: index)
            lowPassStageOne += (rawNoise - lowPassStageOne) * 0.13
            lowPassStageTwo += (lowPassStageOne - lowPassStageTwo) * 0.13
            value += lowPassStageTwo * exp(-95 * time) * 0.42

            let attack = min(time / 0.0015, 1)
            let release = min(max((duration - time) / 0.045, 0), 1)
            result[index] = Float(tanh(value * attack * release * 1.05))
        }

        // Match the loudness the candidates were auditioned at.
        let peak = result.map { abs($0) }.max() ?? 1
        if peak > 0 {
            let scale = Float(0.85) / peak
            for index in result.indices { result[index] *= scale }
        }
        return result
    }

    private static func pseudoNoise(at index: Int) -> Double {
        let seed = Double(index)
        return sin((seed * 12.9898) + (sin(seed * 0.173) * 78.233))
    }
}

/// The score reward: a rising pluck arpeggio, chosen by ear from auditioned
/// WAV candidates ("2-arpej") — C5 E5 G5 for two points, escalated to
/// C5 E5 G5 C6 with a faster gait and a shimmer tail for three. Ported
/// sample-for-sample from the approved waveform — resist "fixing" the math
/// here, because what was approved is the sound.
enum ScoreChimeSynthesizer {
    static func duration(threePointer: Bool) -> Double {
        threePointer ? 0.60 : 0.52
    }

    static func samples(sampleRate: Double, threePointer: Bool) -> [Float] {
        let duration = duration(threePointer: threePointer)
        let frameCount = Int(duration * sampleRate)
        var canvas = [Double](repeating: 0, count: frameCount)

        let notes: [Double] = threePointer
            ? [523.25, 659.25, 783.99, 1046.5]
            : [523.25, 659.25, 783.99]
        let noteSpacing = threePointer ? 0.062 : 0.072

        for (noteIndex, frequency) in notes.enumerated() {
            let start = Int(Double(noteIndex) * noteSpacing * sampleRate)
            let gain = 1.0 + (0.12 * Double(noteIndex))
            for index in start..<frameCount {
                let time = Double(index - start) / sampleRate
                canvas[index] += gain * pluck(time: time, frequency: frequency)
            }
        }

        if threePointer {
            // A quiet sparkling tail after the last note: a detuned high pair.
            let start = Int(Double(notes.count) * noteSpacing * sampleRate)
            let end = min(start + Int(0.3 * sampleRate), frameCount)
            for index in start..<end {
                let time = Double(index - start) / sampleRate
                canvas[index] += 0.12 *
                    (sin(2 * .pi * 3_100 * time) + sin(2 * .pi * 3_100 * 1.007 * time)) *
                    exp(-10 * time)
            }
        }

        var peak = 0.0
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let attack = min(time / 0.004, 1)
            let release = min(max((duration - time) / 0.05, 0), 1)
            canvas[index] *= attack * release
            peak = max(peak, abs(canvas[index]))
        }

        // Match the loudness the candidates were auditioned at.
        let scale = peak > 0 ? 0.8 / peak : 1
        return canvas.map { Float($0 * scale) }
    }

    /// Marimba-ish pluck: fundamental plus a soft 4th harmonic dying quickly.
    private static func pluck(time: Double, frequency: Double) -> Double {
        sin(2 * .pi * frequency * time) * exp(-14 * time)
            + 0.22 * sin(2 * .pi * 4 * frequency * time) * exp(-14 * 3.2 * time)
    }
}

/// The personal-record flourish: three rising brass stabs (C5 E5 C6) with a
/// glitter tail, pitched to sit in C major over the score arpeggio it lands on
/// top of. Ported sample-for-sample from the auditioned candidate.
enum NewBestFanfareSynthesizer {
    static let duration: Double = 0.85

    static func samples(sampleRate: Double) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        var canvas = [Double](repeating: 0, count: frameCount)

        // (frequency, start second, gain) — each stab louder than the last.
        let stabs: [(Double, Double, Double)] = [
            (523.25, 0.00, 0.80),
            (659.25, 0.10, 0.92),
            (1_046.5, 0.20, 1.04)
        ]

        for (frequency, start, gain) in stabs {
            let first = Int(start * sampleRate)
            for index in first..<frameCount {
                let time = Double(index - first) / sampleRate
                canvas[index] += gain * horn(time: time, frequency: frequency)
            }
        }

        // Glitter over the last stab: a detuned high pair, gone in half a second.
        let shimmerStart = Int(0.24 * sampleRate)
        let shimmerEnd = min(shimmerStart + Int(0.5 * sampleRate), frameCount)
        for index in shimmerStart..<shimmerEnd {
            let time = Double(index - shimmerStart) / sampleRate
            canvas[index] += 0.14 *
                (sin(2 * .pi * 3_136 * time) + sin(2 * .pi * 3_136 * 1.006 * time)) *
                exp(-6 * time)
        }

        var peak = 0.0
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let attack = min(time / 0.004, 1)
            let release = min(max((duration - time) / 0.06, 0), 1)
            canvas[index] *= attack * release
            peak = max(peak, abs(canvas[index]))
        }

        let scale = peak > 0 ? 0.8 / peak : 1
        return canvas.map { Float($0 * scale) }
    }

    /// Brass-ish: odd and even harmonics over a short swell, decaying together.
    private static func horn(time: Double, frequency: Double) -> Double {
        let bright = 0.5
        var value = sin(2 * .pi * frequency * time)
        value += 0.45 * bright * sin(2 * .pi * frequency * 2 * time)
        value += 0.22 * bright * sin(2 * .pi * frequency * 3 * time)
        value += 0.10 * bright * sin(2 * .pi * frequency * 4 * time)
        return value * min(time / 0.03, 1) * exp(-3.4 * time)
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
        case .rim, .backboard: duration = HoopImpactSynthesizer.duration
        case .scoreTwo: duration = ScoreChimeSynthesizer.duration(threePointer: false)
        case .scoreThree: duration = ScoreChimeSynthesizer.duration(threePointer: true)
        case .newBest: duration = NewBestFanfareSynthesizer.duration
        case .buzzer: duration = 0.72
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

        if effect == .rim || effect == .backboard {
            // One impact voice for both, chosen by ear: the rim and the board
            // deliberately share the same padded thud.
            let impactSamples = HoopImpactSynthesizer.samples(
                sampleRate: format.sampleRate
            )
            for index in 0..<min(Int(frameCount), impactSamples.count) {
                samples[index] = impactSamples[index]
            }
            return buffer
        }

        if effect == .newBest {
            let fanfare = NewBestFanfareSynthesizer.samples(sampleRate: format.sampleRate)
            for index in 0..<min(Int(frameCount), fanfare.count) {
                samples[index] = fanfare[index]
            }
            return buffer
        }

        if effect == .scoreTwo || effect == .scoreThree {
            let chimeSamples = ScoreChimeSynthesizer.samples(
                sampleRate: format.sampleRate,
                threePointer: effect == .scoreThree
            )
            for index in 0..<min(Int(frameCount), chimeSamples.count) {
                samples[index] = chimeSamples[index]
            }
            return buffer
        }

        for index in 0..<Int(frameCount) {
            let time = Double(index) / format.sampleRate
            let normalizedTime = time / duration
            let value: Double

            switch effect {
            case .bounce:
                // Bounce buffers are generated by BasketballCourtBounceSynthesizer.
                value = 0

            case .rim, .backboard:
                // Generated above by HoopImpactSynthesizer.
                value = 0

            case .newBest:
                // Generated above by NewBestFanfareSynthesizer.
                value = 0

            case .scoreTwo, .scoreThree:
                // Generated above by ScoreChimeSynthesizer.
                value = 0

            case .buzzer:
                // An arena horn: a rough, square-ish stack of odd harmonics with
                // a close detuned pair for beating, held flat and released fast.
                let horn =
                    sin(2 * .pi * 311 * time) * 0.42 +
                    sin(2 * .pi * 317 * time) * 0.34 +
                    sin(2 * .pi * 933 * time) * 0.20 +
                    sin(2 * .pi * 1_555 * time) * 0.09
                let attack = min(time / 0.006, 1)
                let release = min(max((duration - time) / 0.06, 0), 1)
                value = horn * attack * release * 0.8

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
