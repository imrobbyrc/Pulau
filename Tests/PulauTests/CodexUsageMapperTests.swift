import Foundation
import Testing
@testable import Pulau

@Test func codexMapsStringPercentAndReset() throws {
    let data = Data(#"{"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":"63","limit_window_seconds":"18000","reset_at":"1700000000"},"secondary_window":{"used_percent":25,"limit_window_seconds":604800,"reset_after_seconds":"60"}}}"#.utf8)
    let usage = try CodexUsageMapper.usage(data, now: Date(timeIntervalSince1970: 100))
    #expect(usage.primary?.remainingPercent == 37)
    #expect(usage.primary?.resetAt == Date(timeIntervalSince1970: 1700000000))
    #expect(usage.secondary?.remainingPercent == 75)
    #expect(usage.secondary?.resetAt == Date(timeIntervalSince1970: 160))
    #expect(usage.planName == "Pro 100")
}

@Test func codexNullAndWeeklyInPrimarySlot() throws {
    let data = Data(#"{"plan_type":"self_serve_business_prolite","rate_limit":{"primary_window":{"used_percent":"40","limit_window_seconds":604800,"reset_at":null},"secondary_window":null}}"#.utf8)
    let usage = try CodexUsageMapper.usage(data)
    #expect(usage.primary == nil)
    #expect(usage.secondary?.remainingPercent == 60)
    #expect(usage.secondary?.resetAt == nil)
    #expect(usage.planName == "Business Premium")
}

@Test func codexRejectsBodyErrorsAndNullPercent() throws {
    #expect(throws: (any Error).self) { try CodexUsageMapper.usage(Data(#"{"code":401,"error":"unauthorized"}"#.utf8)) }
    #expect(throws: (any Error).self) { try CodexUsageMapper.usage(Data(#"{"rate_limit":{"primary_window":{"used_percent":null}}}"#.utf8)) }
    let usage = try CodexUsageMapper.usage(Data(#"{"rate_limit":{"primary_window":{"used_percent":null}}}"#.utf8), primaryHeader: "10")
    #expect(usage.primary?.remainingPercent == 90)
}
