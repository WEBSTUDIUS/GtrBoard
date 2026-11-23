//  GtrBoardAudioUnit.swift
//  GtrBoardAU
//
//  AUv3 wrapper around the BoardCore guitar rig. The audio unit owns a
//  BoardProcessor, exposes the whole board as host parameters and renders the
//  DAW's input through the same chain as the standalone app.

import AVFoundation
import AudioToolbox
import CoreAudioKit
import BoardCore

public final class GtrBoardAudioUnit: AUAudioUnit, @unchecked Sendable {
    private let processor = BoardProcessor()
    private let stateLock = NSLock()
    private var settings = BoardSettings.defaultBoard().sanitized()
    private var syncingParameters = false
    private var notifyScheduled = false

    /// Called on the main queue when the host or automation changes a value.
    var onSettingsChanged: (() -> Void)?

    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!

    private var parametersByIdentifier: [String: AUParameter] = [:]
    private var bindingsByAddress: [UInt64: Binding] = [:]

    private var scratchL: UnsafeMutablePointer<Double>?
    private var scratchR: UnsafeMutablePointer<Double>?
    private var scratchCapacity = 0

    private enum Binding {
        case pedal(FXKind, String)
        case master
        case trim
        case bypass
        case limiter
        case feedbackGuard
        case eqEnabled
        case eqBand(Int)
    }

    // MARK: - Init

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try super.init(componentDescription: componentDescription, options: options)

        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputBus.maximumChannelCount = 2
        outputBus.maximumChannelCount = 2

        _inputBusses = AUAudioUnitBusArray(
            audioUnit: self, busType: .input, busses: [inputBus]
        )
        _outputBusses = AUAudioUnitBusArray(
            audioUnit: self, busType: .output, busses: [outputBus]
        )

        setupParameterTree()
        processor.update(settings: settings)
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    public override var channelCapabilities: [NSNumber] {
        [NSNumber(value: 2), NSNumber(value: 2)]
    }

    public override var latency: TimeInterval {
        let rate = outputBus?.format.sampleRate ?? 48_000
        return Double(processor.latencyFrames) / max(rate, 1)
    }

    public override var tailTime: TimeInterval { 0.5 }

    // MARK: - Board state (used by the custom UI)

    var boardSettings: BoardSettings {
        stateLock.lock()
        let copy = settings
        stateLock.unlock()
        return copy
    }

    func applySettings(_ newSettings: BoardSettings, syncParameters: Bool = true) {
        let clean = newSettings.sanitized()
        stateLock.lock()
        settings = clean
        stateLock.unlock()

        processor.update(settings: clean)
        if syncParameters {
            syncParameterValues(from: clean)
        }
        scheduleNotification()
    }

