import Combine
import Foundation
import IOKit
import IOKit.pwr_mgt

struct AgentAwakePreferences {
    let defaults: UserDefaults

    var enabled: Bool {
        get { defaults.bool(forKey: "agentAwakeEnabled") }
        nonmutating set { defaults.set(newValue, forKey: "agentAwakeEnabled") }
    }

    var idleMinutes: Int {
        get { defaults.object(forKey: "agentAwakeIdleMinutes") as? Int ?? 2 }
        nonmutating set { defaults.set(newValue, forKey: "agentAwakeIdleMinutes") }
    }
}

/// Keeps the Mac awake while Rex reports a working agent, and releases the
/// power assertion after the configured idle delay so the laptop can sleep.
@MainActor
final class SleepGuard: ObservableObject {
    @Published private(set) var preventingSleep = false
    @Published var isEnabled: Bool {
        didSet {
            preferences.enabled = isEnabled
            evaluate()
        }
    }
    @Published var idleMinutes: Int {
        didSet {
            let clamped = min(5, max(1, idleMinutes))
            if clamped != idleMinutes {
                idleMinutes = clamped
                return
            }
            if idleMinutes != oldValue { preferences.idleMinutes = idleMinutes }
            evaluate()
        }
    }

    private let preferences: AgentAwakePreferences
    private let clock: () -> Date
    private let setAssertion: (Bool) -> Void
    private var lastWorkingAt: Date?
    private var lastBusy = false
    private var ticker: Task<Void, Never>?

    init(preferences: AgentAwakePreferences,
         clock: @escaping () -> Date = Date.init,
         preventSleep: @escaping (Bool) -> Void = { SleepGuard.preventSystemSleep($0) }) {
        self.preferences = preferences
        self.clock = clock
        self.setAssertion = preventSleep
        self.isEnabled = preferences.enabled
        self.idleMinutes = preferences.idleMinutes
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.evaluate()
            }
        }
    }

    deinit {
        ticker?.cancel()
    }

    func update(snapshot: RexSnapshot) {
        let busy = snapshot.connection != .offline && snapshot.reports.contains { $0.state == .working }
        if busy { lastWorkingAt = clock() }
        lastBusy = busy
        evaluate()
    }

    /// Re-checks whether the assertion should currently be held.
    func evaluate() {
        guard isEnabled, lastBusy, let last = lastWorkingAt else {
            setPreventing(false)
            return
        }
        setPreventing(clock().timeIntervalSince(last) < Double(idleMinutes) * 60)
    }

    private func setPreventing(_ preventing: Bool) {
        guard preventing != preventingSleep else { return }
        preventingSleep = preventing
        setAssertion(preventing)
    }

    private static func preventSystemSleep(_ prevent: Bool) {
        assertionIDLock.lock()
        defer { assertionIDLock.unlock() }
        if prevent {
            guard sharedAssertionID == nil else { return }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Pulau: agent working" as CFString, &id)
            if result == kIOReturnSuccess { sharedAssertionID = id }
        } else if let id = sharedAssertionID {
            IOPMAssertionRelease(id)
            sharedAssertionID = nil
        }
    }

    private static let assertionIDLock = NSLock()
    private static var sharedAssertionID: IOPMAssertionID?
}
