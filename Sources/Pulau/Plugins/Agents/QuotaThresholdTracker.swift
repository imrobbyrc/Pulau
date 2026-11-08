import Foundation

struct QuotaThresholdTracker {
    enum Provider: String { case codex, glm }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func crossedThreshold(for provider: Provider, remaining: Double) -> Int? {
        guard remaining.isFinite, (0...100).contains(remaining) else { return nil }
        let key = "usage.lastRemaining.\(provider.rawValue)"
        let previous = defaults.object(forKey: key) as? Double
        defaults.set(remaining, forKey: key)
        guard let previous else { return nil }
        return [0, 10, 30, 50].first { previous > Double($0) && remaining <= Double($0) }
    }

    func reset(_ provider: Provider) {
        defaults.removeObject(forKey: "usage.lastRemaining.\(provider.rawValue)")
    }
}
