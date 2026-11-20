//  AudioDevice.swift
//  GtrBoard
//
//  Core Audio device discovery. Keeps the UI supplied with friendly input and
//  output lists without exposing HAL types to SwiftUI.

import Foundation
import CoreAudio

/// A physical (or virtual) Core Audio device and the facts the UI needs.
struct AudioDevice: Identifiable, Hashable {
    /// Core Audio object id. Changes across reboots.
    let id: AudioObjectID
    /// Persistent UID, used to restore the selection between launches.
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRate: Double
    let isDefaultInput: Bool
    let isDefaultOutput: Bool

    var hasInput: Bool { inputChannels > 0 }
    var hasOutput: Bool { outputChannels > 0 }

    /// Short `48 kHz` style label.
    var sampleRateLabel: String {
        if sampleRate >= 1_000 { return String(format: "%.0f kHz", sampleRate / 1_000) }
        return String(format: "%.0f Hz", sampleRate)
    }

    /// `2 in / 2 out` style channel summary.
    var channelLabel: String {
        "\(inputChannels) in · \(outputChannels) out"
    }
}

/// Thin, forgiving wrappers around the HAL property API.
enum AudioDevices {
    /// UID prefix used by the private GtrBoard input+output aggregate. The
    /// creating process can still see its own aggregate, so filter it out of
    /// the input/output menus.
    static let aggregateUIDPrefix = "com.andreyilin.gtrboard.aggregate."

    static func isOwnAggregate(uid: String) -> Bool {
        uid.hasPrefix(aggregateUIDPrefix)
    }

    static func all() -> [AudioDevice] {
        let ids = deviceIDs()
        let defaultInput = defaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutput = defaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)

        return ids.compactMap { id -> AudioDevice? in
            guard let uid = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, selector: kAudioObjectPropertyName) else { return nil }
            guard !isOwnAggregate(uid: uid) else { return nil }
            let inputs = channelCount(id, scope: kAudioObjectPropertyScopeInput)
            let outputs = channelCount(id, scope: kAudioObjectPropertyScopeOutput)
            guard inputs > 0 || outputs > 0 else { return nil }
            let rate = sampleRate(id)
            return AudioDevice(
                id: id,
                uid: uid,
                name: name,
                inputChannels: inputs,
                outputChannels: outputs,
                sampleRate: rate,
                isDefaultInput: id == defaultInput,
                isDefaultOutput: id == defaultOutput
            )
        }
    }

    static func inputs() -> [AudioDevice] {
        all().filter(\.hasInput).sorted { lhs, rhs in
            if lhs.isDefaultInput != rhs.isDefaultInput { return lhs.isDefaultInput }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func outputs() -> [AudioDevice] {
        all().filter(\.hasOutput).sorted { lhs, rhs in
            if lhs.isDefaultOutput != rhs.isDefaultOutput { return lhs.isDefaultOutput }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func device(uid: String?) -> AudioDevice? {
        guard let uid else { return nil }
        return all().first { $0.uid == uid }
    }

    static func defaultInput() -> AudioDevice? {
        inputs().first(where: \.isDefaultInput) ?? inputs().first
    }

    static func defaultOutput() -> AudioDevice? {
        outputs().first(where: \.isDefaultOutput) ?? outputs().first
    }

    // MARK: - HAL helpers

    static func deviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func defaultDevice(selector: AudioObjectPropertySelector) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return device
    }

    static func stringProperty(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }

    static func channelCount(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func sampleRate(_ device: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else {
            return 0
        }
        return rate
    }

    static func bufferFrameSize(_ device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &frames) == noErr else {
            return 0
        }
        return Int(frames)
    }

    @discardableResult
    static func setBufferFrameSize(_ device: AudioObjectID, frames: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = frames
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        ) == noErr
    }

    static func setSampleRate(_ device: AudioObjectID, rate: Double) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64(rate)
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value
        ) == noErr
    }

    static func latencyFrames(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyLatency,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var frames: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &frames) == noErr else {
            return 0
        }
        return Int(frames)
    }
}
