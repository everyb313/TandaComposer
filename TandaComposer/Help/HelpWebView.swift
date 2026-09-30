//
//  HelpWebView.swift
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
//

import SwiftUI
import WebKit

/// Loads a bundled HTML manual into a plain WKWebView. The file
/// ships as a bundle resource (added via Xcode's "Help" group), so
/// this needs no network access and works fully offline.
struct HelpWebView: NSViewRepresentable {

    /// Resource name without extension, e.g. "help_en".
    let resourceName: String

    func makeNSView(context: Context) -> WKWebView {

        let webView = WKWebView()

        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "html"
        ) {

            webView.loadFileURL(
                url,
                allowingReadAccessTo: url.deletingLastPathComponent()
            )

        } else {

            webView.loadHTMLString(
                "<p style='font-family: -apple-system; padding: 24px;'>" +
                "Help file '\(resourceName).html' not found in the app bundle.</p>",
                baseURL: nil
            )
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Static content — nothing to update.
    }
}
