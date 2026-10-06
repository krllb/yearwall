import XCTest
@testable import TimeModel

final class ProgressCalculatorTests: XCTestCase {
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let utc = TimeZone(identifier: "UTC")!

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0, in timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Year length

    func testLeapAndCommonYearsHaveTheRightTotal() {
        let model = ProgressCalculator(timeZone: utc)
        let cases: [(year: Int, total: Int)] = [
            (2023, 365), (2024, 366), (2000, 366), (1900, 365), (2100, 365),
        ]
        for testCase in cases {
            let progress = model.progress(for: makeDate(testCase.year, 6, 15, in: utc), mode: .year)
            XCTAssertEqual(progress.total, testCase.total, "year \(testCase.year)")
        }
    }

    func testYearRollover() {
        let model = ProgressCalculator(timeZone: utc)

        let lastDay = model.progress(for: makeDate(2023, 12, 31, hour: 23, minute: 59, in: utc), mode: .year)
        XCTAssertEqual(lastDay.todayIndex, 364)
        XCTAssertEqual(lastDay.total, 365)
        XCTAssertEqual(lastDay.summary, "day 365 of 365")

        let firstDay = model.progress(for: makeDate(2024, 1, 1, hour: 0, minute: 0, in: utc), mode: .year)
        XCTAssertEqual(firstDay.todayIndex, 0)
        XCTAssertEqual(firstDay.total, 366)
        XCTAssertEqual(firstDay.elapsed, 0)
        XCTAssertEqual(firstDay.summary, "day 1 of 366")
    }

    // MARK: - DST

    func testSpringForwardDayIsStillOneDay() {
        let model = ProgressCalculator(timeZone: newYork)
        // 2024-03-10 in New York is 23 hours long.
        let before = makeDate(2024, 3, 9, in: newYork)
        let after = makeDate(2024, 3, 10, in: newYork)
        XCTAssertEqual(model.dayDifference(from: before, to: after), 1)

        let progress = model.progress(for: after, mode: .year)
        XCTAssertEqual(progress.todayIndex, 69, "10 March 2024 is day 70 of a leap year")
        XCTAssertEqual(progress.total, 366)
        XCTAssertEqual(progress.dayKey, "2024-03-10")
    }

    func testFallBackDayIsStillOneDay() {
        let model = ProgressCalculator(timeZone: newYork)
        // 2024-11-03 in New York is 25 hours long.
        let before = makeDate(2024, 11, 2, in: newYork)
        let after = makeDate(2024, 11, 3, in: newYork)
        XCTAssertEqual(model.dayDifference(from: before, to: after), 1)

        let progress = model.progress(for: after, mode: .year)
        XCTAssertEqual(progress.todayIndex, 307, "3 November 2024 is day 308 of a leap year")
        XCTAssertEqual(progress.dayKey, "2024-11-03")
    }

    func testDSTDoesNotAccumulateDriftAcrossAFullYear() {
        let model = ProgressCalculator(timeZone: newYork)
        let start = makeDate(2024, 1, 1, hour: 0, minute: 30, in: newYork)
        let end = makeDate(2025, 1, 1, hour: 0, minute: 30, in: newYork)
        XCTAssertEqual(model.dayDifference(from: start, to: end), 366)
    }

    func testDayKeyFollowsTheModelTimeZoneNotTheSystemOne() {
        // 2024-06-15 03:00 UTC is still 2024-06-14 in New York.
        let instant = makeDate(2024, 6, 15, hour: 3, in: utc)
        XCTAssertEqual(ProgressCalculator(timeZone: utc).dayKey(for: instant), "2024-06-15")
        XCTAssertEqual(ProgressCalculator(timeZone: newYork).dayKey(for: instant), "2024-06-14")
    }

    // MARK: - Life mode

    func testLifeCountsWholeWeeks() {
        let model = ProgressCalculator(timeZone: utc)
        let birth = makeDate(2000, 1, 1, hour: 0, in: utc)

        let sixDays = model.progress(for: makeDate(2000, 1, 7, in: utc), mode: .life, birthDate: birth)
        XCTAssertEqual(sixDays.todayIndex, 0)

        let sevenDays = model.progress(for: makeDate(2000, 1, 8, in: utc), mode: .life, birthDate: birth)
        XCTAssertEqual(sevenDays.todayIndex, 1)
        XCTAssertEqual(sevenDays.total, 80 * 52)
        XCTAssertEqual(sevenDays.summary, "week 2 of 4160")
        XCTAssertFalse(sevenDays.isClamped)
    }

