//  AudioEngine.swift
//  GtrBoard
//
//  Low-latency guitar I/O built directly on the Core Audio HAL output unit.
//  The engine joins the selected input and output into a private aggregate
//  device (drift-compensated), asks the HAL unit for float32 non-interleaved
//  client streams and runs the whole board in the render callback.
//
//  Why a HAL AudioUnit instead of AVAudioEngine: the HAL unit lets us own the
//  device pair, the buffer size and the format conversion. With 64–128 frame
//  buffers that is the difference between "feels like an amp" and "feels like
//  a plugin".

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import BoardCore

/// Lifecycle of the audio engine as seen by the interface.
enum AudioEngineState: Equatable {
    case idle
    case starting
    case running
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle: return "Audio off"
        case .starting: return "Opening audio device…"
        case .running: return "Processing"
        case let .failed(message): return message
        }
    }
}

/// Facts about the running session, shown in the header/footer.
struct AudioEngineFormat: Equatable {
    var sampleRate: Double
    var bufferFrames: Int
    var inputChannels: Int
    var outputChannels: Int
    var latencyFrames: Int
    var latencyMS: Double
    var inputName: String
    var outputName: String
    var isAggregate: Bool

    var sampleRateLabel: String {
        String(format: "%.0f kHz", sampleRate / 1_000)
    }

    var latencyLabel: String {
        String(format: "%.1f ms", latencyMS)
    }
}

/// Recoverable setup failures with actionable text.
enum AudioEngineError: LocalizedError {
    case noSuchDevice
    case aggregateCreation(OSStatus)
    case componentMissing
    case unitCreation(OSStatus)
    case unitConfiguration(String, OSStatus)
    case unitStart(OSStatus)
    case noChannels

    var errorDescription: String? {
        switch self {
        case .noSuchDevice:
            return "The selected audio device is no longer available."
        case let .aggregateCreation(status):
            return "Could not combine the input and output devices (error \(status)). Try choosing another pair."
        case .componentMissing:
            return "The system audio unit is unavailable."
        case let .unitCreation(status):
            return "Could not create the audio unit (error \(status))."
        case let .unitConfiguration(step, status):
            return "Audio unit setup failed at \(step) (error \(status))."
        case let .unitStart(status):
            if status == -10851 || status == -10875 || status == -50 {
                return "The input device could not be opened. Allow GtrBoard to use the microphone in System Settings → Privacy & Security → Microphone, then try again."
            }
            return "The audio device could not be started (error \(status))."
        case .noChannels:
            return "The selected devices do not expose usable audio channels."
        }
    }
}

/// Owns the device pair, the HAL unit and the DSP renderer.
final class AudioEngine: @unchecked Sendable {
    /// The board renderer shared with the interface.
    let processor = BoardProcessor()

    /// Set by AppModel. Appends the processed output to a WAV file.
    var recorder: Recorder?

    /// Hidden `--tone-record` diagnostic: replaces the input with a sine so a
    /// recording can be checked for dropouts independently of the guitar.
    var testToneFrequency: Double?
    private var testTonePhase: Double = 0

    /// Serial queue for all slow Core Audio work.
    private let controlQueue = DispatchQueue(label: "com.andreyilin.GtrBoard.audio", qos: .userInitiated)
    /// Protects `generation` and `stopRequested`.
    private let operationLock = NSLock()

    private(set) var state: AudioEngineState = .idle
    private(set) var format: AudioEngineFormat?

    var onStateChange: ((AudioEngineState) -> Void)?
    var onFormatChange: ((AudioEngineFormat?) -> Void)?

    private var audioUnit: AudioComponentInstance?
    private var aggregateDevice: AudioObjectID = kAudioObjectUnknown
    private var activeDevice: AudioObjectID = kAudioObjectUnknown
    private var inputChannelCount = 1
    private var outputChannelCount = 2
    private var actualBufferFrames = 128
    private var sampleRate: Double = 48_000
    private var currentSettings = BoardSettings.defaultBoard()
    /// User IR staged for the next start. Guarded by `operationLock` because
    /// the UI can import a file while the engine is being started.
    private var pendingCustomIR: (samples: [Float], sampleRate: Double)?
    private var generation = 0
    private var stopRequested = false

