//
//  PreviewPlayer.swift
//  TandaComposer
//
//  Created by Hagen Eckert on 10.08.26.
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

import Foundation
import AVFoundation
import CoreAudio
import Combine

@MainActor
final class PreviewPlayer: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var isPlaying = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var currentSong: Song?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastPlayErrorMessage: String?
    
    // MARK: - Audio
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var audioFile: AVAudioFile?
    private var timer: Timer?

    // The actual (post-clamping) start time, in seconds, of whatever
    // segment was most recently handed to
    // playerNode.scheduleSegment(startingFrame:...) — in prepareFile()
    // and seek(). AVAudioPlayerNode's own playerTime(forNodeTime:)
    // reports elapsed time RELATIVE TO THAT SEGMENT'S START, not an
    // absolute track position, so updateCurrentTime() must add this
    // back in. Without it, every seek() schedules a fresh segment
    // whose sampleTime resets to ~0, making the progress bar visibly
    // snap back toward the start and count up from there instead of
    // continuing from the seeked-to position.
    private var segmentStartTime: TimeInterval = 0

    private var selectedDeviceID: AudioDeviceID?
    private var selectedSampleRate: Double?
    
    private var sampleRateObserver: NSObjectProtocol?
    
    // MARK: - Playback Generation
    //
    // Every new playback/reconfiguration gets a new generation.
    //
    // AVAudioPlayerNode completion handlers are asynchronous and may
    // still be called after the player has been stopped/re-scheduled.
    //
    // A completion handler is therefore only allowed to modify player
    // state if it still belongs to the current playback generation.
    
    private var playbackGeneration: UInt64 = 0
    
    // MARK: - Init
    
    override init() {
        
        super.init()
        
        engine.attach(playerNode)
        
        // Placeholder connection so the engine graph is valid before
        // the first file is loaded. This gets torn down and rebuilt
        // with the real per-file format by reconnectPlayerNode(format:)
        // in play(url:)/prepareFile() — see that method's doc comment
        // for why a fixed-at-init format breaks mono files.
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: nil
        )
        
        let manager =
        AudioOutputManager.shared
        
        selectedDeviceID =
        manager.selectedDeviceID
        
        selectedSampleRate =
        manager.selectedSampleRate
        
        installAudioSettingsObserver()
        
        do {
            
            try configureAudioOutput()
            
        } catch {
            
            // print("PREVIEW PLAYER: Initial output setup failed: \(error.localizedDescription)")
        }
    }
    
    deinit {
        
        timer?.invalidate()
        
        if let sampleRateObserver {
            
            NotificationCenter.default.removeObserver(
                sampleRateObserver
            )
        }
        
        engine.stop()
    }
    
    // =============================================================
    // MARK: Playback Generation
    // =============================================================
    
    private func invalidatePlayback() {
        
        playbackGeneration &+= 1
    }
    
    // =============================================================
    // MARK: Audio Settings Observer
    // =============================================================
    
    private func installAudioSettingsObserver() {
        
        sampleRateObserver =
        NotificationCenter.default.addObserver(
            forName:
                    .tandaAudioOutputSettingsChanged,
            object:
                nil,
            queue:
                    .main
        ) { _ in
            
            Task { @MainActor [weak self] in
                
                self?.audioSettingsChanged()
            }
        }
    }
    
    private func audioSettingsChanged() {
        
        let manager =
        AudioOutputManager.shared
        
        selectedDeviceID =
        manager.selectedDeviceID
        
        selectedSampleRate =
        manager.selectedSampleRate
        
        let wasPlaying =
        isPlaying
        
        let position =
        currentTime
        
        guard
            let url = currentURL
        else {
            
            return
        }
        
        // ---------------------------------------------------------
        // Invalidate all completion handlers belonging to the
        // previous scheduling.
        // ---------------------------------------------------------
        
        invalidatePlayback()
        
        do {
            
            playerNode.stop()
            stopTimer()
            engine.stop()
            
            try configureAudioOutput()
            
            try prepareFile(
                url:
                    url,
                startTime:
                    position
            )
            
            try engine.start()
            
            if wasPlaying {
                
                playerNode.play()
                
                isPlaying =
                true
                
                startTimer()
            }
            
        } catch {
            
            // print("PREVIEW PLAYER: Could not reconfigure audio: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            error.localizedDescription
            
            isPlaying =
            false
        }
    }
    
    // =============================================================
    // MARK: Reconnect Player Node
    //
    // playerNode -> mainMixerNode was originally connected once, at
    // init time, with format: nil. That locks the connection to
    // whatever the default format happens to be (2-channel stereo)
    // and never changes it again. Every later scheduleFile/
    // scheduleSegment call then has to upmix through that fixed
    // stereo bus regardless of the actual file's channel count.
    //
    // For stereo files (and dual-mono-interleaved-as-stereo files)
    // this happens to work, but for a genuinely mono AVAudioFile,
    // AVAudioEngine silently fails to produce the upmixed audio:
    // playerTime/renderTime still advance normally (so the progress
    // bar and completion handler behave as if playback is fine), but
    // no samples reach the output — zero audio, ok-looking UI.
    //
    // Fix: rebuild the connection using the file's own
    // processingFormat every time a new file is loaded. The mixer
    // accepts any channel count per input bus, so this makes both
    // mono and stereo files route correctly. Must be called while
    // the engine is stopped (all call sites already stop it first).
    // =============================================================
    
    private func reconnectPlayerNode(
        format: AVAudioFormat
    ) {
        
        engine.disconnectNodeOutput(
            playerNode
        )
        
        engine.connect(
            playerNode,
            to:
                engine.mainMixerNode,
            format:
                format
        )
    }
    
    // =============================================================
    // MARK: Configure Audio Output
    // =============================================================
    
    private func configureAudioOutput() throws {
        
        let manager =
        AudioOutputManager.shared
        
        selectedDeviceID =
        manager.selectedDeviceID
        
        selectedSampleRate =
        manager.selectedSampleRate
        
        let outputNode =
        engine.outputNode
        
        guard
            let audioUnit =
                outputNode.audioUnit
        else {
            
            throw NSError(
                domain:
                    "TandaComposer.Audio",
                code:
                    1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not access the audio output unit."
                ]
            )
        }
        
        // ---------------------------------------------------------
        // Output Device
        //
        // AudioOutputManager owns the selected device.
        // PreviewPlayer only applies it to its AVAudioEngine.
        // ---------------------------------------------------------
        
        if let deviceID =
            selectedDeviceID {
            
            var device =
            deviceID
            
            let size =
            UInt32(
                MemoryLayout<AudioDeviceID>.size
            )
            
            let result =
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                size
            )
            
            // print("PREVIEW PLAYER: Set output device: \(deviceID), result = \(result)")
            
            guard result == noErr else {
                
                throw NSError(
                    domain:
                        NSOSStatusErrorDomain,
                    code:
                        Int(result),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Could not set audio output device. " +
                        "OSStatus \(result)"
                    ]
                )
            }
        }
        
        // ---------------------------------------------------------
        // Hardware Sample Rate
        //
        // IMPORTANT:
        //
        // The hardware sample rate is controlled exclusively by
        // AudioOutputManager.
        //
        // Do NOT call AudioObjectSetPropertyData here.
        // ---------------------------------------------------------
        
        // print("PREVIEW PLAYER: Selected sample rate: \(selectedSampleRate as Any)")
        
        // print("PREVIEW PLAYER: Output configuration complete")
        
        // print("PREVIEW PLAYER: Output format: \(outputNode.outputFormat(forBus: 0))")
        
        // print("PREVIEW PLAYER: Output sample rate: \(outputNode.outputFormat(forBus: 0).sampleRate) Hz")
    }
    
    // =============================================================
    // MARK: Output Device
    // =============================================================
    
    func setOutputDevice(
        _ deviceID: AudioDeviceID?
    ) {
        
        selectedDeviceID =
        deviceID
        
        let wasPlaying =
        isPlaying
        
        let position =
        currentTime
        
        guard
            let url = currentURL
        else {
            
            return
        }
        
        invalidatePlayback()
        
        do {
            
            playerNode.stop()
            stopTimer()
            engine.stop()
            
            try configureAudioOutput()
            
            try prepareFile(
                url:
                    url,
                startTime:
                    position
            )
            
            try engine.start()
            
            if wasPlaying {
                
                playerNode.play()
                
                isPlaying =
                true
                
                startTimer()
            }
            
        } catch {
            
            // print("PREVIEW PLAYER: Output device error: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            "Couldn't select audio output:\n" +
            error.localizedDescription
            
            isPlaying =
            false
        }
    }
    
    // =============================================================
    // MARK: Sample Rate
    // =============================================================
    
    func setSampleRate(
        _ sampleRate: Double?
    ) {
        
        selectedSampleRate =
        sampleRate
        
        let wasPlaying =
        isPlaying
        
        let position =
        currentTime
        
        // print("PREVIEW PLAYER: Sample rate requested: \(sampleRate as Any)")
        
        guard
            let url = currentURL
        else {
            
            return
        }
        
        invalidatePlayback()
        
        do {
            
            playerNode.stop()
            stopTimer()
            engine.stop()
            
            try configureAudioOutput()
            
            try prepareFile(
                url:
                    url,
                startTime:
                    position
            )
            
            try engine.start()
            
            if wasPlaying {
                
                playerNode.play()
                
                isPlaying =
                true
                
                startTimer()
            }
            
        } catch {
            
            // print("PREVIEW PLAYER: Sample rate change failed: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            error.localizedDescription
            
            isPlaying =
            false
        }
    }
    
    // =============================================================
    // MARK: Play Song
    // =============================================================
    
    func play(
        song: Song
    ) {
        
        currentSong =
        song
        
        play(
            url:
                URL(
                    fileURLWithPath:
                        song.path
                )
        )
    }
    
    // =============================================================
    // MARK: Play URL
    // =============================================================
    
    func play(
        url: URL
    ) {
        
        // ---------------------------------------------------------
        // Every new song gets a new generation.
        //
        // Completion handlers from the previous song can therefore
        // never modify the state of the new song.
        // ---------------------------------------------------------
        
        invalidatePlayback()
        
        let generation =
        playbackGeneration
        
        stopTimer()
        
        lastPlayErrorMessage =
        nil
        
        guard
            FileManager.default.fileExists(
                atPath:
                    url.path
            )
        else {
            
            // print("PREVIEW PLAYER: File not found: \(url.path)")
            
            lastPlayErrorMessage =
            "File not found — is the drive still connected?\n" +
            url.lastPathComponent
            
            playerNode.stop()
            
            audioFile =
            nil
            
            currentURL =
            nil
            
            currentSong =
            nil
            
            currentTime =
            0
            
            segmentStartTime =
            0
            
            duration =
            0
            
            isPlaying =
            false
            
            return
        }
        
        do {
            
            // -----------------------------------------------------
            // Completely replace the old scheduled file.
            // -----------------------------------------------------
            
            playerNode.stop()
            engine.stop()
            
            try configureAudioOutput()
            
            let file =
            try AVAudioFile(
                forReading:
                    url
            )
            
            audioFile =
            file
            
            currentURL =
            url
            
            // -----------------------------------------------------
            // A newly selected song ALWAYS starts at zero.
            //
            // segmentStartTime must be reset here too: play(url:)
            // schedules via scheduleFile(...), a different path from
            // prepareFile()/seek()'s scheduleSegment(...), and never
            // touched segmentStartTime otherwise — leaving it at
            // whatever the PREVIOUS song's last seek left behind,
            // which updateCurrentTime() would then wrongly add on top
            // of the new song's elapsed time instead of starting at 0.
            // -----------------------------------------------------
            
            currentTime =
            0
            
            segmentStartTime =
            0
            
            let sourceSampleRate =
            file.processingFormat.sampleRate
            
            guard
                sourceSampleRate > 0
            else {
                
                throw NSError(
                    domain:
                        "TandaComposer.Audio",
                    code:
                        2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Invalid source sample rate."
                    ]
                )
            }
            
            duration =
            Double(file.length) /
            sourceSampleRate
            
            // print("PREVIEW PLAYER: Source file: \(url.lastPathComponent)")
            
            // print("PREVIEW PLAYER: Source sample rate: \(sourceSampleRate) Hz")
            
            // print("PREVIEW PLAYER: Selected output rate: \(selectedSampleRate as Any)")
            
            // -----------------------------------------------------
            // Rebuild playerNode -> mixer using THIS file's own
            // format (channel count included) before scheduling —
            // see reconnectPlayerNode(format:)'s doc comment. Engine
            // is already stopped at this point (above).
            // -----------------------------------------------------
            
            reconnectPlayerNode(
                format:
                    file.processingFormat
            )
            
            // -----------------------------------------------------
            // Schedule the new song.
            // -----------------------------------------------------
            
            playerNode.scheduleFile(
                file,
                at:
                    nil
            ) {
                
                Task { @MainActor [weak self] in
                    
                    guard let self else {
                        return
                    }
                    
                    // -------------------------------------------------
                    // Completion may belong to an old song.
                    // -------------------------------------------------
                    
                    guard
                        generation ==
                            self.playbackGeneration
                    else {
                        
                        return
                    }
                    
                    self.stopTimer()
                    
                    self.isPlaying =
                    false
                    
                    self.currentTime =
                    self.duration
                }
            }
            
            try engine.start()
            
            // print("PREVIEW PLAYER: Engine started")
            
            // print("PREVIEW PLAYER: Actual output format: \(engine.outputNode.outputFormat(forBus: 0))")
            
            playerNode.play()
            
            isPlaying =
            true
            
            startTimer()
            
        } catch {
            
            // print("PREVIEW PLAYER: Could not play: \(url.path)")
            
            // print("PREVIEW PLAYER ERROR: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            "Couldn't play \(url.lastPathComponent):\n" +
            error.localizedDescription
            
            playerNode.stop()
            engine.stop()
            
            audioFile =
            nil
            
            currentURL =
            nil
            
            currentSong =
            nil
            
            currentTime =
            0
            
            segmentStartTime =
            0
            
            duration =
            0
            
            isPlaying =
            false
        }
    }
    
    // =============================================================
    // MARK: Toggle Song
    // =============================================================
    
    func toggle(
        song: Song
    ) {
        
        if currentSong == song {
            
            if isPlaying {
                
                pause()
                
            } else {
                
                resume()
            }
            
        } else {
            
            play(
                song:
                    song
            )
        }
    }
    
    // =============================================================
    // MARK: Toggle URL
    // =============================================================
    
    func toggle(
        url: URL
    ) {
        
        if currentURL == url {
            
            if isPlaying {
                
                pause()
                
            } else {
                
                resume()
            }
            
        } else {
            
            play(
                url:
                    url
            )
        }
    }
    
    // =============================================================
    // MARK: Pause
    // =============================================================
    
    func pause() {
        
        guard
            isPlaying
        else {
            
            return
        }
        
        playerNode.pause()
        
        isPlaying =
        false
        
        stopTimer()
        
        updateCurrentTime()
    }
    
    // =============================================================
    // MARK: Resume
    // =============================================================
    
    func resume() {
        
        guard
            currentURL != nil
        else {
            
            return
        }
        
        do {
            
            if !engine.isRunning {
                
                try engine.start()
            }
            
            playerNode.play()
            
            isPlaying =
            true
            
            startTimer()
            
        } catch {
            
            // print("PREVIEW PLAYER: Resume failed: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            error.localizedDescription
        }
    }
    
    // =============================================================
    // MARK: Stop
    // =============================================================
    
    func stop() {
        
        invalidatePlayback()
        
        stopTimer()
        
        playerNode.stop()
        engine.stop()
        
        audioFile =
        nil
        
        isPlaying =
        false
        
        currentURL =
        nil
        
        currentSong =
        nil
        
        currentTime =
        0
        
        duration =
        0
    }
    
    // =============================================================
    // MARK: Error
    // =============================================================
    
    func clearPlayError() {
        
        lastPlayErrorMessage =
        nil
    }
    
    // =============================================================
    // MARK: Seek
    // =============================================================
    
    func seek(
        to time: TimeInterval
    ) {
        
        guard
            let audioFile
        else {
            
            return
        }
        
        let sampleRate =
        audioFile.processingFormat.sampleRate
        
        guard
            sampleRate > 0
        else {
            
            return
        }
        
        let targetTime =
        max(
            0,
            min(
                time,
                duration
            )
        )
        
        let targetFrame =
        AVAudioFramePosition(
            targetTime * sampleRate
        )
        
        let safeFrame =
        min(
            targetFrame,
            max(
                0,
                audioFile.length - 1
            )
        )
        
        let frameCount =
        AVAudioFrameCount(
            max(
                0,
                audioFile.length - safeFrame
            )
        )
        
        let wasPlaying =
        isPlaying
        
        // ---------------------------------------------------------
        // Invalidate previous scheduled segment.
        // ---------------------------------------------------------
        
        invalidatePlayback()
        
        let generation =
        playbackGeneration
        
        playerNode.stop()
        
        playerNode.scheduleSegment(
            audioFile,
            startingFrame:
                safeFrame,
            frameCount:
                frameCount,
            at:
                nil
        ) {
            
            Task { @MainActor [weak self] in
                
                guard let self else {
                    return
                }
                
                guard
                    generation ==
                        self.playbackGeneration
                else {
                    
                    return
                }
                
                self.stopTimer()
                
                self.isPlaying =
                false
                
                self.currentTime =
                self.duration
            }
        }
        
        segmentStartTime =
        Double(safeFrame) /
        sampleRate

        currentTime =
        Double(safeFrame) /
        sampleRate
        
        do {
            
            if !engine.isRunning {
                
                try engine.start()
            }
            
            if wasPlaying {
                
                playerNode.play()
                
                isPlaying =
                true
                
                startTimer()
            }
            
        } catch {
            
            // print("PREVIEW PLAYER: Seek failed: \(error.localizedDescription)")
            
            lastPlayErrorMessage =
            error.localizedDescription
            
            isPlaying =
            false
        }
    }
    
    // =============================================================
    // MARK: Volume
    // =============================================================
    
    func setVolume(
        _ volume: Float
    ) {
        
        playerNode.volume =
        max(
            0,
            min(
                volume,
                1
            )
        )
    }
    
    // =============================================================
    // MARK: Prepare File
    // =============================================================
    
    private func prepareFile(
        url: URL,
        startTime: TimeInterval
    ) throws {
        
        let file =
        try AVAudioFile(
            forReading:
                url
        )
        
        let sampleRate =
        file.processingFormat.sampleRate
        
        guard
            sampleRate > 0
        else {
            
            throw NSError(
                domain:
                    "TandaComposer.Audio",
                code:
                    3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid audio file sample rate."
                ]
            )
        }
        
        audioFile =
        file
        
        currentURL =
        url
        
        duration =
        Double(file.length) /
        sampleRate
        
        let requestedFrame =
        AVAudioFramePosition(
            max(
                0,
                min(
                    startTime,
                    duration
                )
            ) * sampleRate
        )
        
        let safeFrame =
        min(
            requestedFrame,
            max(
                0,
                file.length - 1
            )
        )
        
        let frameCount =
        AVAudioFrameCount(
            max(
                0,
                file.length - safeFrame
            )
        )
        
        segmentStartTime =
        Double(safeFrame) /
        sampleRate

        // ---------------------------------------------------------
        // Same reconnect as play(url:) — see reconnectPlayerNode
        // (format:)'s doc comment. All three callers of prepareFile
        // (audioSettingsChanged, setOutputDevice, setSampleRate)
        // already stop the engine before calling this.
        // ---------------------------------------------------------
        
        reconnectPlayerNode(
            format:
                file.processingFormat
        )
        
        playerNode.scheduleSegment(
            file,
            startingFrame:
                safeFrame,
            frameCount:
                frameCount,
            at:
                nil
        )
    }
    
    // =============================================================
    // MARK: Timer
    // =============================================================
    
    private func startTimer() {
        
        stopTimer()
        
        timer =
        Timer.scheduledTimer(
            withTimeInterval:
                0.1,
            repeats:
                true
        ) { [weak self] _ in
            
            guard let self else {
                return
            }
            
            Task { @MainActor in
                
                self.updateCurrentTime()
            }
        }
    }
    
    private func stopTimer() {
        
        timer?.invalidate()
        
        timer =
        nil
    }
    
    // =============================================================
    // MARK: Current Time
    // =============================================================
    
    private func updateCurrentTime() {
        
        guard
            let audioFile
        else {
            
            return
        }
        
        let sampleRate =
        audioFile.processingFormat.sampleRate
        
        guard
            sampleRate > 0
        else {
            
            return
        }
        
        guard
            let nodeTime =
                playerNode.lastRenderTime,
            
                let playerTime =
                playerNode.playerTime(
                    forNodeTime:
                        nodeTime
                )
        else {
            
            return
        }
        
        // playerTime.sampleTime is relative to the CURRENTLY
        // scheduled segment's own start (see segmentStartTime's doc
        // comment) — segmentStartTime converts that back into an
        // absolute track position.
        currentTime =
        segmentStartTime +
        Double(
            playerTime.sampleTime
        ) /
        sampleRate
        
        currentTime =
        max(
            0,
            min(
                currentTime,
                duration
            )
        )
    }
}
