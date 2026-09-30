//
//  PreviewPlayerView.swift
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

//
//  PreviewPlayerView.swift
//  TandaComposer
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreviewPlayerView: View {

    @ObservedObject var player: PreviewPlayer

    let selectedSong: Song?

    @State private var volume: Double = 1.0
    @State private var showingFileImporter = false

    var body: some View {

        HStack(spacing: 12) {

            // =====================================================
            // PREVIEW PLAYER TITLE
            // =====================================================

            Text("Preview Player")
                .font(.title)
                .foregroundStyle(.secondary)
                .fixedSize()

            Divider()
                .frame(height: 18)

            // =====================================================
            // SONG INFORMATION
            // =====================================================

            HStack(spacing: 8) {

                Image(
                    systemName:
                        player.isPlaying
                        ? "waveform"
                        : "music.note"
                )
                .frame(width: 20)

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {

                    Text(
                        displaySong?.title
                        ?? displayURL?
                            .deletingPathExtension()
                            .lastPathComponent
                        ?? "No preview selected"
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)

                    if let song = displaySong {

                        let subtitle =
                            [
                                song.artist,
                                song.album
                            ]
                            .compactMap { $0 }
                            .joined(
                                separator: " — "
                            )

                        if !subtitle.isEmpty {

                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .frame(
                    width: 240,
                    alignment: .leading
                )
            }

            // =====================================================
            // PLAY / STOP
            // =====================================================

            HStack(spacing: 8) {

                Button {

                    guard let selectedSong
                    else {
                        return
                    }

                    player.toggle(
                        song: selectedSong
                    )

                } label: {

                    Image(
                        systemName:
                            player.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 20))
                    .frame(
                        width: 32,
                        height: 32
                    )
                }
                .buttonStyle(.borderless)
                .disabled(
                    selectedSong == nil
                )

                Button {

                    player.stop()

                } label: {

                    Image(
                        systemName:
                            "stop.fill"
                    )
                    .font(.system(size: 20))
                    .frame(
                        width: 32,
                        height: 32
                    )
                }
                .buttonStyle(.borderless)
            }

            // =====================================================
            // CURRENT TIME
            // =====================================================

            Text(
                formatTime(
                    player.currentTime
                )
            )
            .font(
                .caption.monospacedDigit()
            )
            .foregroundStyle(.secondary)

            // =====================================================
            // PROGRESS SLIDER
            // =====================================================

            Slider(
                value: Binding(
                    get: {
                        min(
                            max(
                                player.currentTime,
                                0
                            ),
                            max(
                                player.duration,
                                0
                            )
                        )
                    },
                    set: { newValue in
                        player.seek(
                            to: newValue
                        )
                    }
                ),
                in: 0...max(
                    player.duration,
                    1
                )
            )
            .frame(
                minWidth: 120,
                maxWidth: .infinity
            )

            // =====================================================
            // DURATION
            // =====================================================

            Text(
                formatTime(
                    player.duration
                )
            )
            .font(
                .caption.monospacedDigit()
            )
            .foregroundStyle(.secondary)

            // =====================================================
            // VOLUME
            // =====================================================

            Image(
                systemName:
                    "speaker.wave.2.fill"
            )
            .foregroundStyle(.secondary)

            Slider(
                value: $volume,
                in: 0.0...1.0,
                step: 0.01
            )
            .frame(width: 80)
            .onChange(
                of: volume
            ) { _, newValue in

                player.setVolume(
                    Float(newValue)
                )
            }

            // =====================================================
            // FILE
            // =====================================================

            Button {

                showingFileImporter = true

            } label: {

                Image(
                    systemName:
                        "folder"
                )
            }
            .buttonStyle(.borderless)
            .help("Choose audio file")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    Color.secondary.opacity(0.55),
                    lineWidth: 1
                )
        )

        .fileImporter(
            isPresented:
                $showingFileImporter,
            allowedContentTypes:
                [.audio]
        ) { result in

            switch result {

            case .success(let url):

                player.play(
                    url: url
                )

            case .failure(let error):

                // print(
                //     "PREVIEW FILE ERROR:",
                //     error.localizedDescription
                // )
                _ = error
            }
        }

        // =========================================================
        // Playback Error
        // =========================================================

        .alert(
            "Playback Error",
            isPresented:
                Binding(
                    get: {
                        player.lastPlayErrorMessage != nil
                    },
                    set: { value in

                        if !value {

                            player.clearPlayError()
                        }
                    }
                )
        ) {

            Button("OK") {

                player.clearPlayError()
            }

        } message: {

            Text(
                player.lastPlayErrorMessage ?? ""
            )
        }
    }

    // =============================================================
    // MARK: - Display Song / URL
    // =============================================================

    private var displaySong: Song? {

        if player.isPlaying {
            return player.currentSong
        }

        return selectedSong ?? player.currentSong
    }

    private var displayURL: URL? {

        if player.isPlaying {
            return player.currentURL
        }

        return selectedURL
    }

    // =============================================================
    // MARK: - Selected URL
    // =============================================================

    private var selectedURL: URL? {

        if let selectedSong {

            return URL(
                fileURLWithPath:
                    selectedSong.path
            )
        }

        return player.currentURL
    }

    // =============================================================
    // MARK: - Time
    // =============================================================

    private func formatTime(
        _ time: TimeInterval
    ) -> String {

        guard time.isFinite
        else {
            return "0:00"
        }

        let total =
            max(
                0,
                Int(time)
            )

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }
}
