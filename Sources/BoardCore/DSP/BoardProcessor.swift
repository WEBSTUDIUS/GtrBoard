//  BoardProcessor.swift
//  GtrBoard
//
//  Real-time renderer for the whole board. It owns two independent chains
//  (nodes, graphic EQ, master and limiter). Normal playing uses the active
//  chain only; a preset change prepares the other chain and crossfades the
//  two outputs over 30 ms. No silence gap, no level jump and no reset click.
//
//  Threading contract
//  ------------------
//  * The UI writes a complete settings snapshot into lock-protected buffers.
//  * The audio thread copies that snapshot with `trylock` into a chain.
//  * No allocation, no blocking locks and no Swift collection mutation ever
//    happens inside `process`.

import Foundation
import os.lock

public final class BoardProcessor: @unchecked Sendable {
    /// One instance of every effect kind per chain.
    public static let maxUnits = FXKind.allCases.count
    /// The amp has the longest descriptor (seven knobs); round up.
    public static let maxParams = 8

    private let lock: UnsafeMutablePointer<os_unfair_lock_s>

    // Snapshot published by the UI.
    private let sharedParams: UnsafeMutablePointer<Double>
    private let sharedOrder: UnsafeMutablePointer<Int32>
    private let sharedEnabled: UnsafeMutablePointer<Bool>
    private let sharedEQ: UnsafeMutablePointer<Double>
    private var sharedEQEnabled = true
    private var sharedChainCount = 0
    private var sharedMasterDB: Double = -6
    private var sharedBypass = false
    private var sharedLimiter = true
    private var sharedRevision: UInt64 = 0
    private var sharedIsPresetTransition = false

    private let chains: [BoardChain]
    private var activeChain = 0
    private var incomingChain = 1
    private var crossfadeActive = false
    private var crossfadeProgress: Double = 0
    private var crossfadeStep: Double = 1.0 / 2_400.0

    private var appliedRevision: UInt64 = .max
    private var sampleRate: Double = 48_000
    private var maxFrames = 16_384
    private var dryL: UnsafeMutablePointer<Double>
    private var dryR: UnsafeMutablePointer<Double>
    private var workL: [UnsafeMutablePointer<Double>]
    private var workR: [UnsafeMutablePointer<Double>]
    private var prepared = false

    /// Diagnostic timing of the incoming chain reset.
    public private(set) var lastTransitionResetMicros: Double = 0
    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    private static let nodeIndices: [FXKind: Int] = {
        var indices: [FXKind: Int] = [:]
        for (index, kind) in FXKind.allCases.enumerated() {
            indices[kind] = index
        }
        return indices
    }()

    /// Output/input peak meter read by the interface.
    public let levels = LevelMeter()

