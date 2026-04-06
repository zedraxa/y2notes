import XCTest
@testable import Y2GoogleDrive

final class Y2GoogleDriveTests: XCTestCase {

    func testModuleVersion() {
        XCTAssertEqual(Y2GoogleDriveModule.version, "1.0.0")
    }
}
