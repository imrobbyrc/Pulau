import Foundation
import Testing
@testable import Pulau

@Test func resetCountdownFormatting() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ResetCountdown.text(until: now, now: now) == nil)
    #expect(ResetCountdown.text(until: now.addingTimeInterval(-60), now: now) == nil)
    #expect(ResetCountdown.text(until: now.addingTimeInterval(1), now: now) == "1m")
    #expect(ResetCountdown.text(until: now.addingTimeInterval(3_660), now: now) == "1h 1m")
    #expect(ResetCountdown.text(until: now.addingTimeInterval(172_800), now: now) == "2d")
    #expect(ResetCountdown.text(until: now.addingTimeInterval(180_000), now: now) == "2d 2h")
}
