import Foundation

/// What the wallpaper counts.
public enum TimeMode: String, Sendable, Codable, CaseIterable, Identifiable {
    /// One unit == one day of the current calendar year.
    case year
    /// One unit == one week of a fixed lifespan (default 80 years).
    case life

    public var id: String { rawValue }

    /// Noun for a single unit, used by the menu ("day 252 of 365").
    public var unitName: String {
        switch self {
        case .year: return "day"
        case .life: return "week"
        }
    }
}

/// Pure description of "where we are" in a span of time.
///
/// `elapsed` counts units *fully behind us*, `todayIndex` is the index of the
/// unit we are living through right now, so `todayIndex == elapsed` always
/// holds for the modes shipped in v0. Both are kept in the type because a
/// future mode (a goal countdown) may want them to diverge.
public struct Progress: Equatable, Sendable, Codable {
    public let mode: TimeMode
    /// Units completed before today. `0 ..< total`.
    public let elapsed: Int
    /// Total units in the span.
    public let total: Int
    /// Index of the unit representing "now". `0 ..< total`.
    public let todayIndex: Int
    /// `yyyy-MM-dd` in the model's calendar/time zone. Drives the day seed.
    public let dayKey: String
    /// True when the input had to be clamped (birth date in the future,
    /// lifespan already exceeded).
    public let isClamped: Bool
    /// True when `.life` was requested without a birth date and we fell back to `.year`.
    public let didFallBackToYear: Bool
    /// The size of each group, in order. Empty means no grouping.
    ///
    /// A list rather than a single number because the natural groups of a year
    /// are its months, and those are 28, 29, 30 or 31 days long. A life is the
    /// easy case: eighty groups of fifty-two.
    public let groupSizes: [Int]
    /// Every n-th group boundary is emphasised: decades, for a life.
    /// 0 means no emphasis.
    public let majorGroupInterval: Int

    public init(
        mode: TimeMode,
        elapsed: Int,
        total: Int,
        todayIndex: Int,
        dayKey: String,
        isClamped: Bool = false,
        didFallBackToYear: Bool = false,
        groupSizes: [Int] = [],
        majorGroupInterval: Int = 0
    ) {
        self.mode = mode
        self.elapsed = elapsed
        self.total = total
        self.todayIndex = todayIndex
        self.dayKey = dayKey
        self.isClamped = isClamped
        self.didFallBackToYear = didFallBackToYear
        self.groupSizes = groupSizes
        self.majorGroupInterval = majorGroupInterval
    }

    /// Missing group fields decode to "ungrouped" rather than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try container.decode(TimeMode.self, forKey: .mode),
            elapsed: try container.decode(Int.self, forKey: .elapsed),
            total: try container.decode(Int.self, forKey: .total),
            todayIndex: try container.decode(Int.self, forKey: .todayIndex),
            dayKey: try container.decode(String.self, forKey: .dayKey),
            isClamped: try container.decodeIfPresent(Bool.self, forKey: .isClamped) ?? false,
            didFallBackToYear: try container.decodeIfPresent(Bool.self, forKey: .didFallBackToYear) ?? false,
            groupSizes: try container.decodeIfPresent([Int].self, forKey: .groupSizes) ?? [],
            majorGroupInterval: try container.decodeIfPresent(Int.self, forKey: .majorGroupInterval) ?? 0
        )
    }

    // MARK: - Groups

    public var hasGroups: Bool { groupSizes.count > 1 }

    public var groupCount: Int { groupSizes.count }

    /// The longest group. A grid gives every group this many columns and lets
    /// the short ones end early.
    public var widestGroup: Int { groupSizes.max() ?? 0 }

    /// Index of the first unit of each group, plus a final entry equal to the
    /// sum, so a group's extent is `groupStarts[i] ..< groupStarts[i + 1]`.
    public var groupStarts: [Int] {
        var starts: [Int] = [0]
        starts.reserveCapacity(groupSizes.count + 1)
        var running = 0
        for size in groupSizes {
            running += size
            starts.append(running)
        }
        return starts
    }

    /// Which group a unit falls in, and how far into it.
    public func position(of unit: Int) -> (group: Int, offset: Int) {
        guard hasGroups else { return (0, unit) }
        var low = 0
        var high = groupSizes.count - 1
        var running = groupStarts
        while low < high {
            let mid = (low + high + 1) / 2
            if running[mid] <= unit { low = mid } else { high = mid - 1 }
        }
        return (low, unit - running[low])
    }

    /// Units still ahead, today excluded.
    public var remaining: Int { max(0, total - todayIndex - 1) }

    /// 0...1 fraction of the span consumed, today included.
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(todayIndex + 1) / Double(total)
    }

    /// "day 252 of 365"
    public var summary: String {
        "\(mode.unitName) \(todayIndex + 1) of \(total)"
    }
}
