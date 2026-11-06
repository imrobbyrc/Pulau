import Foundation
import Testing
@testable import Pulau

@Test func mapsZAIWindowsAndRenamedTokenLimit() throws {
    let data = Data(#"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":63,"nextResetTime":1700000000000},{"name":"CREDIT_LIMIT","unit":6,"number":1,"percentage":"25"}]}}"#.utf8)
    let limits = try ZAIUsageMapper.quota(data)
    #expect(limits.count == 2)
    #expect(limits[0].kind == .fiveHour)
    #expect(limits[0].remainingPercent == 37)
    #expect(limits[0].resetAt == Date(timeIntervalSince1970: 1700000000))
    #expect(limits[1].kind == .weekly)
    #expect(limits[1].remainingPercent == 75)
}

@Test func zaiClampsAndRejectsMalformedPercent() throws {
    let data = Data(#"{"limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"percentage":120}]}"#.utf8)
    #expect(try ZAIUsageMapper.quota(data).first?.remainingPercent == 0)
    let bad = Data(#"{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5}]}"#.utf8)
    #expect(throws: (any Error).self) { try ZAIUsageMapper.quota(bad) }
}
