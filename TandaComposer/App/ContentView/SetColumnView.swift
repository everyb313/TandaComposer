import SwiftUI
import AppKit

struct SetColumnView<Content: View>: View {

    @EnvironmentObject private var setlistStore: SetlistStore
    @EnvironmentObject private var settings: AppSettings

    @Binding var showingOrchestraBreakdown: Bool
    @Binding var columnHeaderHeight: CGFloat
    let content: Content

    init(
        showingOrchestraBreakdown: Binding<Bool>,
        columnHeaderHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
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
    }
}
