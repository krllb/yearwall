import XCTest
@testable import PatternEngine

final class SeededRNGTests: XCTestCase {
    /// Golden values. If the generator is ever "improved", these fail and the
    /// determinism guarantee is not lost by accident.
    func testSplitMix64MatchesTheReferenceSequence() {
        var zero = SeededRNG(seed: 0)
        XCTAssertEqual(
            (0 ..< 3).map { _ in zero.next() },
            [16_294_208_416_658_607_535, 7_960_286_522_194_355_700, 487_617_019_471_545_679]
        )

        var answer = SeededRNG(seed: 42)
        XCTAssertEqual(
            (0 ..< 3).map { _ in answer.next() },
            [13_679_457_532_755_275_413, 2_949_826_092_126_892_291, 5_139_283_748_462_763_858]
        )
    }

    func testSameSeedGivesTheSameStream() {
        var a = SeededRNG(seed: 0xDEAD_BEEF)
        var b = SeededRNG(seed: 0xDEAD_BEEF)
        for _ in 0 ..< 1000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededRNG(seed: 1)
        var b = SeededRNG(seed: 2)
        let left = (0 ..< 32).map { _ in a.next() }
        let right = (0 ..< 32).map { _ in b.next() }
        XCTAssertNotEqual(left, right)
    }

    func testUnitValuesStayInRange() {
        var rng = SeededRNG(seed: 7)
        var sum = 0.0
        for _ in 0 ..< 10_000 {
            let value = rng.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            sum += value
        }
        XCTAssertEqual(sum / 10_000, 0.5, accuracy: 0.02, "should be roughly uniform")
    }

    func testIntRangeStaysInBounds() {
        var rng = SeededRNG(seed: 99)
        for _ in 0 ..< 10_000 {
            let value = rng.nextInt(in: 3 ..< 11)
            XCTAssertTrue((3 ..< 11).contains(value))
        }
    }

    func testBranchingDoesNotConsumeTheParentStream() {
        var parent = SeededRNG(seed: 5)
        let firstBefore = parent.next()

        var parentAgain = SeededRNG(seed: 5)
        var branch = parentAgain.branched("palette")
        _ = branch.next()
        XCTAssertEqual(parentAgain.next(), firstBefore)
    }
}

final class SeedsTests: XCTestCase {
    /// FNV-1a is spelled out in the source precisely so this value can be
    /// pinned. `Hasher` would change every process launch.
    func testHashIsStableAcrossLaunches() {
        XCTAssertEqual(Seeds.hash("2026-09-09"), 9_712_248_808_809_514_931)
        XCTAssertEqual(Seeds.hash(""), 14_695_981_039_346_656_037)
    }

    func testDaySeedDependsOnBothTheDayAndTheInstall() {
        let install: UInt64 = 0x1234_5678
        let today = Seeds.daySeed(dayKey: "2026-09-09", installSeed: install)
        let tomorrow = Seeds.daySeed(dayKey: "2026-09-10", installSeed: install)
        let otherInstall = Seeds.daySeed(dayKey: "2026-09-09", installSeed: install &+ 1)

        XCTAssertNotEqual(today, tomorrow)
        XCTAssertNotEqual(today, otherInstall)
        XCTAssertEqual(today, Seeds.daySeed(dayKey: "2026-09-09", installSeed: install))
    }

    func testInstallFacetsAreIndependentOfEachOther() {
        let install: UInt64 = 777
        XCTAssertNotEqual(
            Seeds.installFacet("palette", installSeed: install),
            Seeds.installFacet("character", installSeed: install)
        )
    }

    func testPatternCharacterIsStableForAnInstall() {
        for seed in [UInt64(0), 1, 12_345, .max] {
            XCTAssertEqual(
                PatternCharacter.derived(installSeed: seed),
                PatternCharacter.derived(installSeed: seed)
            )
        }
        XCTAssertNotEqual(
            PatternCharacter.derived(installSeed: 1),
            PatternCharacter.derived(installSeed: 2)
        )
    }
}
