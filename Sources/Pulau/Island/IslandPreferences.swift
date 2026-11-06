import Foundation

struct IslandPreferences {
    let defaults: UserDefaults

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        nonmutating set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    var expandPreference: ExpandPreference {
        get { defaults.string(forKey: "expandPreference").flatMap(ExpandPreference.init(rawValue:)) ?? .default }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "expandPreference") }
    }

    var look: IslandLook {
        get { defaults.string(forKey: "islandLook").flatMap(IslandLook.init(rawValue:)) ?? .glassy }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "islandLook") }
    }
}
