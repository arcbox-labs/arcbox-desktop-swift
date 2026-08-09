import GRPCCore
import XCTest

@testable import ArcBox

final class OnboardingMigrationModelTests: XCTestCase {
    func testReconnectsOnlyForUnavailableRPCs() {
        XCTAssertTrue(OnboardingMigrationModel.shouldReconnect(after: .unavailable))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .internalError))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .invalidArgument))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .failedPrecondition))
    }
}
