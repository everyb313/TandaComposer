//  Extracted from ContentView.swift

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Split View Width Persistence

struct SplitViewWidthPersistence:
    NSViewRepresentable {

    let settings:
        AppSettings

    var onWindowWillClose:
        (() -> Void)?
        = nil


    func makeNSView(
        context:
            Context
    ) -> NSView {

        let view =
            SplitViewObserverView()

        view.settings =
            settings

        view.onWindowWillClose =
            onWindowWillClose

        return view
    }


    func updateNSView(
        _ nsView:
            NSView,
        context:
            Context
    ) {

        guard
            let view =
                nsView as?
                SplitViewObserverView
        else {
            return
        }

        view.settings =
            settings

        view.onWindowWillClose =
            onWindowWillClose

        view.applySavedWidthsIfPossible()
    }
}


// MARK: - AppKit Split View Observer

private final class SplitViewObserverView:
    NSView {

    weak var splitView:
        NSSplitView?

    private var observerToken:
        NSObjectProtocol?

    private var windowWillCloseToken:
        NSObjectProtocol?

    var settings:
        AppSettings?

    var onWindowWillClose:
        (() -> Void)?


    private var didRestoreInitialWidths =
        false

    private var isApplyingSavedWidths =
        false

    private var ignoreNextResizeNotification =
        false

    // Coalesces disk writes — NSSplitView.didResizeSubviewsNotification
    // fires on every single frame during a live window/divider drag
    // (see splitViewDidResize below), so writing AppSettings.json on
    // every notification means dozens of disk writes per second, each
    // differing only by sub-pixel rounding. The in-memory widths still
    // update immediately; only the actual save to disk is debounced
    // until resizing has paused for a moment.
    private var pendingSettingsSaveWorkItem:
        DispatchWorkItem?


    override func viewDidMoveToWindow() {

        super.viewDidMoveToWindow()

        guard let window else {

            windowWillCloseToken =
                nil

            return
        }

        if windowWillCloseToken == nil {

            windowWillCloseToken =
                NotificationCenter.default.addObserver(
                    forName:
                        NSWindow.willCloseNotification,
                    object:
                        window,
                    queue:
                        .main
                ) { [weak self] _ in

                    Task { @MainActor [weak self] in

                        // Flush any pending (debounced) split-width
                        // save immediately — don't let a resize right
                        // before quitting get lost.
                        if let workItem =
                            self?.pendingSettingsSaveWorkItem {

                            workItem.cancel()

                            self?.settings?.save()
                        }

                        self?.onWindowWillClose?()
                    }
                }
        }

        DispatchQueue.main.async { [weak self] in

            self?.connectToSplitView()
        }
    }


    deinit {

        if let observerToken {

            NotificationCenter.default.removeObserver(
                observerToken
            )
        }

        if let windowWillCloseToken {

            NotificationCenter.default.removeObserver(
                windowWillCloseToken
            )
        }

        pendingSettingsSaveWorkItem?.cancel()
    }


    private func connectToSplitView() {

        guard let window else {
            return
        }

        if let splitView,
           splitView.window === window {

            return
        }

        guard
            let split =
                findSplitView(
                    in:
                        window.contentView
                )
        else {

            DispatchQueue.main.async { [weak self] in

                self?.connectToSplitView()
            }

            return
        }

        guard
            split.arrangedSubviews.count >= 3
        else {

            DispatchQueue.main.async { [weak self] in

                self?.connectToSplitView()
            }

            return
        }

        splitView =
            split

        observerToken =
            NotificationCenter.default.addObserver(
                forName:
                    NSSplitView.didResizeSubviewsNotification,
                object:
                    split,
                queue:
                    .main
            ) { [weak self] _ in

                self?.splitViewDidResize()
            }

        print(
            "SPLIT VIEW FOUND:",
            split
        )

        DispatchQueue.main.async { [weak self] in

            self?.applySavedWidthsIfPossible()
        }

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.15
        ) { [weak self] in

            guard let self else {
                return
            }

            if !self.didRestoreInitialWidths {

                self.applySavedWidthsIfPossible()
            }
        }
    }


    private func splitViewDidResize() {

        guard
            let splitView,
            let settings
        else {
            return
        }

        guard
            splitView.arrangedSubviews.count >= 3
        else {
            return
        }

        if isApplyingSavedWidths {

            return
        }

        if ignoreNextResizeNotification {

            ignoreNextResizeNotification =
                false

            return
        }

        guard didRestoreInitialWidths else {

            return
        }

        let widths =
            currentPaneWidths(
                from:
                    splitView
            )

        guard widths.count >= 3 else {
            return
        }

        guard widths.allSatisfy({
            $0.isFinite && $0 > 1
        }) else {
            return
        }

        let oldWidths = [

            settings.setPaneWidth,
            settings.libraryPaneWidth,
            settings.smartlistsPaneWidth
        ]

        let changed =
            zip(
                oldWidths,
                widths
            ).contains {

                abs(
                    $0 - $1
                ) > 1.5
            }

        guard changed else {

            return
        }

        DispatchQueue.main.async {

            settings.setPaneWidth =
                widths[0]

            settings.libraryPaneWidth =
                widths[1]

            settings.smartlistsPaneWidth =
                widths[2]

            settings.currentLibraryPaneWidth =
                widths[1]

            print(
                "SPLIT SAVE (pending):",
                widths
            )
        }

        // Debounce the actual disk write — only the last width in a
        // burst of resize notifications actually gets persisted.
        pendingSettingsSaveWorkItem?.cancel()

        let workItem =
            DispatchWorkItem { [weak settings] in

                settings?.save()

                print(
                    "SPLIT SAVE (flushed to disk)"
                )
            }

        pendingSettingsSaveWorkItem =
            workItem

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.4,
            execute:
                workItem
        )
    }


    private func currentPaneWidths(
        from splitView:
            NSSplitView
    ) -> [Double] {

        splitView.arrangedSubviews.map {

            Double(
                $0.frame.width
            )
        }
    }


    func applySavedWidthsIfPossible() {

        guard !didRestoreInitialWidths else {
            return
        }

        guard
            let splitView,
            let settings
        else {
            return
        }

        guard
            splitView.arrangedSubviews.count >= 3
        else {
            return
        }

        let totalWidth =
            splitView.bounds.width

        guard totalWidth > 100 else {
            return
        }

        let savedWidths = [

            settings.setPaneWidth,
            settings.libraryPaneWidth,
            settings.smartlistsPaneWidth
        ]

        guard savedWidths.allSatisfy({
            $0.isFinite && $0 > 1
        }) else {
            return
        }

        let savedTotal =
            savedWidths.reduce(
                0,
                +
            )

        let actualWidths:
            [Double]

        if abs(savedTotal - Double(totalWidth)) > 0.5 {

            let scale =
                Double(totalWidth) /
                savedTotal

            actualWidths =
                savedWidths.map {
                    $0 * scale
                }

            print(
                "SPLIT LOAD SCALE:",
                "saved:",
                savedTotal,
                "available:",
                totalWidth,
                "scale:",
                scale,
                "result:",
                actualWidths
            )

        } else {

            actualWidths =
                savedWidths
        }

        let currentWidths =
            currentPaneWidths(
                from:
                    splitView
            )

        if currentWidths.count >= 3 {

            let alreadyCorrect =
                zip(
                    currentWidths,
                    actualWidths
                ).allSatisfy {

                    abs(
                        $0 - $1
                    ) < 0.5
                }

            if alreadyCorrect {

                didRestoreInitialWidths =
                    true

                DispatchQueue.main.async {

                    settings.currentLibraryPaneWidth =
                        currentWidths[1]
                }

                print(
                    "SPLIT LOAD: already correct:",
                    currentWidths
                )

                return
            }
        }

        isApplyingSavedWidths =
            true

        ignoreNextResizeNotification =
            true

        let firstDivider =
            actualWidths[0]

        let secondDivider =
            actualWidths[0] +
            actualWidths[1]

        splitView.setPosition(
            CGFloat(
                firstDivider
            ),
            ofDividerAt:
                0
        )

        splitView.setPosition(
            CGFloat(
                secondDivider
            ),
            ofDividerAt:
                1
        )

        DispatchQueue.main.async { [weak self] in

            guard let self else {
                return
            }

            self.isApplyingSavedWidths =
                false

            self.didRestoreInitialWidths =
                true

            // Kept live even though the corresponding libraryPaneWidth
            // save is deliberately suppressed above (this scale is a
            // one-off fit-to-window correction, not a preference to
            // persist) — other windows sizing themselves off the
            // Library column's REAL current width still need this to
            // be accurate. Deferred to main.async along with the flags
            // above — setting a @Published property synchronously
            // inside this NSSplitView layout callback risks re-entrant
            // SwiftUI view updates (same class of bug as the earlier
            // "Publishing changes from within view updates" issue).
            settings.currentLibraryPaneWidth =
                actualWidths[1]
        }

        print(
            "SPLIT LOAD:",
            actualWidths
        )
    }


    private func findSplitView(
        in root:
            NSView?
    ) -> NSSplitView? {

        guard let root else {
            return nil
        }

        if let split =
            root as? NSSplitView,
           split.arrangedSubviews.count >= 3 {

            return split
        }

        for subview in root.subviews {

            if let split =
                findSplitView(
                    in:
                        subview
                ) {

                return split
            }
        }

        return nil
    }
}


