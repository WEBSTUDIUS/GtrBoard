//  IRConvolution.swift
//  BoardCore
//
//  Zero-allocation partitioned convolution for speaker impulse responses.
//
//  Uniformly partitioned overlap-save: the IR is cut into 64-sample blocks,
//  each block is transformed once (``IRKernel``) and shared by every chain,
//  and the input is transformed in 64-sample frames of 128 points. The first
//  partition contributes to the current block, so there is no algorithmic
//  latency beyond the one-block pipeline needed to emit audio in place.
//
//  A 2 400-tap cabinet needs 38 partitions: about 45 MFLOP/s per channel at
//  48 kHz, a fraction of one M-series core. Two chains can run the same
//  kernel objects at the same time because kernels are immutable.

import Foundation

/// Immutable frequency-domain form of one impulse response.
final class IRKernel {
    static let maxTaps = 8_192

    let blockSize: Int
    let fftSize: Int
    let bins: Int
    let partitionCount: Int
    let spectraReal: [Float]
    let spectraImaginary: [Float]

    /// Transforms every partition of `impulse`. Call off the audio thread.
    init(impulse: [Float], blockSize: Int) {
        let size = blockSize * 2
        self.blockSize = blockSize
        fftSize = size
        bins = size

        let usable = min(impulse.count, IRKernel.maxTaps)
        partitionCount = max(1, (usable + blockSize - 1) / blockSize)

        let fft = FFT(size: size)!
        let real = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let imaginary = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let outReal = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let outImaginary = UnsafeMutablePointer<Float>.allocate(capacity: size)
        real.initialize(repeating: 0, count: size)
        imaginary.initialize(repeating: 0, count: size)
        outReal.initialize(repeating: 0, count: size)
        outImaginary.initialize(repeating: 0, count: size)
        defer {
            real.deallocate()
            imaginary.deallocate()
            outReal.deallocate()
            outImaginary.deallocate()
        }

        var spectraReal = [Float]()
        var spectraImaginary = [Float]()
        spectraReal.reserveCapacity(partitionCount * size)
        spectraImaginary.reserveCapacity(partitionCount * size)

        for partition in 0..<partitionCount {
            real.update(repeating: 0, count: size)
            imaginary.update(repeating: 0, count: size)
            let start = partition * blockSize
            let end = min(usable, start + blockSize)
            if start < end {
                for index in start..<end {
                    real[index - start] = impulse[index]
                }
            }
            fft.forward(
                real: real,
                imaginary: nil,
                outputReal: outReal,
                outputImaginary: outImaginary
            )
            spectraReal.append(contentsOf: UnsafeBufferPointer(start: outReal, count: size))
            spectraImaginary.append(contentsOf: UnsafeBufferPointer(start: outImaginary, count: size))
        }

        self.spectraReal = spectraReal
        self.spectraImaginary = spectraImaginary
    }
}

/// Streaming partitioned convolver for one channel.
///
/// The processor writes `frames` samples and reads one delayed sample at the
/// same index, so it is safe to call with the same pointer for input and
/// output. All storage is allocated in `init`; `process` never allocates.
public final class IRConvolver {
    /// Partition length in frames. The convolver delays audio by this much.
    public static let blockSize = 64
    /// Reported pipeline latency, in frames.
    public static let latencyFrames = 64

    private let blockSize: Int
    private let fftSize: Int
    private let bins: Int
    private let maxPartitions: Int
    private let fft: FFT

    private let frame: UnsafeMutablePointer<Float>
    private let specReal: UnsafeMutablePointer<Float>
    private let specImaginary: UnsafeMutablePointer<Float>
    private let fdlReal: UnsafeMutablePointer<Float>
    private let fdlImaginary: UnsafeMutablePointer<Float>
    private let accumReal: UnsafeMutablePointer<Float>
    private let accumImaginary: UnsafeMutablePointer<Float>
    private let timeReal: UnsafeMutablePointer<Float>
    private let timeImaginary: UnsafeMutablePointer<Float>
    private let inputBlock: UnsafeMutablePointer<Float>
    private let history: UnsafeMutablePointer<Float>

    private var outputRing: UnsafeMutablePointer<Float>
    private var outputRead = 0
    private var outputCount = 0
    private var inputCount = 0
    private var fdlPosition = 0

    private var kernel: IRKernel?
    private var appliedPartitions = 0

    /// Builds a convolver and loads `impulse` straight away.
    public convenience init(impulse: [Float]) {
        self.init()
        load(impulse: impulse)
    }

