//
//  LibraryLockBanner.swift
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

/// Prominent notice for windows whose main action needs the Library
/// unlocked (the lock icon in the main window's Library column).
///
/// Disabled buttons plus a hover tooltip leave the user guessing why
/// nothing works; this says it outright, in the warning colour, and
/// names the next step. Show it only while `libraryStore.isLocked`.
///
/// `thenClick` is the title of the button to press once unlocked,
/// e.g. "Apply Fixes".
struct LibraryLockBanner: View {

    let thenClick: String

    var body: some View {

        HStack(
            alignment: .top,
            spacing: 10
        ) {

            Image(
                systemName:
                    "lock.fill"
            )
            .font(
                .system(size: 22, weight: .semibold)
            )
            .foregroundStyle(
                Color.orange
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(
                    "The Library is locked."
                )
                .font(
                    .system(size: 15, weight: .bold)
                )

                Text(
                    "First click the lock icon in the Library column of the main window to unlock it. Then click \"\(thenClick)\"."
                )
                .font(
                    .system(size: 15)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.orange.opacity(0.15)
        )
        .overlay(
            alignment: .bottom
        ) {
            Rectangle()
                .fill(Color.orange.opacity(0.6))
                .frame(height: 1)
        }
        .accessibilityElement(
            children: .combine
        )
    }
}
