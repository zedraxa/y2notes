import XCTest
@testable import Y2Components

final class Y2ComponentsTests: XCTestCase {

    func testModuleVersion() {
        XCTAssertEqual(Y2ComponentsModule.version, "1.0.0")
    }
}
