//  main.swift
//  GtrBoardSelfTest
//
//  Standalone DSP and preset self-test. Runs without XCTest (Command Line
//  Tools only) and is intentionally brute-force: it renders every factory
//  preset, checks numerical stability, validates delay/reverb timing, and
//  measures throughput on a release build.

import Foundation
import BoardCore

// MARK: - Harness

var checks = 0
var failures = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(message)")
    }
}

func expectClose(_ value: Double, _ expected: Double, _ tolerance: Double, _ message: String) {
    expect(abs(value - expected) <= tolerance, "\(message): got \(value), expected \(expected) ± \(tolerance)")
}

func expectFinite(_ values: [Double], _ message: String) {
    expect(values.allSatisfy { $0.isFinite }, "\(message): non-finite sample found")
}

func rms(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sum = values.reduce(0) { $0 + $1 * $1 }
    return sqrt(sum / Double(values.count))
}

func peak(_ values: [Double]) -> Double {
    values.reduce(0) { max($0, abs($1)) }
}

func sine(frequency: Double, amplitude: Double, seconds: Double, sampleRate: Double = 48_000) -> [Double] {
    let count = Int(seconds * sampleRate)
    return (0..<count).map { amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate) }
}

/// Decaying harmonic note used for factory-preset loudness calibration.
func guitarPluck(frequency: Double, amplitude: Double, seconds: Double, sampleRate: Double = 48_000) -> [Double] {
    let count = Int(seconds * sampleRate)
    var values = [Double](repeating: 0, count: count)
    var maximum = 0.0
    for index in 0..<count {
        let time = Double(index) / sampleRate
        let envelope = exp(-time * 3.2)
        var sample = 0.0
        for harmonic in 1...9 {
            sample += sin(2 * .pi * frequency * Double(harmonic) * time) / Double(harmonic)
        }
        let value = sample * envelope
        values[index] = value
        maximum = max(maximum, abs(value))
    }
    let gain = amplitude / max(maximum, 1e-9)
    return values.map { $0 * gain }
}

@discardableResult
func render(
    _ processor: BoardProcessor,
    left inputLeft: [Double],
    right inputRight: [Double]? = nil,
    blockSize: Int = 128
) -> (left: [Double], right: [Double]) {
    let right = inputRight ?? inputLeft
    var outLeft = inputLeft
    var outRight = right
    let frames = outLeft.count
    outLeft.withUnsafeMutableBufferPointer { leftBuffer in
        outRight.withUnsafeMutableBufferPointer { rightBuffer in
            var offset = 0
            while offset < frames {
                let count = min(blockSize, frames - offset)
                processor.process(
                    left: leftBuffer.baseAddress!.advanced(by: offset),
                    right: rightBuffer.baseAddress!.advanced(by: offset),
                    frames: count
                )
                offset += count
            }
        }
    }
    return (outLeft, outRight)
}

/// Renders a buffer while switching from the processor's current preset to
/// `second` at `switchFrame`, using the real public API.
func renderWithPresetSwitch(
    _ processor: BoardProcessor,
    input: [Double],
    switchFrame: Int,
    second: BoardSettings,
    blockSize: Int = 128
) -> [Double] {
    var left = input
    var right = input
    left.withUnsafeMutableBufferPointer { leftBuffer in
        right.withUnsafeMutableBufferPointer { rightBuffer in
            var offset = 0
            var switched = false
            while offset < leftBuffer.count {
                if !switched, offset >= switchFrame {
                    processor.update(settings: second, transition: true)
                    // A second, immediate snapshot must not cancel the duck.
                    processor.update(settings: second, transition: false)
                    switched = true
                }
                let count = min(blockSize, leftBuffer.count - offset)
                processor.process(
                    left: leftBuffer.baseAddress!.advanced(by: offset),
                    right: rightBuffer.baseAddress!.advanced(by: offset),
                    frames: count
                )
                offset += count
            }
        }
    }
    return left
}

/// All pedals off, flat EQ, limiter on; one pedal can then be enabled.
func bareBoard(master: Double = 0) -> BoardSettings {
    var settings = BoardSettings()
    settings.units = FXKind.allCases.map { kind in
        var unit = FXUnit(kind: kind)
        unit.enabled = false
        return unit
    }
    settings.graphicEQ = GraphicEQSettings(enabled: false, gains: Array(repeating: 0, count: 10))
    settings.masterVolume = master
    settings.limiter = true
    settings.bypass = false
    // Isolation: every effect test runs without the automatic guard unless it
    // is testing the guard itself.
    settings.feedbackGuard = false
    return settings
}

func enabling(_ kind: FXKind, in settings: BoardSettings, _ params: [String: Double]) -> BoardSettings {
    var copy = settings
    copy.units = copy.units.map { unit in
        guard unit.kind == kind else { return unit }
        var updated = unit
        updated.enabled = true
        for (key, value) in params { updated.setValue(value, for: key) }
        return updated
    }
    return copy
}


/// Closes an acoustic loop around the processor: a speaker feeds a microphone
/// that hears the output with a delay and a loss. Use a delay larger than the
/// block size so the block can be rendered in one go.
func renderAcousticLoop(
    settings: BoardSettings,
    seconds: Double,
    acousticGain: Double,
    delaySamples: Int,
    highPassHz: Double = 2_000,
    blockSize: Int = 128,
    sampleRate: Double = 48_000
) -> (output: [Double], processor: BoardProcessor) {
    let processor = makeProcessor(settings, sampleRate: sampleRate)
    // A real speaker/microphone path loses the low end; without this the
    // simulated loop howls at 100–300 Hz, which is not what the guard targets.
    let pathHighPass = BiquadDesign.coefficients(
        shape: .highPass, frequency: highPassHz, gainDB: 0, q: 0.707, sampleRate: sampleRate
    )
    var pathState = BiquadState()
    var pathState2 = BiquadState()
    let frames = Int(seconds * sampleRate)
    var output = [Double](repeating: 0, count: frames)
    let capacity = delaySamples + blockSize * 2
    var ring = [Double](repeating: 0, count: capacity)
    var writePosition = 0
    var offset = 0
    var seed: UInt64 = 0x1234_5678

    while offset < frames {
        let count = min(blockSize, frames - offset)
        var block = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let readPosition = (writePosition + index + capacity - delaySamples) % capacity
            var excitation = 0.0
            if offset + index < 2_400 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                excitation = 0.02 * Double(Int64(bitPattern: seed) >> 40) / Double(1 << 23)
            }
            var feedback = pathState.process(ring[readPosition], pathHighPass)
            feedback = pathState2.process(feedback, pathHighPass)
            block[index] = excitation + acousticGain * feedback
        }
        block.withUnsafeMutableBufferPointer { buffer in
            processor.process(
                left: buffer.baseAddress!,
                right: buffer.baseAddress!,
                frames: count
            )
        }
        for index in 0..<count {
            output[offset + index] = block[index]
            ring[(writePosition + index) % capacity] = block[index]
        }
        writePosition = (writePosition + count) % capacity
        offset += count
    }
    return (output, processor)
}

func makeProcessor(_ settings: BoardSettings, sampleRate: Double = 48_000) -> BoardProcessor {
    let processor = BoardProcessor()
    processor.prepare(sampleRate: sampleRate, maxFrames: 256)
    processor.update(settings: settings)
    return processor
}

/// Plain time-domain convolution used as the reference for the partitioned
/// convolver. Deliberately naive: it is the ground truth, not the product.
func directConvolve(_ input: [Double], _ impulse: [Float]) -> [Double] {
    guard !input.isEmpty, !impulse.isEmpty else { return [] }
    var output = [Double](repeating: 0, count: input.count + impulse.count - 1)
    for index in input.indices {
        let sample = input[index]
        guard sample != 0 else { continue }
        for tap in impulse.indices {
            output[index + tap] += sample * Double(impulse[tap])
        }
    }
    return output
}