    private func scheduleNotification() {
        guard onSettingsChanged != nil else { return }
        stateLock.lock()
        if notifyScheduled {
            stateLock.unlock()
            return
        }
        notifyScheduled = true
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.notifyScheduled = false
            self.stateLock.unlock()
            self.onSettingsChanged?()
        }
    }

    // MARK: - Lifecycle

    public override func allocateRenderResources() throws {
        let inputChannels = Int(inputBusses[0].format.channelCount)
        let outputChannels = Int(outputBusses[0].format.channelCount)
        guard inputChannels == outputChannels, inputChannels == 2 else {
            setRenderResourcesAllocated(false)
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kAudioUnitErr_FailedInitialization),
                userInfo: [NSLocalizedDescriptionKey: "GtrBoard needs a stereo in/out bus"]
            )
        }

        let frames = Int(maximumFramesToRender)
        allocateScratch(frames: frames)
        processor.prepare(sampleRate: outputBusses[0].format.sampleRate, maxFrames: frames)
        processor.update(settings: boardSettings)
        try super.allocateRenderResources()
    }

    public override func deallocateRenderResources() {
        processor.reset()
        scratchL?.deallocate(); scratchL = nil
        scratchR?.deallocate(); scratchR = nil
        scratchCapacity = 0
        super.deallocateRenderResources()
    }

    private func allocateScratch(frames: Int) {
        guard frames > scratchCapacity else { return }
        scratchL?.deallocate()
        scratchR?.deallocate()
        let left = UnsafeMutablePointer<Double>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Double>.allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        right.initialize(repeating: 0, count: frames)
        scratchL = left
        scratchR = right
        scratchCapacity = frames
    }

    // MARK: - Render

    public override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] actionFlags, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let self else { return noErr }
            return self.render(
                actionFlags: actionFlags,
                timestamp: timestamp,
                frameCount: frameCount,
                outputData: outputData,
                pullInputBlock: pullInputBlock
            )
        }
    }

    private func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AUAudioFrameCount,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        pullInputBlock: AURenderPullInputBlock?
    ) -> OSStatus {
        guard let pullInputBlock else {
            silence(outputData: outputData, frames: frameCount)
            return noErr
        }

        let status = pullInputBlock(actionFlags, timestamp, frameCount, 0, outputData)
        guard status == noErr else {
            silence(outputData: outputData, frames: frameCount)
            return noErr
        }

        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard buffers.count >= 2,
              let leftRaw = buffers[0].mData,
              let rightRaw = buffers[1].mData,
              let scratchL, let scratchR else {
            silence(outputData: outputData, frames: frameCount)
            return noErr
        }

        let frames = min(Int(frameCount), scratchCapacity)
        let left = leftRaw.assumingMemoryBound(to: Float.self)
        let right = rightRaw.assumingMemoryBound(to: Float.self)
        for index in 0..<frames {
            scratchL[index] = Double(left[index])
            scratchR[index] = Double(right[index])
        }

        processor.process(left: scratchL, right: scratchR, frames: frames)

        var peak: Float = 0
        for index in 0..<frames {
            let l = Float(scratchL[index])
            let r = Float(scratchR[index])
            left[index] = l
            right[index] = r
            peak = max(peak, abs(l), abs(r))
        }
        if peak > 0 {
            actionFlags.pointee.remove(.unitRenderAction_OutputIsSilence)
        } else {
            actionFlags.pointee.insert(.unitRenderAction_OutputIsSilence)
        }
        return noErr
    }

    private func silence(
        outputData: UnsafeMutablePointer<AudioBufferList>,
        frames: AUAudioFrameCount
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in buffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    // MARK: - Parameters

    private func setupParameterTree() {
        var groups: [AUParameterNode] = []
        var address: UInt64 = 0

        for kind in FXKind.allCases {
            var parameters: [AUParameter] = []
            for descriptor in kind.descriptor.parameters {
                let identifier = "\(kind.rawValue)_\(descriptor.id)"
                let parameter = AUParameterTree.createParameter(
                    withIdentifier: identifier,
                    name: "\(kind.descriptor.shortName) \(descriptor.name)",
                    address: address,
                    min: Float(descriptor.minValue),
                    max: Float(descriptor.maxValue),
                    unit: Self.parameterUnit(descriptor.unit),
                    unitName: nil,
                    flags: [.flag_IsReadable, .flag_IsWritable],
                    valueStrings: descriptor.isStepped ? descriptor.choices : nil,
                    dependentParameters: nil
                )
                parameter.value = Float(descriptor.fallback)
                parametersByIdentifier[identifier] = parameter
                bindingsByAddress[address] = .pedal(kind, descriptor.id)
                address += 1
                parameters.append(parameter)
            }
            groups.append(AUParameterTree.createGroup(
                withIdentifier: "group_\(kind.rawValue)",
                name: kind.descriptor.name,
                children: parameters
            ))
        }

        var globals: [AUParameter] = []
        globals.append(globalParameter(
            identifier: "global_master", name: "Master", address: &address,
            binding: .master, range: BoardSettings.masterRange, value: settings.masterVolume,
            unit: .decibels
        ))
        globals.append(globalParameter(
            identifier: "global_trim", name: "Preset Level", address: &address,
            binding: .trim, range: BoardSettings.trimRange, value: settings.outputTrim,
            unit: .decibels
        ))
        globals.append(switchParameter(
            identifier: "global_bypass", name: "Bypass", address: &address,
            binding: .bypass, value: settings.bypass
        ))
        globals.append(switchParameter(
            identifier: "global_limiter", name: "Limiter", address: &address,
            binding: .limiter, value: settings.limiter
        ))
        globals.append(switchParameter(
            identifier: "global_guard", name: "Feedback Guard", address: &address,
            binding: .feedbackGuard, value: settings.feedbackGuard
        ))
        groups.append(AUParameterTree.createGroup(
            withIdentifier: "group_global", name: "Global", children: globals
        ))

        var eq: [AUParameter] = []
        let eqSwitch = AUParameterTree.createParameter(
            withIdentifier: "eq_enabled",
            name: "Graphic EQ",
            address: address,
            min: 0, max: 1,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: ["Off", "On"],
            dependentParameters: nil
        )
        eqSwitch.value = settings.graphicEQ.enabled ? 1 : 0
        parametersByIdentifier["eq_enabled"] = eqSwitch
        bindingsByAddress[address] = .eqEnabled
        address += 1
        eq.append(eqSwitch)

        for band in 0..<GraphicEQSettings.frequencies.count {
            let parameter = AUParameterTree.createParameter(
                withIdentifier: "eq_band_\(band)",
                name: GraphicEQSettings.labels[band] + " Hz",
                address: address,
                min: -12, max: 12,
                unit: .decibels,
                unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable],
                valueStrings: nil,
                dependentParameters: nil
            )
            parameter.value = Float(settings.graphicEQ.gains[band])
            parametersByIdentifier["eq_band_\(band)"] = parameter
            bindingsByAddress[address] = .eqBand(band)
            address += 1
            eq.append(parameter)
        }
        groups.append(AUParameterTree.createGroup(
            withIdentifier: "group_eq", name: "Graphic EQ", children: eq
        ))

        let tree = AUParameterTree.createTree(withChildren: groups)
        tree.implementorValueObserver = { [weak self] parameter, value in
            self?.parameterChanged(address: parameter.address, value: value)
        }
        tree.implementorValueProvider = { [weak self] parameter in
            self?.parameterValue(address: parameter.address) ?? parameter.value
        }
        parameterTree = tree
    }

    private func globalParameter(
        identifier: String,
        name: String,
        address: inout UInt64,
        binding: Binding,
        range: ClosedRange<Double>,
        value: Double,
        unit: AudioUnitParameterUnit
    ) -> AUParameter {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: identifier,
            name: name,
            address: address,
            min: Float(range.lowerBound),
            max: Float(range.upperBound),
            unit: unit,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        parameter.value = Float(value)
        parametersByIdentifier[identifier] = parameter
        bindingsByAddress[address] = binding
        address += 1
        return parameter
    }

    private func switchParameter(
        identifier: String,
        name: String,
        address: inout UInt64,
        binding: Binding,
        value: Bool
    ) -> AUParameter {
        let parameter = AUParameterTree.createParameter(
            withIdentifier: identifier,
            name: name,
            address: address,
            min: 0, max: 1,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: ["Off", "On"],
            dependentParameters: nil
        )
        parameter.value = value ? 1 : 0
        parametersByIdentifier[identifier] = parameter
        bindingsByAddress[address] = binding
        address += 1
        return parameter
    }

    private func parameterChanged(address: UInt64, value: Float) {
        guard !syncingParameters, let binding = bindingsByAddress[address] else { return }

        stateLock.lock()
        switch binding {
        case let .pedal(kind, parameter):
            settings.setParam(Double(value), for: kind, parameter: parameter)
        case .master:
            settings.masterVolume = Double(value)
        case .trim:
            settings.outputTrim = Double(value)
        case .bypass:
            settings.bypass = value >= 0.5
        case .limiter:
            settings.limiter = value >= 0.5
        case .feedbackGuard:
            settings.feedbackGuard = value >= 0.5
        case .eqEnabled:
            settings.graphicEQ.enabled = value >= 0.5
        case let .eqBand(band):
            guard settings.graphicEQ.gains.indices.contains(band) else { break }
            settings.graphicEQ.gains[band] = Double(value)
        }
        let snapshot = settings.sanitized()
        settings = snapshot
        stateLock.unlock()

        processor.update(settings: snapshot)
        scheduleNotification()
    }

    private func parameterValue(address: UInt64) -> Float? {
        guard let binding = bindingsByAddress[address] else { return nil }
        stateLock.lock()
        defer { stateLock.unlock() }
        switch binding {
        case let .pedal(kind, parameter):
            return Float(settings.unit(kind)?.value(parameter) ?? 0)
        case .master:
            return Float(settings.masterVolume)
        case .trim:
            return Float(settings.outputTrim)
        case .bypass:
            return settings.bypass ? 1 : 0
        case .limiter:
            return settings.limiter ? 1 : 0
        case .feedbackGuard:
            return settings.feedbackGuard ? 1 : 0
        case .eqEnabled:
            return settings.graphicEQ.enabled ? 1 : 0
        case let .eqBand(band):
            return settings.graphicEQ.gains.indices.contains(band)
                ? Float(settings.graphicEQ.gains[band])
                : 0
        }
    }

    private func syncParameterValues(from board: BoardSettings) {
        syncingParameters = true
        defer { syncingParameters = false }
        for (identifier, parameter) in parametersByIdentifier {
            parameter.value = Float(Self.value(for: identifier, in: board))
        }
    }

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func value(for identifier: String, in board: BoardSettings) -> Double {
        if identifier == "global_master" { return board.masterVolume }
        if identifier == "global_trim" { return board.outputTrim }
        if identifier == "global_bypass" { return board.bypass ? 1 : 0 }
        if identifier == "global_limiter" { return board.limiter ? 1 : 0 }
        if identifier == "global_guard" { return board.feedbackGuard ? 1 : 0 }
        if identifier == "eq_enabled" { return board.graphicEQ.enabled ? 1 : 0 }
        if identifier.hasPrefix("eq_band_"),
           let band = Int(identifier.dropFirst("eq_band_".count)),
           board.graphicEQ.gains.indices.contains(band) {
            return board.graphicEQ.gains[band]
        }
        let parts = identifier.split(separator: "_", maxSplits: 1)
        guard parts.count == 2,
              let kind = FXKind(rawValue: String(parts[0])) else { return 0 }
        return board.unit(kind)?.value(String(parts[1])) ?? 0
    }

    private static func parameterUnit(_ unit: ParameterUnit) -> AudioUnitParameterUnit {
        switch unit {
        case .decibels: return .decibels
        case .hertz: return .hertz
        case .milliseconds: return .milliseconds
        case .percent: return .percent
        case .ratio: return .ratio
        case .choice: return .indexed
        }
    }

    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            // AUv2 hosts (and auval) read the bridged class info and require
            // the component identity before they accept the state blob.
            state["type"] = NSNumber(value: Self.fourCC("aufx"))
            state["subtype"] = NSNumber(value: Self.fourCC("GtrB"))
            state["manufacturer"] = NSNumber(value: Self.fourCC("GtrB"))
            state["version"] = 67072
            if let data = try? JSONEncoder().encode(boardSettings) {
                state["board"] = data
            }
            return state
        }
        set {
            guard let newValue else { return }
            // Let the base class restore its own parameter snapshot first, then
            // apply the board so the chain order and IR model win.
            super.fullState = newValue
            if let data = newValue["board"] as? Data,
               let board = try? JSONDecoder().decode(BoardSettings.self, from: data) {
                applySettings(board, syncParameters: true)
            }
        }
    }

    override public var shouldBypassEffect: Bool {
        get { boardSettings.bypass }
        set { applySettings(boardSettings.withBypass(newValue), syncParameters: true) }
    }
}

private extension BoardSettings {
    func withBypass(_ value: Bool) -> BoardSettings {
        var copy = self
        copy.bypass = value
        return copy
    }
}
