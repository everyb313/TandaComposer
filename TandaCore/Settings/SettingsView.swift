//
//  SettingsView.swift
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
//  SettingsView.swift
//  TandaComposer
//

import SwiftUI
import CoreAudio


struct SettingsView:
    View {


    @EnvironmentObject
    private var settings:
        AppSettings


    @EnvironmentObject
    private var audioOutputManager:
        AudioOutputManager


    var body:
        some View {

        Form {

            // =====================================================
            // Appearance
            // =====================================================

            Section("Appearance") {

                Picker(
                    "Appearance",
                    selection:
                        $settings.appearanceMode
                ) {

                    ForEach(
                        AppearanceMode.allCases
                    ) { mode in

                        Text(
                            mode.displayName
                        )
                        .tag(
                            mode
                        )
                    }
                }
                .pickerStyle(
                    .segmented
                )
                .onChange(
                    of:
                        settings.appearanceMode
                ) { _, _ in

                    settings.save()
                }
            }


            // =====================================================
            // Separator
            // =====================================================

            Divider()


            // =====================================================
            // Tagging (Orchestra / Singer)
            // =====================================================

            Section("Tagging") {

                Text(
                    "Define which tag fields represent Orchestra and Singer"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )

                Picker(
                    "Orchestra Source",
                    selection:
                        $settings.orchestraSource
                ) {

                    ForEach(
                        TagSource.allCases
                    ) { source in

                        Text(
                            source.displayName
                        )
                        .tag(
                            source
                        )
                    }
                }
                .onChange(
                    of:
                        settings.orchestraSource
                ) { _, _ in

                    settings.save()
                }

                Picker(
                    "Singer Source",
                    selection:
                        $settings.singerSource
                ) {

                    ForEach(
                        TagSource.allCases
                    ) { source in

                        Text(
                            source.displayName
                        )
                        .tag(
                            source
                        )
                    }
                }
                .onChange(
                    of:
                        settings.singerSource
                ) { _, _ in

                    settings.save()
                }

                // Same source for both is allowed (no validation
                // here) but produces a degenerate Tanda folder
                // structure (Tandas/<X>/<X>/) — flagged, not
                // prevented; see conversation history.
                if
                    settings.orchestraSource ==
                        settings.singerSource
                {

                    Text(
                        "Orchestra and Singer source are the same — new Tandas will land in Tandas/<value>/<value>/."
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .orange
                    )
                }
            }

            // =====================================================
            // Separator
            // =====================================================

            Divider()

            // =====================================================
            // Audio Output
            // =====================================================

            Section("Audio Output") {

                Picker(
                    "Device",
                    selection:
                        Binding<AudioDeviceID?>(
                            get: {

                                audioOutputManager
                                    .selectedDeviceID
                            },
                            set: { value in

                                audioOutputManager
                                    .setSelectedDevice(
                                        value
                                    )
                            }
                        )
                ) {

                    Text(
                        "System Default"
                    )
                    .tag(
                        AudioDeviceID?.none
                    )


                    ForEach(
                        audioOutputManager.devices
                    ) { device in

                        Text(
                            device.name
                        )
                        .tag(
                            AudioDeviceID?(
                                device.id
                            )
                        )
                    }
                }


                Picker(
                    "Sample Rate",
                    selection:
                        Binding<Double?>(
                            get: {

                                audioOutputManager
                                    .selectedSampleRate
                            },
                            set: { value in

                                audioOutputManager
                                    .setSampleRate(
                                        value
                                    )
                            }
                        )
                ) {

                    Text(
                        "Auto"
                    )
                    .tag(
                        Double?.none
                    )


                    ForEach(
                        audioOutputManager
                            .supportedSampleRates,
                        id:
                            \.self
                    ) { rate in

                        Text(
                            sampleRateText(
                                rate
                            )
                        )
                        .tag(
                            Double?.some(
                                rate
                            )
                        )
                    }
                }
                .disabled(
                    audioOutputManager
                        .supportedSampleRates
                        .isEmpty
                )
            }
        }
        .padding(
            24
        )
        .frame(
            width:
                560
        )
    }


    // =============================================================
    // MARK: - Sample Rate Text
    // =============================================================

    private func sampleRateText(
        _ rate: Double
    ) -> String {

        if rate >= 1000 {

            return String(
                format:
                    "%.1f kHz",
                rate / 1000.0
            )
        }


        return String(
            format:
                "%.0f Hz",
            rate
        )
    }
}
