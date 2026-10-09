//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - M3U8 Document

struct M3U8Document:
    FileDocument {

    static var readableContentTypes:
        [UTType] = []

    let data:
        Data


    init(
        data:
            Data
    ) {

        self.data =
            data
    }


    init(
        configuration:
            ReadConfiguration
    ) throws {

        fatalError(
            "M3U8Document is export-only"
        )
    }


    func fileWrapper(
        configuration:
            WriteConfiguration
    ) throws -> FileWrapper {

        FileWrapper(
            regularFileWithContents:
                data
        )
    }
}


