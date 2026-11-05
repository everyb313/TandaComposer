//
//  TandaConventionsTests.swift
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

import XCTest
import Foundation

/// `TandaConventions` mirrors the Orchestra / Singer tag-source settings
/// for code that writes a Tanda file without having the settings at hand.
@MainActor
final class TandaConventionsTests: XCTestCase {

    private var savedOrchestra: TagSource = .artist
    private var savedSinger: TagSource = .albumArtist

    override func setUp() {
        super.setUp()
        savedOrchestra = TandaConventions.orchestra
        savedSinger = TandaConventions.singer
    }

    override func tearDown() {
        TandaConventions.orchestra = savedOrchestra
        TandaConventions.singer = savedSinger
        super.tearDown()
    }

    func testChangingTheSettingsUpdatesTheMirror() throws {
        try withTemporaryAppRoot { _ in
            let settings = AppSettings()

            settings.orchestraSource = .grouping
            settings.singerSource = .artist

            XCTAssertEqual(TandaConventions.orchestra, .grouping)
            XCTAssertEqual(TandaConventions.singer, .artist)
        }
    }

    func testLoadingSavedSettingsUpdatesTheMirror() throws {
        try withTemporaryAppRoot { _ in
            let first = AppSettings()
            first.orchestraSource = .albumArtist
            first.singerSource = .grouping
            first.save()

            // Forget what the mirror knows, then start "the app" again.
            TandaConventions.orchestra = .artist
            TandaConventions.singer = .artist

            _ = AppSettings()

            XCTAssertEqual(TandaConventions.orchestra, .albumArtist)
            XCTAssertEqual(TandaConventions.singer, .grouping)
        }
    }
}
