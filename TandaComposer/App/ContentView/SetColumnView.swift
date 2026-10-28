import SwiftUI
import AppKit

struct SetColumnView<Content: View>: View {

    @EnvironmentObject private var setlistStore: SetlistStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sameTitleSession: SameTitleSession


    @Binding var libraryDisplayMode: LibraryDisplayMode
    @Binding var showingOrchestraBreakdown: Bool
    @Binding var columnHeaderHeight: CGFloat
    let content: Content

    init(
        libraryDisplayMode: Binding<LibraryDisplayMode>,
        showingOrchestraBreakdown: Binding<Bool>,
        columnHeaderHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._libraryDisplayMode = libraryDisplayMode
        self._showingOrchestraBreakdown = showingOrchestraBreakdown
        self._columnHeaderHeight = columnHeaderHeight
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

                Text(
                    "SetList:"
                )
                .font(
                    .headline
                )

                Text(
                    setlistStore.name
                )
                .font(
                    .headline
                )
                .lineLimit(
                    1
                )
                .truncationMode(
                    .tail
                )
                .frame(
                    maxWidth:
                        .infinity,
                    alignment:
                        .leading
                )


                // =====================================================
                // SAME-TITLE TRACKVIEW FILTER
                // =====================================================

                Button {
                    if sameTitleSession.trackViewFilterSong != nil {
                        // While active, the button always turns the filter off.
                        sameTitleSession.clearTrackViewFilter()
                    } else {
                        guard setlistStore.selectedRowIndexes.count == 1,
                              let index = setlistStore.selectedRowIndexes.first,
                              setlistStore.entries.indices.contains(index) else { return }
                        let entry = setlistStore.entries[index]
                        // Filter the existing TrackView only. Selecting a result
                        // continues to use TrackView's normal insertion behavior.
                        sameTitleSession.setTrackViewFilter(for: entry.song)
                        libraryDisplayMode = .tracks
                    }
                } label: {
                    Image(
                        systemName: sameTitleSession.trackViewFilterSong != nil
                            ? "questionmark.circle.fill"
                            : "questionmark.circle"
                    )
                    .font(.system(size: 18))
                    // Inactive is always gray; active uses the accent color.
                    .foregroundStyle(
                        sameTitleSession.trackViewFilterSong != nil
                            ? Color.orange
                            : Color.gray
                    )
                }
                .buttonStyle(.plain)
                .disabled(
                    sameTitleSession.trackViewFilterSong == nil
                        && setlistStore.selectedRowIndexes.count != 1
                )
                .help(
                    sameTitleSession.trackViewFilterSong != nil
                        ? "Turn off the same-title TrackView filter"
                        : "Show TrackView tracks with the selected Setlist title"
                )


                // =====================================================
                // DUPLICATE HIGHLIGHTING TOGGLE
                // =====================================================

                Button {

                    setlistStore.toggleDuplicateHighlighting()

                } label: {

                    Image(
                        systemName:
                            setlistStore.isDuplicateHighlightingEnabled
                            ? "doc.on.doc.fill"
                            : "doc.on.doc"
                    )
                    .foregroundStyle(
                        !setlistStore.isDuplicateHighlightingEnabled
                        ? Color.gray
                        : setlistStore.duplicateSongIDs.isEmpty
                        ? Color.green
                        : Color.orange
                    )
                    .font(
                        .system(size: 18)
                    )
                }
                .buttonStyle(
                    .plain
                )
                .disabled(
                    setlistStore.songs.isEmpty
                )
                .help(
                    !setlistStore.isDuplicateHighlightingEnabled
                    ? "Highlight Duplicates"
                    : setlistStore.duplicateSongIDs.isEmpty
                    ? "No duplicates found"
                    : "Hide Duplicate Highlighting"
                )


                // =====================================================
                // TANDA COLORING TOGGLE
                // =====================================================

                Button {

                    setlistStore.toggleTandaColoring()

                } label: {

                    Image(
                        systemName:
                            setlistStore.isTandaColoringEnabled
                            ? "paintpalette.fill"
                            : "paintpalette"
                    )
                    .foregroundStyle(
                        setlistStore.isTandaColoringEnabled
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
                    setlistStore.isTandaColoringEnabled
                    ? "Hide Tanda Coloring"
                    : "Show Tanda Coloring"
                )


                // =====================================================
                // ORCHESTRA MIX
                // =====================================================

                Button {

                    showingOrchestraBreakdown.toggle()

                } label: {

                    Image(
                        systemName:
                            "chart.bar"
                    )
                    .foregroundStyle(
                        showingOrchestraBreakdown
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
                .disabled(
                    setlistStore.songs.isEmpty
                )
                .help(
                    "Orchestra Mix"
                )
                .popover(
                    isPresented:
                        $showingOrchestraBreakdown
                ) {

                    OrchestraBreakdownView(
                        songs:
                            setlistStore.songs
                    )
                    .environmentObject(
                        settings
                    )
                }
            }
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                10 // war 5
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
        .onChange(of: setlistStore.selectedRowIndexes) { _, newSelection in
            // Keep the filter active, but retarget it whenever Setlist focus
            // moves to a different single row.
            guard sameTitleSession.trackViewFilterSong != nil,
                  newSelection.count == 1,
                  let index = newSelection.first,
                  setlistStore.entries.indices.contains(index) else {
                return
            }

            sameTitleSession.setTrackViewFilter(
                for: setlistStore.entries[index].song
            )
            libraryDisplayMode = .tracks
        }
    }
}
