/*
 * VibeIsland (DynamicIsland)
 * Copyright (C) 2024-2026 VibeIsland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import AVFoundation

/// Plays a sound once for Settings previews. Bypasses the feature's enabled
/// flag (the user is auditioning the sound), plays a single non-looping pass,
/// and retains the player so it isn't deallocated mid-playback.
enum SoundPreview {
    private static var player: AVAudioPlayer?

    /// Plays a bundled resource (e.g. `play(bundled: "timer", ext: "mp3")`).
    static func play(bundled name: String, ext: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            NSSound.beep()
            return
        }
        play(url: url)
    }

    /// Plays a file at an arbitrary URL (e.g. a user-picked custom timer sound).
    static func play(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = 0
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            NSSound.beep()
        }
    }

    /// Plays a named system sound (e.g. `"Tink"`).
    static func playSystem(named name: String) {
        NSSound(named: name)?.play()
    }
}