    public init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())

        sharedParams = .allocate(capacity: Self.maxUnits * Self.maxParams)
        sharedOrder = .allocate(capacity: Self.maxUnits)
        sharedEnabled = .allocate(capacity: Self.maxUnits)
        sharedEQ = .allocate(capacity: GraphicEQNode.bandCount)
        sharedParams.initialize(repeating: 0, count: Self.maxUnits * Self.maxParams)
        sharedOrder.initialize(repeating: 0, count: Self.maxUnits)
        sharedEnabled.initialize(repeating: false, count: Self.maxUnits)
        sharedEQ.initialize(repeating: 0, count: GraphicEQNode.bandCount)

        dryL = .allocate(capacity: maxFrames)
        dryR = .allocate(capacity: maxFrames)
        dryL.initialize(repeating: 0, count: maxFrames)
        dryR.initialize(repeating: 0, count: maxFrames)
        workL = [
            .allocate(capacity: maxFrames),
            .allocate(capacity: maxFrames)
        ]
        workR = [
            .allocate(capacity: maxFrames),
            .allocate(capacity: maxFrames)
        ]
        for index in 0..<2 {
            workL[index].initialize(repeating: 0, count: maxFrames)
            workR[index].initialize(repeating: 0, count: maxFrames)
        }

        chains = [BoardChain(), BoardChain()]

        // Never leave the renderer with an all-zero snapshot.
        update(settings: .defaultBoard())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
        sharedParams.deallocate()
        sharedOrder.deallocate()
        sharedEnabled.deallocate()
        sharedEQ.deallocate()
        dryL.deallocate()
        dryR.deallocate()
        for index in 0..<2 {
            workL[index].deallocate()
            workR[index].deallocate()
        }
    }

    fileprivate static func makeNode(for kind: FXKind) -> FXNode {
        switch kind {
        case .gate: return GateNode()
        case .compressor: return CompressorNode()
        case .boost: return BoostNode()
        case .overdrive, .distortion, .fuzz: return DriveNode(kind: kind)
        case .amp: return AmpNode()
        case .cabinet: return CabinetNode()
        case .chorus: return ChorusNode()
        case .flanger: return FlangerNode()
        case .phaser: return PhaserNode()
        case .tremolo: return TremoloNode()
        case .delay: return DelayNode()
        case .reverb: return ReverbNode()
        }
    }

    /// Latency in frames introduced by the output limiter (both chains match).
    public var latencyFrames: Int { chains[activeChain].limiter.latencyFrames }

    /// Sample rate of the current session.
    public var currentSampleRate: Double { sampleRate }

    /// Prepares both chains for playback. Call only while audio is stopped.
    public func prepare(sampleRate: Double, maxFrames requestedFrames: Int = 4_096) {
        self.sampleRate = sampleRate
        let frames = max(1_024, min(16_384, requestedFrames))

        if frames > maxFrames {
            maxFrames = frames
            dryL.deallocate()
            dryR.deallocate()
            dryL = .allocate(capacity: maxFrames)
            dryR = .allocate(capacity: maxFrames)
            dryL.initialize(repeating: 0, count: maxFrames)
            dryR.initialize(repeating: 0, count: maxFrames)
            for index in 0..<2 {
                workL[index].deallocate()
                workR[index].deallocate()
                workL[index] = .allocate(capacity: maxFrames)
                workR[index] = .allocate(capacity: maxFrames)
                workL[index].initialize(repeating: 0, count: maxFrames)
                workR[index].initialize(repeating: 0, count: maxFrames)
            }
        }

        crossfadeStep = 1 / max(1, 0.050 * sampleRate)
        for chain in chains {
            chain.prepare(sampleRate: sampleRate, maxFrames: maxFrames)
        }
        activeChain = 0
        incomingChain = 1
        crossfadeActive = false
        crossfadeProgress = 0
        reset()
        appliedRevision = .max
        prepared = true
    }

    /// Publishes a new settings snapshot. Safe to call from the main thread on
    /// every slider movement.
    public func update(settings: BoardSettings, transition: Bool = false) {
        let clean = settings.sanitized()

        os_unfair_lock_lock(lock)
        // A preset transition must not be cancelled by an immediate follow-up
        // update. A big master/trim jump is treated as a transition too.
        let gainJump = abs(
            (clean.masterVolume + clean.outputTrim) - sharedMasterDB
        ) > 6
        let wantsTransition = transition || sharedIsPresetTransition || gainJump

        var slot = 0
        for unit in clean.units {
            guard let index = Self.nodeIndices[unit.kind], slot < Self.maxUnits else { continue }
            sharedOrder[slot] = Int32(index)
            sharedEnabled[slot] = unit.enabled

            let base = index * Self.maxParams
            let values = unit.orderedValues
            for parameter in 0..<Self.maxParams {
                sharedParams[base + parameter] = parameter < values.count ? values[parameter] : 0
            }
            slot += 1
        }
        while slot < Self.maxUnits {
            sharedOrder[slot] = 0
            sharedEnabled[slot] = false
            slot += 1
        }
        sharedChainCount = clean.units.count

        for band in 0..<GraphicEQNode.bandCount {
            sharedEQ[band] = clean.graphicEQ.gains[band]
        }
        sharedEQEnabled = clean.graphicEQ.enabled
        sharedMasterDB = clean.masterVolume + clean.outputTrim
        sharedBypass = clean.bypass
        sharedLimiter = clean.limiter
        sharedIsPresetTransition = wantsTransition
        sharedRevision &+= 1

        os_unfair_lock_unlock(lock)
    }

    /// Clears all delay lines and filter memory. Call only while stopped.
    public func reset() {
        for chain in chains {
            chain.reset()
        }
        activeChain = 0
        incomingChain = 1
        crossfadeActive = false
        crossfadeProgress = 0
    }

    /// Best-effort snapshot pull. Uses `trylock` so the UI can never block the
    /// render thread; the previous snapshot is reused on contention.
    private func pullSnapshot() {
        guard os_unfair_lock_trylock(lock) else { return }
        let revision = sharedRevision
        guard revision != appliedRevision else {
            os_unfair_lock_unlock(lock)
            return
        }

        let wantsTransition = sharedIsPresetTransition
        if wantsTransition {
            sharedIsPresetTransition = false
            let target = chains[incomingChain]
            copySharedLocked(to: target)
            appliedRevision = revision
            os_unfair_lock_unlock(lock)

            let started = mach_absolute_time()
            target.apply()
            target.reset()
            target.masterGain.snap()
            target.bypassMix.snap()
            lastTransitionResetMicros = Double(mach_absolute_time() - started)
                * Self.timebase / 1_000
            crossfadeActive = true
            crossfadeProgress = 0
            return
        }

        // Normal knob move, or a knob move during a crossfade: apply to the
        // chain that will remain active.
        let target = crossfadeActive ? chains[incomingChain] : chains[activeChain]
        copySharedLocked(to: target)
        os_unfair_lock_unlock(lock)
        target.apply()
    }

    /// Copies the UI snapshot into a chain. Caller holds the lock.
    private func copySharedLocked(to chain: BoardChain) {
        chain.params.update(from: sharedParams, count: Self.maxUnits * Self.maxParams)
        chain.order.update(from: sharedOrder, count: Self.maxUnits)
        chain.enabled.update(from: sharedEnabled, count: Self.maxUnits)
        chain.eq.update(from: sharedEQ, count: GraphicEQNode.bandCount)
        chain.eqEnabled = sharedEQEnabled
        chain.chainCount = min(sharedChainCount, Self.maxUnits)
        chain.masterDB = sharedMasterDB
        chain.bypass = sharedBypass
        chain.limiterEnabled = sharedLimiter
        appliedRevision = sharedRevision
    }

    /// Processes stereo planar audio in place. Real-time safe.
    public func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        guard prepared, frames > 0 else { return }

        var offset = 0
        var inputPeak: Float = 0
        var outputPeak: Float = 0
        let chunkLimit = maxFrames

        while offset < frames {
            let chunk = min(frames - offset, chunkLimit)
            let l = left.advanced(by: offset)
            let r = right.advanced(by: offset)

            pullSnapshot()

            let a = activeChain
            let b = incomingChain
            let aL = workL[a]
            let aR = workR[a]
            let bL = workL[b]
            let bR = workR[b]

            for index in 0..<chunk {
                let peak = max(abs(l[index]), abs(r[index]))
                if peak > Double(inputPeak) { inputPeak = Float(peak) }
                let dryLeft = l[index]
                let dryRight = r[index]
                dryL[index] = dryLeft
                dryR[index] = dryRight
                aL[index] = dryLeft
                aR[index] = dryRight
                if crossfadeActive {
                    bL[index] = dryLeft
                    bR[index] = dryRight
                }
            }

            chains[a].process(
                left: aL,
                right: aR,
                dryL: dryL,
                dryR: dryR,
                frames: chunk
            )
            if crossfadeActive {
                chains[b].process(
                    left: bL,
                    right: bR,
                    dryL: dryL,
                    dryR: dryR,
                    frames: chunk
                )
            }

            for index in 0..<chunk {
                var leftSample: Double
                var rightSample: Double
                if crossfadeActive {
                    crossfadeProgress += crossfadeStep
                    if crossfadeProgress >= 1 { crossfadeProgress = 1 }
                    let oldGain = 1 - crossfadeProgress
                    let newGain = crossfadeProgress
                    leftSample = aL[index] * oldGain + bL[index] * newGain
                    rightSample = aR[index] * oldGain + bR[index] * newGain
                } else {
                    leftSample = aL[index]
                    rightSample = aR[index]
                }

                if !leftSample.isFinite { leftSample = 0 }
                if !rightSample.isFinite { rightSample = 0 }
                leftSample = clampValue(leftSample, -1, 1)
                rightSample = clampValue(rightSample, -1, 1)
                l[index] = leftSample
                r[index] = rightSample
                let peak = max(abs(leftSample), abs(rightSample))
                if peak > Double(outputPeak) { outputPeak = Float(peak) }
            }

            if crossfadeActive, crossfadeProgress >= 1 {
                activeChain = b
                incomingChain = a
                crossfadeActive = false
                crossfadeProgress = 0
            }

            offset += chunk
        }

        levels.publish(input: inputPeak, output: outputPeak)
    }
}

