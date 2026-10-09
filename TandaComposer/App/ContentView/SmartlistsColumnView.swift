import SwiftUI

struct SmartlistsColumnView<Content: View>: View {

    @EnvironmentObject private var smartlistStore: SmartlistStore

    @Binding var libraryDisplayMode: LibraryDisplayMode
    @Binding var columnHeaderHeight: CGFloat
    let content: Content

    init(
        libraryDisplayMode: Binding<LibraryDisplayMode>,
        columnHeaderHeight: Binding<CGFloat>,
        @ViewBuilder content: () -> Content
    ) {
        self._libraryDisplayMode = libraryDisplayMode
        self._columnHeaderHeight = columnHeaderHeight
        self.content = content()
    }

    private var smartlistsColumnTitle: String {

        switch libraryDisplayMode {
        case .tracks:
            return "Smartlists"
        case .tandas:
            return "Tanda Folders"
        case .savedsetlist:
            return "Saved Setlists"
        }
    }

    var body: some View {


        VStack(
            spacing:
                0
        ) {

            HStack {

                Text(
                    smartlistsColumnTitle
                )
                .font(
                    .headline
                )
                
                //spacing:
                //    0
                Spacer()


                // -----------------------------------------------------
                // Smartlist Lock
                //
                // Only meaningful for Tracks mode's actual Smartlists
                // (SmartlistStore.isLocked) — Tanda Folders and
                // Saved Setlists have no analogous lock, so this is
                // hidden rather than shown irrelevantly next to them.
                // -----------------------------------------------------

                if libraryDisplayMode == .tracks {

                    Button {

                        smartlistStore.isLocked.toggle()

                    } label: {

                        Image(
                            systemName:
                                smartlistStore.isLocked
                                ? "lock.fill"
                                : "lock.open.fill"
                        )
                        .foregroundStyle(
                            smartlistStore.isLocked
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
                        smartlistStore.isLocked
                        ? "Unlock to edit, delete, or move smartlists"
                        : "Lock smartlists"
                    )
                }
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                8 // war 6
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
