//
//  BoundedConcurrency.swift
//
//  Copyright © 2026 Hagen Eckert.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

/// Runs an async operation over a collection with a maximum number of
/// tasks in flight at once. Swift's TaskGroup has no built-in concurrency
/// cap — without this, kicking off one Task per file in a large library
/// (thousands of files) would spawn all of them at once, contending
/// heavily for disk I/O with no real throughput benefit.
public enum BoundedConcurrency {
    /// - Parameters:
    ///   - items: the work items to process.
    ///   - maxConcurrent: how many `operation` calls may run at once
    ///     (the spec's "4-8 threads" guidance — tune per call site).
    ///   - operation: transforms one item; may throw without cancelling
    ///     the other in-flight work (errors are collected, not propagated
    ///     immediately), so one bad file doesn't abort an entire import.
    /// - Returns: results in the same order as `items`, paired with any
    ///   error that occurred for that item.
    public static func run<Item: Sendable, Result: Sendable>(
        items: [Item],
        maxConcurrent: Int = 6,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil,
        operation: @escaping @Sendable (Item) async -> Swift.Result<Result, Error>
    ) async -> [Swift.Result<Result, Error>] {
        var results = [Swift.Result<Result, Error>?](repeating: nil, count: items.count)
        var completed = 0

        await withTaskGroup(of: (Int, Swift.Result<Result, Error>).self) { group in
            var nextIndex = 0

            func addNext() {
                guard nextIndex < items.count else { return }
                let index = nextIndex
                let item = items[index]
                nextIndex += 1
                group.addTask {
                    (index, await operation(item))
                }
            }

            for _ in 0..<min(maxConcurrent, items.count) {
                addNext()
            }

            for await (index, result) in group {
                results[index] = result
                completed += 1
                onProgress?(completed, items.count)
                addNext()
            }
        }

        return results.map { $0! }
    }
}
