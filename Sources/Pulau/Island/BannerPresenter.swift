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
    case systemExperimental
}

enum ExpandPreference: String {
    case `default`, minimal
}

enum IslandState {
    case collapsed, minimal, full

    var width: CGFloat { self == .collapsed ? 185 : 360 }
    var height: CGFloat { self == .full ? 174 : 32 }
}

@MainActor
final class BannerPresenter: ObservableObject {
    @Published private(set) var note: PulauNotification?
    @Published private(set) var state: IslandState = .collapsed
    @Published var expandPreference: ExpandPreference = .default {
        didSet {
            if note == nil && hovered { showHoverState() }
        }
    }
    @Published private(set) var generation = UUID()
    private(set) var hovered = false
    @Published var look: IslandLook = UserDefaults.standard.string(forKey: "islandLook").flatMap(IslandLook.init(rawValue:)) ?? .glassy

    func present(_ notification: PulauNotification) {
        note = notification
        state = .collapsed
        generation = UUID()
    }

    func expandFromView() {
        withAnimation(Motion.spring) { state = .full }
    }

    private func showHoverState() {
        withAnimation(Motion.spring) { state = expandPreference == .minimal ? .minimal : .full }
    }

    func setHovered(_ value: Bool) {
        hovered = value
        guard note == nil else { return }
        if value { showHoverState() } else { dismiss() }
    }

    func dismiss(duration: Double = Motion.dismissDuration) {
        withAnimation(Motion.quick(duration: duration)) { state = .collapsed }
    }

    func clear() {
        note = nil
        if hovered { showHoverState() }
    }
}

