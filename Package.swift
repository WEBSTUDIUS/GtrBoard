// swift-tools-version: 5.9
//
//  Package.swift
//  GtrBoard
//
//  SwiftPM manifest. BoardCore is a pure DSP/model library (no Core Audio,
//  no AppKit) so the whole signal chain can be unit-tested headlessly.
//  The GtrBoard target contains the app, the low-latency audio engine and
//  the SwiftUI interface. GtrBoardSelfTest is a standalone test harness
//  because the Command Line Tools do not ship XCTest.
//
import PackageDescription

let package = Package(
    name: "GtrBoard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GtrBoard", targets: ["GtrBoard"])
    ],
    targets: [
        .target(
            name: "BoardCore",
            path: "Sources/BoardCore",
            resources: [.copy("IRs")]
        ),
        .executableTarget(
            name: "GtrBoard",
            dependencies: ["BoardCore"],
            path: "Sources/GtrBoard"
        ),
        .executableTarget(
            name: "GtrBoardSelfTest",
            dependencies: ["BoardCore"],
            path: "Tests/GtrBoardSelfTest"
        )
    ]
)
