import Foundation
import SQLite3

struct PulauNotification: Equatable {
    let app: String
    let title: String
    let body: String

    static func decode(_ data: Data, app: String) -> PulauNotification? {
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let body = [request["subt"] as? String, request["body"] as? String]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return PulauNotification(app: app, title: title, body: body)
    }
}

@MainActor
final class NotificationCapture {
    private let database = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path
    private var startedAt = 0.0
    private var seen: [String: Double] = [:]
    private(set) var status = "Off"

    func start() {
        startedAt = Date().timeIntervalSinceReferenceDate
        seen.removeAll()
    }

    func stop() {
        seen.removeAll()
        status = "Off"
    }

    func poll(show: (PulauNotification) -> Void) {
        let fd = open(database, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            status = "Grant Full Disk Access, then relaunch Pulau."
            return
        }
        close(fd)

        var db: OpaquePointer?
        guard sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            status = "Cannot open notification store; check Full Disk Access."
            return
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT hex(r.uuid), r.delivered_date, a.identifier, r.data FROM record AS r JOIN app AS a ON a.app_id = r.app_id WHERE r.delivered_date > ? ORDER BY r.delivered_date ASC"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            status = "Notification store unsupported on this macOS version."
            return
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = max(startedAt, Date().timeIntervalSinceReferenceDate - 30)
        sqlite3_bind_double(statement, 1, cutoff)
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let rawID = sqlite3_column_text(statement, 0),
               let rawApp = sqlite3_column_text(statement, 2),
               let bytes = sqlite3_column_blob(statement, 3) {
                let id = String(cString: rawID)
                let deliveredAt = sqlite3_column_double(statement, 1)
                if seen[id] == nil {
                    seen[id] = deliveredAt
                    let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 3)))
                    if let notification = PulauNotification.decode(data, app: String(cString: rawApp)) {
                        show(notification)
                    }
                }
            }
            result = sqlite3_step(statement)
        }
        seen = seen.filter { $0.value > cutoff }
        status = result == SQLITE_DONE ? "Listening for new notifications" : "Read failed; retrying."
    }

}
