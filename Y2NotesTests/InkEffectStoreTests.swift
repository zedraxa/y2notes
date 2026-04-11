import XCTest
@testable import Y2Notes

// MARK: - InkEffectStoreTests

/// Tests for the simplified InkEffectStore covering preset selection,
/// user preset management, and resolvedFX computation.
@MainActor
final class InkEffectStoreTests: XCTestCase {

    private var store: InkEffectStore!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Clear UserDefaults to ensure clean state for each test
        let keys = [
            "y2notes.ink.fxEnabled",
            "y2notes.ink.userPresets",
            "y2notes.ink.activePresetID"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        store = InkEffectStore()
    }

    override func tearDown() async throws {
        store = nil
        try await super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(store.fxEnabled, "FX should be enabled by default")
        XCTAssertNil(store.activePreset, "No preset should be selected initially")
        XCTAssertTrue(store.userPresets.isEmpty, "User presets should be empty initially")
    }

    func testResolvedFXWhenDisabled() {
        store.fxEnabled = false
        store.selectPreset(InkFamilyRegistry.shared.allBuiltIn.first)
        XCTAssertEqual(store.resolvedFX, .none, "resolvedFX should be .none when FX disabled")
    }

    func testResolvedFXWhenNoPresetSelected() {
        store.fxEnabled = true
        store.activePreset = nil
        XCTAssertEqual(store.resolvedFX, .none, "resolvedFX should be .none when no preset")
    }

    func testResolvedFXWhenPresetSelected() {
        store.fxEnabled = true
        let firePreset = InkFamilyRegistry.shared.allBuiltIn.first { $0.writingFX == .fire }
        store.selectPreset(firePreset)
        XCTAssertEqual(store.resolvedFX, .fire, "resolvedFX should match preset FX")
    }

    // MARK: - Preset Selection

    func testSelectPreset() {
        let preset = InkFamilyRegistry.shared.allBuiltIn.first!
        store.selectPreset(preset)
        XCTAssertEqual(store.activePreset?.id, preset.id)
    }

    func testClearPreset() {
        let preset = InkFamilyRegistry.shared.allBuiltIn.first!
        store.selectPreset(preset)
        store.clearPreset()
        XCTAssertNil(store.activePreset)
    }

    // MARK: - User Preset Management

    func testSaveUserPreset() {
        store.saveUserPreset(
            name: "Custom Fire",
            family: .fire,
            traits: .standard,
            fx: .fire,
            color: .red,
            width: 2.0
        )

        XCTAssertEqual(store.userPresets.count, 1)
        XCTAssertEqual(store.userPresets[0].name, "Custom Fire")
        XCTAssertEqual(store.userPresets[0].family, .fire)
        XCTAssertEqual(store.userPresets[0].writingFX, .fire)
        XCTAssertFalse(store.userPresets[0].isBuiltIn)
    }

    func testSaveUserPresetWithEmptyNameUsesFamily() {
        store.saveUserPreset(
            name: "  ",
            family: .metallic,
            traits: .metallic,
            fx: .sparkle,
            color: .yellow,
            width: 1.5
        )

        XCTAssertEqual(store.userPresets.count, 1)
        XCTAssertEqual(store.userPresets[0].name, InkFamily.metallic.displayName)
    }

    func testDeleteUserPreset() {
        store.saveUserPreset(
            name: "Test",
            family: .standard,
            traits: .standard,
            fx: .none,
            color: .black,
            width: 1.0
        )

        let presetID = store.userPresets[0].id
        store.deleteUserPreset(id: presetID)
        XCTAssertTrue(store.userPresets.isEmpty)
    }

    func testDeleteNonExistentPresetDoesNothing() {
        store.saveUserPreset(
            name: "Test",
            family: .standard,
            traits: .standard,
            fx: .none,
            color: .black,
            width: 1.0
        )

        store.deleteUserPreset(id: UUID())
        XCTAssertEqual(store.userPresets.count, 1, "Should not delete anything")
    }

    func testDeleteBuiltInPresetIsIgnored() {
        // Built-in presets cannot be in userPresets array, but test the guard logic
        let builtIn = InkFamilyRegistry.shared.allBuiltIn.first!
        store.deleteUserPreset(id: builtIn.id)
        // Should not crash
    }

    func testToggleFavorite() {
        store.saveUserPreset(
            name: "Favorite Test",
            family: .neon,
            traits: .standard,
            fx: .sparkle,
            color: .cyan,
            width: 1.5
        )

        let presetID = store.userPresets[0].id
        XCTAssertFalse(store.userPresets[0].isFavorite)

        store.toggleFavorite(id: presetID)
        XCTAssertTrue(store.userPresets[0].isFavorite)

        store.toggleFavorite(id: presetID)
        XCTAssertFalse(store.userPresets[0].isFavorite)
    }

    // MARK: - All Presets

    func testAllPresetsIncludesBuiltInAndUser() {
        store.saveUserPreset(
            name: "Custom",
            family: .standard,
            traits: .standard,
            fx: .none,
            color: .blue,
            width: 1.0
        )

        let builtInCount = InkFamilyRegistry.shared.allBuiltIn.count
        XCTAssertEqual(store.allPresets.count, builtInCount + 1)
    }

    func testPresetsByFamilyGroupsCorrectly() {
        let grouped = store.presetsByFamily
        XCTAssertFalse(grouped.isEmpty)

        // Each family should contain at least one preset
        for (family, presets) in grouped {
            XCTAssertFalse(presets.isEmpty, "\(family) should have presets")
            presets.forEach { preset in
                XCTAssertEqual(preset.family, family, "Preset should match family")
            }
        }
    }

    // MARK: - Persistence

    func testFXEnabledPersistence() {
        store.fxEnabled = false

        // Create new store instance to test persistence
        let newStore = InkEffectStore()
        XCTAssertFalse(newStore.fxEnabled, "fxEnabled should persist")
    }

    func testUserPresetsPersistence() {
        store.saveUserPreset(
            name: "Persistent",
            family: .watercolour,
            traits: .watercolour,
            fx: .none,
            color: .green,
            width: 2.5
        )

        // Create new store instance to test persistence
        let newStore = InkEffectStore()
        XCTAssertEqual(newStore.userPresets.count, 1)
        XCTAssertEqual(newStore.userPresets[0].name, "Persistent")
    }

    func testActivePresetPersistence() {
        let preset = InkFamilyRegistry.shared.allBuiltIn.first!
        store.selectPreset(preset)

        // Create new store instance to test persistence
        let newStore = InkEffectStore()
        XCTAssertEqual(newStore.activePreset?.id, preset.id)
    }

    // MARK: - Theme Hook

    func testPresetsForThemeReturnsBuiltIn() {
        let presets = store.presetsForTheme(.dark)
        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.allSatisfy { $0.isBuiltIn })
    }
}
