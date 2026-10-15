import XCTest
import Foundation

private nonisolated enum TestError: Error {
    case boom
}

/// Counts how many operations are inside the critical section at once.
private actor ConcurrencyProbe {
    private var current = 0
    private(set) var maxSeen = 0

    func enter() {
        current += 1
        maxSeen = max(maxSeen, current)
    }

    func leave() {
        current -= 1
    }
}

/// Thread-safe append-only log for callbacks that are not async.
private nonisolated final class LockedLog<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
final class BoundedConcurrencyTests: XCTestCase {

    func testResultsKeepTheOrderOfTheItems() async throws {
        let items = Array(1...10)

        let results = await BoundedConcurrency.run(
            items: items,
            maxConcurrent: 4,
            operation: { (item: Int) async -> Result<Int, Error> in
                // Earlier items take longer, so they finish last.
                try? await Task.sleep(nanoseconds: UInt64(11 - item) * 3_000_000)
                return .success(item * 2)
            }
        )

        XCTAssertEqual(try results.map { try $0.get() }, items.map { $0 * 2 })
    }

    func testNeverExceedsTheConcurrencyLimit() async {
        let probe = ConcurrencyProbe()

        _ = await BoundedConcurrency.run(
            items: Array(0..<12),
            maxConcurrent: 3,
            operation: { (item: Int) async -> Result<Int, Error> in
                await probe.enter()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await probe.leave()
                return .success(item)
            }
        )

        let maxSeen = await probe.maxSeen
        XCTAssertEqual(maxSeen, 3, "should use the full limit, but never more")
    }

    func testLimitOfOneRunsSerially() async {
        let probe = ConcurrencyProbe()

        _ = await BoundedConcurrency.run(
            items: Array(0..<5),
            maxConcurrent: 1,
            operation: { (item: Int) async -> Result<Int, Error> in
                await probe.enter()
                try? await Task.sleep(nanoseconds: 5_000_000)
                await probe.leave()
                return .success(item)
            }
        )

        let maxSeen = await probe.maxSeen
        XCTAssertEqual(maxSeen, 1)
    }

    func testLimitLargerThanItemCountIsFine() async throws {
        let results = await BoundedConcurrency.run(
            items: [1, 2],
            maxConcurrent: 10,
            operation: { (item: Int) async -> Result<Int, Error> in .success(item) }
        )

        XCTAssertEqual(try results.map { try $0.get() }, [1, 2])
    }

    func testEmptyInputGivesNoResultsAndNoProgress() async {
        let progress = LockedLog<Int>()

        let results = await BoundedConcurrency.run(
            items: [Int](),
            maxConcurrent: 4,
            onProgress: { completed, _ in progress.append(completed) },
            operation: { (item: Int) async -> Result<Int, Error> in .success(item) }
        )

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(progress.values.isEmpty)
    }

    func testAFailingItemDoesNotStopTheOthers() async {
        let results = await BoundedConcurrency.run(
            items: [1, 2, 3, 4, 5],
            maxConcurrent: 2,
            operation: { (item: Int) async -> Result<Int, Error> in
                if item == 3 {
                    return .failure(TestError.boom)
                }
                return .success(item)
            }
        )

        XCTAssertEqual(results.count, 5)

        if case .failure(let error) = results[2] {
            XCTAssertTrue(error is TestError)
        } else {
            XCTFail("the third item should have failed")
        }

        let successes = results.filter {
            if case .success = $0 { return true }
            return false
        }
        XCTAssertEqual(successes.count, 4)
    }

    func testProgressCountsUpToTheTotal() async {
        let completedLog = LockedLog<Int>()
        let totalLog = LockedLog<Int>()

        _ = await BoundedConcurrency.run(
            items: Array(0..<5),
            maxConcurrent: 2,
            onProgress: { completed, total in
                completedLog.append(completed)
                totalLog.append(total)
            },
            operation: { (item: Int) async -> Result<Int, Error> in .success(item) }
        )

        XCTAssertEqual(completedLog.values, [1, 2, 3, 4, 5])
        XCTAssertEqual(totalLog.values, [5, 5, 5, 5, 5])
    }

    func testProgressIsAlsoReportedForFailures() async {
        let completedLog = LockedLog<Int>()

        _ = await BoundedConcurrency.run(
            items: [1, 2, 3],
            maxConcurrent: 3,
            onProgress: { completed, _ in completedLog.append(completed) },
            operation: { (item: Int) async -> Result<Int, Error> in .failure(TestError.boom) }
        )

        XCTAssertEqual(completedLog.values, [1, 2, 3])
    }
}
