//  FFT.swift
//  BoardCore
//
//  Small radix-2 complex FFT wrapper around Accelerate. The impulse-response
//  convolver and the feedback analyser both need a transform whose buffers
//  are allocated once: the audio thread must never touch the allocator.
//
//  Storage is split real/imaginary (`vDSP_fft_zop`), not the packed format
//  used by `vDSP_fft_zrip`, so the convolution code can multiply spectra bin
//  by bin without special cases around DC and Nyquist.

import Foundation
import Accelerate

final class FFT {
    /// Transform length, a power of two.
    let size: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let inputReal: UnsafeMutablePointer<Float>
    private let inputImaginary: UnsafeMutablePointer<Float>

    /// Creates a transform of `size` points. Returns nil when `size` is not a
    /// power of two or the setup cannot be allocated.
    init?(size: Int) {
        guard size >= 8, size & (size - 1) == 0 else { return nil }
        self.size = size

        let log = vDSP_Length(log2(Double(size)).rounded())
        guard let created = vDSP_create_fftsetup(log, FFTRadix(kFFTRadix2)) else { return nil }
        log2n = log
        setup = created

        inputReal = .allocate(capacity: size)
        inputImaginary = .allocate(capacity: size)
        inputReal.initialize(repeating: 0, count: size)
        inputImaginary.initialize(repeating: 0, count: size)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        inputReal.deallocate()
        inputImaginary.deallocate()
    }

    /// Forward transform. `imaginary` may be nil for a real input.
    func forward(
        real: UnsafePointer<Float>,
        imaginary: UnsafePointer<Float>?,
        outputReal: UnsafeMutablePointer<Float>,
        outputImaginary: UnsafeMutablePointer<Float>
    ) {
        inputReal.update(from: real, count: size)
        if let imaginary {
            inputImaginary.update(from: imaginary, count: size)
        } else {
            inputImaginary.update(repeating: 0, count: size)
        }
        var inputSplit = DSPSplitComplex(realp: inputReal, imagp: inputImaginary)
        var outputSplit = DSPSplitComplex(realp: outputReal, imagp: outputImaginary)
        vDSP_fft_zop(
            setup,
            &inputSplit, 1,
            &outputSplit, 1,
            log2n,
            FFTDirection(FFT_FORWARD)
        )
    }

    /// Inverse transform, normalised by `1 / size`.
    func inverse(
        real: UnsafePointer<Float>,
        imaginary: UnsafePointer<Float>,
        outputReal: UnsafeMutablePointer<Float>,
        outputImaginary: UnsafeMutablePointer<Float>
    ) {
        inputReal.update(from: real, count: size)
        inputImaginary.update(from: imaginary, count: size)
        var inputSplit = DSPSplitComplex(realp: inputReal, imagp: inputImaginary)
        var outputSplit = DSPSplitComplex(realp: outputReal, imagp: outputImaginary)
        vDSP_fft_zop(
            setup,
            &inputSplit, 1,
            &outputSplit, 1,
            log2n,
            FFTDirection(FFT_INVERSE)
        )
        var scale = 1 / Float(size)
        vDSP_vsmul(outputReal, 1, &scale, outputReal, 1, vDSP_Length(size))
        vDSP_vsmul(outputImaginary, 1, &scale, outputImaginary, 1, vDSP_Length(size))
    }
}
