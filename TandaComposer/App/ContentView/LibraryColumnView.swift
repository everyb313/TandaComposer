import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct LibraryColumnView<Content: View>: View {

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @Binding var smartSelection: SmartlistSelection
    @Binding var tandaFolderSelection: TandaFolderSelection
    @Binding var tandaDanceFilter: TandaDanceFilter
    @Binding var trackDanceFilter: TandaDanceFilter
    @Binding var libraryDisplayMode: LibraryDisplayMode
    @Binding var showingModeHelp: Bool
    @Binding var savedSetlistDuplicateCheckEnabled: Bool
    @Binding var columnHeaderHeight: CGFloat

    let savedSetlistViewer: SavedSetlistViewerStore
    let tandaStore: TandaStore
    @Binding var showingImporter: Bool

    let content: Content

    init(
        smartSelection: Binding<SmartlistSelection>,
        tandaFolderSelection: Binding<TandaFolderSelection>,
        tandaDanceFilter: Binding<TandaDanceFilter>,
        trackDanceFilter: Binding<TandaDanceFilter>,
        libraryDisplayMode: Binding<LibraryDisplayMode>,
        showingModeHelp: Binding<Bool>,
        savedSetlistDuplicateCheckEnabled: Binding<Bool>,
        columnHeaderHeight: Binding<CGFloat>,
        savedSetlistViewer: SavedSetlistViewerStore,
        tandaStore: TandaStore,
        showingImporter: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self._smartSelection = smartSelection
        self._tandaFolderSelection = tandaFolderSelection
        self._tandaDanceFilter = tandaDanceFilter
        self._trackDanceFilter = trackDanceFilter
        self._libraryDisplayMode = libraryDisplayMode
        self._showingModeHelp = showingModeHelp
        self._savedSetlistDuplicateCheckEnabled = savedSetlistDuplicateCheckEnabled
        self._columnHeaderHeight = columnHeaderHeight
        self.savedSetlistViewer = savedSetlistViewer
        self.tandaStore = tandaStore
        self._showingImporter = showingImporter
        self.content = content()
    }

    var body: some View {


        VStack(
            spacing:
                0
        ) {

            HStack(
                spacing:
                    6
            ) {

                // =====================================================
                // TRACKS / TANDAS SWITCH
                // =====================================================

                Picker(
                    "",
                    selection:
                        $libraryDisplayMode
                ) {

                    Text(
                        "TrackLibrary"
                    )
                    .tag(
                        LibraryDisplayMode.tracks
                    )


                    Text(
                        "TandaLibrary"
                    )
                    .tag(
                        LibraryDisplayMode.tandas
                    )


                    Text(
                        "SavedSetlist"
                    )
                    .tag(
                        LibraryDisplayMode.savedsetlist
                    )
                }
                .pickerStyle(
                    .segmented
                )
                .fixedSize()


                // =====================================================
                // MODE HELP
                //
                // Replaces the old plain-text .help() tooltip that used
                // to hang directly off the Picker above — same three
                // sections, now a popover so the titles can actually be
                // bold/larger instead of flat tooltip text.
                // =====================================================

                Button {

                    showingModeHelp.toggle()

                } label: {

                    Image(
                        systemName:
                            "questionmark.circle"
                    )
                    .foregroundStyle(
                        showingModeHelp
                        ? Color.accentColor
                        : Color.gray
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .help(
                    "How These Modes Work"
                )
                .popover(
                    isPresented:
                        $showingModeHelp
                ) {

                    LibraryModeHelpView()
                }

                
                // =====================================================
                // ACTIVE LIBRARY NAME
                //
                // Only shown in TrackLibrary mode — TandaLibrary and
                // Setlist have their own name displays already
                // (see activeLibraryFilterLabel below: Folder for
                // .tandas, Setlist name for .setlist).
                // =====================================================

                if libraryDisplayMode == .tracks {

                    Text(
                        "Library: "
                        + libraryStore.currentLibraryName
                    )
                    .font(
                        .title3
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(
                        1
                    )
                }


                // =====================================================
                // ACTIVE FILTER INDICATOR
                //
                // Only shown when a Smartlist (Tracks) or folder
                // (Tandas) filter is actually applied — hidden on
                // "Show All". Placed right after the Library name,
                // left-aligned in the gap before the lock icon (the
                // Spacer below pushes the lock icon to the far right,
                // not this label).
                // =====================================================

                if let label =
                    activeLibraryFilterLabel {

                    Text(
                        label
                    )
                    .font(
                        .title3
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(
                        1
                    )
                }


                Spacer()


                // =====================================================
                // DANCE TYPE FILTER
                //
                // A = all
                // T = Tango
                // V = Vals
                // M = Milonga
                // X = VariousGenres
                //
                // TrackLibrary: the buttons are enabled while Smartlists
                // is on "Show All", OR while the selected Smartlist's
                // name doesn't encode a single defined dance type (see
                // trackDanceFilterButtonsShouldShow above). Only a
                // Smartlist whose name's genre component is exactly
                // T/V/M disables them.
                //
                // TandaLibrary: existing independent Tanda filter.
                // =====================================================

                if libraryDisplayMode == .tracks {

                    HStack(
                        spacing:
                            3
                    ) {

                        ForEach(
                            TandaDanceFilter.allCases
                        ) { filter in

                            Button {

                                trackDanceFilter =
                                    filter

                            } label: {

                                Text(
                                    filter.title
                                )
                                .font(
                                    .system(
                                        size:
                                            14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    Color.white
                                )
                                .frame(
                                    width:
                                        22,
                                    height:
                                        22
                                )
                                .background(
                                    trackDanceFilter == filter
                                    ? Color.blue
                                    : Color.secondary.opacity(0.35)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            4
                                    )
                                )
                                .opacity(
                                    trackDanceFilterButtonsShouldShow
                                    ? 1
                                    : 0.35
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .disabled(
                                !trackDanceFilterButtonsShouldShow
                            )
                            .help(
                                trackDanceFilterButtonsShouldShow
                                ? filter.helpText
                                : "Disabled while a Smartlist with a defined genre is active"
                            )
                        }
                    }
                }

                if libraryDisplayMode == .tandas {

                    HStack(
                        spacing:
                            3
                    ) {

                        ForEach(
                            TandaDanceFilter.allCases
                        ) { filter in

                            Button {

                                tandaDanceFilter =
                                    filter

                            } label: {

                                Text(
                                    filter.title
                                )
                                .font(
                                    .system(
                                        size:
                                            14,
                                        weight:
                                            .semibold
                                    )
                                )
                                .foregroundStyle(
                                    Color.white
                                )
                                .frame(
                                    width:
                                        22,
                                    height:
                                        22
                                )
                                .background(
                                    tandaDanceFilter == filter
                                    ? Color.blue
                                    : Color.secondary.opacity(0.35)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius:
                                            4
                                    )
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .help(
                                filter.helpText
                            )
                        }
                    }
                }


                // =====================================================
                // SAVED SETLIST DUPLICATE CHECK
                //
                // Only in SavedSetlist mode while a saved Setlist is
                // shown. Sits directly left of the Library lock.
                // =====================================================

                if libraryDisplayMode == .savedsetlist,
                   savedSetlistViewer.setlistName != nil {

                    Button {

                        savedSetlistDuplicateCheckEnabled.toggle()

                    } label: {

                        Image(
                            systemName:
                                savedSetlistDuplicateCheckEnabled
                                ? "doc.on.doc.fill"
                                : "doc.on.doc"
                        )
                        .foregroundStyle(
                            savedSetlistDuplicateCheckEnabled
                            ? Color.orange
                            : Color.gray
                        )
                        .font(
                            .system(size: 18)
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    .help(
                        savedSetlistDuplicateCheckEnabled
                        ? "Duplicate check is on — highlight tracks already in the active Setlist"
                        : "Duplicate check is off"
                    )
                    .accessibilityLabel(
                        "Duplicate check"
                    )
                    .accessibilityValue(
                        savedSetlistDuplicateCheckEnabled
                        ? "On"
                        : "Off"
                    )
                    .accessibilityHint(
                        "Toggles duplicate checking against the active Setlist"
                    )
                }


                // =====================================================
                // LIBRARY LOCK
                // =====================================================

                Button {

                    libraryStore.isLocked.toggle()

                } label: {

                    Image(
                        systemName:
                            libraryStore.isLocked
                            ? "lock.fill"
                            : "lock.open.fill"
                    )
                    .foregroundStyle(
                        libraryStore.isLocked
                        ? Color.gray
                        : Color.orange
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .help(
                    libraryStore.isLocked
                    ? "Unlock Library"
                    : "Lock Library"
                )
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                6
            )
            .background(
                GeometryReader { proxy in

                    Color.clear
                        .preference(
                            key:
                                ColumnHeaderHeightKey.self,
                            value:
                                proxy.size.height
                        )
                }
            )
            .frame(
                height:
                    columnHeaderHeight > 0
                    ? columnHeaderHeight
                    : nil
            )


            Divider()


            content
        }
        .frame(
            maxWidth:
                .infinity,
            maxHeight:
                .infinity
        )
    }

    // MARK: - Active Library Filter Label
    //
    // Compact indicator shown in the libraryColumn header when a filter
    // is active — a Smartlist in Tracks mode, or a folder in Tandas
    // mode. Hidden entirely on "Show All" so the common case stays
    // uncluttered. (Replaces the old unused `libraryTitle`, which also
    // always prefixed the Library name — dropped here since the Library
    // name isn't otherwise shown persistently anywhere.)

    private var activeLibraryFilterLabel: String? {

        switch libraryDisplayMode {

        case .tracks:

            if case .node(let node) =
                smartSelection {

                return "Smartlist: \(node.name)"
            }

            return nil


        case .tandas:

            if case .folder(let path) =
                tandaFolderSelection {

                return "Folder: \(path)"
            }

            return nil


        case .savedsetlist:

            if let name =
                savedSetlistViewer.setlistName {

                return "Setlist: \(name)"
            }

            return nil
        }
    }


    // MARK: - Track Dance Filter Buttons Visibility
    //
    // Show All → always show. A selected Smartlist → show only if its
    // name's genre component is NOT a single defined dance type.
    // Naming convention: ###_<genre>_<artist>_<albumartist>_<year>.
    // Genre component exactly "T"/"V"/"M" (case-insensitive) = defined
    // → hide the buttons. Anything else (explicitly "TVM"/"All"/"Mix",
    // or a name that doesn't match this pattern at all) = not defined
    // → show the buttons.

    private var trackDanceFilterButtonsShouldShow: Bool {

        guard case .node(let node) = smartSelection else {

            // .showAll
            return true
        }

        let components =
            node.name.components(
                separatedBy: "_"
            )

        guard components.count >= 2 else {
            return true
        }

        let genreToken =
            components[1]
                .trimmingCharacters(
                    in: .whitespaces
                )
                .lowercased()

        let definedGenreTokens:
            Set<String> = ["t", "v", "m"]

        return !definedGenreTokens.contains(
            genreToken
        )
    }



}
