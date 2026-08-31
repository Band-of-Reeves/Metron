import Foundation
import Testing
@testable import Metron

/// `--measure` used to skip the KatechonOS glance because its source is a NAS
/// over ssh, so that popover was compared empty-against-empty and reported as
/// passing. These tests cover the fixture path that replaced the skip, and the
/// `hasData` flag the check now asserts on.
@Suite("Measure fixtures")
@MainActor
struct FixtureTests {

    @Test("The KatechonOS fixture decodes into the shape the panel draws")
    func katechonFixtureDecodes() throws {
        let data = try #require(Fixtures.json(for: "katechon"))
        let state = try JSONDecoder().decode(KatechonState.self, from: data)

        #expect(state.hostname == "katechon")
        #expect(state.pool?.isHealthy == true)
        #expect(state.allCells.count == 4)
        #expect(state.allServices.count == 4)
        #expect(state.bootc?.rollback != nil)
    }

    @Test("It exercises the branches the panel draws differently")
    func katechonFixtureCoversBranches() throws {
        let data = try #require(Fixtures.json(for: "katechon"))
        let state = try JSONDecoder().decode(KatechonState.self, from: data)

        // An unbounded cell has no fullness — the panel must not divide by it.
        let archive = try #require(state.allCells.first { $0.name == "archive" })
        #expect(archive.fraction == nil)

        // A quota'd cell does, and `fullestCell` has to ignore the nil one.
        // backups is 2.902T of 4T (72.6%); media is the bigger cell but only
        // 55.9% of its 12T quota. Fullest means fraction, not size.
        #expect(state.fullestCell?.name == "backups")
        #expect(try #require(state.fullestCell?.fraction) > 0.7)

        // A socket-activated unit sits in `listening` and is healthy.
        let socket = try #require(state.allServices.first { $0.unit.hasSuffix(".socket") })
        #expect(socket.isUp == false)
        #expect(socket.isAcceptable == true)
        #expect(state.downServices.isEmpty)

        // And a stopped cell is still reported, just not as running.
        let scratch = try #require(state.allCells.first { $0.name == "scratch" })
        #expect(scratch.isRunning == false)
    }

    @Test("Loading a fixture marks the glance as loaded, like a real refresh")
    func fixtureStampsHasData() throws {
        let store = KatechonStore()
        #expect(store.hasData == false)

        let data = try #require(Fixtures.json(for: "katechon"))
        #expect(store.loadFixture(data) == true)

        // This is the flag --measure asserts on. Without it the popover check
        // measures an empty panel and calls it a pass.
        #expect(store.hasData == true)
        #expect(store.state?.hostname == "katechon")
        #expect(store.error == nil)
    }

    @Test("A glance with no fixture says so rather than pretending")
    func noFixtureForOtherGlances() {
        #expect(Fixtures.json(for: "usage") == nil)
        #expect(Fixtures.json(for: "system") == nil)
        #expect(Fixtures.json(for: "omlx") == nil)
    }

    @Test("Malformed JSON leaves the glance untouched instead of half-loaded")
    func malformedFixtureRejected() {
        let store = KatechonStore()
        #expect(store.loadFixture(Data("{ not json".utf8)) == false)
        #expect(store.hasData == false)
        #expect(store.state == nil)
    }

    @Test("The default store has no fixture, so the hook is opt-in")
    func defaultStoreDeclinesFixtures() {
        let plain = GlanceStore(id: "plain", name: "Plain", symbol: "circle")
        #expect(plain.loadFixture(Data("{}".utf8)) == false)
        #expect(plain.hasData == false)
    }
}
