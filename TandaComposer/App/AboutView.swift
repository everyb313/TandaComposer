//
//  AboutView.swift
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

struct AboutView: View {

    @EnvironmentObject private var settings: AppSettings

    var body: some View {

        VStack(alignment: .leading, spacing: 10) {

            // MARK: - Application

            Text("TandaComposer")
                .font(
                    .system(
                        size: 28,
                        weight: .semibold
                    )
                )

            Text(
                "Version \(settings.appVersion) " +
                "(Build \(settings.buildNumber))"
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)


            Divider()
                .padding(.vertical, 6)


            // MARK: - Copyright

            Text("Copyright - TandaComposer Source Code © 2026 Hagen Eckert")
                .font(.system(size: 12))

            Text(
                "TandaComposer is licensed under the " +
                "GNU General Public License version 3 or later."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Text(
                "Created with the assistance of Claude (Anthropic) and ChatGPT (OpenAI)."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)


            Divider()
                .padding(.vertical, 6)


            // MARK: - Third-Party Software

            Text("Copyright for Third-Party Software")
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )


            // MARK: GRDB

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text("GRDB.swift 7.11.1")
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )

                Text(
                    "Copyright © Gwendal Roué and contributors"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Text(
                    "Licensed under the MIT License."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: 500,
            height: 350,
            alignment: .topLeading
        )
        .padding(24)
    }
}
