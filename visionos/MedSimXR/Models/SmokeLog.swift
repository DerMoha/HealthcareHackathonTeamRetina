import Foundation

/// Runtime evidence for the simulator smoke test. No-op unless launched with `-autoDemo`.
/// Lines go to stdout and to <app container>/Documents/smoke.log, which
/// visionos/scripts/simulator_smoke_test.sh reads to time its screenshots.
enum SmokeLog {
    static let scenarioDemo = ProcessInfo.processInfo.arguments.contains("-scenarioDemo")
    static let enabled = ProcessInfo.processInfo.arguments.contains("-autoDemo") || scenarioDemo
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("smoke.log")

    static func mark(_ line: String) {
        guard enabled else { return }
        print("SMOKE \(line)")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
