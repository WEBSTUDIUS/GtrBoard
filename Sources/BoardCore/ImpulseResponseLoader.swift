//  ImpulseResponseLoader.swift
//  BoardCore
//
//  Reads third-party cabinet IRs from WAV files and conditions them for the
//  convolver: channel average, resampling to the session rate, truncation to
//  the supported window and energy normalisation. The app never writes into
//  the user's original file.
//
//  Supported: RIFF/WAVE, PCM 8/16/24/32-bit and IEEE float 32/64-bit,
//  WAVEFORMATEXTENSIBLE, any chunk order, mono or multichannel.

import Foundation

/// Errors surfaced by the IR importer.
public enum ImpulseResponseError: LocalizedError, Equatable {
    case unreadableFile
    case notAWaveFile
    case unsupportedFormat(String)
    case empty
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The impulse response file could not be read."
        case .notAWaveFile:
            return "This is not a WAV file. Export the IR as WAV and try again."
        case let .unsupportedFormat(detail):
            return "Unsupported WAV encoding: \(detail)."
        case .empty:
            return "The impulse response contains no audio."
        case .tooLong:
            return "The impulse response is too long for the convolver."
        }
    }
}

/// One decoded impulse-response file.
public struct ImpulseResponseFile: Sendable {
    /// Mono samples, channels averaged.
    public let samples: [Float]
    /// Original sample rate in Hz.
    public let sampleRate: Double
    /// Number of channels found in the file.
    public let channelCount: Int

    public init(samples: [Float], sampleRate: Double, channelCount: Int = 1) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// Length in seconds.
    public var duration: Double {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }

    // MARK: - Loading

    /// Reads and decodes a WAV file.
    public static func load(url: URL) throws -> ImpulseResponseFile {
        guard let data = try? Data(contentsOf: url) else {
            throw ImpulseResponseError.unreadableFile
        }
        return try decode(data)
    }

    /// Decodes WAV data already in memory.
    public static func decode(_ data: Data) throws -> ImpulseResponseFile {
        let bytes = [UInt8](data)
        guard bytes.count >= 44 else { throw ImpulseResponseError.notAWaveFile }
        guard ascii(bytes, 0, 4) == "RIFF", ascii(bytes, 8, 4) == "WAVE" else {
            throw ImpulseResponseError.notAWaveFile
        }

        var format: UInt16 = 0
        var channels = 0
        var rate = 0.0
        var bits = 0
        var blockAlign = 0
        var dataRange: Range<Int>?

        var offset = 12
        while offset + 8 <= bytes.count {
            let id = ascii(bytes, offset, 4)
            let size = Int(readUInt32(bytes, offset + 4))
            let payloadStart = offset + 8
            guard size >= 0, payloadStart <= bytes.count else { break }
            let payloadEnd = min(bytes.count, payloadStart + size)

            switch id {
            case "fmt ":
                guard payloadEnd - payloadStart >= 16 else {
                    throw ImpulseResponseError.unsupportedFormat("short fmt chunk")
                }
                format = readUInt16(bytes, payloadStart)
                channels = Int(readUInt16(bytes, payloadStart + 2))
                let rawRate = readUInt32(bytes, payloadStart + 4)
                rate = Double(rawRate)
                blockAlign = Int(readUInt16(bytes, payloadStart + 12))
                bits = Int(readUInt16(bytes, payloadStart + 14))

                // WAVEFORMATEXTENSIBLE stores the real format tag in the
                // first two bytes of the SubFormat GUID at offset 24.
                if format == 0xFFFE, payloadEnd - payloadStart >= 40 {
                    format = readUInt16(bytes, payloadStart + 24)
                }
            case "data":
                dataRange = payloadStart..<payloadEnd
            default:
                break
            }

            let advance = 8 + size + (size & 1)
            if advance <= 0 { break }
            offset += advance
        }

        guard let dataRange, dataRange.count > 0 else { throw ImpulseResponseError.empty }
        guard channels > 0 else { throw ImpulseResponseError.unsupportedFormat("zero channels") }
        guard rate > 1_000, rate < 768_000 else {
            throw ImpulseResponseError.unsupportedFormat("sample rate \(Int(rate)) Hz")
        }

        var bytesPerSample = 0
        var isFloat = false
        switch (format, bits) {
        case (1, 8), (1, 16), (1, 24), (1, 32):
            bytesPerSample = bits / 8
        case (3, 32), (3, 64):
            bytesPerSample = bits / 8
            isFloat = true
        default:
            throw ImpulseResponseError.unsupportedFormat("format \(format), \(bits)-bit")
        }

        let frameSize = max(1, blockAlign > 0 ? blockAlign : channels * bytesPerSample)
        let frameCount = dataRange.count / frameSize
        guard frameCount > 0 else { throw ImpulseResponseError.empty }
        guard frameCount <= 5_000_000 else { throw ImpulseResponseError.tooLong }

        var samples = [Float](repeating: 0, count: frameCount)
        let base = dataRange.lowerBound
        for frame in 0..<frameCount {
            var sum = 0.0
            let frameStart = base + frame * frameSize
            for channel in 0..<channels {
                let sampleStart = frameStart + channel * bytesPerSample
                guard sampleStart + bytesPerSample <= dataRange.upperBound else { break }
                sum += Double(sampleValue(
                    bytes: bytes,
                    offset: sampleStart,
                    bits: bits,
                    isFloat: isFloat
                ))
            }
            samples[frame] = Float(sum / Double(channels))
        }

        return ImpulseResponseFile(samples: samples, sampleRate: rate, channelCount: channels)
    }

