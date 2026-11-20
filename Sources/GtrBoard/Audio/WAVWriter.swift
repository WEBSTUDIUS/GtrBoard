//  WAVWriter.swift
//  GtrBoard
//
//  Minimal 16-bit PCM WAV writer used by the hidden `--capture` diagnostic.

import Foundation

enum WAVWriter {
    static func writeStereo(left: [Float], right: [Float], sampleRate: Double, to url: URL) {
        let frames = min(left.count, right.count)
        var payload = Data(capacity: frames * 4)
        for index in 0..<frames {
            for sample in [left[index], right[index]] {
                let clamped = min(max(Double(sample), -1), 1)
                let value = Int16((clamped * 32_767).rounded())
                var little = UInt16(bitPattern: value).littleEndian
                withUnsafeBytes(of: &little) { payload.append(contentsOf: $0) }
            }
        }

        func append32(_ data: inout Data, _ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ data: inout Data, _ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        append32(&wav, UInt32(36 + payload.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(&wav, 16)
        append16(&wav, 1)
        append16(&wav, 2)
        append32(&wav, UInt32(sampleRate))
        append32(&wav, UInt32(sampleRate) * 4)
        append16(&wav, 4)
        append16(&wav, 16)
        wav.append(contentsOf: Array("data".utf8))
        append32(&wav, UInt32(payload.count))
        wav.append(payload)
        try? wav.write(to: url)
    }
}
