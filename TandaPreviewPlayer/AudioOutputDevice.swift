//
//  AudioOutputDevice.swift
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
//  AudioOutputDevice.swift
//  TandaComposer
//

import Foundation
import CoreAudio
import Combine

struct AudioOutputDevice: Identifiable, Hashable {

    let id: AudioDeviceID
    let name: String

    var identifiableID: UInt32 {
        UInt32(id)
    }
}

@MainActor
final class AudioOutputManager: ObservableObject {

    static let shared = AudioOutputManager()

    // MARK: - Published

    @Published private(set) var devices:
        [AudioOutputDevice] = []

    @Published var selectedDeviceID:
        AudioDeviceID?

    @Published var selectedSampleRate:
        Double?

    @Published private(set) var supportedSampleRates:
        [Double] = []

    // MARK: - Private

    private var deviceListenerBlock:
        AudioObjectPropertyListenerBlock?

    // MARK: - Init

    init() {

        refreshDevices()
        updateSupportedSampleRates()
        installDeviceChangeListener()
    }

    deinit {
    }

    // ============================================================
    // MARK: Devices
    // ============================================================

    func refreshDevices() {

        devices = Self.outputDevices()

        if let currentID = selectedDeviceID,
           !devices.contains(where: {
               $0.id == currentID
           }) {

            selectedDeviceID = nil
        }

        updateSupportedSampleRates()
    }

    // ============================================================
    // MARK: Select Device
    // ============================================================

    func setSelectedDevice(
        _ deviceID: AudioDeviceID?
    ) {

        selectedDeviceID = deviceID
        selectedSampleRate = nil

        updateSupportedSampleRates()

        NotificationCenter.default.post(
            name:
                .tandaAudioOutputSettingsChanged,
            object:
                nil
        )
    }

    // ============================================================
    // MARK: Sample Rates
    // ============================================================

    private func updateSupportedSampleRates() {

        let deviceID =
            selectedDeviceID
            ?? Self.defaultOutputDeviceID()

        guard deviceID != 0 else {

            supportedSampleRates = []

            return
        }

        supportedSampleRates =
            Self.sampleRates(
                for: deviceID
            )
    }

    // ============================================================
    // MARK: Set Hardware Sample Rate
    // ============================================================

    func setSampleRate(
        _ sampleRate: Double?
    ) {

        selectedSampleRate = sampleRate

        guard
            let sampleRate,
            sampleRate > 0
        else {

            NotificationCenter.default.post(
                name:
                    .tandaAudioOutputSettingsChanged,
                object:
                    nil
            )

            return
        }

        let deviceID =
            selectedDeviceID
            ?? Self.defaultOutputDeviceID()

        guard deviceID != 0 else {

            NotificationCenter.default.post(
                name:
                    .tandaAudioOutputSettingsChanged,
                object:
                    nil
            )

            return
        }

        _ =
            Self.setHardwareSampleRate(
                sampleRate,
                for: deviceID
            )

        NotificationCenter.default.post(
            name:
                .tandaAudioOutputSettingsChanged,
            object:
                nil
        )
    }

    // ============================================================
    // MARK: Default Output Device
    // ============================================================

    private static func defaultOutputDeviceID()
        -> AudioDeviceID
    {

        let systemObject =
            AudioObjectID(
                kAudioObjectSystemObject
            )

        var deviceID =
            AudioDeviceID(0)

        var size =
            UInt32(
                MemoryLayout<AudioDeviceID>.size
            )

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioHardwarePropertyDefaultOutputDevice,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        let result =
            AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &size,
                &deviceID
            )

        if result != noErr {
            // print(
            //     "AUDIO OUTPUT: Could not get default output device:",
            //     result
            // )
        }

