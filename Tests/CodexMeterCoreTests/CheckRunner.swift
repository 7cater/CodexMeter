import Foundation

private var failures = 0
func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    if lhs != rhs { failures += 1; print("FAIL \(file):\(line): \(lhs) != \(rhs)") }
}
func checkEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) {
    if abs(lhs - rhs) > accuracy { failures += 1; print("FAIL \(file):\(line): \(lhs) != \(rhs)") }
}
func checkNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    if value != nil { failures += 1; print("FAIL \(file):\(line): expected nil") }
}
func checkNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    if value == nil { failures += 1; print("FAIL \(file):\(line): expected value") }
}
func checkFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    checkEqual(value, false, file: file, line: line)
}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "CoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected non-nil value"]) }
    return value
}

@main
enum CheckRunner {
    static func main() async {
        let suite = CoreTests()
        let checks: [(String, () async throws -> Void)] = [
            ("cumulative deltas and repeats", { suite.testCumulativeDeltasAndRepeatedNotifications() }),
            ("cache/reasoning inclusion", { suite.testCacheAndReasoningAreNotDoubleCounted() }),
            ("counter reset and model change", { suite.testCounterResetAndModelChange() }),
            ("carry-in baseline", { suite.testCarryInUsesLastRequestRatherThanOldCumulativeHistory() }),
            ("null info and partial line", { suite.testNullInfoAndPartialWriterLine() }),
            ("malformed complete line", { suite.testMalformedCompleteLineIsReported() }),
            ("archive/fork dedup and cache invalidation", { try await suite.testScanDeduplicatesArchiveAndRefreshAndPicksUpAppend() }),
            ("pricing and unknown models", { try suite.testPricingCacheSubtractionAndUnknownModel() }),
            ("long context, fast and cache writes", { try suite.testLongContextFastAndCacheWriteCost() }),
            ("local date aggregation and empty days", { try suite.testDailyAggregationUsesLocalTimeAndZeroFillsDays() }),
            ("rate window duration mapping", { try suite.testRateWindowMappingByDuration() }),
            ("missing bucket", { try suite.testMissingBucketDoesNotBecomeZeroUsage() }),
            ("RPC handshake", { try await suite.testRPCHandshakeAndResponse() }),
            ("RPC deadline", { try await suite.testRPCDeadline() })
        ]
        for (name, check) in checks {
            let previous = failures
            do { try await check() }
            catch { failures += 1; print("FAIL \(name): \(error)") }
            if previous == failures { print("PASS \(name)") }
        }
        print("\(checks.count) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