// MARK: - One complete chain

private final class BoardChain {
    let nodes: [FXNode]
    let equalizer = GraphicEQNode()
    let limiter = LimiterNode()

    let params: UnsafeMutablePointer<Double>
    let order: UnsafeMutablePointer<Int32>
    let enabled: UnsafeMutablePointer<Bool>
    let eq: UnsafeMutablePointer<Double>
    var eqEnabled = true
    var chainCount = 0
    var masterDB: Double = -6
    var bypass = false
    var limiterEnabled = true

    var masterGain = Smoothed(0.5)
    var bypassMix = Smoothed(1)

    init() {
        nodes = FXKind.allCases.map { BoardProcessor.makeNode(for: $0) }

        params = .allocate(capacity: BoardProcessor.maxUnits * BoardProcessor.maxParams)
        order = .allocate(capacity: BoardProcessor.maxUnits)
        enabled = .allocate(capacity: BoardProcessor.maxUnits)
        eq = .allocate(capacity: GraphicEQNode.bandCount)
        params.initialize(repeating: 0, count: BoardProcessor.maxUnits * BoardProcessor.maxParams)
        order.initialize(repeating: 0, count: BoardProcessor.maxUnits)
        enabled.initialize(repeating: false, count: BoardProcessor.maxUnits)
        eq.initialize(repeating: 0, count: GraphicEQNode.bandCount)
    }