    func testBirthDateInTheFutureClampsToZero() {
        let model = ProgressCalculator(timeZone: utc)
        let birth = makeDate(2030, 5, 5, in: utc)
        let progress = model.progress(for: makeDate(2024, 5, 5, in: utc), mode: .life, birthDate: birth)

        XCTAssertEqual(progress.todayIndex, 0)
        XCTAssertEqual(progress.elapsed, 0)
        XCTAssertTrue(progress.isClamped)
        XCTAssertEqual(progress.mode, .life)
    }

    func testLifespanExceededClampsToTheLastUnit() {
        let model = ProgressCalculator(timeZone: utc)
        let birth = makeDate(1900, 1, 1, in: utc)
        let progress = model.progress(for: makeDate(2024, 1, 1, in: utc), mode: .life, birthDate: birth)

        XCTAssertEqual(progress.todayIndex, progress.total - 1)
        XCTAssertTrue(progress.isClamped)
    }

    func testLifeWithoutBirthDateFallsBackToYear() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(for: makeDate(2024, 6, 15, in: utc), mode: .life, birthDate: nil)

        XCTAssertEqual(progress.mode, .year)
        XCTAssertTrue(progress.didFallBackToYear)
        XCTAssertEqual(progress.total, 366)
    }

    func testCustomLifespan() {
        let model = ProgressCalculator(timeZone: utc)
        let birth = makeDate(2000, 1, 1, in: utc)
        let progress = model.progress(
            for: makeDate(2024, 1, 1, in: utc), mode: .life, birthDate: birth, lifespanYears: 90
        )
        XCTAssertEqual(progress.total, 90 * 52)
    }

    // MARK: - Scheduling

    func testNextMidnightIsTheNextLocalMidnight() {
        let model = ProgressCalculator(timeZone: newYork)
        let evening = makeDate(2024, 6, 15, hour: 23, minute: 30, in: newYork)
        XCTAssertEqual(model.dayKey(for: model.nextMidnight(after: evening)), "2024-06-16")
    }

    func testNextMidnightCrossesTheSpringForwardBoundary() {
        let model = ProgressCalculator(timeZone: newYork)
        // The night that loses an hour: midnight itself is not skipped.
        let evening = makeDate(2024, 3, 9, hour: 23, minute: 30, in: newYork)
        let midnight = model.nextMidnight(after: evening)
        XCTAssertEqual(model.dayKey(for: midnight), "2024-03-10")
        XCTAssertEqual(midnight.timeIntervalSince(evening), 30 * 60, accuracy: 1)
    }

    func testProgressFractionAndRemaining() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(for: makeDate(2023, 12, 31, in: utc), mode: .year)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.fraction, 1.0, accuracy: 0.0001)
    }
}

// MARK: - Groups

extension ProgressCalculatorTests {
    func testAYearIsGroupedByItsMonths() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(for: makeDate(2023, 6, 15, in: utc), mode: .year)

        XCTAssertEqual(progress.groupSizes, [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        XCTAssertEqual(progress.groupSizes.reduce(0, +), progress.total, "the months must add up")
        XCTAssertEqual(progress.widestGroup, 31)
    }

    func testALeapFebruaryIsTwentyNineDays() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(for: makeDate(2024, 6, 15, in: utc), mode: .year)

        XCTAssertEqual(progress.groupSizes[1], 29)
        XCTAssertEqual(progress.groupSizes.reduce(0, +), 366)
    }

    func testALifeIsGroupedByYears() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(
            for: makeDate(2024, 6, 15, in: utc), mode: .life,
            birthDate: makeDate(1990, 1, 1, in: utc)
        )

        XCTAssertEqual(progress.groupSizes.count, 80)
        XCTAssertEqual(Set(progress.groupSizes), [52])
        XCTAssertEqual(progress.majorGroupInterval, 10)
        XCTAssertEqual(progress.groupSizes.reduce(0, +), progress.total)
    }

    func testTodayLandsInTheRightMonth() {
        let model = ProgressCalculator(timeZone: utc)
        // 15 March 2023 is day 74; the month is index 2, the 15th day of it.
        let progress = model.progress(for: makeDate(2023, 3, 15, in: utc), mode: .year)
        let placed = progress.position(of: progress.todayIndex)
        XCTAssertEqual(placed.group, 2)
        XCTAssertEqual(placed.offset, 14)
    }

    func testPositionCoversEveryDayOfALeapYear() {
        let model = ProgressCalculator(timeZone: utc)
        let progress = model.progress(for: makeDate(2024, 6, 15, in: utc), mode: .year)
        for day in 0 ..< progress.total {
            let placed = progress.position(of: day)
            XCTAssertTrue(progress.groupSizes.indices.contains(placed.group), "day \(day)")
            XCTAssertLessThan(placed.offset, progress.groupSizes[placed.group], "day \(day)")
        }
    }
}
