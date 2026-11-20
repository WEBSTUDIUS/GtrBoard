//  LevelMeter.swift
//  GtrBoard
//
//  Lock-free-ish peak meter shared by the audio thread and the UI. The audio
//  thread only ever uses `trylock`, so a busy UI can never stall the render
//  callback; the meter simply keeps its last published value.

import Foundation
import os.lock

public final class LevelMeter: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock_s>
    private var inputPeak: Float = 0
    private var outputPeak: Float = 0

    public init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock_s())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Called from the audio thread with the peaks of one render block.
    func publish(input: Float, output: Float) {
        guard os_unfair_lock_trylock(lock) else { return }
        inputPeak = input
        outputPeak = output
        os_unfair_lock_unlock(lock)
    }

    /// Last published peaks. Safe to call from the main thread.
    public func snapshot() -> (input: Float, output: Float) {
        os_unfair_lock_lock(lock)
        let value = (inputPeak, outputPeak)
        os_unfair_lock_unlock(lock)
        return value
    }
}
