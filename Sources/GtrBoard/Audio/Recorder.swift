//  Recorder.swift
//  GtrBoard
//
//  Records the processed output to a 32-bit float WAV. The audio thread is a
//  lock-free producer into a single-producer/single-consumer ring; a
//  background queue drains it into an AVAudioFile. Nothing in the render
//  callback blocks, allocates or waits for the writer, so recording can never
//  punch holes in the signal.

import Foundation
import AVFoundation
import Darwin

final class Recorder: @unchecked Sendable {
    /// Twenty seconds at 48 kHz / ten at 96 kHz. The writer drains every 20 ms.
    private let capacity = 960_000
    private var left: UnsafeMutablePointer<Float>
    private var right: UnsafeMutablePointer<Float>

    // Monotonic sample counters. OSAtomicAdd64 with a zero delta is an atomic
    // load with a full barrier; the audio thread increments writeIndex only
    // after the samples are in place, and the writer increments readIndex only
    // after copying them out.
    private var writeIndex: Int64 = 0
    private var readIndex: Int64 = 0

    private let queue = DispatchQueue(label: "com.andreyilin.GtrBoard.recorder", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var file: AVAudioFile?
    private var scratchBuffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 48_000
    private var framesWritten: AVAudioFramePosition = 0
    private(set) var isRecording = false
    private(set) var outputURL: URL?
    private(set) var droppedFrames: Int64 = 0

    init() {
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        timer?.cancel()
        left.deallocate()
        right.deallocate()
    }

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(framesWritten) / sampleRate
    }

    /// Creates the WAV file and starts the drain timer. Call on the main thread.
    func start(url: URL, sampleRate: Double, bitDepth: Int = 24) throws {
        if isRecording {
            _ = stop()
        }

        let depth = bitDepth == 32 ? 32 : 24
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: depth,
            AVLinearPCMIsFloatKey: depth == 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let newFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let scratch = AVAudioPCMBuffer(
            pcmFormat: newFile.processingFormat,
            frameCapacity: 4_096
        ) else {
            throw NSError(
                domain: "GtrBoard.Recorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate the recording buffer."]
            )
        }

        writeIndex = 0
        readIndex = 0
        droppedFrames = 0
        framesWritten = 0
        self.sampleRate = sampleRate
        self.file = newFile
        self.scratchBuffer = scratch
        self.outputURL = url
        self.isRecording = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.02, repeating: 0.02, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.drainAll()
        }
        timer.resume()
        self.timer = timer
    }

    /// Called from the audio thread. No lock, no allocation.
    func append(left leftSamples: UnsafeMutablePointer<Double>,
                right rightSamples: UnsafeMutablePointer<Double>,
                frames: Int) {
        guard isRecording, frames > 0 else { return }

        let read = OSAtomicAdd64(0, &readIndex)
        let write = OSAtomicAdd64(0, &writeIndex)
        let used = write - read
        let free = Int64(capacity) - used
        guard free > 0 else {
            OSAtomicAdd64(Int64(frames), &droppedFrames)
            return
        }

        let toWrite = min(Int64(frames), free)
        var index = Int(write % Int64(capacity))
        for frame in 0..<Int(toWrite) {
            left[index] = Float(leftSamples[frame])
            right[index] = Float(rightSamples[frame])
            index += 1
            if index >= capacity { index = 0 }
        }
        OSAtomicAdd64(toWrite, &writeIndex)
        if toWrite < Int64(frames) {
            OSAtomicAdd64(Int64(frames) - toWrite, &droppedFrames)
        }
    }

    /// Stops recording, flushes everything buffered and closes the file.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return outputURL }
        isRecording = false
        // Let a callback that already passed the isRecording check finish its
        // append before the final drain.
        Thread.sleep(forTimeInterval: 0.020)
        timer?.cancel()
        timer = nil

        queue.sync {
            self.drainAll()
        }
        file = nil
        scratchBuffer = nil
        return outputURL
    }

    /// Runs on the recording queue. Copies one chunk under no lock, publishes
    /// the new read position, then writes it to disk.
    private func drainAll() {
        guard let file, let buffer = scratchBuffer else { return }
        let chunkCapacity = Int(buffer.frameCapacity)

        while true {
            let write = OSAtomicAdd64(0, &writeIndex)
            let read = OSAtomicAdd64(0, &readIndex)
            let available = write - read
            guard available > 0 else { return }

            let count = Int(min(available, Int64(chunkCapacity)))
            guard let channels = buffer.floatChannelData else { return }

            var index = Int(read % Int64(capacity))
            for frame in 0..<count {
                channels[0][frame] = left[index]
                if buffer.format.channelCount > 1 {
                    channels[1][frame] = right[index]
                }
                index += 1
                if index >= capacity { index = 0 }
            }
            // The samples are safely in the scratch buffer; the producer may
            // reuse this part of the ring.
            OSAtomicAdd64(Int64(count), &readIndex)

            buffer.frameLength = AVAudioFrameCount(count)
            do {
                try file.write(from: buffer)
                framesWritten += AVAudioFramePosition(count)
            } catch {
                return
            }
        }
    }
}
