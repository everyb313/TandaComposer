import Foundation

enum AppNotification {

    static let tandaPreviewSongSelected =
        Notification.Name("TandaComposer.PreviewSongSelected")

    static let tandaPreviewSongDoubleClicked =
        Notification.Name("TandaComposer.PreviewSongDoubleClicked")

    static let tandaSaved =
        Notification.Name("TandaComposer.TandaSaved")

    static let setlistSaved =
        Notification.Name("TandaComposer.SetlistSaved")

    static let tandaComposerBackupImported =
        Notification.Name("TandaComposer.BackupImported")

    static let tandaComposerLibrarySwitched =
        Notification.Name("TandaComposer.LibrarySwitched")
}


// MARK: - Notification

extension Notification.Name {

    static let tandaLibraryAddSelectedToSet =
        Notification.Name(
            "tandaLibraryAddSelectedToSet"
        )
}
