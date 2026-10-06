import Foundation

/// Turns a wall-clock `Date` into a `Progress`.
///
/// Deliberately holds an explicit `Calendar` (gregorian) with an explicit
/// `TimeZone`, so behaviour is reproducible in tests and immune to whatever
/// the current locale would otherwise pick.
public struct ProgressCalculator: Sendable {
    public static let defaultLifespanYears = 80
    /// Weeks per year used by `.life`. 52 * 80 = 4160, the familiar "life in weeks" grid.
    public static let weeksPerYear = 52

    public let calendar: Calendar

    public init(
        timeZone: TimeZone = .current,
        calendarIdentifier: Calendar.Identifier = .gregorian,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) {
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = timeZone
        calendar.locale = locale
        self.calendar = calendar
    }

    /// `yyyy-MM-dd` for `date` in this model's calendar. Built from components
    /// rather than a `DateFormatter` so it can never pick up a locale-specific
    /// numbering system.
    public func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whole days between two instants, measured between *starts of day* so a
    /// DST transition (a 23- or 25-hour day) still counts as exactly one day.
    public func dayDifference(from start: Date, to end: Date) -> Int {
        let a = calendar.startOfDay(for: start)
        let b = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public func progress(
        for date: Date,
        mode: TimeMode,
        birthDate: Date? = nil,
        lifespanYears: Int = ProgressCalculator.defaultLifespanYears
    ) -> Progress {
        switch mode {
        case .year:
            return yearProgress(for: date)
        case .life:
            guard let birthDate else {
                let fallback = yearProgress(for: date)
                return Progress(
                    mode: .year,
                    elapsed: fallback.elapsed,
                    total: fallback.total,
                    todayIndex: fallback.todayIndex,
                    dayKey: fallback.dayKey,
                    isClamped: fallback.isClamped,
                    didFallBackToYear: true
                )
            }
            return lifeProgress(for: date, birthDate: birthDate, lifespanYears: lifespanYears)
        }
    }

    // MARK: - Modes

    private func yearProgress(for date: Date) -> Progress {
        let total = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let ordinal = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let todayIndex = min(max(ordinal - 1, 0), total - 1)
        return Progress(
            mode: .year,
            elapsed: todayIndex,
            total: total,
            todayIndex: todayIndex,
            dayKey: dayKey(for: date),
            groupSizes: monthLengths(inYearOf: date)
        )
    }

    private func lifeProgress(for date: Date, birthDate: Date, lifespanYears: Int) -> Progress {
        let years = max(1, lifespanYears)
        let total = years * ProgressCalculator.weeksPerYear
        let days = dayDifference(from: birthDate, to: date)
        let rawWeek = days >= 0 ? days / 7 : -1
        let clamped = min(max(rawWeek, 0), total - 1)
        return Progress(
            mode: .life,
            elapsed: clamped,
            total: total,
            todayIndex: clamped,
            dayKey: dayKey(for: date),
            isClamped: rawWeek != clamped,
            groupSizes: Array(repeating: ProgressCalculator.weeksPerYear, count: years),
            majorGroupInterval: 10
        )
    }

    /// Days in each month of the year containing `date`, in order.
    ///
    /// Read from the calendar rather than a table, so a leap February is 29 and
    /// a non-Gregorian calendar with a different month count still works.
    func monthLengths(inYearOf date: Date) -> [Int] {
        guard let months = calendar.range(of: .month, in: .year, for: date),
              let year = calendar.dateComponents([.year], from: date).year
        else { return [] }

        return months.compactMap { month in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let start = calendar.date(from: components),
                  let days = calendar.range(of: .day, in: .month, for: start)
            else { return nil }
            return days.count
        }
    }

    // MARK: - Scheduling helper

    /// The next local midnight strictly after `date`. Used to schedule the
    /// daily regeneration without assuming a day is 24 hours long.
    public func nextMidnight(after date: Date) -> Date {
        if let next = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) {
            return next
        }
        // Should not happen with a gregorian calendar; keep the app alive anyway.
        return date.addingTimeInterval(24 * 60 * 60)
    }
}
