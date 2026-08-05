import Foundation

/// Opt-in main-thread responsiveness instrumentation.
///
/// Two jobs:
///
///  1. **Watchdog** — a dedicated background thread round-trips a block through
///     the main queue every 100 ms. The round-trip time *is* main-thread
///     latency, so a stall shows up as a single number with a timestamp and
///     needs no sampling tools. This is the same quantity the socket `ping`
///     measures, but observed from inside the process and at 10 Hz.
///
///  2. **Hot-path timers** — `MainThreadProbe.measure` wraps a suspect call and
///     records how long it actually took, so a stall can be attributed to a
///     named call instead of guessed at. Cost when disabled is one `Bool` read.
///
/// Entirely off unless `FADICODE_PERF_LOG` names a writable path. Nothing in
/// the shipping app turns it on; it exists so this class of bug is falsifiable
/// next time instead of re-litigated.
///
/// Output is NDJSON, one record per line:
///
///     {"t":1234.567,"ev":"readTerminalContent","ms":3412.8,"bytes":"8412331"}
enum MainThreadProbe {

    // MARK: - Configuration

    /// Log every hot-path call that takes at least this long.
    private static let hotPathThresholdMs: Double = 2.0

    /// Log every main-queue round trip that takes at least this long.
    private static let stallThresholdMs: Double = 100.0

    static let isEnabled: Bool = {
        guard let path = ProcessInfo.processInfo.environment["FADICODE_PERF_LOG"],
              !path.isEmpty else { return false }
        FileManager.default.createFile(atPath: path, contents: nil)
        return true
    }()

    private static let sink: FileHandle? = {
        guard isEnabled,
              let path = ProcessInfo.processInfo.environment["FADICODE_PERF_LOG"]
        else { return nil }
        return FileHandle(forWritingAtPath: path)
    }()

    private static let writeQueue = DispatchQueue(label: "com.fadicode.perfprobe.write")
    private static let start = ProcessInfo.processInfo.systemUptime

    // MARK: - Recording

    static func record(_ event: String, ms: Double, extra: [String: String] = [:]) {
        guard isEnabled else { return }
        let t = ProcessInfo.processInfo.systemUptime - start
        var line = "{\"t\":\(String(format: "%.3f", t)),\"ev\":\"\(event)\",\"ms\":\(String(format: "%.2f", ms))"
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) {
            line += ",\"\(k)\":\"\(v)\""
        }
        line += "}\n"
        writeQueue.async {
            if let data = line.data(using: .utf8) { sink?.write(data) }
        }
    }

    /// Times `body`, recording it when it crosses the hot-path threshold.
    ///
    /// `extra` is an autoclosure so the (possibly expensive) description of the
    /// result is only built for calls that are actually slow.
    @inline(__always)
    static func measure<T>(
        _ event: String,
        extra: (T) -> [String: String] = { _ in [:] },
        _ body: () -> T
    ) -> T {
        guard isEnabled else { return body() }
        let t0 = ProcessInfo.processInfo.systemUptime
        let result = body()
        let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000.0
        if ms >= hotPathThresholdMs {
            record(event, ms: ms, extra: extra(result))
        }
        return result
    }

    // MARK: - Watchdog

    private static var watchdogStarted = false

    /// Starts the main-queue latency watchdog. Idempotent.
    static func startWatchdog() {
        guard isEnabled, !watchdogStarted else { return }
        watchdogStarted = true
        let thread = Thread {
            while true {
                let t0 = ProcessInfo.processInfo.systemUptime
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let ms = (ProcessInfo.processInfo.systemUptime - t0) * 1000.0
                if ms >= stallThresholdMs {
                    record("mainQueueStall", ms: ms)
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread.name = "com.fadicode.perfprobe.watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
        record("watchdogStarted", ms: 0)
    }
}
