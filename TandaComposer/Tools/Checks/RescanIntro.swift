//
//  RescanIntro.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 28.08.26.
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

/// Short "what does this window do" text shown at the top of the
/// Rescan windows: three one-line points instead of a paragraph.
///
/// - `what`:   what the rescan does (shown in the normal text colour)
/// - `limits`: what it covers / does not cover
/// - `hint`:   what to do next, or when to do something else first
struct RescanIntro: View {

    let what: String
    let limits: String
    let hint: String

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 6
        ) {

            row(
                symbol: "arrow.triangle.2.circlepath",
                text: what,
                isPrimary: true
            )

            row(
                symbol: "info.circle",
                text: limits,
                isPrimary: false
            )

            row(
                symbol: "arrow.right.circle",
                text: hint,
                isPrimary: false
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func row(
        symbol: String,
        text: String,
        isPrimary: Bool
    ) -> some View {

        HStack(
            alignment: .firstTextBaseline,
            spacing: 8
        ) {

            Image(
                systemName: symbol
            )
            .font(
                .system(size: 15)
            )
            .foregroundStyle(
                Color.secondary
            )
            .frame(
                width: 20
            )

            Text(
                text
            )
            .font(
                .system(size: 16)
            )
            .foregroundStyle(
                isPrimary
                ? Color.primary
                : Color.secondary
            )
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        }
    }
}