    private let maxFrames = 4_096
    private let inputFloatL: UnsafeMutablePointer<Float>
    private let inputFloatR: UnsafeMutablePointer<Float>
    private let scratchL: UnsafeMutablePointer<Double>
    private let scratchR: UnsafeMutablePointer<Double>
    private let inputABL: UnsafeMutablePointer<AudioBufferList>

    // Diagnostic capture (hidden `--capture` flag). The storage is
    // preallocated so the render callback can always write without locking.
    private let captureCapacity = 48_000 * 30
    private let captureInL: UnsafeMutablePointer<Float>
    private let captureInR: UnsafeMutablePointer<Float>
    private let captureOutL: UnsafeMutablePointer<Float>
    private let captureOutR: UnsafeMutablePointer<Float>
    private var captureActive = false
    private var captureIndex = 0
    private var captureLimit = 0

    init() {
        inputFloatL = .allocate(capacity: maxFrames)
        inputFloatR = .allocate(capacity: maxFrames)
        scratchL = .allocate(capacity: maxFrames)
        scratchR = .allocate(capacity: maxFrames)
        inputFloatL.initialize(repeating: 0, count: maxFrames)
        inputFloatR.initialize(repeating: 0, count: maxFrames)
        scratchL.initialize(repeating: 0, count: maxFrames)
        scratchR.initialize(repeating: 0, count: maxFrames)

        let byteCount = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        inputABL = raw.assumingMemoryBound(to: AudioBufferList.self)
        inputABL.pointee.mNumberBuffers = 2

        captureInL = .allocate(capacity: captureCapacity)
        captureInR = .allocate(capacity: captureCapacity)
        captureOutL = .allocate(capacity: captureCapacity)
        captureOutR = .allocate(capacity: captureCapacity)
        captureInL.initialize(repeating: 0, count: captureCapacity)
        captureInR.initialize(repeating: 0, count: captureCapacity)
        captureOutL.initialize(repeating: 0, count: captureCapacity)
        captureOutR.initialize(repeating: 0, count: captureCapacity)
    }

