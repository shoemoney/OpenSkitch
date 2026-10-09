import Foundation

// Removed by product decision: OpenSnap is silent. W1-B/WP4 deletes the remaining call sites.
@MainActor
final class SoundEffects {
    init() {}
    func play(_ name: String, enabled: Bool) {}
    func stop() {}
}
typealias OriginalSoundEffects = SoundEffects
