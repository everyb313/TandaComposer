import XCTest
import Foundation

/// Smoke tests: prove that the TandaCoreTests target builds, links GRDB and
/// can run code from TandaCore. Real tests live in the folders that mirror
/// TandaCore (TandaKit/, Export/, Import/, ...).
@MainActor
final class TandaCoreSmokeTests: XCTestCase {

    func testInMemoryDatabaseMigrates() throws {
        XCTAssertNoThrow(try DatabaseManager())
    }

    func testAppNotificationNameIsStable() {
        XCTAssertEqual(AppNotification.tandaSaved.rawValue, "TandaComposer.TandaSaved")
    }
}
