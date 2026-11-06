import AppKit
import SwiftUI

// Motion tokens modeled on NotchIsland: springy open, quicker close, ease
// instead of spring when Reduce Motion is on.
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    // Lively open with a controlled settle.
    static var spring: Animation { reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.83) }
    // A finite curve lets the panel hide as soon as the collapse finishes.
    static var dismissDuration: Double { reduce ? 0.1 : 0.2 }
    static func quick(duration: Double) -> Animation { .easeOut(duration: duration) }
}

/// Island look presets selectable from the menu; persisted per launch.
enum IslandLook: String, CaseIterable {
    case glassy
    case solid
}

@MainActor
final class BannerPresenter: ObservableObject {
    @Published private(set) var note: PulauNotification?
    @Published private(set) var expanded = false
    @Published private(set) var generation = UUID()
    @Published var look: IslandLook = UserDefaults.standard.string(forKey: "islandLook").flatMap(IslandLook.init(rawValue:)) ?? .glassy

    func present(_ notification: PulauNotification) {
        note = notification
        expanded = false
        generation = UUID()
    }

    /// Expand from the view's onAppear so the first render is the collapsed
    /// notch and the spring animates from there.
    func expandFromView() {
        guard !expanded else { return }
        withAnimation(Motion.spring) { expanded = true }
    }

    func dismiss(duration: Double = Motion.dismissDuration) {
        withAnimation(Motion.quick(duration: duration)) { expanded = false }
    }

    /// Clears content; call after the panel is hidden so the collapsed
    /// island never lingers on screen.
    func clear() {
        note = nil
    }
}

