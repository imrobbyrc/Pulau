import Foundation
import XCTest
@testable import Pulau

final class CodexAuthTests: XCTestCase {
    func testFragmentedCallbackRequestLine() throws {
        var parser = CallbackRequestLine()
        XCTAssertNil(try parser.append(Data("GET /callback?code=abc&sta".utf8)))
        XCTAssertNil(try parser.append(Data("te=fixture HTTP/1.1\r".utf8)))
        XCTAssertEqual(try parser.append(Data("\nHost: localhost\r\n".utf8)),
                       "GET /callback?code=abc&state=fixture HTTP/1.1")
        var oversized = CallbackRequestLine()
        XCTAssertThrowsError(try oversized.append(Data(repeating: 65, count: 16385)))
    }

    func testPKCEAndJWTAccountID() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(CodexAuth.codeChallenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let generated = try CodexAuth.makeCodeVerifier()
        XCTAssertEqual(generated.count, 43)
        XCTAssertTrue(generated.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        func encode(_ value: String) -> String {
            Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let token = "\(encode("{\"alg\":\"none\"}" )).\(encode("{\"https://api.openai.com/auth\":{\"chatgpt_account_id\":\"fixture-account\"}}" ))."
        XCTAssertEqual(CodexAuth.accountID(from: token), "fixture-account")
    }
}
