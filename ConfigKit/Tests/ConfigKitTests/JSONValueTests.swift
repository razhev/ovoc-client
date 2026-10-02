import XCTest
@testable import ConfigKit

final class JSONValueTests: XCTestCase {
    func testIntegerConversionRejectsUnrepresentableNumbers() {
        for value in [1e100, -1e100, Double(Int.max), Double.infinity, -Double.infinity, Double.nan, 300.5] {
            XCTAssertNil(JSONValue.number(value).asInt, "Must reject \(value) without trapping")
        }
        XCTAssertEqual(JSONValue.number(300).asInt, 300)
        XCTAssertEqual(JSONValue.number(Double(Int.min)).asInt, Int.min)
        XCTAssertEqual(JSONValue.string(" 300 ").asInt, 300)
    }

    func testOversizedStreamTimeoutDoesNotCrashPastedKeyImport() throws {
        let json = SyntheticKey.serverJSON(cloakLast: SyntheticKey.cloakLastConfig(streamTimeout: 1e100))
        let imported = try ImportedConfig.make(fromPastedText: SyntheticKey.key(from: json))
        let cloak = try SyntheticKey.cloakDict(fromProfile: imported.ovpnProfile)
        XCTAssertEqual(cloak["StreamTimeout"] as? Int, 300)
    }
}
