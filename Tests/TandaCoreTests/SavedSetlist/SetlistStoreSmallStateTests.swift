import XCTest
import Foundation

/// Two small pieces of Setlist state: the Tanda coloring toggle and the
/// "already saved" notice counter.
@MainActor
final class SetlistStoreSmallStateTests: XCTestCase {

    private func makeStore() throws -> SetlistStore {
        SetlistStore(db: try DatabaseManager())
    }

    func testTandaColoringIsOnByDefaultAndTogglesBackAndForth() throws {
        let store = try makeStore()

        XCTAssertTrue(store.isTandaColoringEnabled)

        store.toggleTandaColoring()
        XCTAssertFalse(store.isTandaColoringEnabled)

        store.toggleTandaColoring()
        XCTAssertTrue(store.isTandaColoringEnabled)
    }

    func testEachAnnouncementCountsOneTickSoTheViewCanReactToEveryRepeat() throws {
        let store = try makeStore()
        let start = store.alreadySavedNoticeTick

        store.announceAlreadySaved()
        store.announceAlreadySaved()
        store.announceAlreadySaved()

        XCTAssertEqual(store.alreadySavedNoticeTick, start + 3)
    }
}