    deinit {
        params.deallocate()
        order.deallocate()
        enabled.deallocate()
        eq.deallocate()
    }

    func prepare(sampleRate: Double, maxFrames: Int) {
        for node in nodes {
            node.prepare(sampleRate: sampleRate, maxFrames: maxFrames)
        }
        equalizer.prepare(sampleRate: sampleRate)
        limiter.prepare(sampleRate: sampleRate)
        reset()
    }

    func reset() {
        for node in nodes {
            node.reset()
        }
        equalizer.reset()
        limiter.reset()
        masterGain.snap()
        bypassMix.snap()
    }

    func apply() {
        for (index, node) in nodes.enumerated() {
            node.apply(
                values: params.advanced(by: index * BoardProcessor.maxParams),
                count: BoardProcessor.maxParams
            )
        }
        equalizer.apply(gains: eq, enabled: eqEnabled)
        limiter.setEnabled(limiterEnabled)
        masterGain.set(dbToGain(masterDB))
        bypassMix.set(bypass ? 0 : 1)
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        dryL: UnsafeMutablePointer<Double>,
        dryR: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        for slot in 0..<min(chainCount, BoardProcessor.maxUnits) {
            guard enabled[slot] else { continue }
            let index = Int(order[slot])
            guard index >= 0, index < nodes.count else { continue }
            nodes[index].process(left: left, right: right, frames: frames)
        }

        equalizer.process(left: left, right: right, frames: frames)

        for index in 0..<frames {
            let gain = masterGain.step(0.0025)
            let wet = bypassMix.step(0.0025)
            let processed = left[index] * gain
            let dry = dryL[index]
            left[index] = dry + (processed - dry) * wet
            let processedR = right[index] * gain
            let dryRValue = dryR[index]
            right[index] = dryRValue + (processedR - dryRValue) * wet
        }

        limiter.process(left: left, right: right, frames: frames)
    }
}
