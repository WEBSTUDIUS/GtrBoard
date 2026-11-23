//  CabinetIRLibrary.swift
//  BoardCore
//
//  Built-in speaker impulse responses. Every cabinet is synthesised from the
//  same physical sketch — a close mic, a few strong early reflections, the
//  low resonance of the cone, the presence lift of the dust cap and a short
//  diffused tail — with its own frequencies, decays and microphone distance.
//
//  Generating the IRs instead of shipping WAV files keeps the app small,
//  makes the library identical on every machine and avoids redistributing
//  third-party cabinet captures. The set leans deliberately towards modern
//  metal: tight low end, aggressive upper mids and a choice between scooped
//  and mid-forward voicings.

import Foundation

/// One entry in the built-in cabinet library.
public struct CabinetIRModel: Identifiable, Hashable, Sendable {
    /// Stable slug, used in tests and in documentation.
    public let id: String
    /// Name displayed in the pedal menu.
    public let name: String
    /// One-line description of the voicing.
    public let character: String
}

/// Built-in impulse responses for the IR Cabinet pedal.
public enum CabinetIRLibrary {
    /// Name of the custom slot appended to the built-in models.
    public static let customName = "Custom WAV"

    public static let models: [CabinetIRModel] = voices.map {
        CabinetIRModel(id: $0.id, name: $0.name, character: $0.character)
    }

    /// Choice list for the `model` parameter. The last entry is the custom slot.
    public static let presetNames: [String] = models.map(\.name) + [customName]

    /// Index of the custom slot in ``presetNames``.
    public static let customIndex: Int = models.count

    /// Human-readable library summary for the UI.
    public static var libraryDescription: String {
        "\(models.count) built-in cabs · custom WAV slot"
    }

    // MARK: - Voice table

    /// Synthesis parameters. The values are musical rather than measured:
    /// each row is a different cab/mic combination, not a copy of one.
    struct Voice {
        let id: String
        let name: String
        let character: String
        let seed: UInt64
        let lowCutHz: Double
        let lowHz: Double
        let lowGainDB: Double
        let lowQ: Double
        let midHz: Double
        let midGainDB: Double
        let midQ: Double
        let presenceHz: Double
        let presenceGainDB: Double
        let presenceQ: Double
        let highCutHz: Double
        let brightnessDB: Double
        let reflection: Double
        let micDelayMS: Double
        let bodyDecayMS: Double
        let tailDecayMS: Double
    }

