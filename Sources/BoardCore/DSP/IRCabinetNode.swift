//  IRCabinetNode.swift
//  BoardCore
//
//  The IR Cabinet pedal: a speaker impulse response in place of the analogue
//  cabinet simulation, with a dry/wet mix, low/high cut and output level.
//
//  Switching models is done with a short wet fade instead of an instant swap,
//  because resetting the convolution history under a sustained note clicks.
//  The dry path is delayed by the same one block as the convolver so a 50/50
//  mix stays phase-correct instead of comb filtering.

import Foundation

final class IRCabinetNode: FXNode {
    let kind: FXKind = .ir

    /// Fixed pipeline delay of the node, in frames.
    static let latencyFrames = IRConvolver.latencyFrames

    private var sampleRate: Double = 48_000
    private var maxFrames = 4_096

    private var builtInKernels: [IRKernel] = []
    private var customKernel: IRKernel?
    private var customSamples: [Float]?
    private var customSampleRate: Double = 0

    private var leftConvolver: IRConvolver?
    private var rightConvolver: IRConvolver?

    private var dryL: UnsafeMutablePointer<Double>?
    private var dryR: UnsafeMutablePointer<Double>?
    private var dryDelayL: UnsafeMutablePointer<Double>?
    private var dryDelayR: UnsafeMutablePointer<Double>?
    private var dryDelayPosition = 0

    private var requestedModel = 0
    private var currentModel = 0

    private var switchGain: Double = 1
    private var switching = false
    private var fadingOut = false
    private var switchStep: Double = 0.003

    private var lowCutDB: Double = 80
    private var highCutDB: Double = 9_000
    private var mix = Smoothed(1)
    private var level = Smoothed(1)

    private var highPassCoefficients = BiquadCoefficients.identity
    private var lowPassCoefficients = BiquadCoefficients.identity
    private var highPassL = BiquadState(), highPassR = BiquadState()
    private var lowPassL = BiquadState(), lowPassR = BiquadState()
    private var cachedCutSignature = Int.min

    private let iModel = parameterIndex("model", in: .ir)
    private let iLowCut = parameterIndex("lowCut", in: .ir)
    private let iHighCut = parameterIndex("highCut", in: .ir)
    private let iMix = parameterIndex("mix", in: .ir)
    private let iLevel = parameterIndex("level", in: .ir)

    // MARK: - FXNode

    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = max(8_000, sampleRate)
        self.maxFrames = max(64, maxFrames)

        builtInKernels = CabinetIRLibrary.kernels(sampleRate: self.sampleRate)
        rebuildCustomKernel()
        switchStep = 1 / max(1, 0.008 * self.sampleRate)

        allocateScratch()
        leftConvolver = IRConvolver()
        rightConvolver = IRConvolver()

