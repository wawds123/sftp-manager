import Foundation

// The app is normally launched as a GUI. `--selftest` runs the headless checks
// in SelfTest.swift instead — this machine has Command Line Tools only, so
// XCTest is unavailable and this is how the core logic gets verified.
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--selftest") {
    SelfTest.run(arguments: arguments)
} else if arguments.contains("--snapshot") {
    MainActor.assumeIsolated { Snapshot.run(arguments: arguments) }
} else {
    // `--demo` opens the normal window on invented data, for screenshots. It
    // has to be decided before the model exists, since that is what picks the
    // scratch connection store.
    if arguments.contains("--demo") { Demo.isOn = true }
    SFTPManagerApp.main()
}