    static let voices: [Voice] = [
        Voice(id: "v30-sm57", name: "V30 4x12 · SM57",
              character: "The modern metal reference: tight low mid, barking 2.7 kHz presence.",
              seed: 11, lowCutHz: 70, lowHz: 96, lowGainDB: 7, lowQ: 2.6,
              midHz: 520, midGainDB: -1, midQ: 1.1,
              presenceHz: 2_700, presenceGainDB: 5, presenceQ: 1.3,
              highCutHz: 6_200, brightnessDB: 1, reflection: 0.9,
              micDelayMS: 0.35, bodyDecayMS: 5, tailDecayMS: 18),
        Voice(id: "v30-57-121", name: "V30 4x12 · 57+121",
              character: "SM57 and Royer 121 blend: rounder top, bigger low mid.",
              seed: 23, lowCutHz: 65, lowHz: 92, lowGainDB: 8, lowQ: 2.8,
              midHz: 480, midGainDB: 1, midQ: 0.9,
              presenceHz: 2_500, presenceGainDB: 3.5, presenceQ: 1.1,
              highCutHz: 7_000, brightnessDB: 2.5, reflection: 0.7,
              micDelayMS: 0.55, bodyDecayMS: 7, tailDecayMS: 24),
        Voice(id: "mesa-os-sm57", name: "Mesa OS · SM57",
              character: "Oversized Recto cab: huge low end, scooped mids, wide sizzle.",
              seed: 37, lowCutHz: 60, lowHz: 82, lowGainDB: 10, lowQ: 2.2,
              midHz: 620, midGainDB: -3, midQ: 1.2,
              presenceHz: 2_900, presenceGainDB: 4, presenceQ: 1.4,
              highCutHz: 5_600, brightnessDB: 0, reflection: 1.0,
              micDelayMS: 0.30, bodyDecayMS: 8, tailDecayMS: 26),
        Voice(id: "g12t75", name: "1960 · G12T-75",
              character: "Bright and scooped with the classic '75 top-end sizzle.",
              seed: 41, lowCutHz: 75, lowHz: 102, lowGainDB: 5, lowQ: 2.0,
              midHz: 740, midGainDB: -4, midQ: 1.0,
              presenceHz: 3_200, presenceGainDB: 2.5, presenceQ: 1.6,
              highCutHz: 6_800, brightnessDB: 3, reflection: 0.8,
              micDelayMS: 0.45, bodyDecayMS: 5, tailDecayMS: 16),
        Voice(id: "marshall-v30", name: "1960 · V30",
              character: "The hard-rock workhorse: mid-forward, dry and punchy.",
              seed: 53, lowCutHz: 72, lowHz: 99, lowGainDB: 6, lowQ: 2.4,
              midHz: 560, midGainDB: 1, midQ: 1.0,
              presenceHz: 2_600, presenceGainDB: 6, presenceQ: 1.2,
              highCutHz: 6_000, brightnessDB: 2, reflection: 0.85,
              micDelayMS: 0.40, bodyDecayMS: 6, tailDecayMS: 18),
        Voice(id: "diezel-v30", name: "Diezel 4x12 · V30",
              character: "Tight, dry and aggressive; the top stays articulate under gain.",
              seed: 67, lowCutHz: 78, lowHz: 88, lowGainDB: 7, lowQ: 2.3,
              midHz: 500, midGainDB: 2, midQ: 1.1,
              presenceHz: 3_000, presenceGainDB: 6, presenceQ: 1.5,
              highCutHz: 6_400, brightnessDB: 2, reflection: 0.95,
              micDelayMS: 0.30, bodyDecayMS: 6, tailDecayMS: 20),
        Voice(id: "engl-v30", name: "ENGL 4x12 · V30",
              character: "Hairy upper mids and a fast, tight low end for modern rhythm.",
              seed: 79, lowCutHz: 76, lowHz: 94, lowGainDB: 6, lowQ: 2.5,
              midHz: 620, midGainDB: -1, midQ: 1.0,
              presenceHz: 3_400, presenceGainDB: 7, presenceQ: 1.4,
              highCutHz: 7_200, brightnessDB: 4, reflection: 0.9,
              micDelayMS: 0.35, bodyDecayMS: 5, tailDecayMS: 17),
        Voice(id: "orange-ppc", name: "Orange PPC412 · V30",
              character: "Doom wall: thick low mid, dark top and a long cone decay.",
              seed: 83, lowCutHz: 55, lowHz: 78, lowGainDB: 11, lowQ: 2.0,
              midHz: 420, midGainDB: 3, midQ: 0.9,
              presenceHz: 2_400, presenceGainDB: 1.5, presenceQ: 1.0,
              highCutHz: 5_000, brightnessDB: -2, reflection: 1.1,
              micDelayMS: 0.50, bodyDecayMS: 9, tailDecayMS: 30),
        Voice(id: "peavey-5150", name: "5150 · Sheffield",
              character: "Djent and hardcore staple: big lows, scooped centre, cutting top.",
              seed: 97, lowCutHz: 80, lowHz: 86, lowGainDB: 8, lowQ: 2.2,
              midHz: 700, midGainDB: -3, midQ: 1.2,
              presenceHz: 3_100, presenceGainDB: 5, presenceQ: 1.3,
              highCutHz: 6_500, brightnessDB: 2.5, reflection: 0.9,
              micDelayMS: 0.30, bodyDecayMS: 6, tailDecayMS: 19),
        Voice(id: "fredman", name: "Fredman · 57/57",
              character: "Swedish chainsaw: two 57s, a hard 1.1 kHz bite and almost no tail.",
              seed: 101, lowCutHz: 85, lowHz: 96, lowGainDB: 6, lowQ: 2.6,
              midHz: 1_150, midGainDB: 4, midQ: 1.4,
              presenceHz: 3_300, presenceGainDB: 3, presenceQ: 1.7,
              highCutHz: 5_800, brightnessDB: 1, reflection: 1.2,
              micDelayMS: 0.25, bodyDecayMS: 4, tailDecayMS: 12),
        Voice(id: "djent-tight", name: "Djent · Low-Cut Tight",
              character: "Maximum string separation: 110 Hz low cut, hard mids, open top.",
              seed: 113, lowCutHz: 110, lowHz: 105, lowGainDB: 4, lowQ: 2.8,
              midHz: 850, midGainDB: -2, midQ: 1.5,
              presenceHz: 3_000, presenceGainDB: 6, presenceQ: 1.2,
              highCutHz: 7_600, brightnessDB: 3.5, reflection: 0.7,
              micDelayMS: 0.30, bodyDecayMS: 4, tailDecayMS: 14),
        Voice(id: "modern-scoop", name: "Modern Metal · Scoop+",
              character: "Deep scooped wall for drop tunings and big choruses.",
              seed: 127, lowCutHz: 68, lowHz: 84, lowGainDB: 9, lowQ: 2.1,
              midHz: 650, midGainDB: -5, midQ: 1.1,
              presenceHz: 3_300, presenceGainDB: 5, presenceQ: 1.5,
              highCutHz: 7_000, brightnessDB: 3, reflection: 0.85,
              micDelayMS: 0.40, bodyDecayMS: 7, tailDecayMS: 22)
    ]