        return deviceID
    }

    // ============================================================
    // MARK: Hardware Sample Rate
    // ============================================================

    private static func setHardwareSampleRate(
        _ sampleRate: Double,
        for deviceID: AudioDeviceID
    ) -> OSStatus {

        var rate =
            sampleRate

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioDevicePropertyNominalSampleRate,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        let size =
            UInt32(
                MemoryLayout<Double>.size
            )

        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &rate
        )
    }

    // ============================================================
    // MARK: Available Sample Rates
    // ============================================================

    private static func sampleRates(
        for deviceID: AudioDeviceID
    ) -> [Double] {

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioDevicePropertyAvailableNominalSampleRates,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        var dataSize: UInt32 = 0

        let sizeResult =
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &dataSize
            )

        guard sizeResult == noErr else {
            return []
        }

        let count =
            Int(dataSize) /
            MemoryLayout<AudioValueRange>.stride

        guard count > 0 else {
            return []
        }

        var ranges =
            Array(
                repeating:
                    AudioValueRange(
                        mMinimum: 0,
                        mMaximum: 0
                    ),
                count:
                    count
            )

        let result =
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &ranges
            )

        guard result == noErr else {
            return []
        }

        var rates:
            Set<Double> = []

        for range in ranges {

            rates.insert(
                range.mMinimum
            )

            rates.insert(
                range.mMaximum
            )
        }

        return rates.sorted()
    }

    // ============================================================
    // MARK: Output Devices
    // ============================================================

    private static func outputDevices()
        -> [AudioOutputDevice]
    {

        let systemObject =
            AudioObjectID(
                kAudioObjectSystemObject
            )

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioHardwarePropertyDevices,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        var dataSize: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                systemObject,
                &address,
                0,
                nil,
                &dataSize
            ) == noErr
        else {
            return []
        }

        let count =
            Int(dataSize) /
            MemoryLayout<AudioDeviceID>.size

        guard count > 0 else {
            return []
        }

        var deviceIDs =
            Array(
                repeating:
                    AudioDeviceID(0),
                count:
                    count
            )

        guard
            AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                &deviceIDs
            ) == noErr
        else {
            return []
        }

        return deviceIDs.compactMap { deviceID in

            guard
                hasOutputChannels(deviceID),
                let name = deviceName(deviceID)
            else {
                return nil
            }

            // Hide macOS internal aggregate device.
            if name.hasPrefix(
                "CADefaultDeviceAggregate-"
            ) {
                return nil
            }

            return AudioOutputDevice(
                id:
                    deviceID,
                name:
                    name
            )
        }
    }

    // ============================================================
    // MARK: Output Channels
    // ============================================================

    private static func hasOutputChannels(
        _ deviceID: AudioDeviceID
    ) -> Bool {

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioDevicePropertyStreamConfiguration,

                mScope:
                    kAudioObjectPropertyScopeOutput,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        var size: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &size
            ) == noErr
        else {
            return false
        }

        let buffer =
            UnsafeMutableRawPointer.allocate(
                byteCount:
                    Int(size),
                alignment:
                    MemoryLayout<AudioBufferList>.alignment
            )

        defer {
            buffer.deallocate()
        }

        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                buffer
            ) == noErr
        else {
            return false
        }

        let bufferList =
            buffer.assumingMemoryBound(
                to:
                    AudioBufferList.self
            )

        let buffers =
            UnsafeMutableAudioBufferListPointer(
                bufferList
            )

        for buffer in buffers {

            if buffer.mNumberChannels > 0 {
                return true
            }
        }

        return false
    }

    // ============================================================
    // MARK: Device Name
    // ============================================================

    private static func deviceName(
        _ deviceID: AudioDeviceID
    ) -> String? {

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioObjectPropertyName,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        var name:
            Unmanaged<CFString>?

        var size =
            UInt32(
                MemoryLayout<
                    Unmanaged<CFString>?
                >.size
            )

        let result =
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &name
            )

        guard
            result == noErr,
            let unmanagedName = name
        else {
            return nil
        }

        return unmanagedName.takeUnretainedValue()
            as String
    }

    // ============================================================
    // MARK: Device Listener
    // ============================================================

    private func installDeviceChangeListener() {

        let systemObject =
            AudioObjectID(
                kAudioObjectSystemObject
            )

        var address =
            AudioObjectPropertyAddress(
                mSelector:
                    kAudioHardwarePropertyDevices,

                mScope:
                    kAudioObjectPropertyScopeGlobal,

                mElement:
                    kAudioObjectPropertyElementMain
            )

        deviceListenerBlock =
            { [weak self] _, _ in

                Task { @MainActor in

                    self?.refreshDevices()
                }
            }

        if let deviceListenerBlock {

            AudioObjectAddPropertyListenerBlock(
                systemObject,
                &address,
                DispatchQueue.main,
                deviceListenerBlock
            )
        }
    }
}


// ================================================================
// MARK: - Audio Output Notification
// ================================================================

extension Notification.Name {

    static let tandaAudioOutputSettingsChanged =
        Notification.Name(
            "TandaComposer.AudioOutputSettingsChanged"
        )
}