    deinit {
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        if aggregateDevice != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDevice)
        }
        inputFloatL.deallocate()
        inputFloatR.deallocate()
        scratchL.deallocate()
        scratchR.deallocate()
        captureInL.deallocate()
        captureInR.deallocate()
        captureOutL.deallocate()
        captureOutR.deallocate()
        UnsafeMutableRawPointer(inputABL).deallocate()
    }

    // MARK: - Public control

    func start(input: AudioDevice?, output: AudioDevice, bufferSize: Int, settings: BoardSettings) {
        guard !state.isRunning, !state.isStarting else { return }

        operationLock.lock()
        generation += 1
        let operation = generation
        stopRequested = false
        operationLock.unlock()

        currentSettings = settings.sanitized()
        publish(.starting)
        controlQueue.async { [weak self] in
            self?.performStart(
                input: input,
                output: output,
                bufferSize: bufferSize,
                operation: operation
            )
        }
    }

    func stop() {
        operationLock.lock()
        generation += 1
        stopRequested = true
        operationLock.unlock()

        publish(.idle)
        format = nil
        onFormatChange?(nil)

        controlQueue.async { [weak self] in
            self?.teardown()
        }
    }

    func update(settings: BoardSettings, transition: Bool = false) {
        currentSettings = settings.sanitized()
        processor.update(settings: currentSettings, transition: transition)
    }

    /// Stages a user impulse response. The processor builds its kernels on the
    /// next `prepare`, which happens during a start; callers restart the engine
    /// so the new cab is audible immediately.
    func setCustomImpulseResponse(samples: [Float], sampleRate: Double) {
        operationLock.lock()
        pendingCustomIR = (samples, sampleRate)
        operationLock.unlock()
    }

    func clearCustomImpulseResponse() {
        operationLock.lock()
        pendingCustomIR = nil
        operationLock.unlock()
    }

    private func isCurrent(_ operation: Int) -> Bool {
        operationLock.lock()
        defer { operationLock.unlock() }
        return operation == generation && !stopRequested
    }

    // MARK: - Setup

    private func performStart(input: AudioDevice?, output: AudioDevice, bufferSize: Int, operation: Int) {
        guard isCurrent(operation) else { return }

        var createdAggregate: AudioObjectID = kAudioObjectUnknown
        var unit: AudioComponentInstance?

        do {
            let device = try makeIODevice(input: input, output: output, aggregate: &createdAggregate)
            guard isCurrent(operation) else {
                throw CancellationError()
            }

            let outputRate = output.sampleRate > 0 ? output.sampleRate : AudioDevices.sampleRate(device)
            if outputRate > 0 {
                _ = AudioDevices.setSampleRate(device, rate: outputRate)
            }
            waitForDevice(device, needsInput: input != nil)

            let inputChannels = input == nil
                ? 0
                : AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeInput)
            let outputChannels = AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeOutput)
            guard outputChannels > 0 else {
                throw AudioEngineError.noChannels
            }
            inputChannelCount = min(2, inputChannels)
            outputChannelCount = min(2, outputChannels)

            _ = AudioDevices.setBufferFrameSize(device, frames: UInt32(max(16, min(2_048, bufferSize))))
            let actual = AudioDevices.bufferFrameSize(device)
            actualBufferFrames = actual > 0 ? actual : bufferSize

            let rate = AudioDevices.sampleRate(device)
            let sampleRate = rate > 0 ? rate : outputRate
            guard sampleRate > 1_000 else { throw AudioEngineError.noChannels }
            self.sampleRate = sampleRate
            self.testTonePhase = 0

            let createdUnit = try makeUnit(
                device: device,
                sampleRate: sampleRate,
                inputChannels: inputChannelCount,
                outputChannels: outputChannelCount
            )
            unit = createdUnit

            operationLock.lock()
            let stagedIR = pendingCustomIR
            operationLock.unlock()
            if let stagedIR {
                processor.setCustomImpulseResponse(
                    samples: stagedIR.samples,
                    sampleRate: stagedIR.sampleRate
                )
            }

            processor.prepare(sampleRate: sampleRate, maxFrames: maxFrames)
            processor.update(settings: currentSettings)

            guard isCurrent(operation) else { throw CancellationError() }

            var status = AudioUnitInitialize(createdUnit)
            guard status == noErr else {
                throw AudioEngineError.unitConfiguration("initialize", status)
            }

            status = AudioOutputUnitStart(createdUnit)
            guard status == noErr else {
                AudioUnitUninitialize(createdUnit)
                throw AudioEngineError.unitStart(status)
            }
            guard isCurrent(operation) else {
                AudioOutputUnitStop(createdUnit)
                AudioUnitUninitialize(createdUnit)
                throw CancellationError()
            }

            let inputLatency = input == nil
                ? 0
                : AudioDevices.latencyFrames(device, scope: kAudioObjectPropertyScopeInput)
            let outputLatency = AudioDevices.latencyFrames(device, scope: kAudioObjectPropertyScopeOutput)
            let latencyFrames = actualBufferFrames + inputLatency + outputLatency + processor.latencyFrames
            let latencyMS = Double(latencyFrames) / sampleRate * 1_000

            audioUnit = createdUnit
            activeDevice = device
            aggregateDevice = createdAggregate

            let format = AudioEngineFormat(
                sampleRate: sampleRate,
                bufferFrames: actualBufferFrames,
                inputChannels: inputChannelCount,
                outputChannels: outputChannelCount,
                latencyFrames: latencyFrames,
                latencyMS: latencyMS,
                inputName: input?.name ?? "No input",
                outputName: output.name,
                isAggregate: createdAggregate != kAudioObjectUnknown
            )
            publish(.running, format: format)
        } catch is CancellationError {
            if let unit { AudioComponentInstanceDispose(unit) }
            if createdAggregate != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(createdAggregate)
            }
        } catch {
            if let unit {
                AudioUnitUninitialize(unit)
                AudioComponentInstanceDispose(unit)
            }
            if createdAggregate != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(createdAggregate)
            }
            publish(.failed(error.localizedDescription), format: nil)
        }
    }

    /// Uses the device directly when input and output are the same interface;
    /// otherwise builds a private, drift-compensated aggregate.
    private func makeIODevice(
        input: AudioDevice?,
        output: AudioDevice,
        aggregate: inout AudioObjectID
    ) throws -> AudioObjectID {
        guard output.id != kAudioObjectUnknown else {
            throw AudioEngineError.noSuchDevice
        }
        guard let input else {
            // Output-only: use the output device directly, with input
            // element 1 disabled on the HAL unit.
            return output.id
        }
        guard input.id != kAudioObjectUnknown else {
            throw AudioEngineError.noSuchDevice
        }
        if input.id == output.id {
            return input.id
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GtrBoard \(input.name) + \(output.name)",
            kAudioAggregateDeviceUIDKey: "com.andreyilin.gtrboard.aggregate.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceClockDeviceKey: output.uid,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: input.uid,
                    kAudioSubDeviceDriftCompensationKey: 1
                ],
                [
                    kAudioSubDeviceUIDKey: output.uid
                ]
            ]
        ]

        var device = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw AudioEngineError.aggregateCreation(status)
        }
        aggregate = device
        return device
    }

    /// A brand-new aggregate can take a few milliseconds to publish its
    /// streams; wait briefly instead of failing a valid start.
    private func waitForDevice(_ device: AudioObjectID, needsInput: Bool = true) {
        for _ in 0..<20 {
            let inputs = AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeInput)
            let outputs = AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeOutput)
            if outputs > 0, !needsInput || inputs > 0 { return }
            Thread.sleep(forTimeInterval: 0.025)
        }
    }

    private func makeUnit(
        device: AudioObjectID,
        sampleRate: Double,
        inputChannels: Int,
        outputChannels: Int
    ) throws -> AudioComponentInstance {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioEngineError.componentMissing
        }
        var unit: AudioComponentInstance?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else {
            throw AudioEngineError.unitCreation(status)
        }

        var deviceID = device
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioEngineError.unitConfiguration("current device", status)
        }

        var enableInput: UInt32 = inputChannels > 0 ? 1 : 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioEngineError.unitConfiguration("enable input", status)
        }

        if inputChannels > 0 {
            var inputFormat = Self.streamFormat(sampleRate: sampleRate, channels: inputChannels)
            status = AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &inputFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            )
            guard status == noErr else {
                AudioComponentInstanceDispose(unit)
                throw AudioEngineError.unitConfiguration("input format", status)
            }
        }

        var outputFormat = Self.streamFormat(sampleRate: sampleRate, channels: outputChannels)
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &outputFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioEngineError.unitConfiguration("output format", status)
        }

        var callback = AURenderCallbackStruct(
            inputProc: AudioEngine.renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioEngineError.unitConfiguration("render callback", status)
        }

        var maximumFrames: UInt32 = UInt32(maxFrames)
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(unit)
            throw AudioEngineError.unitConfiguration("maximum frames", status)
        }

        return unit
    }

    private static func streamFormat(sampleRate: Double, channels: Int) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(max(1, channels)),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private func teardown() {
        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }
        if aggregateDevice != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDevice)
            aggregateDevice = kAudioObjectUnknown
        }
        activeDevice = kAudioObjectUnknown
        processor.reset()
    }

    private func publish(_ newState: AudioEngineState, format newFormat: AudioEngineFormat? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = newState
            if let newFormat {
                self.format = newFormat
                self.onFormatChange?(newFormat)
            } else if !newState.isRunning {
                self.format = nil
                self.onFormatChange?(nil)
            }
            self.onStateChange?(newState)
        }
    }

    // MARK: - Render

    private static let renderCallback: AURenderCallback = {
        refCon, actionFlags, timeStamp, _, frameCount, outputData in
        let engine = Unmanaged<AudioEngine>.fromOpaque(refCon).takeUnretainedValue()
        return engine.render(
            actionFlags: actionFlags,
            timeStamp: timeStamp,
            frameCount: Int(frameCount),
            outputData: outputData
        )
    }

    private func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: Int,
        outputData: UnsafeMutablePointer<AudioBufferList>?
    ) -> OSStatus {
        guard let outputData, let audioUnit else { return noErr }
        let frames = min(frameCount, maxFrames)
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)

        var leftIn: UnsafePointer<Float>?
        var rightIn: UnsafePointer<Float>?

        if inputChannelCount > 0 {
            // Pull the guitar signal from input element 1 into our own ABL.
            inputABL.pointee.mNumberBuffers = UInt32(inputChannelCount)
            let inputBuffers = UnsafeMutableAudioBufferListPointer(inputABL)
            inputBuffers[0].mNumberChannels = 1
            inputBuffers[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
            inputBuffers[0].mData = UnsafeMutableRawPointer(inputFloatL)
            if inputChannelCount > 1 {
                inputBuffers[1].mNumberChannels = 1
                inputBuffers[1].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
                inputBuffers[1].mData = UnsafeMutableRawPointer(inputFloatR)
            }

            let status = AudioUnitRender(audioUnit, actionFlags, timeStamp, 1, UInt32(frames), inputABL)
            if status != noErr {
                for buffer in outputBuffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }

            guard let leftRaw = inputBuffers[0].mData else {
                for buffer in outputBuffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            let left = UnsafePointer<Float>(OpaquePointer(leftRaw))
            leftIn = left
            // A guitar is mono: duplicate the first channel to both sides.
            rightIn = inputChannelCount > 1
                ? UnsafePointer<Float>(OpaquePointer(inputBuffers[1].mData!))
                : left
        }

        if let frequency = testToneFrequency {
            let step = 2 * Double.pi * frequency / sampleRate
            for frame in 0..<frames {
                let sample = 0.2 * sin(testTonePhase)
                testTonePhase += step
                if testTonePhase >= 2 * Double.pi { testTonePhase -= 2 * Double.pi }
                scratchL[frame] = sample
                scratchR[frame] = sample
            }
        } else if let leftIn, let rightIn {
            for frame in 0..<frames {
                scratchL[frame] = Double(leftIn[frame])
                scratchR[frame] = Double(rightIn[frame])
            }
        } else {
            // No input selected: the board processes silence.
            for frame in 0..<frames {
                scratchL[frame] = 0
                scratchR[frame] = 0
            }
        }

        processor.process(left: scratchL, right: scratchR, frames: frames)
        recorder?.append(left: scratchL, right: scratchR, frames: frames)

        if captureActive {
            for frame in 0..<frames {
                let index = captureIndex
                if index >= captureLimit { break }
                captureInL[index] = leftIn?[frame] ?? 0
                captureInR[index] = rightIn?[frame] ?? 0
                captureOutL[index] = Float(scratchL[frame])
                captureOutR[index] = Float(scratchR[frame])
                captureIndex = index + 1
            }
            if captureIndex >= captureLimit {
                captureActive = false
            }
        }

        if outputBuffers.count >= 2 {
            write(scratchL, to: outputBuffers[0], frames: frames)
            write(scratchR, to: outputBuffers[1], frames: frames)
        } else if outputBuffers.count == 1 {
            guard let data = outputBuffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let available = min(frames, Int(outputBuffers[0].mDataByteSize) / MemoryLayout<Float>.size)
            let channels = max(1, Int(outputBuffers[0].mNumberChannels))
            if channels == 1 {
                for frame in 0..<available {
                    data[frame] = Float((scratchL[frame] + scratchR[frame]) * 0.5)
                }
            } else {
                for frame in 0..<available {
                    let base = frame * channels
                    data[base] = Float(scratchL[frame])
                    data[base + 1] = Float(scratchR[frame])
                }
            }
        }
        return noErr
    }

    private func write(_ source: UnsafeMutablePointer<Double>, to buffer: AudioBuffer, frames: Int) {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let available = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
        for frame in 0..<available {
            data[frame] = Float(source[frame])
        }
    }

    /// Diagnostic setup pass used by `--probe-audio`: builds the aggregate,
    /// configures the HAL unit and initializes it without starting I/O. This
    /// exercises the fragile half of the engine (device pairing, formats,
    /// buffer size) without triggering the microphone permission prompt.
    func probe(input: AudioDevice, output: AudioDevice, bufferSize: Int) -> String {
        var createdAggregate: AudioObjectID = kAudioObjectUnknown
        var unit: AudioComponentInstance?
        var lines: [String] = []
        do {
            let device = try makeIODevice(input: input, output: output, aggregate: &createdAggregate)
            defer {
                if let unit { AudioComponentInstanceDispose(unit) }
                if createdAggregate != kAudioObjectUnknown {
                    AudioHardwareDestroyAggregateDevice(createdAggregate)
                }
            }
            waitForDevice(device)
            lines.append("device=\(device) aggregate=\(createdAggregate != kAudioObjectUnknown)")

            let inputChannels = AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeInput)
            let outputChannels = AudioDevices.channelCount(device, scope: kAudioObjectPropertyScopeOutput)
            lines.append("channels in=\(inputChannels) out=\(outputChannels)")
            guard inputChannels > 0, outputChannels > 0 else { throw AudioEngineError.noChannels }

            let rate = AudioDevices.sampleRate(device)
            lines.append("sampleRate=\(rate)")
            _ = AudioDevices.setBufferFrameSize(device, frames: UInt32(max(16, min(2_048, bufferSize))))
            lines.append("buffer=\(AudioDevices.bufferFrameSize(device))")

            let createdUnit = try makeUnit(
                device: device,
                sampleRate: rate,
                inputChannels: min(2, inputChannels),
                outputChannels: min(2, outputChannels)
            )
            unit = createdUnit
            lines.append("unit created")

            let status = AudioUnitInitialize(createdUnit)
            lines.append("initialize=\(status)")
            if status == noErr {
                AudioUnitUninitialize(createdUnit)
            }
            return lines.joined(separator: "\n")
        } catch {
            lines.append("FAILED: \(error.localizedDescription)")
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - Diagnostic capture

    /// Starts a diagnostic capture of the raw input and the processed output.
    /// Call while the engine is running; the render thread only writes into
    /// preallocated arrays.
    @discardableResult
    func beginCapture(seconds: Int) -> Bool {
        guard state.isRunning else { return false }
        let requested = max(1, seconds) * Int(AudioDevices.sampleRate(activeDevice))
        captureLimit = min(max(1_024, requested), captureCapacity)
        captureIndex = 0
        captureActive = true
        return true
    }

    var captureProgress: Double {
        guard captureLimit > 0 else { return 0 }
        return Double(captureIndex) / Double(captureLimit)
    }

    var captureDidFinish: Bool {
        captureLimit > 0 && captureIndex >= captureLimit
    }

    /// Copies the captured arrays after the capture has finished.
    func finishCapture() -> (inL: [Float], inR: [Float], outL: [Float], outR: [Float], frames: Int) {
        let count = min(captureIndex, captureLimit)
        return (
            Array(UnsafeBufferPointer(start: captureInL, count: count)),
            Array(UnsafeBufferPointer(start: captureInR, count: count)),
            Array(UnsafeBufferPointer(start: captureOutL, count: count)),
            Array(UnsafeBufferPointer(start: captureOutR, count: count)),
            count
        )
    }

    // MARK: - Permission

    /// Requests microphone access before the engine touches the input device.
    /// The HAL unit itself would trigger the prompt, but asking first lets the
    /// UI explain what is happening.
    static func requestInputPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static var inputPermissionDenied: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .denied
            || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted
    }
}