    // MARK: - Generation

    /// Synthesises the impulse response for a built-in model.
    public static func impulseResponse(at index: Int, sampleRate: Double) -> [Float] {
        guard voices.indices.contains(index) else {
            return impulseResponse(at: 0, sampleRate: sampleRate)
        }
        return synthesise(voices[index], sampleRate: sampleRate)
    }

    /// Synthesises the impulse response for a model name (case-insensitive).
    public static func impulseResponse(named name: String, sampleRate: Double) -> [Float]? {
        guard let index = models.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { return nil }
        return impulseResponse(at: index, sampleRate: sampleRate)
    }

    /// Prepared kernels shared by every chain at a given sample rate.
    static func kernels(sampleRate: Double) -> [IRKernel] {
        let key = Int(sampleRate.rounded())
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = kernelCache[key] { return cached }

        let rate = Double(key)
        let prepared = voices.indices.map { index in
            IRKernel(
                impulse: impulseResponse(at: index, sampleRate: rate),
                blockSize: IRConvolver.blockSize
            )
        }
        kernelCache[key] = prepared
        return prepared
    }

    private static let cacheLock = NSLock()
    private static var kernelCache: [Int: [IRKernel]] = [:]

    // MARK: - Synthesis

    private static func synthesise(_ voice: Voice, sampleRate: Double) -> [Float] {
        let fs = max(8_000, sampleRate)
        let count = min(4_096, max(512, Int(0.050 * fs)))

        var rng = SplitMix64(seed: voice.seed)
        var excitation = [Double](repeating: 0, count: count)

        // Close-mic arrival plus a handful of strong early reflections. Their
        // delays create the comb colour that makes a cab sound like a cab.
        let direct = max(0, Int((0.00010 + voice.micDelayMS * 0.001) * fs))
        if direct < count { excitation[direct] += 1 }

        let reflectionDelays: [(Double, Double)] = [
            (0.00031, -0.55), (0.00067, 0.38), (0.00103, -0.26),
            (0.00151, 0.18), (0.00221, -0.12)
        ]
        for (delay, gain) in reflectionDelays {
            let index = direct + Int(delay * fs)
            if index < count {
                excitation[index] += gain * voice.reflection
            }
        }

        // Cone body: a few milliseconds of filtered noise gives the IR its
        // grain instead of the sterile sound of pure sine resonances.
        var bodyLowPass = 0.0
        let bodyCount = min(count, Int(0.012 * fs))
        for index in 0..<bodyCount {
            let time = Double(index) / fs
            let noise = rng.nextDouble() * 2 - 1
            bodyLowPass = bodyLowPass * 0.72 + noise * 0.28
            let envelope = exp(-time / (0.004 + voice.bodyDecayMS * 0.001))
            excitation[index] += bodyLowPass * envelope * 0.15
        }

        // Diffuse tail. Short for a close-miked cab, longer for a big one.
        var tailLowPass = 0.0
        for index in 0..<count {
            let time = Double(index) / fs
            let noise = rng.nextDouble() * 2 - 1
            tailLowPass = tailLowPass * 0.86 + noise * 0.14
            let envelope = exp(-time / (0.012 + voice.tailDecayMS * 0.001))
            excitation[index] += tailLowPass * envelope * 0.035
        }

        // Speaker + cabinet + microphone response.
        let lowCut = BiquadDesign.coefficients(
            shape: .highPass, frequency: voice.lowCutHz, gainDB: 0, q: 0.707, sampleRate: fs
        )
        let highCut = BiquadDesign.coefficients(
            shape: .lowPass, frequency: voice.highCutHz, gainDB: 0, q: 0.707, sampleRate: fs
        )
        let lowPeak = BiquadDesign.coefficients(
            shape: .peak, frequency: voice.lowHz, gainDB: voice.lowGainDB, q: voice.lowQ, sampleRate: fs
        )
        let midPeak = BiquadDesign.coefficients(
            shape: .peak, frequency: voice.midHz, gainDB: voice.midGainDB, q: voice.midQ, sampleRate: fs
        )
        let presencePeak = BiquadDesign.coefficients(
            shape: .peak, frequency: voice.presenceHz, gainDB: voice.presenceGainDB,
            q: voice.presenceQ, sampleRate: fs
        )
        let brightness = BiquadDesign.coefficients(
            shape: .highShelf, frequency: 5_500, gainDB: voice.brightnessDB, q: 0.7, sampleRate: fs
        )

        var highPass1 = BiquadState()
        var highPass2 = BiquadState()
        var lowPass1 = BiquadState()
        var lowPass2 = BiquadState()
        var lowState = BiquadState()
        var midState = BiquadState()
        var presenceState = BiquadState()
        var brightnessState = BiquadState()

        var response = [Double](repeating: 0, count: count)
        for index in 0..<count {
            var sample = excitation[index]
            sample = highPass1.process(sample, lowCut)
            sample = highPass2.process(sample, lowCut)
            sample = lowState.process(sample, lowPeak)
            sample = midState.process(sample, midPeak)
            sample = presenceState.process(sample, presencePeak)
            sample = brightnessState.process(sample, brightness)
            sample = lowPass1.process(sample, highCut)
            sample = lowPass2.process(sample, highCut)
            response[index] = sample
        }

        // Taper the last 64 samples so truncation cannot click.
        let fadeCount = min(64, count)
        for index in 0..<fadeCount {
            let position = Double(index) / Double(fadeCount)
            response[count - fadeCount + index] *= 0.5 * (1 + cos(Double.pi * position))
        }

        // Energy-normalise so every cabinet loads at a comparable level.
        var energy = 0.0
        for sample in response { energy += sample * sample }
        var scale = energy > 1e-12 ? 1 / sqrt(energy) : 0
        var peak = 0.0
        for sample in response { peak = max(peak, abs(sample)) }
        if peak * scale > 0.95 { scale = 0.95 / max(peak, 1e-9) }

        return response.map { Float($0 * scale) }
    }
}

/// Tiny deterministic generator. Stable across launches and platforms, which
/// keeps presets and tests reproducible.
private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