/// Lag that best aligns `candidate` with `reference`, searched up to 256
/// samples. Used to account for the convolver's one-block pipeline.
func bestAlignment(_ candidate: [Double], _ reference: [Double]) -> Int {
    var bestLag = 0
    var bestScore = -Double.infinity
    for lag in 0...256 {
        var dot = 0.0
        var candidateEnergy = 0.0
        var referenceEnergy = 0.0
        var index = 0
        while index + lag < candidate.count, index < reference.count {
            dot += candidate[index + lag] * reference[index]
            candidateEnergy += candidate[index + lag] * candidate[index + lag]
            referenceEnergy += reference[index] * reference[index]
            index += 1
        }
        let score = dot / sqrt(max(candidateEnergy * referenceEnergy, 1e-12))
        if score > bestScore {
            bestScore = score
            bestLag = lag
        }
    }
    return bestLag
}

/// Brightness proxy for an impulse response: zero crossings per sample.
func zeroCrossingRate(_ samples: [Float]) -> Double {
    guard samples.count > 1 else { return 0 }
    var crossings = 0
    for index in 1..<samples.count where (samples[index] >= 0) != (samples[index - 1] >= 0) {
        crossings += 1
    }
    return Double(crossings) / Double(samples.count)
}

/// Linearly growing tone: the envelope of an acoustic feedback build-up.
func growingTone(
    frequency: Double,
    from start: Double,
    to end: Double,
    seconds: Double,
    sampleRate: Double = 48_000
) -> [Double] {
    let count = Int(seconds * sampleRate)
    return (0..<count).map { index in
        let position = Double(index) / Double(max(count - 1, 1))
        let amplitude = start + (end - start) * position
        return amplitude * sin(2 * .pi * frequency * Double(index) / sampleRate)
    }
}

/// Minimal RIFF/WAVE builder for the importer tests.
func wavData(
    samples: [Double],
    sampleRate: Int,
    channels: Int,
    bits: Int,
    floating: Bool
) -> Data {
    var payload = Data()
    func appendSample(_ sample: Double) {
        let clamped = min(max(sample, -1), 1)
        if floating {
            if bits == 32 {
                var value = Float(clamped).bitPattern.littleEndian
                withUnsafeBytes(of: &value) { payload.append(contentsOf: $0) }
            } else {
                var value = clamped.bitPattern.littleEndian
                withUnsafeBytes(of: &value) { payload.append(contentsOf: $0) }
            }
        } else if bits == 16 {
            let value = Int16((clamped * 32_767).rounded())
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { payload.append(contentsOf: $0) }
        } else {
            let value = UInt32(bitPattern: Int32((clamped * 8_388_607).rounded()))
            payload.append(UInt8(value & 0xFF))
            payload.append(UInt8((value >> 8) & 0xFF))
            payload.append(UInt8((value >> 16) & 0xFF))
        }
    }
    for sample in samples {
        for _ in 0..<channels {
            appendSample(sample)
        }
    }

    var wav = Data()
    func append32(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
    }

    let byteRate = UInt32(sampleRate * channels * bits / 8)
    let blockAlign = UInt16(channels * bits / 8)
    wav.append(contentsOf: Array("RIFF".utf8))
    append32(UInt32(36 + payload.count))
    wav.append(contentsOf: Array("WAVEfmt ".utf8))
    append32(16)
    append16(floating ? 3 : 1)
    append16(UInt16(channels))
    append32(UInt32(sampleRate))
    append32(byteRate)
    append16(blockAlign)
    append16(UInt16(bits))
    wav.append(contentsOf: Array("data".utf8))
    append32(UInt32(payload.count))
    wav.append(payload)
    return wav
}



// MARK: - Diagnostic WAV dump

