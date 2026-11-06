import Foundation

enum ResetCountdown {
    static func text(until reset: Date, now: Date) -> String? {
        let seconds = reset.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = Int(min(ceil(seconds / 60), Double(Int.max / 2)))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes % 60 > 0 ? "\(hours)h \(minutes % 60)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}