    /// Builds an empty convolver. Use ``load(impulse:)`` before processing.
    public init() {
        blockSize = IRConvolver.blockSize
        fftSize = blockSize * 2
        bins = fftSize
        maxPartitions = max(1, (IRKernel.maxTaps + blockSize - 1) / blockSize)
        fft = FFT(size: fftSize)!

        frame = .allocate(capacity: fftSize)
        specReal = .allocate(capacity: bins)
        specImaginary = .allocate(capacity: bins)
        fdlReal = .allocate(capacity: maxPartitions * bins)
        fdlImaginary = .allocate(capacity: maxPartitions * bins)
        accumReal = .allocate(capacity: bins)
        accumImaginary = .allocate(capacity: bins)
        timeReal = .allocate(capacity: bins)
        timeImaginary = .allocate(capacity: bins)
        inputBlock = .allocate(capacity: blockSize)
        history = .allocate(capacity: blockSize)
        outputRing = .allocate(capacity: blockSize * 2)

        frame.initialize(repeating: 0, count: fftSize)
        specReal.initialize(repeating: 0, count: bins)
        specImaginary.initialize(repeating: 0, count: bins)
        fdlReal.initialize(repeating: 0, count: maxPartitions * bins)
        fdlImaginary.initialize(repeating: 0, count: maxPartitions * bins)
        accumReal.initialize(repeating: 0, count: bins)
        accumImaginary.initialize(repeating: 0, count: bins)
        timeReal.initialize(repeating: 0, count: bins)
        timeImaginary.initialize(repeating: 0, count: bins)
        inputBlock.initialize(repeating: 0, count: blockSize)
        history.initialize(repeating: 0, count: blockSize)
        outputRing.initialize(repeating: 0, count: blockSize * 2)
    }

    deinit {
        frame.deallocate()
        specReal.deallocate()
        specImaginary.deallocate()
        fdlReal.deallocate()
        fdlImaginary.deallocate()
        accumReal.deallocate()
        accumImaginary.deallocate()
        timeReal.deallocate()
        timeImaginary.deallocate()
        inputBlock.deallocate()
        history.deallocate()
        outputRing.deallocate()
    }

    /// True when an impulse is loaded.
    public var isLoaded: Bool { kernel != nil }

    /// Replaces the impulse and clears all state. Not real-time safe.
    public func load(impulse: [Float]) {
        kernel = IRKernel(impulse: impulse, blockSize: blockSize)
        applyKernelChange()
    }

    /// Shares an already prepared kernel. Not real-time safe.
    func load(kernel newKernel: IRKernel) {
        kernel = newKernel
        applyKernelChange()
    }

    /// Drops the impulse and all state.
    public func reset() {
        kernel = nil
        appliedPartitions = 0
        clearState()
    }

    /// Clears delay lines without changing the impulse.
    public func clear() {
        clearState()
    }

    private func applyKernelChange() {
        appliedPartitions = min(kernel?.partitionCount ?? 0, maxPartitions)
        clearState()
    }

    private func clearState() {
        inputCount = 0
        fdlPosition = 0
        outputRead = 0
        outputCount = 0
        inputBlock.update(repeating: 0, count: blockSize)
        history.update(repeating: 0, count: blockSize)
        outputRing.update(repeating: 0, count: blockSize * 2)
        fdlReal.update(repeating: 0, count: maxPartitions * bins)
        fdlImaginary.update(repeating: 0, count: maxPartitions * bins)
    }

    /// Processes in place or into a separate buffer. Real-time safe.
    public func process(
        input: UnsafePointer<Double>,
        output: UnsafeMutablePointer<Double>,
        frames: Int
    ) {
        guard let kernel, appliedPartitions > 0 else {
            for index in 0..<frames {
                output[index] = input[index]
            }
            return
        }

        for index in 0..<frames {
            inputBlock[inputCount] = Float(input[index])
            inputCount += 1
            if inputCount == blockSize {
                convolveBlock(kernel: kernel)
                inputCount = 0
            }
            output[index] = Double(popOutput())
        }
    }

    private func convolveBlock(kernel: IRKernel) {
        // Overlap-save frame: the previous block followed by the current one.
        for index in 0..<blockSize {
            frame[index] = history[index]
            frame[blockSize + index] = inputBlock[index]
            history[index] = inputBlock[index]
        }

        fft.forward(
            real: frame,
            imaginary: nil,
            outputReal: specReal,
            outputImaginary: specImaginary
        )

        fdlPosition += 1
        if fdlPosition >= appliedPartitions {
            fdlPosition = 0
        }
        let writeSlot = fdlPosition
        let writeOffset = writeSlot * bins
        for bin in 0..<bins {
            fdlReal[writeOffset + bin] = specReal[bin]
            fdlImaginary[writeOffset + bin] = specImaginary[bin]
        }

        accumReal.update(repeating: 0, count: bins)
        accumImaginary.update(repeating: 0, count: bins)

        for partition in 0..<appliedPartitions {
            var readSlot = fdlPosition - partition
            if readSlot < 0 { readSlot += appliedPartitions }
            let readOffset = readSlot * bins
            let kernelOffset = partition * bins
            for bin in 0..<bins {
                let ar = fdlReal[readOffset + bin]
                let ai = fdlImaginary[readOffset + bin]
                let br = kernel.spectraReal[kernelOffset + bin]
                let bi = kernel.spectraImaginary[kernelOffset + bin]
                accumReal[bin] += ar * br - ai * bi
                accumImaginary[bin] += ar * bi + ai * br
            }
        }

        fft.inverse(
            real: accumReal,
            imaginary: accumImaginary,
            outputReal: timeReal,
            outputImaginary: timeImaginary
        )

        // Overlap-save keeps the second half of the circular convolution.
        for index in 0..<blockSize {
            outputRing[(outputRead + outputCount) % (blockSize * 2)] = timeReal[blockSize + index]
            outputCount += 1
        }
    }

    @inline(__always)
    private func popOutput() -> Float {
        guard outputCount > 0 else { return 0 }
        let value = outputRing[outputRead]
        outputRead += 1
        if outputRead >= blockSize * 2 { outputRead = 0 }
        outputCount -= 1
        return value
    }
}
