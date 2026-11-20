//  FXNode.swift
//  GtrBoard
//
//  The contract every effect implements. Nodes render in place on planar
//  double buffers, own all of their state and never allocate while audio is
//  running. Parameters arrive in descriptor order, once per settings change.

import Foundation

/// One real-time effect processor.
protocol FXNode: AnyObject {
    /// Which pedal this node implements.
    var kind: FXKind { get }

    /// Allocates buffers for a sample rate. Called only while audio is stopped.
    func prepare(sampleRate: Double, maxFrames: Int)

    /// Clears delay lines and filter memory.
    func reset()

    /// Applies a new parameter block in descriptor order.
    func apply(values: UnsafePointer<Double>, count: Int)

    /// Processes stereo planar audio in place without allocating.
    func process(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frames: Int
    )
}

/// Index of a parameter inside a descriptor. Every node resolves its indices
/// once at init, so reordering the descriptor cannot silently swap knobs.
func parameterIndex(_ id: String, in kind: FXKind) -> Int {
    kind.descriptor.parameters.firstIndex { $0.id == id } ?? 0
}

/// Shared helper: reads a value from an applied parameter block.
@inline(__always)
func parameterValue(_ values: UnsafePointer<Double>, _ index: Int, count: Int, fallback: Double) -> Double {
    guard index >= 0, index < count else { return fallback }
    let value = values[index]
    return value.isFinite ? value : fallback
}