        currentModel = requestedModel
        loadKernel(for: requestedModel)
        switchGain = 1
        switching = false
        fadingOut = false
        reset()
        updateCutCoefficients(force: true)
    }

    func reset() {
        leftConvolver?.clear()
        rightConvolver?.clear()
        dryL?.update(repeating: 0, count: maxFrames)
        dryR?.update(repeating: 0, count: maxFrames)
        dryDelayL?.update(repeating: 0, count: IRCabinetNode.dryDelay)
        dryDelayR?.update(repeating: 0, count: IRCabinetNode.dryDelay)
        dryDelayPosition = 0
        highPassL.reset(); highPassR.reset()
        lowPassL.reset(); lowPassR.reset()
        switchGain = 1
        switching = false
        fadingOut = false
        currentModel = resolvedModel(requestedModel)
        mix.snap()
        level.snap()
    }

    func apply(values: UnsafePointer<Double>, count: Int) {
        let model = Int(parameterValue(values, iModel, count: count, fallback: 0).rounded())
        requestedModel = min(max(model, 0), CabinetIRLibrary.customIndex)
        lowCutDB = parameterValue(values, iLowCut, count: count, fallback: 80)
        highCutDB = parameterValue(values, iHighCut, count: count, fallback: 9_000)
        mix.set(parameterValue(values, iMix, count: count, fallback: 1))
        level.set(dbToGain(parameterValue(values, iLevel, count: count, fallback: 0)))
        updateCutCoefficients(force: false)

        let resolved = resolvedModel(requestedModel)
        if leftConvolver != nil, resolved != currentModel, !switching {
            switching = true
            fadingOut = true
        }
    }

    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        guard let leftConvolver, let rightConvolver,
              let dryL, let dryR, let dryDelayL, let dryDelayR,
              frames <= maxFrames else { return }

        let dryDelay = IRCabinetNode.dryDelay
        for index in 0..<frames {
            dryL[index] = left[index]
            dryR[index] = right[index]
        }

        // Delay the dry path by exactly the convolver pipeline length.
        for index in 0..<frames {
            let delayedL = dryDelayL[dryDelayPosition]
            let delayedR = dryDelayR[dryDelayPosition]
            dryDelayL[dryDelayPosition] = dryL[index]
            dryDelayR[dryDelayPosition] = dryR[index]
            dryDelayPosition += 1
            if dryDelayPosition >= dryDelay { dryDelayPosition = 0 }
            dryL[index] = delayedL
            dryR[index] = delayedR
        }

        leftConvolver.process(input: left, output: left, frames: frames)
        rightConvolver.process(input: right, output: right, frames: frames)

        let mixValue = mix.step(0.0035)
        let levelValue = level.step(0.0035)

        for index in 0..<frames {
            if switching {
                if fadingOut {
                    switchGain -= switchStep
                    if switchGain <= 0 {
                        switchGain = 0
                        loadKernel(for: requestedModel)
                        currentModel = resolvedModel(requestedModel)
                        fadingOut = false
                    }
                } else {
                    switchGain += switchStep
                    if switchGain >= 1 {
                        switchGain = 1
                        switching = false
                    }
                }
            }

            var wetL = highPassL.process(left[index], highPassCoefficients)
            wetL = lowPassL.process(wetL, lowPassCoefficients)
            var wetR = highPassR.process(right[index], highPassCoefficients)
            wetR = lowPassR.process(wetR, lowPassCoefficients)

            let wetGain = levelValue * switchGain
            let dryMix = 1 - mixValue
            left[index] = dryL[index] * dryMix + wetL * wetGain * mixValue
            right[index] = dryR[index] * dryMix + wetR * wetGain * mixValue
        }
    }

    // MARK: - Custom impulse

    /// Stores a user IR to be prepared on the next `prepare` call. Call while
    /// audio is stopped; the kernel is built from `prepare`.
    func setCustomSource(samples: [Float]?, sampleRate: Double) {
        customSamples = samples
        customSampleRate = sampleRate
    }

    /// Name reported to the interface, if a custom IR is loaded.
    var customName: String? {
        customKernel == nil ? nil : "Custom"
    }

    var hasCustomImpulse: Bool { customKernel != nil }

    // MARK: - Internals

    deinit {
        dryL?.deallocate()
        dryR?.deallocate()
        dryDelayL?.deallocate()
        dryDelayR?.deallocate()
    }

    private static let dryDelay = IRConvolver.latencyFrames

    private func allocateScratch() {
        dryL?.deallocate()
        dryR?.deallocate()
        dryDelayL?.deallocate()
        dryDelayR?.deallocate()

        let l = UnsafeMutablePointer<Double>.allocate(capacity: maxFrames)
        let r = UnsafeMutablePointer<Double>.allocate(capacity: maxFrames)
        l.initialize(repeating: 0, count: maxFrames)
        r.initialize(repeating: 0, count: maxFrames)
        dryL = l
        dryR = r

        let dl = UnsafeMutablePointer<Double>.allocate(capacity: IRCabinetNode.dryDelay)
        let dr = UnsafeMutablePointer<Double>.allocate(capacity: IRCabinetNode.dryDelay)
        dl.initialize(repeating: 0, count: IRCabinetNode.dryDelay)
        dr.initialize(repeating: 0, count: IRCabinetNode.dryDelay)
        dryDelayL = dl
        dryDelayR = dr
        dryDelayPosition = 0
    }

    private func rebuildCustomKernel() {
        guard let customSamples, customSampleRate > 1_000, !customSamples.isEmpty else {
            customKernel = nil
            return
        }
        let file = ImpulseResponseFile(
            samples: customSamples,
            sampleRate: customSampleRate,
            channelCount: 1
        )
        let prepared = file.prepared(forSampleRate: sampleRate, maxTaps: IRKernel.maxTaps)
        customKernel = prepared.isEmpty
            ? nil
            : IRKernel(impulse: prepared, blockSize: IRConvolver.blockSize)
    }

    private func resolvedModel(_ model: Int) -> Int {
        if model == CabinetIRLibrary.customIndex, customKernel == nil { return 0 }
        guard model >= 0, model < CabinetIRLibrary.models.count else { return 0 }
        return model
    }

    private func kernel(for model: Int) -> IRKernel? {
        if model == CabinetIRLibrary.customIndex { return customKernel }
        guard builtInKernels.indices.contains(model) else { return builtInKernels.first }
        return builtInKernels[model]
    }

    private func loadKernel(for model: Int) {
        let resolved = resolvedModel(model)
        guard let kernel = kernel(for: resolved) else { return }
        leftConvolver?.load(kernel: kernel)
        rightConvolver?.load(kernel: kernel)
        currentModel = resolved
    }

    private func updateCutCoefficients(force: Bool) {
        let signature = Int(lowCutDB * 10) &* 31 &+ Int(highCutDB)
        guard force || signature != cachedCutSignature else { return }
        cachedCutSignature = signature
        highPassCoefficients = BiquadDesign.coefficients(
            shape: .highPass, frequency: lowCutDB, gainDB: 0, q: 0.707,
            sampleRate: sampleRate
        )
        lowPassCoefficients = BiquadDesign.coefficients(
            shape: .lowPass, frequency: highCutDB, gainDB: 0, q: 0.707,
            sampleRate: sampleRate
        )
    }
}