func writeWAV(_ samples: [Double], sampleRate: Double, to path: String) {
    func append32(_ data: inout Data, _ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    func append16(_ data: inout Data, _ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    var payload = Data()
    for sample in samples {
        let clamped = min(max(sample, -1), 1)
        let value = Int16((clamped * 32_767).rounded())
        append16(&payload, UInt16(bitPattern: value))
    }

    var wav = Data()
    wav.append(contentsOf: Array("RIFF".utf8))
    append32(&wav, UInt32(36 + payload.count))
    wav.append(contentsOf: Array("WAVEfmt ".utf8))
    append32(&wav, 16)
    append16(&wav, 1)
    append16(&wav, 1)
    append32(&wav, UInt32(sampleRate))
    append32(&wav, UInt32(sampleRate) * 2)
    append16(&wav, 2)
    append16(&wav, 16)
    wav.append(contentsOf: Array("data".utf8))
    append32(&wav, UInt32(payload.count))
    wav.append(payload)
    try? wav.write(to: URL(fileURLWithPath: path))
}

// MARK: - Catalogue

print("▸ Catalogue")
expect(FXKind.allCases.count == 15, "fifteen effect kinds")
expect(FXKind.defaultChain.count == 15, "default chain contains every kind")
expect(Set(FXKind.defaultChain).count == 15, "default chain has no duplicates")

for kind in FXKind.allCases {
    let descriptor = kind.descriptor
    expect(!descriptor.parameters.isEmpty, "\(kind.rawValue) has parameters")
    expect(descriptor.defaultEnabled == descriptor.defaultEnabled, "\(kind.rawValue) descriptor is stable")
    let ids = descriptor.parameters.map(\.id)
    expect(Set(ids).count == ids.count, "\(kind.rawValue) parameter ids are unique")
    expect(descriptor.parameters.count <= BoardProcessor.maxParams, "\(kind.rawValue) fits the snapshot block")

    for parameter in descriptor.parameters {
        expect(parameter.minValue < parameter.maxValue, "\(kind.rawValue).\(parameter.id) has a valid range")
        expect(parameter.defaultValue >= parameter.minValue && parameter.defaultValue <= parameter.maxValue,
               "\(kind.rawValue).\(parameter.id) default is inside the range")
        let normalized = parameter.normalized(parameter.defaultValue)
        let back = parameter.value(atNormalized: normalized)
        expect(abs(back - parameter.defaultValue) < 0.02,
               "\(kind.rawValue).\(parameter.id) normalisation round-trips")
    }

    var unit = FXUnit(kind: kind)
    expect(unit.isDefault, "\(kind.rawValue) starts at defaults")
    let values = unit.orderedValues
    expect(values.count == descriptor.parameters.count, "\(kind.rawValue) ordered values match descriptor")
    unit.setValue(-100_000, for: descriptor.parameters[0].id)
    expect(unit.value(descriptor.parameters[0].id) == descriptor.parameters[0].minValue,
           "\(kind.rawValue) clamps below minimum")
    unit.setValue(100_000, for: descriptor.parameters[0].id)
    expect(unit.value(descriptor.parameters[0].id) == descriptor.parameters[0].maxValue,
           "\(kind.rawValue) clamps above maximum")
}

// MARK: - Board + presets

print("▸ Board and presets")
let defaultBoard = BoardSettings.defaultBoard().sanitized()
expect(defaultBoard.units.count == 15, "default board contains every pedal")
expect(Set(defaultBoard.units.map(\.kind)).count == 15, "default board has one unit per kind")
expect(defaultBoard.masterVolume >= BoardSettings.masterRange.lowerBound, "master volume is in range")

var shuffled = defaultBoard
shuffled.units.shuffle()
shuffled.units.append(FXUnit(kind: .delay))
let cleaned = shuffled.sanitized()
expect(cleaned.units.count == 15, "sanitising removes duplicates and restores missing kinds")
expect(Set(cleaned.units.map(\.kind)).count == 15, "sanitised board still has every kind")

expect(BuiltInPresets.all.count >= 18, "at least eighteen factory presets")
var presetIDs = Set<String>()
for preset in BuiltInPresets.all {
    expect(!preset.name.isEmpty, "preset has a name")
    expect(preset.isBuiltIn, "\(preset.name) is marked built-in")
    expect(presetIDs.insert(preset.id).inserted, "\(preset.name) id is unique")
    expect(preset.settings.units.count == 15, "\(preset.name) has a full chain")
    expect(preset.settings.sanitized() == preset.settings, "\(preset.name) is already sanitised")
    expect(!preset.gear.isEmpty, "\(preset.name) documents its gear")
    expect(!preset.notes.isEmpty, "\(preset.name) has notes")

    do {
        let data = try PresetDocument(preset: preset).encoded()
        let decoded = try PresetDocument.decode(data)
        expect(decoded.name == preset.name, "\(preset.name) JSON round-trip keeps the name")
        expect(decoded.settings == preset.settings, "\(preset.name) JSON round-trip keeps the board")
    } catch {
        expect(false, "\(preset.name) JSON round-trip failed: \(error)")
    }
}

do {
    let bare = try PresetCodec.encoder.encode(BuiltInPresets.all[0])
    let decoded = try PresetDocument.decode(bare)
    expect(decoded.name == BuiltInPresets.all[0].name, "bare preset JSON is accepted")
} catch {
    expect(false, "bare preset JSON decode failed: \(error)")
}

do {
    _ = try PresetDocument.decode(Data("not json".utf8))
    expect(false, "garbage preset data should throw")
} catch {
    expect(true, "garbage preset data throws")
}

// MARK: - Preset store

print("▸ Preset store")
let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("gtrboard-tests-\(UUID().uuidString)", isDirectory: true)
let store = PresetStore(directory: temporaryRoot)
defer { try? FileManager.default.removeItem(at: temporaryRoot) }
_ = store.ensureDirectory()

var userPreset = BuiltInPresets.all[0]
userPreset.id = UUID().uuidString
userPreset.name = "My Test Rig"
userPreset.isBuiltIn = false
userPreset.gear = "Test gear"
do {
    let url = try store.save(userPreset)
    expect(FileManager.default.fileExists(atPath: url.path), "save writes a .gtrpreset file")
    let loaded = store.loadUserPresets()
    expect(loaded.count == 1, "load finds the saved preset")
    expect(loaded.first?.name == "My Test Rig", "loaded preset keeps its name")
    expect(loaded.first?.isBuiltIn == false, "loaded preset is a user preset")

    let exportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("gtrboard-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: exportDirectory) }
    let exportURL = exportDirectory.appendingPathComponent("Exported.gtrpreset")
    try store.export(userPreset, to: exportURL)
    expect(FileManager.default.fileExists(atPath: exportURL.path), "export writes a shareable file")

    let imported = try store.importPreset(from: exportURL)
    expect(imported.name == userPreset.name, "import keeps the name")
    expect(imported.id != userPreset.id, "import assigns a fresh identity")
    expect(imported.settings == userPreset.settings, "import keeps the board")

    try store.delete(userPreset)
    expect(store.loadUserPresets().isEmpty, "delete removes the preset")
} catch {
    expect(false, "preset store failed: \(error)")
}

// MARK: - Preset loudness

print("▸ Preset loudness")
do {
    let rate = 48_000.0
    let input = guitarPluck(frequency: 110, amplitude: 0.22, seconds: 1.8)
    let target = 0.075
    var levels: [(String, Double)] = []
    for preset in BuiltInPresets.all {
        let output = render(makeProcessor(preset.settings), left: input)
        let start = Int(rate * 0.15)
        let end = min(output.left.count, Int(rate * 1.35))
        levels.append((preset.name, rms(Array(output.left[start..<end]))))
    }
    let decibels = levels.map { 20 * log10(max($0.1, 1e-9) / target) }
    let spread = (decibels.max() ?? 0) - (decibels.min() ?? 0)
    print(String(format: "  • level spread: %.1f dB", spread))
    for (entry, delta) in zip(levels, decibels) {
        expect(abs(delta) < 4.0, "\(entry.0) is level-calibrated (got \(String(format: "%+.1f", delta)) dB)")
    }
}

// MARK: - EQ math

print("▸ EQ math")
let peakCoefficients = BiquadDesign.coefficients(
    shape: .peak, frequency: 1_000, gainDB: 6, q: 1.41, sampleRate: 48_000
)
expectClose(peakCoefficients.magnitudeDB(at: 1_000, sampleRate: 48_000), 6, 0.15, "peak biquad hits +6 dB")

var eqSettings = GraphicEQSettings()
eqSettings.gains[5] = 6
expectClose(eqSettings.responseDB(at: 1_000, sampleRate: 48_000), 6, 0.5, "graphic EQ responds at 1 kHz")
expectClose(GraphicEQSettings.flat.responseDB(at: 1_000, sampleRate: 48_000), 0, 0.001, "flat EQ is transparent")

// MARK: - Processor: stability and levels

print("▸ Processor stability")
let sampleRate = 48_000.0
let sineInput = sine(frequency: 220, amplitude: 0.25, seconds: 0.7)

for preset in BuiltInPresets.all {
    let processor = makeProcessor(preset.settings)
    let output = render(processor, left: sineInput)
    expectFinite(output.left, "\(preset.name) output is finite")
    expectFinite(output.right, "\(preset.name) right output is finite")
    expect(peak(output.left) <= 1.0001, "\(preset.name) stays below full scale")
    expect(rms(output.left) > 0.0005, "\(preset.name) produces audio")
}

let silent = [Double](repeating: 0, count: Int(sampleRate * 0.4))
let cleanProcessor = makeProcessor(BoardSettings.defaultBoard())
let silenceOut = render(cleanProcessor, left: silent)
expectFinite(silenceOut.left, "default board stays finite on silence")

// Bypass should return the input almost untouched after the crossfade.
do {
    var settings = bareBoard(master: -6)
    settings.bypass = true
    let processor = makeProcessor(settings)
    let input = sine(frequency: 440, amplitude: 0.3, seconds: 0.5)
    let output = render(processor, left: input)
    let tail = Array(output.left.suffix(4_000))
    let inputTail = Array(input.suffix(4_000))
    expectClose(rms(tail), rms(inputTail), 0.01, "bypass passes the dry signal")
}

// Master volume at -6 dB halves the amplitude on an otherwise empty board.
do {
    let processor = makeProcessor(bareBoard(master: -6))
    let input = sine(frequency: 440, amplitude: 0.3, seconds: 0.5)
    let output = render(processor, left: input)
    let tailOut = Array(output.left.suffix(8_000))
    let tailIn = Array(input.suffix(8_000))
    expectClose(rms(tailOut) / rms(tailIn), 0.501, 0.02, "master volume -6 dB is a half-gain stage")
}

// Limiter catches a signal that would otherwise clip.
do {
    var settings = bareBoard(master: 12)
    settings.limiter = true
    let processor = makeProcessor(settings)
    let input = sine(frequency: 110, amplitude: 0.9, seconds: 0.6)
    let output = render(processor, left: input)
    expect(peak(output.left) <= 0.9601, "limiter holds the output below full scale")
}

// MARK: - Individual effects

print("▸ Preset transition")
do {
    guard let clean = BuiltInPresets.all.first(where: { $0.name == "Studio Clean" }),
          let metal = BuiltInPresets.all.first(where: { $0.name == "Enter Sandman" }) else {
        expect(false, "transition test presets are present")
        exit(1)
    }

    let processor = BoardProcessor()
    processor.prepare(sampleRate: 48_000, maxFrames: 256)
    processor.update(settings: metal.settings)

    let input = sine(frequency: 220, amplitude: 0.2, seconds: 0.6)
    let switchFrame = Int(48_000 * 0.2)
    let output = renderWithPresetSwitch(
        processor,
        input: input,
        switchFrame: switchFrame,
        second: clean.settings
    )

    expectFinite(output, "preset transition output is finite")
    expect(peak(output) <= 1.0001, "preset transition stays in range")

    let around = Array(output[max(0, switchFrame - 256)..<min(output.count, switchFrame + 4_096)])
    let maxDelta = zip(around, around.dropFirst()).map { abs($0 - $1) }.max() ?? 0
    expect(maxDelta < 0.1, "preset transition has no click (max delta \(maxDelta))")

    var minWindowRMS = 1.0
    var windowStart = switchFrame
    while windowStart + 96 < output.count, windowStart < switchFrame + 2_400 {
        minWindowRMS = min(minWindowRMS, rms(Array(output[windowStart..<(windowStart + 96)])))
        windowStart += 96
    }
    let beforeRMS = rms(Array(output[max(0, switchFrame - 2_400)..<switchFrame]))
    let afterRMS = rms(Array(output[(switchFrame + 3_000)..<min(output.count, switchFrame + 9_600)]))
    print(String(format: "  • dirty→clean RMS before=%.3f min=%.3f after=%.3f", beforeRMS, minWindowRMS, afterRMS))
    expect(minWindowRMS > 0.005, "preset crossfade has no silence gap (min RMS \(minWindowRMS))")

    let after = Array(output[(switchFrame + 3_000)..<min(output.count, switchFrame + 9_600)])
    expect(rms(after) > 0.01, "new preset fades back in")

    // The same transition between two clean presets makes any discontinuity
    // in the fade itself visible: the waveform has no hard clipping to hide it.
    if let sultans = BuiltInPresets.all.first(where: { $0.name == "Sultans of Swing" }) {
        let cleanProcessor = BoardProcessor()
        cleanProcessor.prepare(sampleRate: 48_000, maxFrames: 256)
        cleanProcessor.update(settings: clean.settings)
        let cleanOutput = renderWithPresetSwitch(
            cleanProcessor,
            input: input,
            switchFrame: switchFrame,
            second: sultans.settings
        )
        let cleanAround = Array(cleanOutput[max(0, switchFrame - 256)..<min(cleanOutput.count, switchFrame + 6_000)])
        let cleanDelta = zip(cleanAround, cleanAround.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        expect(cleanDelta < 0.02, "clean-to-clean preset transition is smooth")
    }
}

print("▸ EQ across preset switch")
do {
    var flat = bareBoard(master: 0)
    flat.limiter = false
    flat.graphicEQ = GraphicEQSettings(enabled: true, gains: Array(repeating: 0, count: 10))
    var boosted = flat
    boosted.graphicEQ.gains[5] = 12 // 1 kHz band

    let processor = BoardProcessor()
    processor.prepare(sampleRate: 48_000, maxFrames: 256)
    processor.update(settings: flat)
    let input = sine(frequency: 1_000, amplitude: 0.1, seconds: 0.4)
    let switched = renderWithPresetSwitch(
        processor,
        input: input,
        switchFrame: Int(48_000 * 0.1),
        second: boosted
    )
    let settled = Array(switched[Int(48_000 * 0.25)..<Int(48_000 * 0.40)])
    let reference = Array(input[Int(48_000 * 0.25)..<Int(48_000 * 0.40)])
    let gain = rms(settled) / max(rms(reference), 1e-9)
    print(String(format: "  • 1 kHz band after switch: gain %.2fx (expect ~4)", gain))
    expect(gain > 2.5, "graphic EQ survives a preset crossfade")
}

print("▸ Dynamics")
do {
    var settings = bareBoard()
    settings = enabling(.gate, in: settings, ["threshold": -40, "decay": 60, "range": 80])
    let processor = makeProcessor(settings)
    let quiet = [Double](repeating: 0.0001, count: Int(sampleRate * 0.6))
    let gateOut = render(processor, left: quiet)
    expect(rms(gateOut.left) < 0.00005, "gate closes on a quiet signal")
    let loud = sine(frequency: 220, amplitude: 0.4, seconds: 0.4)
    let pass = render(makeProcessor(settings), left: loud)
    expect(rms(pass.left) > 0.1, "gate opens on a loud signal")
}

do {
    var settings = bareBoard()
    settings = enabling(.compressor, in: settings, [
        "threshold": -30, "ratio": 10, "attack": 5, "release": 100, "makeup": 0
    ])
    let processor = makeProcessor(settings)
    let input = sine(frequency: 220, amplitude: 0.5, seconds: 1.0)
    let output = render(processor, left: input)
    let tailOut = Array(output.left.suffix(20_000))
    let tailIn = Array(input.suffix(20_000))
    expect(rms(tailOut) < rms(tailIn) * 0.45, "compressor reduces a hot signal")
}

print("▸ Drives and amp")
for kind in [FXKind.overdrive, .distortion, .fuzz] {
    var settings = bareBoard()
    switch kind {
    case .overdrive:
        settings = enabling(kind, in: settings, ["drive": 30, "tone": 0.5, "level": 0, "mid": 0.5])
    case .distortion:
        settings = enabling(kind, in: settings, ["gain": 36, "tone": 0.5, "level": 0, "edge": 0.6])
    default:
        settings = enabling(kind, in: settings, ["sustain": 0.9, "tone": 0.5, "level": 0, "bias": 0.5])
    }
    let processor = makeProcessor(settings)
    let input = sine(frequency: 220, amplitude: 0.2, seconds: 0.5)
    let output = render(processor, left: input)
    expectFinite(output.left, "\(kind.rawValue) is finite")
    expect(peak(output.left) <= 1.0001, "\(kind.rawValue) respects full scale")
    expect(rms(output.left) > 0.05, "\(kind.rawValue) makes sound")
}

do {
    var settings = bareBoard()
    settings = enabling(.amp, in: settings, [
        "gain": 30, "bass": 2, "mid": -2, "treble": 3, "presence": 5, "master": -6, "voicing": 3
    ])
    let processor = makeProcessor(settings)
    let input = sine(frequency: 110, amplitude: 0.15, seconds: 0.6)
    let output = render(processor, left: input)
    expectFinite(output.left, "amp is finite")
    expect(rms(output.left) > 0.08, "high-gain amp has healthy level")
    expect(peak(output.left) > 0.25, "high-gain amp reaches a useful peak")
    expect(peak(output.left) <= 1.0001, "amp respects full scale")
}

print("▸ Time effects")
do {
    var settings = bareBoard()
    settings = enabling(.delay, in: settings, [
        "time": 100, "feedback": 0, "mix": 1, "tone": 1, "mode": 0
    ])
    let processor = makeProcessor(settings)
    let count = Int(sampleRate * 0.3)
    var impulse = [Double](repeating: 0, count: count)
    impulse[100] = 0.5
    let output = render(processor, left: impulse, blockSize: 64)
    var bestIndex = 0
    var bestValue = 0.0
    for index in 200..<output.left.count {
        if abs(output.left[index]) > bestValue {
            bestValue = abs(output.left[index])
            bestIndex = index
        }
    }
    expectClose(Double(bestIndex - 100), 4_800, 200, "delay repeats at 100 ms")
    expect(bestValue > 0.2, "delay repeat has level")
}

do {
    var settings = bareBoard()
    settings = enabling(.reverb, in: settings, [
        "size": 0.85, "damping": 0.4, "mix": 1, "predelay": 10, "mode": 1
    ])
    let processor = makeProcessor(settings)
    let count = Int(sampleRate * 1.2)
    var impulse = [Double](repeating: 0, count: count)
    impulse[0] = 0.5
    let output = render(processor, left: impulse, blockSize: 128)
    let early = Array(output.left[0..<2_000])
    let tail = Array(output.left[Int(0.2 * sampleRate)..<Int(0.9 * sampleRate)])
    expectFinite(output.left, "reverb is finite")
    expect(rms(tail) > 0.00005, "reverb has a decaying tail")
    expect(rms(tail) < rms(early) + 1, "reverb tail is not louder than the impulse")
}

print("▸ Modulation")
for kind in [FXKind.chorus, .flanger, .phaser, .tremolo] {
    var settings = bareBoard()
    switch kind {
    case .chorus:
        settings = enabling(kind, in: settings, ["rate": 1.2, "depth": 0.7, "mix": 0.6, "width": 0.8])
    case .flanger:
        settings = enabling(kind, in: settings, ["rate": 0.8, "depth": 0.7, "feedback": 0.5, "mix": 0.6, "manual": 3])
    case .phaser:
        settings = enabling(kind, in: settings, ["rate": 1.0, "depth": 0.7, "feedback": 0.4, "mix": 0.6, "stages": 1])
    default:
        settings = enabling(kind, in: settings, ["rate": 5, "depth": 0.8, "shape": 0, "stereo": 0])
    }
    let processor = makeProcessor(settings)
    let input = sine(frequency: 440, amplitude: 0.3, seconds: 0.6)
    let output = render(processor, left: input)
    expectFinite(output.left, "\(kind.rawValue) is finite")
    expect(rms(output.left) > 0.02, "\(kind.rawValue) makes sound")
    if kind == .tremolo {
        let window = 2_400
        var minimum = 1.0
        var maximum = 0.0
        var index = 4_800
        while index + window < output.left.count {
            let value = rms(Array(output.left[index..<(index + window)]))
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            index += window
        }
        expect(maximum > minimum * 1.5, "tremolo modulates amplitude")
    }
}

// Silence is the strictest test for self-oscillation and block-boundary
// artefacts: any energy here is generated by the DSP itself.
do {
    let processor = makeProcessor(BoardSettings.defaultBoard())
    let silence = [Double](repeating: 0, count: Int(sampleRate * 2))
    let output = render(processor, left: silence)
    expect(peak(output.left) == 0, "default board is bit-silent on silence")
    expect(peak(output.right) == 0, "default board right channel is silent")
}

// A clean amp must preserve the shape of a sine. The RMS/peak ratio catches
// the old buffer-rate spike bug, which also made the amp sound farty.
do {
    var settings = bareBoard(master: 0)
    settings.limiter = false
    settings.units = settings.units.map { unit in
        guard unit.kind == .amp else { return unit }
        var amp = unit
        amp.enabled = true
        amp.setValue(0, for: "gain")
        amp.setValue(0, for: "voicing")
        amp.setValue(0, for: "bass")
        amp.setValue(0, for: "mid")
        amp.setValue(0, for: "treble")
        amp.setValue(0, for: "presence")
        amp.setValue(0, for: "master")
        return amp
    }
    let processor = makeProcessor(settings)
    let input = sine(frequency: 220, amplitude: 0.2, seconds: 1.0)
    let output = render(processor, left: input)
    let settled = Array(output.left.suffix(Int(sampleRate * 0.7)))
    let ratio = rms(settled) / max(peak(settled), 1e-9)
    expect(ratio > 0.65, "clean amp keeps a sine's crest factor (got \(ratio))")
    expect(ratio < 0.75, "clean amp does not add spurious peaks (got \(ratio))")
}


// MARK: - Impulse responses

print("▸ IR library")
do {
    let models = CabinetIRLibrary.models
    expect(models.count >= 12, "library ships at least twelve cabs (\(models.count))")
    expect(Set(models.map(\.name)).count == models.count, "cab names are unique")
    expect(CabinetIRLibrary.presetNames.count == models.count + 1, "one custom slot after the built-ins")
    expect(CabinetIRLibrary.presetNames.last == CabinetIRLibrary.customName, "custom slot is last")

    var responses: [[Float]] = []
    for (index, model) in models.enumerated() {
        let ir = CabinetIRLibrary.impulseResponse(at: index, sampleRate: sampleRate)
        responses.append(ir)
        expect(ir.count >= 1_024, "\(model.name) has a usable length")
        expect(ir.allSatisfy { $0.isFinite }, "\(model.name) is finite")
        var energy = 0.0
        for sample in ir { energy += Double(sample) * Double(sample) }
        expect(abs(energy - 1) < 0.05, "\(model.name) is energy-normalised (E=\(String(format: "%.3f", energy)))")
        expect(ir.allSatisfy { abs($0) <= 0.96 }, "\(model.name) peaks below full scale")
    }

    expect(zip(responses, responses.dropFirst()).allSatisfy { left, right in
        zip(left, right).map { abs($0 - $1) }.max() ?? 0 > 0.01
    }, "every cab has its own response")

    if models.count > 7 {
        let bright = zeroCrossingRate(responses[6])   // ENGL
        let dark = zeroCrossingRate(responses[7])     // Orange
        expect(bright > dark, "bright cab is brighter than the doom cab")
    }
}

print("▸ IR convolution")
do {
    var seed: UInt64 = 0xDEAD_BEEF_1234_5678
    func noise() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(Int64(bitPattern: seed) >> 11) / Double(1 << 52)
    }

    let input = (0..<2_048).map { _ in noise() }
    var impulse = [Float](repeating: 0, count: 400)
    for index in impulse.indices { impulse[index] = Float(noise() * 0.1) }
    impulse[0] = 0.5
    impulse[17] = -0.25

    let convolver = IRConvolver(impulse: impulse)
    var output = input
    input.withUnsafeBufferPointer { source in
        output.withUnsafeMutableBufferPointer { destination in
            var offset = 0
            while offset < destination.count {
                let count = min(128, destination.count - offset)
                convolver.process(
                    input: source.baseAddress!.advanced(by: offset),
                    output: destination.baseAddress!.advanced(by: offset),
                    frames: count
                )
                offset += count
            }
        }
    }

    let reference = directConvolve(input, impulse)
    let lag = bestAlignment(output, reference)
    print("  • convolver pipeline lag: \(lag) samples")
    expect(lag <= 128, "convolver latency stays under two blocks")

    let limit = max(0, min(reference.count, output.count - lag))
    var error = 0.0
    var signal = 0.0
    for index in 0..<limit {
        let difference = output[index + lag] - reference[index]
        error += difference * difference
        signal += reference[index] * reference[index]
    }
    let relative = sqrt(error / max(signal, 1e-12))
    expect(relative < 0.01, "partitioned convolution matches direct convolution (rel \(String(format: "%.2e", relative)))")
}

print("▸ IR cabinet")
do {
    var settings = bareBoard(master: 0)
    settings.limiter = false
    settings = enabling(.ir, in: settings, [
        "model": 0, "mix": 1, "lowCut": 40, "highCut": 16_000, "level": 0
    ])
    let processor = makeProcessor(settings)
    let input = guitarPluck(frequency: 110, amplitude: 0.3, seconds: 1.0)
    let output = render(processor, left: input)
    expectFinite(output.left, "IR cabinet output is finite")
    expect(rms(output.left) > 0.01, "IR cabinet produces sound")
    expect(peak(output.left) <= 1.0001, "IR cabinet respects full scale")
    expect(processor.latencyFrames >= IRConvolver.latencyFrames,
           "IR pedal adds its latency to the report")
}

print("▸ IR preset crossfade and throughput")
do {
    guard let modern = BuiltInPresets.all.first(where: { $0.name == "Modern Metal IR" }),
          let djent = BuiltInPresets.all.first(where: { $0.name == "Djent IR" }) else {
        expect(false, "IR factory presets are present")
        exit(1)
    }

    let processor = BoardProcessor()
    processor.prepare(sampleRate: 48_000, maxFrames: 256)
    processor.update(settings: modern.settings)
    let input = sine(frequency: 220, amplitude: 0.2, seconds: 0.6)
    let output = renderWithPresetSwitch(
        processor,
        input: input,
        switchFrame: Int(48_000 * 0.2),
        second: djent.settings
    )
    expectFinite(output, "IR preset crossfade is finite")
    expect(peak(output) <= 1.0001, "IR preset crossfade stays in range")
    let around = Array(output[9_300..<11_000])
    let maximumDelta = zip(around, around.dropFirst()).map { abs($0 - $1) }.max() ?? 0
    expect(maximumDelta < 0.2, "IR preset crossfade has no click")

    let seconds = 3.0
    let count = Int(sampleRate * seconds)
    var tune = [Double](repeating: 0, count: count)
    for index in 0..<count {
        tune[index] = 0.12 * sin(2 * .pi * 196 * Double(index) / sampleRate)
    }
    var irThroughput = modern.settings
    irThroughput.feedbackGuard = false
    let started = Date()
    _ = render(makeProcessor(irThroughput), left: tune, blockSize: 128)
    let elapsed = Date().timeIntervalSince(started)
    let factor = seconds / max(elapsed, 1e-9)
    print(String(format: "  • IR board: %.1fs rendered in %.3fs (%.1fx realtime)", seconds, elapsed, factor))
    expect(factor > 2, "IR board renders faster than 2x realtime")
}

print("▸ Custom IR and live switching")
do {
    var custom = [Float](repeating: 0, count: 512)
    custom[0] = 0.8
    custom[10] = -0.3
    custom[37] = 0.12
    let file = ImpulseResponseFile(samples: custom, sampleRate: 48_000)

    var settings = bareBoard(master: 0)
    settings.limiter = false
    settings = enabling(.ir, in: settings, [
        "model": Double(CabinetIRLibrary.customIndex),
        "mix": 1, "lowCut": 40, "highCut": 16_000, "level": 0
    ])
    let processor = BoardProcessor()
    processor.setCustomImpulseResponse(samples: file.samples, sampleRate: file.sampleRate)
    processor.prepare(sampleRate: 48_000, maxFrames: 256)
    processor.update(settings: settings)
    let input = guitarPluck(frequency: 110, amplitude: 0.3, seconds: 0.8)
    let output = render(processor, left: input)
    expectFinite(output.left, "custom IR output is finite")
    expect(rms(output.left) > 0.01, "custom IR renders through the chain")

    // Switching models under a sustained note must fade, not click or blow up.
    var first = settings
    first = enabling(.ir, in: first, ["model": 0])
    var second = settings
    second = enabling(.ir, in: second, ["model": 6])
    let switcher = makeProcessor(first)
    let tone = sine(frequency: 220, amplitude: 0.2, seconds: 1.0)
    var switched = tone
    switched.withUnsafeMutableBufferPointer { buffer in
        tone.withUnsafeBufferPointer { source in
            var offset = 0
            while offset < buffer.count {
                if offset >= 24_000 {
                    switcher.update(settings: second)
                }
                let count = min(128, buffer.count - offset)
                switcher.process(
                    left: buffer.baseAddress!.advanced(by: offset),
                    right: buffer.baseAddress!.advanced(by: offset),
                    frames: count
                )
                offset += count
            }
        }
    }
    expectFinite(switched, "IR model switch output is finite")
    expect(peak(switched) <= 1.0001, "IR model switch stays in range")
    let around = Array(switched[23_800..<26_000])
    let maximumDelta = zip(around, around.dropFirst()).map { abs($0 - $1) }.max() ?? 0
    print(String(format: "  • IR switch max delta: %.4f", maximumDelta))
    expect(maximumDelta < 0.2, "IR model switch is click-free")
}

print("▸ IR import")
do {
    let tone = (0..<256).map { sin(2 * .pi * 100 * Double($0) / 48_000) * 0.5 }

    let pcm16 = wavData(samples: tone, sampleRate: 48_000, channels: 1, bits: 16, floating: false)
    do {
        let file = try ImpulseResponseFile.decode(pcm16)
        expect(file.channelCount == 1, "16-bit WAV reads one channel")
        expectClose(file.sampleRate, 48_000, 0.5, "16-bit WAV keeps its sample rate")
        expect(file.samples.count == tone.count, "16-bit WAV frame count is exact")
        expectClose(Double(file.samples[60]), tone[60], 0.001, "16-bit WAV sample decodes")
        let prepared = file.prepared(forSampleRate: 48_000, maxTaps: 8_192)
        var energy = 0.0
        for sample in prepared { energy += Double(sample) * Double(sample) }
        expect(abs(energy - 1) < 0.05, "imported IR is energy-normalised")
    } catch {
        expect(false, "16-bit WAV decode failed: \(error)")
    }

    let pcm24 = wavData(samples: tone, sampleRate: 44_100, channels: 2, bits: 24, floating: false)
    do {
        let file = try ImpulseResponseFile.decode(pcm24)
        expect(file.channelCount == 2, "24-bit stereo WAV reads two channels")
        expect(file.samples.count == tone.count, "stereo WAV is averaged to mono")
        let prepared = file.prepared(forSampleRate: 48_000, maxTaps: 8_192)
        expect(prepared.count > tone.count, "44.1 kHz IR is resampled to the session rate")
    } catch {
        expect(false, "24-bit WAV decode failed: \(error)")
    }

    let float32 = wavData(samples: tone, sampleRate: 96_000, channels: 1, bits: 32, floating: true)
    do {
        let file = try ImpulseResponseFile.decode(float32)
        expectClose(Double(file.samples[60]), tone[60], 0.001, "32-bit float WAV decodes")
    } catch {
        expect(false, "float WAV decode failed: \(error)")
    }

    do {
        _ = try ImpulseResponseFile.decode(Data("not a wav".utf8))
        expect(false, "garbage WAV should throw")
    } catch {
        expect(true, "garbage WAV throws")
    }
}

// MARK: - Feedback guard

print("▸ Feedback guard")
do {
    var settings = bareBoard(master: 0)
    settings.limiter = false
    settings.feedbackGuard = true
    let processor = makeProcessor(settings)
    let silence = [Double](repeating: 0, count: Int(sampleRate * 1.5))
    let output = render(processor, left: silence)
    expect(peak(output.left) == 0, "guard is bit-silent on silence")
    expect(processor.guardStatus.snapshot() == .idle, "guard stays idle on silence")
}

do {
    var guardedSettings = bareBoard(master: 0)
    guardedSettings.limiter = false
    guardedSettings.feedbackGuard = true
    var plainSettings = guardedSettings
    plainSettings.feedbackGuard = false

    let note = guitarPluck(frequency: 196, amplitude: 0.3, seconds: 1.6)
    let guardedProcessor = makeProcessor(guardedSettings)
    let guarded = render(guardedProcessor, left: note)
    let plain = render(makeProcessor(plainSettings), left: note)
    let tailStart = Int(sampleRate * 0.6)
    let guardedRMS = rms(Array(guarded.left[tailStart...]))
    let plainRMS = rms(Array(plain.left[tailStart...]))
    let status = guardedProcessor.guardStatus.snapshot()
    print(String(format: "  • decaying note: guarded %.4f / plain %.4f, muted %@",
                 guardedRMS, plainRMS, status.muted ? "yes" : "no"))
    expectClose(guardedRMS / max(plainRMS, 1e-9), 1, 0.05, "guard leaves a decaying guitar note alone")
    expect(!status.muted, "guard does not mute a decaying guitar note")
}

do {
    // A sustained musical note is stationary and loud too. The guard must not
    // mistake it for feedback just because the player holds a chord.
    guard let preset = BuiltInPresets.all.first(where: { $0.name == "Enter Sandman" }) else {
        expect(false, "Enter Sandman preset exists")
        exit(1)
    }
    var guardedSettings = preset.settings
    guardedSettings.feedbackGuard = true
    var plainSettings = preset.settings
    plainSettings.feedbackGuard = false

    let fundamental = 196.0
    let sustained = (0..<Int(sampleRate * 3.0)).map { index -> Double in
        let time = Double(index) / sampleRate
        var value = 0.0
        for harmonic in 1...8 {
            value += sin(2 * .pi * fundamental * Double(harmonic) * time) / Double(harmonic)
        }
        return value * 0.12
    }
    let guardedProcessor = makeProcessor(guardedSettings)
    let guarded = render(guardedProcessor, left: sustained)
    let plain = render(makeProcessor(plainSettings), left: sustained)
    let tailStart = Int(sampleRate * 1.5)
    let ratio = rms(Array(guarded.left[tailStart...])) / max(rms(Array(plain.left[tailStart...])), 1e-9)
    let status = guardedProcessor.guardStatus.snapshot()
    print(String(format: "  • sustained chord: %.2fx, muted %@", ratio, status.muted ? "yes" : "no"))
    expect(ratio > 0.9, "guard leaves a sustained musical chord alone")
    expect(!status.muted, "guard does not mute a sustained musical chord")
}

do {
    var guardedSettings = bareBoard(master: 0)
    guardedSettings.limiter = false
    guardedSettings.feedbackGuard = true
    var plainSettings = guardedSettings
    plainSettings.feedbackGuard = false

    let howl = growingTone(frequency: 1_500, from: 0.01, to: 0.8, seconds: 1.4)
    let guardedProcessor = makeProcessor(guardedSettings)
    let guarded = render(guardedProcessor, left: howl)
    let plain = render(makeProcessor(plainSettings), left: howl)
    let tailStart = Int(sampleRate * 1.0)
    let guardedRMS = rms(Array(guarded.left[tailStart...]))
    let plainRMS = rms(Array(plain.left[tailStart...]))
    let status = guardedProcessor.guardStatus.snapshot()
    print(String(format: "  • growing howl: guarded %.4f / plain %.4f, notches %d",
                 guardedRMS, plainRMS, status.activeNotches))
    expect(status.activeNotches > 0, "guard notches a growing feedback tone")
    expect(guardedRMS < plainRMS * 0.5, "guard cuts a growing feedback tone")
    expectFinite(guarded.left, "guarded feedback output is finite")
}

do {
    var guardedSettings = bareBoard(master: 0)
    guardedSettings.limiter = false
    guardedSettings.feedbackGuard = true
    var plainSettings = guardedSettings
    plainSettings.feedbackGuard = false

    let hum = (0..<Int(sampleRate * 1.6)).map { index -> Double in
        let time = Double(index) / sampleRate
        return 0.15 * sin(2 * .pi * 50 * time) + 0.05 * sin(2 * .pi * 150 * time)
    }
    let guardedProcessor = makeProcessor(guardedSettings)
    let guarded = render(guardedProcessor, left: hum)
    let plain = render(makeProcessor(plainSettings), left: hum)
    let tailStart = Int(sampleRate * 1.0)
    let guardedRMS = rms(Array(guarded.left[tailStart...]))
    let plainRMS = rms(Array(plain.left[tailStart...]))
    let status = guardedProcessor.guardStatus.snapshot()
    print(String(format: "  • open-jack hum: guarded %.4f / plain %.4f, hum %@",
                 guardedRMS, plainRMS, status.humDetected ? "yes" : "no"))
    expect(status.humDetected, "guard detects open-input mains hum")
    expect(guardedRMS < plainRMS * 0.6, "guard cuts open-input hum")
}

do {
    // A low B (61.7 Hz) must survive the hum detector's narrow notches. The
    // notch Q is high precisely so a musical note near the mains frequency is
    // not gutted when the guard mistakes it for hum.
    var guardedSettings = bareBoard(master: 0)
    guardedSettings.limiter = false
    guardedSettings.feedbackGuard = true
    var plainSettings = guardedSettings
    plainSettings.feedbackGuard = false

    let lowB = guitarPluck(frequency: 61.74, amplitude: 0.25, seconds: 1.6)
    let guarded = render(makeProcessor(guardedSettings), left: lowB)
    let plain = render(makeProcessor(plainSettings), left: lowB)
    let tailStart = Int(sampleRate * 0.6)
    let ratio = rms(Array(guarded.left[tailStart...])) / max(rms(Array(plain.left[tailStart...])), 1e-9)
    print(String(format: "  • low B next to mains: %.2fx", ratio))
    expect(ratio > 0.8, "guard does not gut a note near the mains frequency")
}


print("▸ Acoustic feedback loop")
do {
    guard let preset = BuiltInPresets.all.first(where: { $0.name == "Modern Metal IR" }) else {
        expect(false, "Modern Metal IR preset exists")
        exit(1)
    }
    var guardedSettings = preset.settings
    guardedSettings.feedbackGuard = true
    var openSettings = preset.settings
    openSettings.feedbackGuard = false

    for gain in [0.05, 0.2] {
        let open = renderAcousticLoop(
            settings: openSettings, seconds: 6.0,
            acousticGain: gain, delaySamples: 400
        )
        let guarded = renderAcousticLoop(
            settings: guardedSettings, seconds: 6.0,
            acousticGain: gain, delaySamples: 400
        )
        let tailStart = Int(48_000 * 4.0)
        let openRMS = rms(Array(open.output[tailStart...]))
        let guardedRMS = rms(Array(guarded.output[tailStart...]))
        let status = guarded.processor.guardStatus.snapshot()
        print(String(format: "  • loop gain %.2f: guarded %.4f / open %.4f, muted %@",
                     gain, guardedRMS, openRMS, status.muted ? "yes" : "no"))
        expect(openRMS > 0.02, "open loop howls at gain \(gain)")
        expect(guardedRMS < 0.01, "guard kills the acoustic loop at gain \(gain)")
        expect(status.muted, "guard reports the latched mute at gain \(gain)")
    }
}

print("▸ Throughput")
do {
    let preset = BuiltInPresets.all.first { $0.name == "Djent Tight" } ?? BuiltInPresets.all[0]
    var throughputSettings = preset.settings
    throughputSettings.feedbackGuard = false
    let processor = makeProcessor(throughputSettings)
    let seconds = 5.0
    let count = Int(sampleRate * seconds)
    var input = [Double](repeating: 0, count: count)
    var seed: UInt64 = 0x1234_5678
    for index in 0..<count {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let noise = Double(Int64(bitPattern: seed) >> 40) / Double(1 << 23)
        input[index] = 0.12 * sin(2 * .pi * 196 * Double(index) / sampleRate) + 0.02 * noise
    }
    let started = Date()
    _ = render(processor, left: input, blockSize: 128)
    let elapsed = Date().timeIntervalSince(started)
    let realtimeFactor = seconds / max(elapsed, 1e-9)
    print(String(format: "  • %.1fs of audio rendered in %.3fs (%.1fx realtime)", seconds, elapsed, realtimeFactor))
    expect(realtimeFactor > 2, "full board renders faster than 2x realtime")
}

    // The AI guide ships a ready-to-import example; keep it valid.
    do {
        let path = "docs/examples/ai-british-crunch.gtrpreset"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            do {
                let preset = try PresetDocument.decode(data)
                let amp = preset.settings.unit(.amp)?.enabled == true
                let cab = preset.settings.unit(.cabinet)?.enabled == true
                expect(amp && cab && preset.settings.graphicEQ.gains.count == 10,
                       "AI example preset decodes")
            } catch {
                expect(false, "AI example preset decodes (\(error))")
            }
        } else {
            expect(false, "AI example preset exists at \(path)")
        }
    }


    // Ready-to-import presets in Presets/ must stay valid.
    do {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "Presets"))?
            .filter { $0.hasSuffix(".json") || $0.hasSuffix(".gtrpreset") } ?? []
        var decoded = 0
        for file in files {
            let url = URL(fileURLWithPath: "Presets").appendingPathComponent(file)
            if let data = try? Data(contentsOf: url),
               (try? PresetDocument.decode(data)) != nil {
                decoded += 1
            }
        }
        expect(!files.isEmpty && decoded == files.count, "Presets/ examples decode")
    }

    // Silence through the default board — any energy here is self-oscillation.
