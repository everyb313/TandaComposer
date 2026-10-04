//
//  ImportedTrack.swift
//
//  Copyright © 2026 Hagen Eckert.
//

import Foundation

/// A track as it was described by an external playlist/file.
///
/// This is deliberately NOT a `Song`. An imported track belongs to the
/// source file and is only converted into a current-library `Song` after
/// matching has completed.
public struct ImportedTrack: Identifiable, Equatable {

    public let id: UUID
    public let sourceIndex: Int

    public let path: String?
    public let filename: String?

    public let title: String?
    public let artist: String?
    public let albumArtist: String?
    public let grouping: String?

    public let album: String?
    public let duration: Int?
    public let bpm: Double?
    public let key: String?

    public let fileHash: String?
    public let libraryID: Int64?

    /// The original EXTINF display text, if one existed.
    public let sourceDisplayName: String?

    /// Recording year as written in the source line, e.g. "(1936)".
    /// Only a hint for ordering candidates, never a match criterion.
    public let year: Int?

    /// Singer as written in the source line, e.g. "(Gesang: …)".
    /// Only a hint for ordering candidates.
    public let singer: String?

    public init(
        id: UUID = UUID(),
        sourceIndex: Int,
        path: String? = nil,
        filename: String? = nil,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        grouping: String? = nil,
        album: String? = nil,
        duration: Int? = nil,
        bpm: Double? = nil,
        key: String? = nil,
        fileHash: String? = nil,
        libraryID: Int64? = nil,
        sourceDisplayName: String? = nil,
        year: Int? = nil,
        singer: String? = nil
    ) {
        self.id = id
        self.sourceIndex = sourceIndex
        self.path = path
        self.filename = filename
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.grouping = grouping
        self.album = album
        self.duration = duration
        self.bpm = bpm
        self.key = key
        self.fileHash = fileHash
        self.libraryID = libraryID
        self.sourceDisplayName = sourceDisplayName
        self.year = year
        self.singer = singer
    }
}

