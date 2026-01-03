//
//  MusicPlayer.swift
//  HypnoticSpiral
//
//  Background music player using AVAudioPlayer
//  Handles looping and pause/resume
//

import Foundation
import AVFoundation

/// Manages background music playback
@MainActor
@Observable
class MusicPlayer {
    private var audioPlayer: AVAudioPlayer?
    var isPlaying: Bool = false

    /// Load and start playing music file from iCloud
    func loadMusic(filename: String?) {
        guard let filename = filename, !filename.isEmpty else {
            print("No music file specified")
            return
        }

        // Get URL from iCloud
        guard let url = iCloudResourceManager.shared.getMusicURL(named: filename) else {
            print("Warning: Music file '\(filename)' not found in iCloud Music directory")
            return
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Warning: Music file does not exist at path: \(url.path)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1  // Loop indefinitely
            audioPlayer?.prepareToPlay()
            print("Loaded music from iCloud: \(filename)")
        } catch {
            print("Error loading music file: \(error)")
        }
    }

    /// Start or resume playback
    func play() {
        audioPlayer?.play()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    /// Stop playback and reset position
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
    }

    /// Set volume (0.0 to 1.0)
    func setVolume(_ volume: Float) {
        audioPlayer?.volume = volume
    }
}
