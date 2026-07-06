import XCTest
@testable import HiveLightCore

/// Rename migration (#133): the bundle-ID change moves the UserDefaults
/// domain; known keys are copied from the legacy domain exactly once.
final class DefaultsMigrationTests: XCTestCase {
    private var legacySuite: String!
    private var targetSuite: String!
    private var legacy: UserDefaults!
    private var target: UserDefaults!
    private let flag = "didMigrateLegacyDefaults"

    override func setUpWithError() throws {
        legacySuite = "test.defaults-migration.legacy.\(UUID().uuidString)"
        targetSuite = "test.defaults-migration.target.\(UUID().uuidString)"
        legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
        target = try XCTUnwrap(UserDefaults(suiteName: targetSuite))
    }

    override func tearDownWithError() throws {
        legacy.removePersistentDomain(forName: legacySuite)
        target.removePersistentDomain(forName: targetSuite)
    }

    func test_copiesKnownKeysOnce() {
        legacy.set(true, forKey: "showSubagents")
        legacy.set("opened", forKey: "sessionOrder")

        migrateDefaults(from: legacy, to: target,
                        keys: ["showSubagents", "sessionOrder"], migratedFlagKey: flag)

        XCTAssertTrue(target.bool(forKey: "showSubagents"))
        XCTAssertEqual(target.string(forKey: "sessionOrder"), "opened")
        XCTAssertTrue(target.bool(forKey: flag))
    }

    func test_neverOverwritesExistingTargetValue() {
        legacy.set("opened", forKey: "sessionOrder")
        target.set("project", forKey: "sessionOrder")

        migrateDefaults(from: legacy, to: target,
                        keys: ["sessionOrder"], migratedFlagKey: flag)

        XCTAssertEqual(target.string(forKey: "sessionOrder"), "project")
    }

    func test_flagBlocksSecondRun() {
        legacy.set(true, forKey: "showSubagents")
        migrateDefaults(from: legacy, to: target,
                        keys: ["showSubagents"], migratedFlagKey: flag)

        legacy.set("opened", forKey: "sessionOrder")
        migrateDefaults(from: legacy, to: target,
                        keys: ["showSubagents", "sessionOrder"], migratedFlagKey: flag)

        XCTAssertNil(target.string(forKey: "sessionOrder"))
    }

    func test_emptyLegacyStillStampsFlag() {
        migrateDefaults(from: legacy, to: target, keys: ["showSubagents"], migratedFlagKey: flag)
        XCTAssertTrue(target.bool(forKey: flag))
        XCTAssertNil(target.object(forKey: "showSubagents"))
    }
}
