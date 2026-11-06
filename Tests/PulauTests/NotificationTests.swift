import Foundation
import Testing
@testable import Pulau

@Test func decodesNotificationPayload() throws {
    let payload = try PropertyListSerialization.data(
        fromPropertyList: ["req": ["titl": "Hello", "subt": "Preview", "body": "Message"]],
        format: .binary,
        options: 0
    )
    #expect(PulauNotification.decode(payload, app: "com.example.app") ==
            PulauNotification(app: "com.example.app", title: "Hello", body: "Preview\nMessage"))

    let empty = try PropertyListSerialization.data(fromPropertyList: ["req": [:]], format: .binary, options: 0)
    #expect(PulauNotification.decode(empty, app: "com.example.app") == nil)
    #expect(PulauNotification.decode(Data("invalid".utf8), app: "com.example.app") == nil)
}