    /// Conditions a decoded IR for the convolver: resample, trim, normalise
    /// energy and fade the tail. Call off the audio thread.
    public func prepared(forSampleRate target: Double, maxTaps: Int = 8_192) -> [Float] {
        var working = samples
        if abs(sampleRate - target) > 0.5, target > 1_000 {
            working = ImpulseResponseFile.resample(working, from: sampleRate, to: target)
        }
        guard !working.isEmpty else { return [] }

        // Drop near-silent lead-in but keep musical pre-delay (up to 5 ms).
        var start = 0
        let leadLimit = min(working.count, Int(0.005 * max(target, 1_000)))
        while start < leadLimit, abs(working[start]) < 1e-5 { start += 1 }
        if start > 0, start < working.count { working.removeFirst(start) }

        if working.count > maxTaps {
            working = Array(working.prefix(maxTaps))
        }

        // Taper the end so truncation cannot click.
        let fade = min(64, working.count)
        for index in 0..<fade {
            let position = Double(index) / Double(fade)
            working[working.count - fade + index] *= Float(0.5 * (1 + cos(Double.pi * position)))
        }

        var energy = 0.0
        for sample in working { energy += Double(sample) * Double(sample) }
        guard energy > 1e-12 else { return [] }
        var scale = 1 / sqrt(energy)
        var peak = 0.0
        for sample in working { peak = max(peak, abs(Double(sample))) }
        if peak * scale > 0.95 { scale = 0.95 / max(peak, 1e-9) }

        return working.map { Float(Double($0) * scale) }
    }

    // MARK: - Resampling

    /// Windowed-sinc resampler with an anti-alias cutoff when downsampling.
    static func resample(_ input: [Float], from source: Double, to target: Double) -> [Float] {
        guard !input.isEmpty, source > 0, target > 0 else { return input }
        let ratio = target / source
        let outputCount = max(1, Int((Double(input.count) * ratio).rounded()))
        let cutoff = min(1.0, ratio)
        let radius = 8
        var output = [Float](repeating: 0, count: outputCount)

        input.withUnsafeBufferPointer { samples in
            for index in 0..<outputCount {
                let position = Double(index) / ratio
                let base = Int(floor(position))
                let fraction = position - Double(base)
                var sum = 0.0
                var weightSum = 0.0

                for tap in -radius...radius {
                    let sampleIndex = base + tap
                    guard sampleIndex >= 0, sampleIndex < samples.count else { continue }
                    let x = (Double(tap) - fraction) * cutoff
                    let sinc = abs(x) < 1e-9 ? 1 : sin(Double.pi * x) / (Double.pi * x)
                    let window = 0.5 + 0.5 * cos(Double.pi * x / Double(radius))
                    let weight = sinc * window
                    sum += Double(samples[sampleIndex]) * weight
                    weightSum += weight
                }

                output[index] = Float(weightSum != 0 ? sum / weightSum : 0)
            }
        }
        return output
    }

    // MARK: - Bytes

    private static func sampleValue(bytes: [UInt8], offset: Int, bits: Int, isFloat: Bool) -> Float {
        if isFloat {
            if bits == 32 {
                let raw = readUInt32(bytes, offset)
                return Float(bitPattern: raw)
            }
            let raw = readUInt64(bytes, offset)
            return Float(Double(bitPattern: raw))
        }
        switch bits {
        case 8:
            return (Float(bytes[offset]) - 128) / 128
        case 16:
            let raw = Int16(bitPattern: readUInt16(bytes, offset))
            return Float(raw) / 32_768
        case 24:
            let b0 = UInt32(bytes[offset])
            let b1 = UInt32(bytes[offset + 1])
            let b2 = UInt32(bytes[offset + 2])
            var value = b0 | (b1 << 8) | (b2 << 16)
            if value & 0x800000 != 0 { value |= 0xFF00_0000 }
            return Float(Int32(bitPattern: value)) / 8_388_608
        case 32:
            let raw = Int32(bitPattern: readUInt32(bytes, offset))
            return Float(raw) / 2_147_483_648
        default:
            return 0
        }
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        guard offset + 7 < bytes.count else { return 0 }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << (8 * index)
        }
        return value
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> String {
        guard offset >= 0, offset + count <= bytes.count else { return "" }
        return String(bytes: bytes[offset..<(offset + count)], encoding: .ascii) ?? ""
    }
}
