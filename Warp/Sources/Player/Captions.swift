import Foundation

/// The captions switch. Live TV has one CC button, not a per-program track
/// picker: the choice is global, survives launches, and every flip re-applies
/// it because each program is a fresh `loadfile` that mpv selects tracks for.
struct Captions: Equatable {
    var enabled: Bool

    static let key = "captionsEnabled"

    static func load(from defaults: UserDefaults = .standard) -> Captions {
        Captions(enabled: defaults.bool(forKey: key))
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.key)
    }
}