// MARK: - Diagnostic dumps

if ProcessInfo.processInfo.environment["GTRBOARD_DUMP"] == "1" {
    print("▸ Diagnostic dumps")
    let outputDirectory = FileManager.default.temporaryDirectory

    // A deliberately clean amp: no drive, flat tone stack, no cabinet.
    do {
        var settings = bareBoard(master: 0)
        settings.limiter = false
        settings.units = settings.units.map { unit in
            guard unit.kind == .amp else { return unit }
            var amp = unit
            amp.enabled = true
            amp.setValue(0, for: "gain")
            amp.setValue(0, for: "voicing")
            amp.setValue(0, for: "bass")
            amp.setValue(0, for: "mid")
            amp.setValue(0, for: "treble")
            amp.setValue(0, for: "presence")
            amp.setValue(0, for: "master")
            return amp
        }
        let processor = makeProcessor(settings)
        let input = sine(frequency: 220, amplitude: 0.2, seconds: 2.0)
        let output = render(processor, left: input)
        let url = outputDirectory.appendingPathComponent("gtrboard-clean-amp.wav")
        writeWAV(output.left, sampleRate: sampleRate, to: url.path)
        print("  • clean amp: \(url.path) rms=\(rms(output.left))")
    }

    // The Studio Clean factory preset with a simple input.
    do {
        let preset = BuiltInPresets.all[0]
        let processor = makeProcessor(preset.settings)
        let input = sine(frequency: 220, amplitude: 0.1, seconds: 2.0)
        let output = render(processor, left: input)
        let url = outputDirectory.appendingPathComponent("gtrboard-studio-clean.wav")
        writeWAV(output.left, sampleRate: sampleRate, to: url.path)
        print("  • studio clean: \(url.path) rms=\(rms(output.left))")
    }

    // Isolate the source of any silence-domain artefact.
    do {
        print("  • silence by unit:")
        for kind in FXKind.allCases {
            var settings = bareBoard(master: 0)
            settings.limiter = false
            settings.units = settings.units.map { unit in
                var copy = unit
                copy.enabled = (copy.kind == kind)
                return copy
            }
            let processor = makeProcessor(settings)
            let silence = [Double](repeating: 0, count: Int(sampleRate * 1.2))
            let output = render(processor, left: silence)
            print(String(format: "      %-12s rms=%.6f peak=%.6f", (kind.rawValue as NSString).utf8String!, rms(output.left), peak(output.left)))
            if kind == .amp {
                writeWAV(output.left, sampleRate: sampleRate,
                         to: outputDirectory.appendingPathComponent("gtrboard-amp-silence.wav").path)
            }
        }
    }

    // Gate and high-gain amp behaviour on a continuous tone.
    do {
        print("  • gate/amp steady-state:")
        let input = sine(frequency: 220, amplitude: 0.2, seconds: 2.0)
        var gateSettings = bareBoard(master: 0)
        gateSettings.limiter = false
        gateSettings = enabling(.gate, in: gateSettings, ["threshold": -50, "decay": 120, "range": 70])
        let gateOut = render(makeProcessor(gateSettings), left: input)
        print(String(format: "      gate only   early=%.4f late=%.4f", rms(Array(gateOut.left[0..<4800])), rms(Array(gateOut.left.suffix(48000)))))

        var ampSettings = bareBoard(master: 0)
        ampSettings.limiter = false
        ampSettings = enabling(.amp, in: ampSettings, [
            "gain": 30, "bass": 1, "mid": -4, "treble": 3, "presence": 6,
            "master": -13, "voicing": 3
        ])
        let ampOut = render(makeProcessor(ampSettings), left: input)
        print(String(format: "      high gain   early=%.4f late=%.4f", rms(Array(ampOut.left[0..<4800])), rms(Array(ampOut.left.suffix(48000)))))
    }

    // Output level of every factory preset for a fixed input.
    do {
        print("  • preset levels (220 Hz, 0.2 peak):")
        let input = sine(frequency: 220, amplitude: 0.2, seconds: 0.7)
        for preset in BuiltInPresets.all {
            let processor = makeProcessor(preset.settings)
            let output = render(processor, left: input)
            print(String(format: "      %-26s rms=%.4f peak=%.4f", (preset.name as NSString).utf8String!, rms(output.left), peak(output.left)))
            if preset.name == "Master of Puppets" || preset.name == "Texas Flood" {
                let file = outputDirectory.appendingPathComponent("gtrboard-preset-\(preset.slug).wav")
                writeWAV(output.left, sampleRate: sampleRate, to: file.path)
            }
        }
    }

    // Factory preset loudness calibration (pluck, no trim).
    do {
        print("  • pluck levels (trim 0 dB), target RMS 0.075:")
        let input = guitarPluck(frequency: 110, amplitude: 0.22, seconds: 2.0)
        let target = 0.075
        for preset in BuiltInPresets.all {
            var settings = preset.settings
            settings.outputTrim = 0
            let output = render(makeProcessor(settings), left: input)
            let start = Int(sampleRate * 0.15)
            let end = min(output.left.count, Int(sampleRate * 1.40))
            let segment = Array(output.left[start..<end])
            let level = rms(segment)
            let trim = 20 * log10(target / max(level, 1e-9))
            print(String(format: "      %-26s rms=%.4f peak=%.4f trim=%+.1f dB",
                         (preset.name as NSString).utf8String!, level, peak(segment), trim))
        }
    }

    // Silence through the default board — any energy here is self-oscillation.
    do {
        let processor = makeProcessor(BoardSettings.defaultBoard())
        let silence = [Double](repeating: 0, count: Int(sampleRate * 2))
        let output = render(processor, left: silence)
        let url = outputDirectory.appendingPathComponent("gtrboard-silence.wav")
        writeWAV(output.left, sampleRate: sampleRate, to: url.path)
        print("  • silence: \(url.path) rms=\(rms(output.left)) peak=\(peak(output.left))")
    }
}

// MARK: - Summary

print("")
if failures == 0 {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures) of \(checks) checks failed")
    exit(1)
}
